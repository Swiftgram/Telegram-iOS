//
//  FactCheck.swift
//  tl2swift
//
//  Generated automatically. Any changes will be lost!
//  Based on TDLib 1.8.70-fe61d641-fe61d641
//  https://github.com/tdlib/td/tree/fe61d641
//

import Foundation


/// Describes a fact-check added to the message by an independent checker
public struct FactCheck: Codable, Equatable, Hashable {

    /// A two-letter ISO 3166-1 alpha-2 country code of the country for which the fact-check is shown
    public let countryCode: String

    /// Text of the fact-check
    public let text: FormattedText


    public init(
        countryCode: String,
        text: FormattedText
    ) {
        self.countryCode = countryCode
        self.text = text
    }
}

