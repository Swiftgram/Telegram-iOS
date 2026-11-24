//
//  AccountInfo.swift
//  tl2swift
//
//  Generated automatically. Any changes will be lost!
//  Based on TDLib 1.8.70-fe61d641-fe61d641
//  https://github.com/tdlib/td/tree/fe61d641
//

import Foundation


/// Contains basic information about another user who started a chat with the current user
public struct AccountInfo: Codable, Equatable, Hashable {

    /// Point in time (Unix timestamp) when the user changed name last time; 0 if unknown
    public let lastNameChangeDate: Int

    /// Point in time (Unix timestamp) when the user changed photo last time; 0 if unknown
    public let lastPhotoChangeDate: Int

    /// A two-letter ISO 3166-1 alpha-2 country code based on the phone number of the user; may be empty if unknown
    public let phoneNumberCountryCode: String

    /// Month when the user was registered in Telegram; 0-12; may be 0 if unknown
    public let registrationMonth: Int

    /// Year when the user was registered in Telegram; 0-9999; may be 0 if unknown
    public let registrationYear: Int


    public init(
        lastNameChangeDate: Int,
        lastPhotoChangeDate: Int,
        phoneNumberCountryCode: String,
        registrationMonth: Int,
        registrationYear: Int
    ) {
        self.lastNameChangeDate = lastNameChangeDate
        self.lastPhotoChangeDate = lastPhotoChangeDate
        self.phoneNumberCountryCode = phoneNumberCountryCode
        self.registrationMonth = registrationMonth
        self.registrationYear = registrationYear
    }
}

