//
//  GiftResaleParameters.swift
//  tl2swift
//
//  Generated automatically. Any changes will be lost!
//  Based on TDLib 1.8.70-fe61d641-fe61d641
//  https://github.com/tdlib/td/tree/fe61d641
//

import Foundation


/// Describes parameters of a unique gift available for resale
public struct GiftResaleParameters: Codable, Equatable, Hashable {

    /// Resale price of the gift in 1/100 of TON Gram
    public let gramCentCount: Int64

    /// True, if the gift can be bought only using Grams
    public let gramOnly: Bool

    /// Resale price of the gift in Telegram Stars
    public let starCount: Int64


    public init(
        gramCentCount: Int64,
        gramOnly: Bool,
        starCount: Int64
    ) {
        self.gramCentCount = gramCentCount
        self.gramOnly = gramOnly
        self.starCount = starCount
    }
}

