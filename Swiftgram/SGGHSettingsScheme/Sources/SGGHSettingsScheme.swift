import Foundation

public struct SGGHSettings: Codable, Equatable {
    public let announcementsData: String?
    
    public static var defaultValue: SGGHSettings {
        return SGGHSettings(announcementsData: nil)
    }
}