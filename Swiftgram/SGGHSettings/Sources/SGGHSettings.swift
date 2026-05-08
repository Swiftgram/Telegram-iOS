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
            let _ = await (context.account.postbox.transaction { transaction in
                updateAppConfiguration(transaction: transaction, { configuration -> AppConfiguration in
                    var configuration = configuration
                    configuration.sgGHSettings = settings
                    return configuration
                })
            }).task()
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
    var candidates: [String] = []
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

    var lastError: Error?
    for candidate in candidates {
        let urlString = "\(baseURL)/\(candidate)"
        guard let url = URL(string: urlString) else {
            SGLogger.shared.log("SGGHSettings", "[0] Fetch failed for \(candidate). Invalid URL: \(urlString)")
            continue
        }

        attemptsOuter: for attempt in 1...maxRetries {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let httpResponse = response as? HTTPURLResponse else {
                    SGLogger.shared.log("SGGHSettings", "[\(attempt)] Fetch failed for \(candidate). Invalid response type: \(response)")
                    throw SGGHFetchError.fetchFailed(statusCode: -1)
                }

                switch httpResponse.statusCode {
                case 200:
                    do {
                        let jsonDecoder = JSONDecoder()
                        jsonDecoder.keyDecodingStrategy = .convertFromSnakeCase
                        let settings = try jsonDecoder.decode(SGGHSettings.self, from: data)
                        SGLogger.shared.log("SGGHSettings", "[\(attempt)] Fetched \(candidate): \(settings)")
                        return settings
                    } catch {
                        SGLogger.shared.log("SGGHSettings", "[\(attempt)] Failed to decode \(candidate): \(error)")
                        throw SGGHFetchError.decodingFailed
                    }
                case 404:
                    SGLogger.shared.log("SGGHSettings", "[\(attempt)] Not found \(candidate) on the remote.")
                    break attemptsOuter
                default:
                    SGLogger.shared.log("SGGHSettings", "[\(attempt)] Fetch failed for \(candidate), status code: \(httpResponse.statusCode)")
                    throw SGGHFetchError.fetchFailed(statusCode: httpResponse.statusCode)
                }
            } catch {
                lastError = error
                if attempt == maxRetries {
                    break
                }
                try await Task.sleep(nanoseconds: UInt64(attempt * 2 * 1_000_000_000))
            }
        }
    }

    SGLogger.shared.log("SGGHSettings", "All attempts failed. Last error: \(String(describing: lastError))")
    throw SGGHFetchError.fetchFailed(statusCode: -1)
}
