import Foundation
import BuildConfig

public struct SGConfig: Codable {
    public var apiUrl: String = "https://api.swiftgram.app"
    public var webappUrl: String = "https://my.swiftgram.app"
    public var botUsername: String = "SwiftgramBot"
}

private func parseSGConfig(_ jsonString: String) -> SGConfig {
    let jsonData = Data(jsonString.utf8)
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return (try? decoder.decode(SGConfig.self, from: jsonData)) ?? SGConfig()
}

private let baseAppBundleId = Bundle.main.bundleIdentifier!
private let buildConfig = BuildConfig(baseAppBundleId: baseAppBundleId)
public let SG_CONFIG: SGConfig = parseSGConfig(buildConfig.sgConfig)
public let SG_API_WEBAPP_URL_PARSED = URL(string: SG_CONFIG.webappUrl)!