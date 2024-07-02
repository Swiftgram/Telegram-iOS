import Foundation
import TelegramCore
import SwiftSignalKit

public struct CallListSettings: Codable, Equatable {
    public var showContactsTab: Bool
    public var _showTab: Bool?
    public var defaultShowTab: Bool?
    
    public static var defaultSettings: CallListSettings {
        return CallListSettings(showContactsTab: true, showTab: false)
    }
    
    public var showTab: Bool {
        get {
            if let value = self._showTab {
                return value
            } else if let defaultValue = self.defaultShowTab {
                return defaultValue
            } else {
                return CallListSettings.defaultSettings.showTab
            }
        } set {
            self._showTab = newValue
        }
    }
    
    public init(showContactsTab: Bool, showTab: Bool) {
        self.showContactsTab = showContactsTab
        self._showTab = showTab
    }
    
    public init(showContactsTab: Bool, showTab: Bool?, defaultShowTab: Bool?) {
        self._showTab = showTab
        self.showContactsTab = showContactsTab
        self.defaultShowTab = defaultShowTab
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StringCodingKey.self)
        
        self.showContactsTab = (try container.decode(Int32.self, forKey: "showContactsTab")) != 0
        if let alternativeDefaultValue = try container.decodeIfPresent(Int32.self, forKey: "defaultShowTab") {
            self.defaultShowTab = alternativeDefaultValue != 0
        }
        if let value = try container.decodeIfPresent(Int32.self, forKey: "showTab") {
            self._showTab = value != 0
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)
        
        try container.encode((self.showContactsTab ? 1 : 0) as Int32, forKey: "showContactsTab")
        
        if let defaultShowTab = self.defaultShowTab {
            try container.encode((defaultShowTab ? 1 : 0) as Int32, forKey: "defaultShowTab")
        } else {
            try container.encodeNil(forKey: "defaultShowTab")
        }
        if let showTab = self._showTab {
            try container.encode((showTab ? 1 : 0) as Int32, forKey: "showTab")
        } else {
            try container.encodeNil(forKey: "showTab")
        }
    }
    
    public static func ==(lhs: CallListSettings, rhs: CallListSettings) -> Bool {
        return lhs.showContactsTab == rhs.showContactsTab && lhs._showTab == rhs._showTab && lhs.defaultShowTab == rhs.defaultShowTab
    }
    
    public func withUpdatedShowTab(_ showTab: Bool) -> CallListSettings {
        return CallListSettings(showContactsTab: self.showContactsTab, showTab: showTab, defaultShowTab: self.defaultShowTab)
    }
    
    public func withUpdatedShowContactsTab(_ showContactsTab: Bool) -> CallListSettings {
        return CallListSettings(showContactsTab: showContactsTab, showTab: self.showTab, defaultShowTab: self.defaultShowTab)
    }
}

public func updateCallListSettingsInteractively(accountManager: AccountManager<TelegramAccountManagerTypes>, _ f: @escaping (CallListSettings) -> CallListSettings) -> Signal<Void, NoError> {
    return accountManager.transaction { transaction -> Void in
        transaction.updateSharedData(ApplicationSpecificSharedDataKeys.callListSettings, { entry in
            let currentSettings: CallListSettings
            if let entry = entry?.get(CallListSettings.self) {
                currentSettings = entry
            } else {
                currentSettings = CallListSettings.defaultSettings
            }
            return SharedPreferencesEntry(f(currentSettings))
        })
    }
}
