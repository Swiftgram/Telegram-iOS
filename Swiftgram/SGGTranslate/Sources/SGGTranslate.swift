import Foundation
import SwiftSignalKit

public enum TranslateFetchError {
    case network
}

private let sgTranslateSessionConfiguration: URLSessionConfiguration = .ephemeral
private let sgTranslateSession: URLSession = URLSession(configuration: sgTranslateSessionConfiguration)

public func getTranslateUrl(_ message: String, _ toLang: String) -> String {
    let sanitizedMessage: String = message
    var queryCharSet: CharacterSet = .urlQueryAllowed
    queryCharSet.remove(charactersIn: "+&")
    var url = "https://translate.goo"
    url += "gleapis.com/transl"
    url += "ate_a/sing"
    url += "le?client=gtx&sl=auto&tl=\(toLang)"
    url += "&dt=t&ie=UTF-8&oe=UTF-8&otf=1&ssel=0&tsel=0&kc=7&dt=at&dt=bd&dt=ex&dt=ld&dt=md&dt=qca&dt=rw&dt=rm&dt=ss&q="
    url += sanitizedMessage.addingPercentEncoding(withAllowedCharacters: queryCharSet) ?? ""
    return url
}

public func parseTranslateResponse(_ data: String) -> String {
    guard let responseData: Data = data.data(using: .utf8),
          let response: [Any] = try? JSONSerialization.jsonObject(with: responseData) as? [Any],
          let segments: [Any] = response.first as? [Any] else {
        return ""
    }
    return segments.compactMap { segment in
        return (segment as? [Any])?.first as? String
    }.joined()
}

public func getGTranslateLang(_ userLang: String) -> String {
    var lang: String = userLang
    let rawSuffix: String = "-raw"
    if lang.hasSuffix(rawSuffix) {
        lang = String(lang.dropLast(rawSuffix.count))
    }
    lang = lang.lowercased()

    switch lang {
    case "zh-hans", "zh":
        return "zh-CN"
    case "zh-hant":
        return "zh-TW"
    case "he":
        return "iw"
    default:
        break
    }

    lang = lang.components(separatedBy: "-")[0].components(separatedBy: "_")[0]

    return lang
}

public func requestTranslateUrl(url: URL) -> Signal<String, TranslateFetchError> {
    return Signal { subscriber in
        let completed: Atomic<Bool> = Atomic(value: false)
        var request: URLRequest = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(sgGTranslateUserAgent(), forHTTPHeaderField: "User-Agent")
        let downloadTask: URLSessionDataTask = sgTranslateSession.dataTask(with: request, completionHandler: { data, response, _ in
            let _ = completed.swap(true)
            if let response: HTTPURLResponse = response as? HTTPURLResponse {
                if response.statusCode == 200 {
                    if let data: Data = data {
                        if let result: String = String(data: data, encoding: .utf8) {
                            subscriber.putNext(result)
                            subscriber.putCompletion()
                        } else {
                            subscriber.putError(.network)
                        }
                    } else {
                        subscriber.putError(.network)
                    }
                } else {
                    subscriber.putError(.network)
                }
            } else {
                subscriber.putError(.network)
            }
        })
        downloadTask.resume()

        return ActionDisposable {
            if !completed.with({ $0 }) {
                downloadTask.cancel()
            }
        }
    }
}

private func sgGTranslateUserAgent() -> String {
    let userAgents = [
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_4_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.4 Mobile/15E148 Safari/604.1",
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36"
    ]
    return userAgents.randomElement() ?? userAgents[0]
}

public func gtranslate(_ text: String, _ toLang: String) -> Signal<String, TranslateFetchError> {
    let lines: [String] = text.components(separatedBy: "\n")

    let translationSignals: [Signal<String, TranslateFetchError>] = lines.map { rawLine in
        let leadingWhitespace: Substring = rawLine.prefix { $0.isWhitespace }
        let core: String = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

        if core.isEmpty {
            return .single(rawLine)
        }

        return gtranslateSentence(core, toLang)
        |> map { translatedCore in
            return String(leadingWhitespace) + translatedCore
        }
    }

    return combineLatest(translationSignals)
    |> map { results in
        let joined: String = results.joined(separator: "\n")
        return joined.isEmpty ? text : joined
    }
}

public func gtranslateSentence(_ text: String, _ toLang: String) -> Signal<String, TranslateFetchError> {
    return Signal { subscriber in
        let urlString: String = getTranslateUrl(text, getGTranslateLang(toLang))
        let url: URL = URL(string: urlString)!
        let translateSignal: Signal<String, TranslateFetchError> = requestTranslateUrl(url: url)
        var translateDisposable: Disposable?

        translateDisposable = translateSignal.start(next: { translatedHtml in
            let result: String = parseTranslateResponse(translatedHtml)
            if result.isEmpty {
                subscriber.putError(.network)
            } else {
                subscriber.putNext(result)
                subscriber.putCompletion()
            }
        }, error: { _ in
            subscriber.putError(.network)
        })

        return ActionDisposable {
            translateDisposable?.dispose()
        }
    }
}

public func gtranslateSplitTextBySentences(_ text: String, maxChunkLength: Int = 1500) -> [String] {
    if text.count <= maxChunkLength {
        return [text]
    }
    var chunks: [String] = []
    var currentChunk: String = ""

    text.enumerateSubstrings(in: text.startIndex ..< text.endIndex, options: .bySentences) { substring, _, _, _ in
        guard let sentence: String = substring else {
            return
        }

        if currentChunk.count + sentence.count + 1 < maxChunkLength {
            currentChunk += sentence + " "
        } else {
            if !currentChunk.isEmpty {
                chunks.append(currentChunk.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            currentChunk = sentence + " "
        }
    }

    if !currentChunk.isEmpty {
        chunks.append(currentChunk.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    return chunks
}
