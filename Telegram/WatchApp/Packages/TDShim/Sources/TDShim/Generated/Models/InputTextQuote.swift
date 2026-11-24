//
//  InputTextQuote.swift
//  tl2swift
//
//  Generated automatically. Any changes will be lost!
//  Based on TDLib 1.8.70-fe61d641-fe61d641
//  https://github.com/tdlib/td/tree/fe61d641
//

import Foundation


/// Describes manually chosen quote from another message
public struct InputTextQuote: Codable, Equatable, Hashable {

    /// Quote position in the original message in UTF-16 code units. For quotes from rich messages, it is the position in the text formed by joining plain texts of all quotable texts of the message, separated by line feeds
    public let position: Int

    /// Quote from a rich message; pass an empty array if the quote isn't chosen from a rich message. Must contain one element for each quoted text of the message in the order of their appearance. The first and the last elements can contain only a part of the corresponding text; all other elements must contain the whole text. Formatting of the quoted parts must be kept. Mathematical expressions must be quoted entirely. Buttons in pageBlockButtonRow, anchors and dividers can't be quoted. There can be up to 32 quoted texts with total length up to getOption("message_reply_quote_length_max") characters
    public let richTexts: [RichText]

    /// Text of the quote; 0-getOption("message_reply_quote_length_max") characters. Only Bold, Italic, Underline, Strikethrough, Spoiler, CustomEmoji, and DateTime entities are allowed to be kept and must be kept in the quote. Ignored if rich_texts are non-empty
    public let text: FormattedText


    public init(
        position: Int,
        richTexts: [RichText],
        text: FormattedText
    ) {
        self.position = position
        self.richTexts = richTexts
        self.text = text
    }
}

