//
//  FormattedText.swift
//  tl2swift
//
//  Generated automatically. Any changes will be lost!
//  Based on TDLib 1.8.70-fe61d641-fe61d641
//  https://github.com/tdlib/td/tree/fe61d641
//

import Foundation


/// A text with some entities
public struct FormattedText: Codable, Equatable, Hashable {

    /// Entities contained in the text. Entities can be nested, but must not mutually intersect with each other. Pre, Code, PreCode, and DateTime entities can't contain other entities. BlockQuote entities can't contain other BlockQuote entities. Bold, Italic, Underline, Strikethrough, and Spoiler entities can contain and can be part of any other entities. All other entities can't contain each other
    public let entities: [TextEntity]

    /// The text
    public let text: String


    public init(
        entities: [TextEntity],
        text: String
    ) {
        self.entities = entities
        self.text = text
    }
}

