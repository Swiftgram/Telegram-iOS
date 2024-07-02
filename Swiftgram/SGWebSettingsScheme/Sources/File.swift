import Foundation

public struct SGWebSettings: Codable, Equatable {
    public let global: SGGlobalSettings
    public let user: SGUserSettings
    
    public static var defaultValue: SGWebSettings {
        return SGWebSettings(global: SGGlobalSettings(ytPip: true, qrLogin: true, storiesAvailable: false, canViewMessages: true, canEditSettings: false, canShowTelescope: false, announcementsData: nil, regdateFormat: "month", botMonkeys: [], forceReasons: [], unforceReasons: [], paymentsEnabled: true, duckyAppIconAvailable: true, canGrant: false, proSupportUrl: nil), user: SGUserSettings(contentReasons: [], canSendTelescope: false, canBuyInBeta: true))
    }
}

public struct SGGlobalSettings: Codable, Equatable {
    public let ytPip: Bool
    public let qrLogin: Bool
    public let storiesAvailable: Bool
    public let canViewMessages: Bool
    public let canEditSettings: Bool
    public let canShowTelescope: Bool
    public let announcementsData: String?
    public let regdateFormat: String
    public let botMonkeys: [SGBotMonkeys]
    public let forceReasons: [Int64]
    public let unforceReasons: [Int64]
    public let paymentsEnabled: Bool
    public let duckyAppIconAvailable: Bool
    public let canGrant: Bool
    public let proSupportUrl: String?
}

public struct SGBotMonkeys: Codable, Equatable {
    public let botId: Int64
    public let src: String
    public let enable: String
    public let disable: String
}


public struct SGUserSettings: Codable, Equatable {
    public let contentReasons: [String]
    public let canSendTelescope: Bool
    public let canBuyInBeta: Bool
}


public extension SGUserSettings {
    func expandedContentReasons() -> [String] {
        return contentReasons.compactMap { base64String in
            guard let data = Data(base64Encoded: base64String),
                  let decodedString = String(data: data, encoding: .utf8) else {
                return nil
            }
            return decodedString
        }
    }
}
