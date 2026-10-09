import SensitiveContentAnalysis
import SwiftSignalKit

public enum ContentAnalysisError: Error {
    case generic(_ message: String)
}

public enum ContentAnalysisMediaType {
    case image
    case video
}

public func canAnalyzeMedia() -> Bool {
    if #available(iOS 17, *) {
        let analyzer = SCSensitivityAnalyzer()
        let policy = analyzer.analysisPolicy
        return policy != .disabled
    } else {
        return false
    }
}


public func analyzeMediaSignal(_ url: URL, mediaType: ContentAnalysisMediaType = .image) -> Signal<Bool, Error> {
    return Signal { subscriber in
        analyzeMedia(url: url, mediaType: mediaType, completion: { result, error in
            if let result = result {
                subscriber.putNext(result)
                subscriber.putCompletion()
            } else if let error = error {
                subscriber.putError(error)
            } else {
                subscriber.putError(ContentAnalysisError.generic("Unknown response"))
            }
        })
        
        return ActionDisposable {
        }
    }
}

private func analyzeMedia(url: URL, mediaType: ContentAnalysisMediaType, completion: @escaping (Bool?, Error?) -> Void) {
    if #available(iOS 17, *) {
        let analyzer = SCSensitivityAnalyzer()
        switch mediaType {
        case .image:
            analyzer.analyzeImage(at: url) { analysisResult, analysisError in
                completion(analysisResult?.isSensitive, analysisError)
            }
        case .video:
            Task {
                do {
                    let handler = analyzer.videoAnalysis(forFileAt: url)
                    let response = try await handler.hasSensitiveContent()
                    completion(response.isSensitive, nil)
                } catch {
                    completion(nil, error)
                }
            }
        }
    } else {
        completion(false, nil)
    }
}
