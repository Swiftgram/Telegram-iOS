//
//  Logger.swift
//  tl2swift
//
//  Generated automatically. Any changes will be lost!
//  Based on TDLib 1.8.70-fe61d641-fe61d641
//  https://github.com/tdlib/td/tree/fe61d641
//

import Foundation


public protocol TDLibLogger {
    func log(_ message: String, type: LoggerMessageType?)
}


@available(*, deprecated, renamed: "TDLibLogger", message: "interferes with OSLog.Logger")
public protocol Logger {
    func log(_ message: String, type: LoggerMessageType?)
}


public enum LoggerMessageType: CustomStringConvertible {
    case receive
    case send
    case execute
    case custom(String)

    public var description: String {
        switch self {
        case .receive:
            return "Receive"
        case .send:
            return "Send"
        case .execute:
            return "Execute"
        case .custom(let value):
            return value
        }
    }
}
