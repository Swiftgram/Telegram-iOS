import Foundation
import Postbox
import SwiftSignalKit
import MtProtoKit

public func updateProxySettingsInteractively(accountManager: AccountManager<TelegramAccountManagerTypes>, _ f: @escaping (ProxySettings) -> ProxySettings) -> Signal<Bool, NoError> {
    return accountManager.transaction { transaction -> Bool in
        return updateProxySettingsInteractively(transaction: transaction, f)
    }
}

extension ProxyServerSettings {
    var mtProxySettings: MTSocksProxySettings {
        switch self.connection {
            case let .socks5(username, password):
                return MTSocksProxySettings(ip: self.host, port: UInt16(clamping: self.port), username: username, password: password, secret: nil)
            case let .mtp(secret):
                return MTSocksProxySettings(ip: self.host, port: UInt16(clamping: self.port), username: nil, password: nil, secret: secret)
            case .juicity:
                // Juicity runs a local SOCKS5 proxy. The actual SOCKS5 settings
                // (127.0.0.1:localPort) are set dynamically by JuicityProxyBridge
                // when the connection is activated. This is a placeholder.
                return MTSocksProxySettings(ip: "127.0.0.1", port: 0, username: nil, password: nil, secret: nil)
        }
    }

    /// Whether this proxy server uses the Juicity protocol.
    public var isJuicity: Bool {
        if case .juicity = self.connection {
            return true
        }
        return false
    }
}

public func updateProxySettingsInteractively(transaction: AccountManagerModifier<TelegramAccountManagerTypes>, _ f: @escaping (ProxySettings) -> ProxySettings) -> Bool {
    var hasChanges = false
    transaction.updateSharedData(SharedDataKeys.proxySettings, { current in
        let previous = current?.get(ProxySettings.self) ?? ProxySettings.defaultSettings
        let updated = f(previous)
        hasChanges = previous != updated
        return PreferencesEntry(updated)
    })
    return hasChanges
}
