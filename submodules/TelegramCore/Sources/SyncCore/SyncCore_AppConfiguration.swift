import Foundation
import Postbox
import SGWebSettingsScheme

public struct AppConfiguration: Codable, Equatable {
    // MARK: Swiftgram
    public var sgWebSettings: SGWebSettings
    
    public var data: JSON?
    public var hash: Int32
    
    public static var defaultValue: AppConfiguration {
        return AppConfiguration(sgWebSettings: SGWebSettings.defaultValue, data: nil, hash: 0)
    }
    
    init(sgWebSettings: SGWebSettings, data: JSON?, hash: Int32) {
        self.sgWebSettings = sgWebSettings
        self.data = data
        self.hash = hash
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StringCodingKey.self)
        
        self.sgWebSettings = (try container.decodeIfPresent(SGWebSettings.self, forKey: "sg")) ?? SGWebSettings.defaultValue
        self.data = try container.decodeIfPresent(JSON.self, forKey: "data")
        self.hash = (try container.decodeIfPresent(Int32.self, forKey: "storedHash")) ?? 0
    }

    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)
        
        try container.encode(self.sgWebSettings, forKey: "sg")
        try container.encodeIfPresent(self.data, forKey: "data")
        try container.encode(self.hash, forKey: "storedHash")
    }
}
