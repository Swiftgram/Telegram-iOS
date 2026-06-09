import Foundation
import SwiftSignalKit
import AccountContext
import TelegramCore
import SGLogging
import SGConfig
import SGWebAppExtensions

private let tokenExpirationTime: TimeInterval = 30 * 60 // 30 minutes

private var tokenCache: [Int64: (token: String, expiration: Date)] = [:]

public enum SGAPITokenError {
    case generic(String? = nil)
}

public func getSGApiToken(context: AccountContext, botUsername: String = SG_CONFIG.botUsername) -> Signal<String, SGAPITokenError> {
    let userId = context.account.peerId.id._internalGetInt64Value()
    
    if let (token, expiration) = tokenCache[userId], Date() < expiration {
        // SGLogger.shared.log("SGAPI", "Using cached token. Expiring at: \(expiration)")
        return Signal { subscriber in
            subscriber.putNext(token)
            subscriber.putCompletion()
            return EmptyDisposable
        }
    }
    
    SGLogger.shared.log("SGAPI", "Requesting new token")
    // Workaround for Apple Review
    if context.account.testingEnvironment {
        return context.account.postbox.transaction { transaction -> String? in
            if let testUserPeer = transaction.getPeer(context.account.peerId) as? TelegramUser, let testPhone = testUserPeer.phone {
                return testPhone
            } else {
                return nil
            }
        }
        |> mapToSignalPromotingError { phone -> Signal<String, SGAPITokenError> in
            if let phone = phone {
                // https://core.telegram.org/api/auth#test-accounts
                if phone.starts(with: String(99966)) {
                    SGLogger.shared.log("SGAPI", "Using demo token")
                    tokenCache[userId] = (phone, Date().addingTimeInterval(tokenExpirationTime))
                    return .single(phone)
                } else {
                    return .fail(.generic("Non-demo phone number on test DC"))
                }
            } else {
                return .fail(.generic("Missing test account peer or it's number (how?)"))
            }
        }
    }
    
    return Signal { subscriber in
        let getSettingsURLSignal = getSGSettingsURL(context: context, botUsername: botUsername).start(next: { url in
            if let hashPart = url.components(separatedBy: "#").last {
                let parsedParams = urlParseHashParams(hashPart)
                if let token = parsedParams["tgWebAppData"], let token = token {
                    tokenCache[userId] = (token, Date().addingTimeInterval(tokenExpirationTime))
                    #if DEBUG
                    print("[SGAPI]", "API Token: \(token)")
                    #endif
                    subscriber.putNext(token)
                    subscriber.putCompletion()
                } else {
                    subscriber.putError(.generic("Invalid or missing token in response url! \(url)"))
                }
            } else {
                subscriber.putError(.generic("No hash part in URL \(url)"))
            }
        })
        
        return ActionDisposable {
            getSettingsURLSignal.dispose()
        }
    }
}

public func getSGSettingsURL(context: AccountContext, botUsername: String = SG_CONFIG.botUsername, url: String = SG_CONFIG.webappUrl, themeParams: [String: Any]? = nil) -> Signal<String, SGAPITokenError> {
    return Signal { subscriber in
        //      themeParams = generateWebAppThemeParams(
        //      context.sharedContext.currentPresentationData.with { $0 }.theme
        //      )
        var requestWebViewSignalDisposable: Disposable? = nil
        var requestUpdatePeerIsBlocked: Disposable? = nil
        let resolvePeerSignal = (
            context.engine.peers.resolvePeerByName(name: botUsername, referrer: nil)
            |> mapToSignal { result -> Signal<EnginePeer?, NoError> in
                guard case let .result(result) = result else {
                    return .complete()
                }
                return .single(result)
            }).start(next: { botPeer in
                if let botPeer = botPeer {
                    SGLogger.shared.log("SGAPI", "Botpeer found for \(botUsername)")
                    let requestWebViewSignal = context.engine.messages.requestWebView(peerId: botPeer.id, botId: botPeer.id, url: url, payload: nil, themeParams: themeParams, fromMenu: true, replyToMessageId: nil, threadId: nil)
                    
                    requestWebViewSignalDisposable = requestWebViewSignal.start(next: { webViewResult in
                        subscriber.putNext(webViewResult.url)
                        subscriber.putCompletion()
                    }, error: { e in
                        SGLogger.shared.log("SGAPI", "Webview request error, retrying with unblock")
                        // if e.errorDescription == "YOU_BLOCKED_USER" {
                        requestUpdatePeerIsBlocked = (context.engine.privacy.requestUpdatePeerIsBlocked(peerId: botPeer.id, isBlocked: false)
                          |> afterDisposed(
                            {
                                requestWebViewSignalDisposable?.dispose()
                                requestWebViewSignalDisposable = requestWebViewSignal.start(next: { webViewResult in
                                    SGLogger.shared.log("SGAPI", "Webview retry success \(webViewResult)")
                                    subscriber.putNext(webViewResult.url)
                                    subscriber.putCompletion()
                                }, error: { e in
                                    SGLogger.shared.log("SGAPI", "Webview retry failure \(e)")
                                    subscriber.putError(.generic("Webview retry failure \(e)"))
                                })
                            })).start()
                            // }
                    })
                    
                } else {
                    SGLogger.shared.log("SGAPI", "Botpeer not found for \(botUsername)")
                    subscriber.putError(.generic())
                }
            })
        
        return ActionDisposable {
            resolvePeerSignal.dispose()
            requestUpdatePeerIsBlocked?.dispose()
            requestWebViewSignalDisposable?.dispose()
        }
    }
}
