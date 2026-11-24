//
//  UpgradedGiftBackdrop.swift
//  tl2swift
//
//  Generated automatically. Any changes will be lost!
//  Based on TDLib 1.8.70-fe61d641-fe61d641
//  https://github.com/tdlib/td/tree/fe61d641
//

import Foundation


/// Describes a backdrop of an upgraded gift
public struct UpgradedGiftBackdrop: Codable, Equatable, Hashable, Identifiable {

    /// Colors of the backdrop
    public let colors: UpgradedGiftBackdropColors

    /// Unique identifier of the backdrop
    public let id: Int

    /// Name of the backdrop
    public let name: String

    /// The rarity of the backdrop
    public let rarity: UpgradedGiftAttributeRarity


    public init(
        colors: UpgradedGiftBackdropColors,
        id: Int,
        name: String,
        rarity: UpgradedGiftAttributeRarity
    ) {
        self.colors = colors
        self.id = id
        self.name = name
        self.rarity = rarity
    }
}

