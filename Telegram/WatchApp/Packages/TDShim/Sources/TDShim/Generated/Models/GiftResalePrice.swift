//
//  GiftResalePrice.swift
//  tl2swift
//
//  Generated automatically. Any changes will be lost!
//  Based on TDLib 1.8.70-fe61d641-fe61d641
//  https://github.com/tdlib/td/tree/fe61d641
//

import Foundation


/// Describes price of a resold gift
public indirect enum GiftResalePrice: Codable, Equatable, Hashable {

    /// Describes price of a resold gift in Telegram Stars
    case giftResalePriceStar(GiftResalePriceStar)

    /// Describes price of a resold gift in TON Grams
    case giftResalePriceGram(GiftResalePriceGram)

    /// Decoded when the @type is not one of the known cases (forward-compatible).
    case unsupported

    private enum Kind: String, Codable {
        case giftResalePriceStar
        case giftResalePriceGram
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DtoCodingKeys.self)
        let typeString = try container.decode(String.self, forKey: .type)
        guard let type = Kind(rawValue: typeString) else {
            self = .unsupported
            return
        }
        switch type {
        case .giftResalePriceStar:
            let value = try GiftResalePriceStar(from: decoder)
            self = .giftResalePriceStar(value)
        case .giftResalePriceGram:
            let value = try GiftResalePriceGram(from: decoder)
            self = .giftResalePriceGram(value)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DtoCodingKeys.self)
        switch self {
        case .giftResalePriceStar(let value):
            try container.encode(Kind.giftResalePriceStar, forKey: .type)
            try value.encode(to: encoder)
        case .giftResalePriceGram(let value):
            try container.encode(Kind.giftResalePriceGram, forKey: .type)
            try value.encode(to: encoder)
        case .unsupported:
            try container.encode("unsupported", forKey: .type)
        }
    }
}

/// Describes price of a resold gift in Telegram Stars
public struct GiftResalePriceStar: Codable, Equatable, Hashable {

    /// The Telegram Star amount expected to be paid for the gift. Must be in the range getOption("gift_resale_star_count_min")-getOption("gift_resale_star_count_max") for gifts put for resale
    public let starCount: Int64


    public init(starCount: Int64) {
        self.starCount = starCount
    }
}

/// Describes price of a resold gift in TON Grams
public struct GiftResalePriceGram: Codable, Equatable, Hashable {

    /// The amount of 1/100 of Gram expected to be paid for the gift. Must be in the range getOption("gift_resale_gram_cent_count_min")-getOption("gift_resale_gram_cent_count_max")
    public let gramCentCount: Int64


    public init(gramCentCount: Int64) {
        self.gramCentCount = gramCentCount
    }
}

