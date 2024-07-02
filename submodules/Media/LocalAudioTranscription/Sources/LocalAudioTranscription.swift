import Foundation
import SwiftSignalKit
import Speech

private var sharedRecognizers: [String: NSObject] = [:]

private struct TranscriptionResult {
    var text: String
    var confidence: Float
    var isFinal: Bool
    var locale: String
}

private func transcribeAudio(path: String, locale: String) -> Signal<TranscriptionResult?, NoError> {
    return Signal { subscriber in
        let disposable = MetaDisposable()
        
        if #available(iOS 13.0, *) {
            SFSpeechRecognizer.requestAuthorization { status in
                Queue.mainQueue().async {
                    switch status {
                    case .notDetermined:
                        subscriber.putNext(nil)
                        subscriber.putCompletion()
                    case .restricted:
                        subscriber.putNext(nil)
                        subscriber.putCompletion()
                    case .denied:
                        subscriber.putNext(nil)
                        subscriber.putCompletion()
                    case .authorized:
                        let speechRecognizer: SFSpeechRecognizer
                        if let sharedRecognizer = sharedRecognizers[locale] as? SFSpeechRecognizer {
                            speechRecognizer = sharedRecognizer
                        } else {
                            guard let speechRecognizerValue = SFSpeechRecognizer(locale: Locale(identifier: locale)), speechRecognizerValue.isAvailable else {
                                subscriber.putNext(nil)
                                subscriber.putCompletion()
                                
                                return
                            }
                            speechRecognizerValue.defaultTaskHint = .dictation
                            sharedRecognizers[locale] = speechRecognizerValue
                            speechRecognizer = speechRecognizerValue
                            
                            if locale == "en-US" {
                                speechRecognizer.supportsOnDeviceRecognition = true
                            } else {
                                speechRecognizer.supportsOnDeviceRecognition = false
                            }
                            speechRecognizer.supportsOnDeviceRecognition = true
                        }
                        speechRecognizer.defaultTaskHint = .dictation
                        
                        let tempFilePath = NSTemporaryDirectory() + "/\(UInt64.random(in: 0 ... UInt64.max)).m4a"
                        let _ = try? FileManager.default.copyItem(atPath: path, toPath: tempFilePath)
                        
                        let request = SFSpeechURLRecognitionRequest(url: URL(fileURLWithPath: tempFilePath))
                        if #available(iOS 16.0, *) {
                            request.addsPunctuation = true
                        }
                        request.requiresOnDeviceRecognition = speechRecognizer.supportsOnDeviceRecognition
                        request.shouldReportPartialResults = false
                        
                        let task = speechRecognizer.recognitionTask(with: request, resultHandler: { result, error in
                            if let result = result {
                                var confidence: Float = 0.0
                                for segment in result.bestTranscription.segments {
                                    confidence += segment.confidence
                                }
                                confidence /= Float(result.bestTranscription.segments.count)
                                subscriber.putNext(TranscriptionResult(text: result.bestTranscription.formattedString, confidence: confidence, isFinal: result.isFinal, locale: locale))
                                
                                if result.isFinal {
                                    subscriber.putCompletion()
                                }
                            } else {
                                print("transcribeAudio: locale: \(locale), error: \(String(describing: error))")
                                
                                subscriber.putNext(nil)
                                subscriber.putCompletion()
                            }
                        })
                        
                        disposable.set(ActionDisposable {
                            task.cancel()
                        })
                    @unknown default:
                        subscriber.putNext(nil)
                        subscriber.putCompletion()
                    }
                }
            }
        } else {
            subscriber.putNext(nil)
            subscriber.putCompletion()
        }
        
        return disposable
    }
    |> runOn(.mainQueue())
}

public struct LocallyTranscribedAudio {
    public var text: String
    public var isFinal: Bool
}

public func transcribeAudio(path: String, appLocale: String) -> Signal<LocallyTranscribedAudio?, NoError> {
    var signals: [Signal<TranscriptionResult?, NoError>] = []
    let locales: [String] = [appLocale]
    // Device can effectivelly transcribe only one language at a time. So it will be wise to run language recognition once for each popular language, check the confidence, start over with most confident language and output something it has already generated
//    if !locales.contains(Locale.current.identifier) {
//        locales.append(Locale.current.identifier)
//    }
//    if locales.isEmpty {
//        locales.append("en-US")
//    }
    // Dictionary to hold accumulated transcriptions and confidences for each locale
    var accumulatedTranscription: [String: (confidence: Float, text: [String])] = [:]
    for locale in locales {
        signals.append(transcribeAudio(path: path, locale: locale))
    }
    // We need to combine results per-language and compare their total confidence, (instead of outputting everything we have to the signal)
    // return the one with the most confidence
    let resultSignal: Signal<[TranscriptionResult?], NoError> = signals.reduce(.single([])) { (accumulator, signal) in
        return accumulator
            |> mapToSignal { results in
                return signal
                    |> map { next in
                        return results + [next]
                    }
            }
    }

    
    return resultSignal
    |> map { results -> LocallyTranscribedAudio? in
        for result in results {
            if let result = result {
                var result = result
                if result.text.isEmpty {
                    result.text = "..."
                }
                if var existing = accumulatedTranscription[result.locale] {
                    existing.text.append(result.text)
                    existing.confidence += result.confidence
                    accumulatedTranscription[result.locale] = existing
                } else {
                    accumulatedTranscription[result.locale] = (result.confidence, [result.text])
                }
            }
        }
        
        // Find the locale with the highest accumulated confidence
        guard let bestLocale = accumulatedTranscription.max(by: { $0.value.confidence < $1.value.confidence }) else {
            return nil
        }
        
        let combinedText = bestLocale.value.text.joined(separator: ". ")
        // Assume 'isFinal' is true if the last result in 'results' is final. Adjust if needed.
        let isFinal = results.compactMap({ $0 }).last?.isFinal ?? false
        return LocallyTranscribedAudio(text: combinedText, isFinal: isFinal)
    }

}
