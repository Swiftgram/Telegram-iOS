import Foundation
import SwiftSignalKit
import ManagedFile

private let queue = DispatchQueue(label: "app.swiftgram.ios.trace", qos: .utility)

private var sharedLogger: SGLogger?

private let binaryEventMarker: UInt64 = 0xcadebabef00dcafe

private func rootPathForBasePath(_ appGroupPath: String) -> String {
    return appGroupPath + "/telegram-data"
}

public final class SGLogger {
    private let queue = Queue(name: "app.swiftgram.ios.log", qos: .utility)
    private let maxLength: Int = 2 * 1024 * 1024
    private let maxShortLength: Int = 1 * 1024 * 1024
    private let maxFiles: Int = 20
    
    private let rootPath: String
    private let basePath: String
    private var file: (ManagedFile, Int)?
    private var shortFile: (ManagedFile, Int)?
    
    public static let sgLogsPath = "/logs/app-logs-sg"
    
    public var logToFile: Bool = true
    public var logToConsole: Bool = true
    public var redactSensitiveData: Bool = true
    
    public static func setSharedLogger(_ logger: SGLogger) {
        sharedLogger = logger
    }
    
    public static var shared: SGLogger {
        if let sharedLogger = sharedLogger {
            return sharedLogger
        } else {
            print("SGLogger setup...")
            guard let baseAppBundleId = Bundle.main.bundleIdentifier else {
                print("Can't setup logger (1)!")
                return SGLogger(rootPath: "", basePath: "")
            }
            let appGroupName = "group.\(baseAppBundleId)"
            let maybeAppGroupUrl = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupName)
            guard let appGroupUrl = maybeAppGroupUrl else {
                print("Can't setup logger (2)!")
                return SGLogger(rootPath: "", basePath: "")
            }
            let newRootPath = rootPathForBasePath(appGroupUrl.path)
            let newLogsPath = newRootPath + sgLogsPath
            let _ = try? FileManager.default.createDirectory(atPath: newLogsPath, withIntermediateDirectories: true, attributes: nil)
            self.setSharedLogger(SGLogger(rootPath: newRootPath, basePath: newLogsPath))
            if let sharedLogger = sharedLogger {
                return sharedLogger
            } else {
                print("Can't setup logger (3)!")
                return SGLogger(rootPath: "", basePath: "")
            }
        }
    }
    
    public init(rootPath: String, basePath: String) {
        self.rootPath = rootPath
        self.basePath = basePath
    }
    
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
    
    public func log(_ tag: String, _ what: @autoclosure () -> String) {
        if !self.logToFile && !self.logToConsole {
            return
        }
        
        let string = what()
        
        var rawTime = time_t()
        time(&rawTime)
        var timeinfo = tm()
        localtime_r(&rawTime, &timeinfo)
        
        var curTime = timeval()
        gettimeofday(&curTime, nil)
        let milliseconds = curTime.tv_usec / 1000
        
        var consoleContent: String?
        if self.logToConsole {
            let content = String(format: "[SG.%@] %d-%d-%d %02d:%02d:%02d.%03d %@", arguments: [tag, Int(timeinfo.tm_year) + 1900, Int(timeinfo.tm_mon + 1), Int(timeinfo.tm_mday), Int(timeinfo.tm_hour), Int(timeinfo.tm_min), Int(timeinfo.tm_sec), Int(milliseconds), string])
            consoleContent = content
            print(content)
        }
        
        if self.logToFile {
            self.queue.async {
                let content: String
                if let consoleContent = consoleContent {
                    content = consoleContent
                } else {
                    content = String(format: "[SG.%@] %d-%d-%d %02d:%02d:%02d.%03d %@", arguments: [tag, Int(timeinfo.tm_year) + 1900, Int(timeinfo.tm_mon + 1), Int(timeinfo.tm_mday), Int(timeinfo.tm_hour), Int(timeinfo.tm_min), Int(timeinfo.tm_sec), Int(milliseconds), string])
                }
                
                var currentFile: ManagedFile?
                var openNew = false
                if let (file, length) = self.file {
                    if length >= self.maxLength {
                        self.file = nil
                        openNew = true
                    } else {
                        currentFile = file
                    }
                } else {
                    openNew = true
                }
                if openNew {
                    let _ = try? FileManager.default.createDirectory(atPath: self.basePath, withIntermediateDirectories: true, attributes: nil)
                    
                    var createNew = false
                    if let files = try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: self.basePath), includingPropertiesForKeys: [URLResourceKey.creationDateKey], options: []) {
                        var minCreationDate: (Date, URL)?
                        var maxCreationDate: (Date, URL)?
                        var count = 0
                        for url in files {
                            if url.lastPathComponent.hasPrefix("log-") {
                                if let values = try? url.resourceValues(forKeys: Set([URLResourceKey.creationDateKey])), let creationDate = values.creationDate {
                                    count += 1
                                    if minCreationDate == nil || minCreationDate!.0 > creationDate {
                                        minCreationDate = (creationDate, url)
                                    }
                                    if maxCreationDate == nil || maxCreationDate!.0 < creationDate {
                                        maxCreationDate = (creationDate, url)
                                    }
                                }
                            }
                        }
                        if let (_, url) = minCreationDate, count >= self.maxFiles {
                            let _ = try? FileManager.default.removeItem(at: url)
                        }
                        if let (_, url) = maxCreationDate {
                            var value = stat()
                            if stat(url.path, &value) == 0 && Int(value.st_size) < self.maxLength {
                                if let file = ManagedFile(queue: self.queue, path: url.path, mode: .append) {
                                    self.file = (file, Int(value.st_size))
                                    currentFile = file
                                }
                            } else {
                                createNew = true
                            }
                        } else {
                            createNew = true
                        }
                    }
                    
                    if createNew {
                        let fileName = String(format: "log-%d-%d-%d_%02d-%02d-%02d.%03d.txt", arguments: [Int(timeinfo.tm_year) + 1900, Int(timeinfo.tm_mon + 1), Int(timeinfo.tm_mday), Int(timeinfo.tm_hour), Int(timeinfo.tm_min), Int(timeinfo.tm_sec), Int(milliseconds)])
                        
                        let path = self.basePath + "/" + fileName
                        
                        if let file = ManagedFile(queue: self.queue, path: path, mode: .append) {
                            self.file = (file, 0)
                            currentFile = file
                        }
                    }
                }
                
                if let currentFile = currentFile {
                    if let data = content.data(using: .utf8) {
                        data.withUnsafeBytes { rawBytes -> Void in
                            let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: UInt8.self)

                            let _ = currentFile.write(bytes, count: data.count)
                        }
                        var newline: UInt8 = 0x0a
                        let _ = currentFile.write(&newline, count: 1)
                        if let file = self.file {
                            self.file = (file.0, file.1 + data.count + 1)
                        } else {
                            assertionFailure()
                        }
                    }
                }
            }
        }
    }
}
