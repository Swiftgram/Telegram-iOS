import Foundation
import SwiftSignalKit
import SwiftSoup

public enum TranslateFetchError {
    case network
}

private let sgTranslateSessionConfiguration: URLSessionConfiguration = .ephemeral
private let sgTranslateSession: URLSession = URLSession(configuration: sgTranslateSessionConfiguration)

public func getTranslateUrl(_ message: String, _ toLang: String) -> String {
    let sanitizedMessage: String = message
    var queryCharSet: CharacterSet = .urlQueryAllowed
    queryCharSet.remove(charactersIn: "+&")
    return "https://translate.google.com/m?hl=en&tl=\(toLang)&sl=auto&q=\(sanitizedMessage.addingPercentEncoding(withAllowedCharacters: queryCharSet) ?? "")"
}

private func prepareResultString(_ str: String) -> String {
    return str
}

public func parseTranslateResponse(_ data: String) -> String {
    do {
        let document: Document = try SwiftSoup.parse(data)
        if let resultContainer: Element = try document.select("div.result-container").first() {
            return prepareResultString(try resultContainer.text())
        } else if let tZero: Element = try document.select("div.t0").first() {
            return prepareResultString(try tZero.text())
        }
    } catch {
    }
    return ""
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
        request.setValue("Mozilla/4.0 (compatible;MSIE 6.0;Windows NT 5.1;SV1;.NET CLR 1.1.4322;.NET CLR 2.0.50727;.NET CLR 3.0.04506.30)", forHTTPHeaderField: "User-Agent")
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
