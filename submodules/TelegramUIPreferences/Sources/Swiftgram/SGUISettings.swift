import Foundation
import SwiftSignalKit
import TelegramCore

public struct SGUISettings: Equatable, Codable {
    public var hideStories: Bool
    public var showProfileId: Bool
    public var warnOnStoriesOpen: Bool
    public var sendWithReturnKey: Bool
    
    public static var `default`: SGUISettings {
        return SGUISettings(hideStories: false, showProfileId: true, warnOnStoriesOpen: false, sendWithReturnKey: false)
    }
    
    public init(hideStories: Bool, showProfileId: Bool, warnOnStoriesOpen: Bool, sendWithReturnKey: Bool) {
        self.hideStories = hideStories
        self.showProfileId = showProfileId
        self.warnOnStoriesOpen = warnOnStoriesOpen
        self.sendWithReturnKey = sendWithReturnKey
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StringCodingKey.self)

        self.hideStories = (try container.decode(Int32.self, forKey: "hideStories")) != 0
        self.showProfileId = (try container.decode(Int32.self, forKey: "showProfileId")) != 0
        self.warnOnStoriesOpen = (try container.decode(Int32.self, forKey: "warnOnStoriesOpen")) != 0
        self.sendWithReturnKey = (try container.decode(Int32.self, forKey: "sendWithReturnKey")) != 0
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)

        try container.encode((self.hideStories ? 1 : 0) as Int32, forKey: "hideStories")
        try container.encode((self.showProfileId ? 1 : 0) as Int32, forKey: "showProfileId")
        try container.encode((self.warnOnStoriesOpen ? 1 : 0) as Int32, forKey: "warnOnStoriesOpen")
        try container.encode((self.sendWithReturnKey ? 1 : 0) as Int32, forKey: "sendWithReturnKey")
    }
}

public func updateSGUISettings(engine: TelegramEngine, _ f: @escaping (SGUISettings) -> SGUISettings) -> Signal<Never, NoError> {
    return engine.preferences.update(id: ApplicationSpecificPreferencesKeys.SGUISettings, { entry in
        let currentSettings: SGUISettings
        if let entry = entry?.get(SGUISettings.self) {
            currentSettings = entry
        } else {
            currentSettings = .default
        }
        return SharedPreferencesEntry(f(currentSettings))
    })
}
