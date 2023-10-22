#if DEBUG
import SGSimpleSettings
#endif
import SGTranslationLangFix
import SwiftSoup

import Foundation
import Postbox
import SwiftSignalKit
import TelegramApi
import MtProtoKit

public enum TranslationError {
    case generic
    case invalidMessageId
    case textIsEmpty
    case textTooLong
    case invalidLanguage
    case limitExceeded
}

func _internal_translate(network: Network, text: String, toLang: String) -> Signal<String?, TranslationError> {
    var flags: Int32 = 0
    flags |= (1 << 1)

    return network.request(Api.functions.messages.translateText(flags: flags, peer: nil, id: nil, text: [.textWithEntities(text: text, entities: [])], toLang: sgTranslationLangFix(toLang)))
    |> mapError { error -> TranslationError in
        if error.errorDescription.hasPrefix("FLOOD_WAIT") {
            return .limitExceeded
        } else if error.errorDescription == "MSG_ID_INVALID" {
            return .invalidMessageId
        } else if error.errorDescription == "INPUT_TEXT_EMPTY" {
            return .textIsEmpty
        } else if error.errorDescription == "INPUT_TEXT_TOO_LONG" {
            return .textTooLong
        } else if error.errorDescription == "TO_LANG_INVALID" {
            return .invalidLanguage
        } else {
            return .generic
        }
    }
    |> mapToSignal { result -> Signal<String?, TranslationError> in
        switch result {
        case let .translateResult(results):
            if case let .textWithEntities(text, _) = results.first {
                return .single(text)
            } else {
                return .single(nil)
            }
        }
    }
}

func _internal_translateMessages(account: Account, messageIds: [EngineMessage.Id], toLang: String) -> Signal<Void, TranslationError> {
    guard let peerId = messageIds.first?.peerId else {
        return .never()
    }
    return account.postbox.transaction { transaction -> Api.InputPeer? in
        return transaction.getPeer(peerId).flatMap(apiInputPeer)
    }
    |> castError(TranslationError.self)
    |> mapToSignal { inputPeer -> Signal<Void, TranslationError> in
        guard let inputPeer = inputPeer else {
            return .never()
        }
        
        var flags: Int32 = 0
        flags |= (1 << 0)
        
        let id: [Int32] = messageIds.map { $0.id }
        return account.network.request(Api.functions.messages.translateText(flags: flags, peer: inputPeer, id: id, text: nil, toLang: sgTranslationLangFix(toLang)))
        |> mapError { error -> TranslationError in
            if error.errorDescription.hasPrefix("FLOOD_WAIT") {
                return .limitExceeded
            } else if error.errorDescription == "MSG_ID_INVALID" {
                return .invalidMessageId
            } else if error.errorDescription == "INPUT_TEXT_EMPTY" {
                return .textIsEmpty
            } else if error.errorDescription == "INPUT_TEXT_TOO_LONG" {
                return .textTooLong
            } else if error.errorDescription == "TO_LANG_INVALID" {
                return .invalidLanguage
            } else {
                return .generic
            }
        }
        |> mapToSignal { result -> Signal<Void, TranslationError> in
            guard case let .translateResult(results) = result else {
                return .complete()
            }
            return account.postbox.transaction { transaction in
                var index = 0
                for result in results {
                    let messageId = messageIds[index]
                    if case let .textWithEntities(text, entities) = result {
                        let updatedAttribute: TranslationMessageAttribute = TranslationMessageAttribute(text: text, entities: messageTextEntitiesFromApiEntities(entities), toLang: toLang)
                        transaction.updateMessage(messageId, update: { currentMessage in
                            let storeForwardInfo = currentMessage.forwardInfo.flatMap(StoreMessageForwardInfo.init)
                            var attributes = currentMessage.attributes.filter { !($0 is TranslationMessageAttribute) }
                            
                            attributes.append(updatedAttribute)
                            
                            return .update(StoreMessage(id: currentMessage.id, globallyUniqueId: currentMessage.globallyUniqueId, groupingKey: currentMessage.groupingKey, threadId: currentMessage.threadId, timestamp: currentMessage.timestamp, flags: StoreMessageFlags(currentMessage.flags), tags: currentMessage.tags, globalTags: currentMessage.globalTags, localTags: currentMessage.localTags, forwardInfo: storeForwardInfo, authorId: currentMessage.author?.id, text: currentMessage.text, attributes: attributes, media: currentMessage.media))
                        })
                    }
                    index += 1
                }
            }
            |> castError(TranslationError.self)
        }
    }
}

func _internal_translateMessagesViaText(account: Account, messagesDict: [EngineMessage.Id: String], toLang: String, generateEntitiesFunction: @escaping (String) -> [MessageTextEntity]) -> Signal<Void, TranslationError> {
    var listOfSignals: [Signal<Void, TranslationError>] = []
    for (messageId, text) in messagesDict {
        listOfSignals.append(
            //                _internal_translate(network: account.network, text: text, toLang: toLang)
            //                |> mapToSignal { result -> Signal<Void, TranslationError> in
            //                guard let translatedText = result else {
            //                    return .complete()
            //                }
            gtranslate(text, toLang)
            |> mapError { _ -> TranslationError in
                return .generic
            }
            |> mapToSignal { translatedText -> Signal<Void, TranslationError> in
//                guard case let .result(translatedText) = result else {
//                    return .complete()
//                }
                return account.postbox.transaction { transaction in
                    transaction.updateMessage(messageId, update: { currentMessage in
                        let updatedAttribute: TranslationMessageAttribute = TranslationMessageAttribute(text: translatedText, entities: generateEntitiesFunction(translatedText), toLang: toLang)
                        let storeForwardInfo = currentMessage.forwardInfo.flatMap(StoreMessageForwardInfo.init)
                        var attributes = currentMessage.attributes.filter { !($0 is TranslationMessageAttribute) }

                        attributes.append(updatedAttribute)

                        return .update(StoreMessage(id: currentMessage.id, globallyUniqueId: currentMessage.globallyUniqueId, groupingKey: currentMessage.groupingKey, threadId: currentMessage.threadId, timestamp: currentMessage.timestamp, flags: StoreMessageFlags(currentMessage.flags), tags: currentMessage.tags, globalTags: currentMessage.globalTags, localTags: currentMessage.localTags, forwardInfo: storeForwardInfo, authorId: currentMessage.author?.id, text: currentMessage.text, attributes: attributes, media: currentMessage.media))
                    })
                }
                |> castError(TranslationError.self)
//                |> castError(TranslateFetchError.self)
            }
        )
    }
    return combineLatest(listOfSignals) |> map { _ in Void() }
}

func _internal_togglePeerMessagesTranslationHidden(account: Account, peerId: EnginePeer.Id, hidden: Bool) -> Signal<Never, NoError> {
    return account.postbox.transaction { transaction -> Api.InputPeer? in
        transaction.updatePeerCachedData(peerIds: Set([peerId]), update: { _, cachedData -> CachedPeerData? in
            if let cachedData = cachedData as? CachedUserData {
                var updatedFlags = cachedData.flags
                if hidden {
                    updatedFlags.insert(.translationHidden)
                } else {
                    updatedFlags.remove(.translationHidden)
                }
                return cachedData.withUpdatedFlags(updatedFlags)
            } else if let cachedData = cachedData as? CachedGroupData {
                var updatedFlags = cachedData.flags
                if hidden {
                    updatedFlags.insert(.translationHidden)
                } else {
                    updatedFlags.remove(.translationHidden)
                }
                return cachedData.withUpdatedFlags(updatedFlags)
            } else if let cachedData = cachedData as? CachedChannelData {
                var updatedFlags = cachedData.flags
                if hidden {
                    updatedFlags.insert(.translationHidden)
                } else {
                    updatedFlags.remove(.translationHidden)
                }
                return cachedData.withUpdatedFlags(updatedFlags)
            } else {
                return cachedData
            }
        })
        return transaction.getPeer(peerId).flatMap(apiInputPeer)
    }
    |> mapToSignal { inputPeer -> Signal<Never, NoError> in
        guard let inputPeer = inputPeer else {
            return .never()
        }
        var flags: Int32 = 0
        if hidden {
            flags |= (1 << 0)
        }
        
        return account.network.request(Api.functions.messages.togglePeerTranslations(flags: flags, peer: inputPeer))
        |> map(Optional.init)
        |> `catch` { _ -> Signal<Api.Bool?, NoError> in
            return .single(nil)
        }
        |> ignoreValues
    }
}

// TODO(swiftgram): Refactor
public struct TranslateRule: Codable {
    public let name: String
    public let pattern: String
    public let data_check: String
    public let match_group: Int
}

public func getTranslateUrl(_ message: String,_ toLang: String) -> String {
    let sanitizedMessage = message.replaceCharactersFromSet(characterSet:CharacterSet.newlines, replacementString: "<br>")

    var queryCharSet = NSCharacterSet.urlQueryAllowed
    queryCharSet.remove(charactersIn: "+&")
    return "https://translate.google.com/m?hl=en&tl=\(toLang)&sl=auto&q=\(sanitizedMessage.addingPercentEncoding(withAllowedCharacters: queryCharSet) ?? "")"
}

func prepareResultString(_ str: String) -> String {
    return str.htmlDecoded.replacingOccurrences(of: "<br>", with: "\n").replacingOccurrences(of: "< br>", with: "\n").replacingOccurrences(of: "<br >", with: "\n")
}

var regexCache: [String: NSRegularExpression] = [:]

public func parseTranslateResponse(_ data: String) -> String {
    do {
        let document = try SwiftSoup.parse(data)
        
        if let resultContainer = try document.select("div.result-container").first() {
            // new_mobile
            return prepareResultString(try resultContainer.text())
        } else if let tZero = try document.select("div.t0").first() {
            // old_mobile
            return prepareResultString(try tZero.text())
        }
    } catch Exception.Error(let type, let message) {
        #if DEBUG
        SGtrace("translate", what: "Translation parser failure, An error of type \(type) occurred: \(message)")
        #endif
        // print("Translation parser failure, An error of type \(type) occurred: \(message)")
    } catch {
        #if DEBUG
        SGtrace("translate", what: "Translation parser failure, An error occurred: \(error)")
        #endif
        // print("Translation parser failure, An error occurred: \(error)")
    }
    return ""
}

public func getGoogleLang(_ userLang: String) -> String {
    var lang = userLang
    let rawSuffix =  "-raw"
    if lang.hasSuffix(rawSuffix) {
        lang = String(lang.dropLast(rawSuffix.count))
    }
    lang = lang.lowercased()

    // Fallback To Google lang
    switch (lang) {
        case "zh-hans", "zh":
            return "zh-CN"
        case "zh-hant":
            return "zh-TW"
        case "he":
            return "iw"
        default:
            break
    }


    // Fix for pt-br and other regional langs
    // https://cloud.google.com/translate/docs/languages
    lang = lang.components(separatedBy: "-")[0].components(separatedBy: "_")[0]

    return lang
}


public enum TranslateFetchError {
    case network
}


let TranslateSessionConfiguration = URLSessionConfiguration.ephemeral

// Create a URLSession with the ephemeral configuration
let TranslateSession = URLSession(configuration: TranslateSessionConfiguration)

public func requestTranslateUrl(url: URL) -> Signal<String, TranslateFetchError> {
    return Signal { subscriber in
        let completed = Atomic<Bool>(value: false)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        // Set headers
        request.setValue("Mozilla/4.0 (compatible;MSIE 6.0;Windows NT 5.1;SV1;.NET CLR 1.1.4322;.NET CLR 2.0.50727;.NET CLR 3.0.04506.30)", forHTTPHeaderField: "User-Agent")
        let downloadTask = TranslateSession.dataTask(with: request, completionHandler: { data, response, error in
            let _ = completed.swap(true)
            if let response = response as? HTTPURLResponse {
                if response.statusCode == 200 {
                    if let data = data {
                        if let result = String(data: data, encoding: .utf8) {
                            subscriber.putNext(result)
                            subscriber.putCompletion()
                        } else {
                            subscriber.putError(.network)
                        }
                    } else {
//                        print("Empty data")
                        subscriber.putError(.network)
                    }
                } else {
//                    print("Non 200 status")
                    subscriber.putError(.network)
                }
            } else {
//                print("No response (??)")
                subscriber.putError(.network)
            }
        })
        downloadTask.resume()

        return ActionDisposable {
            if !completed.with({ $0 }) {
                downloadTask.cancel()
            }
        }
    }
}


public func gtranslate(_ text: String, _ toLang: String) -> Signal<String, TranslateFetchError> {
    return Signal { subscriber in
        let urlString = getTranslateUrl(text, getGoogleLang(toLang))
        let url = URL(string: urlString)!
        let translateSignal = requestTranslateUrl(url: url)
        var translateDisposable: Disposable? = nil

        translateDisposable = translateSignal.start(next: {
            translatedHtml in
            #if DEBUG
            let startTime = CFAbsoluteTimeGetCurrent()
            #endif
            let result = parseTranslateResponse(translatedHtml)
            #if DEBUG
            SGtrace("translate", what: "Translation parsed in \(CFAbsoluteTimeGetCurrent() - startTime)")
            #endif
            if result.isEmpty {
//                print("EMPTY RESULT")
                subscriber.putError(.network) // Fake
            } else {
                subscriber.putNext(result)
                subscriber.putCompletion()
            }

        }, error: { _ in
            subscriber.putError(.network)
        })

        return ActionDisposable {
            translateDisposable?.dispose()
        }
    }
}


extension String {
    var htmlDecoded: String {
        let attributedOptions: [NSAttributedString.DocumentReadingOptionKey : Any] = [
            NSAttributedString.DocumentReadingOptionKey.documentType : NSAttributedString.DocumentType.html,
            NSAttributedString.DocumentReadingOptionKey.characterEncoding : String.Encoding.utf8.rawValue
        ]

        let decoded = try? NSAttributedString(data: Data(utf8), options: attributedOptions, documentAttributes: nil).string
        return decoded ?? self
    }

    func replaceCharactersFromSet(characterSet: CharacterSet, replacementString: String = "") -> String {
        return components(separatedBy: characterSet).joined(separator: replacementString)
    }
}
