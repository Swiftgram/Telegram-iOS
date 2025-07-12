import Foundation
import SGLogging
import SGGHSettingsScheme
import AccountContext
import TelegramCore


public func updateSGGHSettingsInteractivelly(context: AccountContext) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let locale = presentationData.strings.baseLanguageCode
    let _ = Task {
        do {
            let settings = try await fetchSGGHSettings(locale: locale)
            await (context.account.postbox.transaction { transaction in
                updateAppConfiguration(transaction: transaction, { configuration -> AppConfiguration in
                    var configuration = configuration
                    configuration.sgGHSettings = settings
                    return configuration
                })
            }).task
        } catch {
            return
        }

    }
}


let maxRetries: Int = 3

enum SGGHFetchError: Error {
    case invalidURL
    case notFound
    case fetchFailed(statusCode: Int)
    case decodingFailed
}

func fetchSGGHSettings(locale: String) async throws -> SGGHSettings {
    let baseURL = "https://raw.githubusercontent.com/Swiftgram/settings/refs/heads/main"
    var candidates = []
    if let buildNumber = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
        if locale != "en" {
            candidates.append("\(buildNumber)_\(locale).json")
        }
        candidates.append("\(buildNumber).json")
    }
    if locale != "en" {
        candidates.append("latest_\(locale).json")
    }
    candidates.append("latest.json")
    
    for candidate in candidates {
        let urlString = "\(baseURL)/\(candidate)"
        guard let url = URL(string: urlString) else {
            SGLogger.shared.log("SGGHSettings", "Fetch failed for \(candidate). Invalid URL: \(urlString)")
            continue
        }

        var lastError: Error?
        for attempt in 1...maxRetries {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let httpResponse = response as? HTTPURLResponse else {
                    SGLogger.shared.log("SGGHSettings", "Fetch failed for \(candidate). Invalid response type: \(response)")
                    throw SGGHFetchError.fetchFailed(statusCode: -1)
                }

                switch httpResponse.statusCode {
                case 200:
                    do {
                        let settings = try JSONDecoder().decode(SGGHSettings.self, from: data)
                        SGLogger.shared.log("SGGHSettings", "Fetched \(candidate). \(settings)")
                        return settings
                    } catch {
                        SGLogger.shared.log("SGGHSettings", "Failed to decode \(candidate). Error: \(error)")
                        throw SGGHFetchError.decodingFailed
                    }
                case 404:
                    break // Try the next fallback
                default:
                    SGLogger.shared.log("SGGHSettings", "Fetch failed for \(candidate). Status code: \(httpResponse.statusCode)")
                    throw SGGHFetchError.fetchFailed(statusCode: httpResponse.statusCode)
                }
            } catch {
                lastError = error
                if attempt == maxRetries {
                    break
                }
                try await Task.sleep(seconds: attempt * 2.0)
            }
        }
    }

    throw SGGHFetchError.fetchFailed(statusCode: -1)
}


extension Task {
    static func sleep(seconds: Double) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}