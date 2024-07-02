import Foundation

import SGAPIToken
import SGAPI
import SGLogging

import AccountContext

import SGSimpleSettings
import TelegramCore

public func updateSGWebSettingsInteractivelly(context: AccountContext) {
    let _ = getSGApiToken(context: context).startStandalone(next: { token in
        let _ = getSGSettings(token: token).startStandalone(next: { webSettings in
            SGLogger.shared.log("SGAPI", "New SGWebSettings for id \(context.account.peerId.id._internalGetInt64Value()): \(webSettings) ")
            SGSimpleSettings.shared.canUseStealthMode = webSettings.global.storiesAvailable
            let _ = (context.account.postbox.transaction { transaction in
                updateAppConfiguration(transaction: transaction, { configuration -> AppConfiguration in
                    var configuration = configuration
                    configuration.sgWebSettings = webSettings
                    return configuration
                })
            }).startStandalone()
        }, error: { e in
            if case let .generic(errorMessage) = e, let errorMessage = errorMessage {
                SGLogger.shared.log("SGAPI", errorMessage)
            }
        })
    }, error: { e in
        if case let .generic(errorMessage) = e, let errorMessage = errorMessage {
            SGLogger.shared.log("SGAPI", errorMessage)
        }
    })
}


public func postSGWebSettingsInteractivelly(context: AccountContext, data: [String: Any]) {
    let _ = getSGApiToken(context: context).startStandalone(next: { token in
        let _ = postSGSettings(token: token, data: data).startStandalone(error: { e in
            if case let .generic(errorMessage) = e, let errorMessage = errorMessage {
                SGLogger.shared.log("SGAPI", errorMessage)
            }
        })
    }, error: { e in
        if case let .generic(errorMessage) = e, let errorMessage = errorMessage {
            SGLogger.shared.log("SGAPI", errorMessage)
        }
    })
}
