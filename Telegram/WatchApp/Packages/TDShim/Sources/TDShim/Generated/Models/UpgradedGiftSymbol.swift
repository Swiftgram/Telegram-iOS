//
//  UpgradedGiftSymbol.swift
//  tl2swift
//
//  Generated automatically. Any changes will be lost!
//  Based on TDLib 1.8.70-fe61d641-fe61d641
//  https://github.com/tdlib/td/tree/fe61d641
//

import Foundation


/// Describes a symbol shown on the pattern of an upgraded gift
public struct UpgradedGiftSymbol: Codable, Equatable, Hashable {

    /// Name of the symbol
    public let name: String

    /// The rarity of the symbol
    public let rarity: UpgradedGiftAttributeRarity

    /// The sticker representing the symbol
    public let sticker: Sticker


    public init(
        name: String,
        rarity: UpgradedGiftAttributeRarity,
        sticker: Sticker
    ) {
        self.name = name
        self.rarity = rarity
        self.sticker = sticker
    }
}

