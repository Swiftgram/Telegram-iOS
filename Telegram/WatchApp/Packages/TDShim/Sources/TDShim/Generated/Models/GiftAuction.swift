//
//  GiftAuction.swift
//  tl2swift
//
//  Generated automatically. Any changes will be lost!
//  Based on TDLib 1.8.70-fe61d641-fe61d641
//  https://github.com/tdlib/td/tree/fe61d641
//

import Foundation


/// Describes an auction on which a gift can be purchased
public struct GiftAuction: Codable, Equatable, Hashable, Identifiable {

    /// Number of gifts distributed in each round
    public let giftsPerRound: Int

    /// Identifier of the auction
    public let id: String

    /// Point in time (Unix timestamp) when the auction will start
    public let startDate: Int


    public init(
        giftsPerRound: Int,
        id: String,
        startDate: Int
    ) {
        self.giftsPerRound = giftsPerRound
        self.id = id
        self.startDate = startDate
    }
}

