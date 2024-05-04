import Foundation
import SwiftSignalKit

import SGConfig
import SGLogging
import SGSimpleSettings
import SGWebAppExtensions
import SGWebSettingsScheme
import SGRequests
import SGRegDateScheme

private let API_VERSION: String = "0"

private func buildApiUrl(_ endpoint: String) -> String {
    return "\(SG_CONFIG.apiUrl)/v\(API_VERSION)/\(endpoint)"
}

public let SG_API_AUTHORIZATION_HEADER = "Authorization"
public let SG_API_DEVICE_TOKEN_HEADER = "Device-Token"

private enum HTTPRequestError {
    case network
}

public enum SGAPIError {
    case generic(String? = nil)
}

public func getSGSettings(token: String) -> Signal<SGWebSettings, SGAPIError> {
    return Signal { subscriber in

        let url = URL(string: buildApiUrl("settings"))!
        let headers = [SG_API_AUTHORIZATION_HEADER: "Token \(token)"]
        let completed = Atomic<Bool>(value: false)
        
        var request = URLRequest(url: url)
        headers.forEach { key, value in
            request.addValue(value, forHTTPHeaderField: key)
        }
        
        let downloadSignal = requestsCustom(request: request).start(next: { data, urlResponse in
            let _ = completed.swap(true)
            do {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let settings = try decoder.decode(SGWebSettings.self, from: data)
                subscriber.putNext(settings)
                subscriber.putCompletion()
            } catch {
                subscriber.putError(.generic("Can't parse user settings: \(error). Response: \(String(data: data, encoding: .utf8) ?? "")"))
            }
        }, error: { error in
            subscriber.putError(.generic("Error requesting user settings: \(String(describing: error))"))
        })
        
        return ActionDisposable {
            if !completed.with({ $0 }) {
                downloadSignal.dispose()
            }
        }
    }
}



public func postSGSettings(token: String, data: [String:Any]) -> Signal<Void, SGAPIError> {
    return Signal { subscriber in

        let url = URL(string: buildApiUrl("settings"))!
        let headers = [SG_API_AUTHORIZATION_HEADER: "Token \(token)"]
        let completed = Atomic<Bool>(value: false)
        
        var request = URLRequest(url: url)
        headers.forEach { key, value in
            request.addValue(value, forHTTPHeaderField: key)
        }
        request.httpMethod = "POST"
        
        let jsonData = try? JSONSerialization.data(withJSONObject: data, options: [])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        
        let dataSignal = requestsCustom(request: request).start(next: { data, urlResponse in
            let _ = completed.swap(true)
            
            if let httpResponse = urlResponse as? HTTPURLResponse {
                switch httpResponse.statusCode {
                case 200...299:
                    subscriber.putCompletion()
                default:
                    subscriber.putError(.generic("Can't update settings: \(httpResponse.statusCode). Response: \(String(data: data, encoding: .utf8) ?? "")"))
                }
            } else {
                subscriber.putError(.generic("Not an HTTP response: \(String(describing: urlResponse))"))
            }
        }, error: { error in
            subscriber.putError(.generic("Error updating settings: \(String(describing: error))"))
        })
        
        return ActionDisposable {
            if !completed.with({ $0 }) {
                dataSignal.dispose()
            }
        }
    }
}

public func getSGAPIRegDate(token: String, deviceToken: String, userId: Int64) -> Signal<RegDate, SGAPIError> {
    return Signal { subscriber in

        let url = URL(string: buildApiUrl("regdate/\(userId)"))!
        let headers = [
            SG_API_AUTHORIZATION_HEADER: "Token \(token)",
            SG_API_DEVICE_TOKEN_HEADER: deviceToken
        ]
        let completed = Atomic<Bool>(value: false)
        
        var request = URLRequest(url: url)
        headers.forEach { key, value in
            request.addValue(value, forHTTPHeaderField: key)
        }
        request.timeoutInterval = 10
        
        let downloadSignal = requestsCustom(request: request).start(next: { data, urlResponse in
            let _ = completed.swap(true)
            do {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let settings = try decoder.decode(RegDate.self, from: data)
                subscriber.putNext(settings)
                subscriber.putCompletion()
            } catch {
                subscriber.putError(.generic("Can't parse regDate: \(error). Response: \(String(data: data, encoding: .utf8) ?? "")"))
            }
        }, error: { error in
            subscriber.putError(.generic("Error requesting regDate: \(String(describing: error))"))
        })
        
        return ActionDisposable {
            if !completed.with({ $0 }) {
                downloadSignal.dispose()
            }
        }
    }
}
