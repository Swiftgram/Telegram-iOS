//
//  CheckAuthenticationPassword.swift
//  tl2swift
//
//  Generated automatically. Any changes will be lost!
//  Based on TDLib 1.8.70-fe61d641-fe61d641
//  https://github.com/tdlib/td/tree/fe61d641
//

import Foundation


/// Checks the 2-step verification password for correctness. Works only when the current authorization state is authorizationStateWaitPassword
public struct CheckAuthenticationPassword: Codable, Equatable, Hashable {

    /// The 2-step verification password to check
    public let password: String?


    public init(password: String?) {
        self.password = password
    }
}

