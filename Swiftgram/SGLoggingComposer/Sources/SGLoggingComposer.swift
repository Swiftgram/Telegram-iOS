import Foundation
import SGLogging
import SwiftSignalKit


extension SGLogger {
    public func collectLogs(prefix: String? = nil) -> Signal<[(String, String)], NoError> {
        return Signal { subscriber in
            self.queue.async {
                let logsPath: String
                if let prefix = prefix {
                    logsPath = self.rootPath + prefix
                } else {
                    logsPath = self.basePath
                }
                
                var result: [(Date, String, String)] = []
                if let files = try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: logsPath), includingPropertiesForKeys: [URLResourceKey.creationDateKey], options: []) {
                    for url in files {
                        if url.lastPathComponent.hasPrefix("log-") {
                            if let creationDate = (try? url.resourceValues(forKeys: Set([.creationDateKey])))?.creationDate {
                                result.append((creationDate, url.lastPathComponent, url.path))
                            }
                        }
                    }
                }
                result.sort(by: { $0.0 < $1.0 })
                subscriber.putNext(result.map { ($0.1, $0.2) })
                subscriber.putCompletion()
            }
            
            return EmptyDisposable
        }
    }
    
    public func collectLogs(basePath: String) -> Signal<[(String, String)], NoError> {
        return Signal { subscriber in
            self.queue.async {
                let logsPath: String = basePath
                
                var result: [(Date, String, String)] = []
                if let files = try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: logsPath), includingPropertiesForKeys: [URLResourceKey.creationDateKey], options: []) {
                    for url in files {
                        if url.lastPathComponent.hasPrefix("log-") {
                            if let creationDate = (try? url.resourceValues(forKeys: Set([.creationDateKey])))?.creationDate {
                                result.append((creationDate, url.lastPathComponent, url.path))
                            }
                        }
                    }
                }
                result.sort(by: { $0.0 < $1.0 })
                subscriber.putNext(result.map { ($0.1, $0.2) })
                subscriber.putCompletion()
            }
            
            return EmptyDisposable
        }
    }
}
