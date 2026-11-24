//
//  TextQuote.swift
//  tl2swift
//
//  Generated automatically. Any changes will be lost!
//  Based on TDLib 1.8.70-fe61d641-fe61d641
//  https://github.com/tdlib/td/tree/fe61d641
//

import Foundation


/// Describes manually or automatically chosen quote from another message
public struct TextQuote: Codable, Equatable, Hashable {

    /// True, if the quote was manually chosen by the message sender
    public let isManual: Bool

    /// Approximate quote position in the original message in UTF-16 code units as specified by the message sender. For quotes from rich messages, it is the position in the text formed by joining plain texts of all quotable texts of the message, separated by line feeds
    public let position: Int

    /// Rich text of the quote if it was chosen from a rich message; empty if the quote wasn't chosen from a rich message. Only richTextPlain, richTextBold, richTextItalic, richTextUnderline, richTextStrikethrough, richTextSpoiler, richTextSubscript, richTextSuperscript, richTextDateTime, richTextCustomEmoji, richTextMathematicalExpression, and richTexts can be present in the texts
    public let richTexts: [RichText]

    /// Text of the quote. Only Bold, Italic, Underline, Strikethrough, Spoiler, CustomEmoji, and DateTime entities can be present in the text. May be empty if the quote was chosen from a rich message
    public let text: FormattedText


    public init(
        isManual: Bool,
        position: Int,
        richTexts: [RichText],
        text: FormattedText
    ) {
        self.isManual = isManual
        self.position = position
        self.richTexts = richTexts
        self.text = text
    }
}

