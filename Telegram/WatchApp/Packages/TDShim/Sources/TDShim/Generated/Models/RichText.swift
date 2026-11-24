//
//  RichText.swift
//  tl2swift
//
//  Generated automatically. Any changes will be lost!
//  Based on TDLib 1.8.70-fe61d641-fe61d641
//  https://github.com/tdlib/td/tree/fe61d641
//

import Foundation


/// Describes a formatted text object
/// This Swift enum is recursive.
public indirect enum RichText: Codable, Equatable, Hashable {

    /// A plain text
    case richTextPlain(RichTextPlain)

    /// A bold rich text
    case richTextBold(RichTextBold)

    /// An italicized rich text
    case richTextItalic(RichTextItalic)

    /// An underlined rich text
    case richTextUnderline(RichTextUnderline)

    /// A strikethrough rich text
    case richTextStrikethrough(RichTextStrikethrough)

    /// A spoilered rich text
    case richTextSpoiler(RichTextSpoiler)

    /// A subscript rich text
    case richTextSubscript(RichTextSubscript)

    /// A superscript rich text
    case richTextSuperscript(RichTextSuperscript)

    /// A marked rich text
    case richTextMarked(RichTextMarked)

    /// A date and time
    case richTextDateTime(RichTextDateTime)

    /// A mention of a Telegram user or chat by a username
    case richTextMention(RichTextMention)

    /// A hashtag
    case richTextHashtag(RichTextHashtag)

    /// A cashtag
    case richTextCashtag(RichTextCashtag)

    /// A bank card number
    case richTextBankCardNumber(RichTextBankCardNumber)

    /// An address in the TON blockchain
    case richTextTonAddress(RichTextTonAddress)

    /// A bot command
    case richTextBotCommand(RichTextBotCommand)

    /// A fixed-width rich text
    case richTextFixed(RichTextFixed)

    /// A rich text that serves as a mention of a user
    case richTextMentionName(RichTextMentionName)

    /// A rich text URL link
    case richTextUrl(RichTextUrl)

    /// A rich text email address
    case richTextEmailAddress(RichTextEmailAddress)

    /// A rich text phone number
    case richTextPhoneNumber(RichTextPhoneNumber)

    /// A custom emoji
    case richTextCustomEmoji(RichTextCustomEmoji)

    /// A small image inside the text; instant view only
    case richTextIcon(RichTextIcon)

    /// A mathematical expression
    case richTextMathematicalExpression(RichTextMathematicalExpression)

    /// A rich text replacing another rich text; not supported in inputRichMessage
    case richTextDiff(RichTextDiff)

    /// A reference
    case richTextReference(RichTextReference)

    /// A link to a reference on the same page
    case richTextReferenceLink(RichTextReferenceLink)

    /// An anchor
    case richTextAnchor(RichTextAnchor)

    /// A link to an anchor on the same page
    case richTextAnchorLink(RichTextAnchorLink)

    /// A concatenation of rich texts
    case richTexts(RichTexts)

    /// Decoded when the @type is not one of the known cases (forward-compatible).
    case unsupported

    private enum Kind: String, Codable {
        case richTextPlain
        case richTextBold
        case richTextItalic
        case richTextUnderline
        case richTextStrikethrough
        case richTextSpoiler
        case richTextSubscript
        case richTextSuperscript
        case richTextMarked
        case richTextDateTime
        case richTextMention
        case richTextHashtag
        case richTextCashtag
        case richTextBankCardNumber
        case richTextTonAddress
        case richTextBotCommand
        case richTextFixed
        case richTextMentionName
        case richTextUrl
        case richTextEmailAddress
        case richTextPhoneNumber
        case richTextCustomEmoji
        case richTextIcon
        case richTextMathematicalExpression
        case richTextDiff
        case richTextReference
        case richTextReferenceLink
        case richTextAnchor
        case richTextAnchorLink
        case richTexts
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DtoCodingKeys.self)
        let typeString = try container.decode(String.self, forKey: .type)
        guard let type = Kind(rawValue: typeString) else {
            self = .unsupported
            return
        }
        switch type {
        case .richTextPlain:
            let value = try RichTextPlain(from: decoder)
            self = .richTextPlain(value)
        case .richTextBold:
            let value = try RichTextBold(from: decoder)
            self = .richTextBold(value)
        case .richTextItalic:
            let value = try RichTextItalic(from: decoder)
            self = .richTextItalic(value)
        case .richTextUnderline:
            let value = try RichTextUnderline(from: decoder)
            self = .richTextUnderline(value)
        case .richTextStrikethrough:
            let value = try RichTextStrikethrough(from: decoder)
            self = .richTextStrikethrough(value)
        case .richTextSpoiler:
            let value = try RichTextSpoiler(from: decoder)
            self = .richTextSpoiler(value)
        case .richTextSubscript:
            let value = try RichTextSubscript(from: decoder)
            self = .richTextSubscript(value)
        case .richTextSuperscript:
            let value = try RichTextSuperscript(from: decoder)
            self = .richTextSuperscript(value)
        case .richTextMarked:
            let value = try RichTextMarked(from: decoder)
            self = .richTextMarked(value)
        case .richTextDateTime:
            let value = try RichTextDateTime(from: decoder)
            self = .richTextDateTime(value)
        case .richTextMention:
            let value = try RichTextMention(from: decoder)
            self = .richTextMention(value)
        case .richTextHashtag:
            let value = try RichTextHashtag(from: decoder)
            self = .richTextHashtag(value)
        case .richTextCashtag:
            let value = try RichTextCashtag(from: decoder)
            self = .richTextCashtag(value)
        case .richTextBankCardNumber:
            let value = try RichTextBankCardNumber(from: decoder)
            self = .richTextBankCardNumber(value)
        case .richTextTonAddress:
            let value = try RichTextTonAddress(from: decoder)
            self = .richTextTonAddress(value)
        case .richTextBotCommand:
            let value = try RichTextBotCommand(from: decoder)
            self = .richTextBotCommand(value)
        case .richTextFixed:
            let value = try RichTextFixed(from: decoder)
            self = .richTextFixed(value)
        case .richTextMentionName:
            let value = try RichTextMentionName(from: decoder)
            self = .richTextMentionName(value)
        case .richTextUrl:
            let value = try RichTextUrl(from: decoder)
            self = .richTextUrl(value)
        case .richTextEmailAddress:
            let value = try RichTextEmailAddress(from: decoder)
            self = .richTextEmailAddress(value)
        case .richTextPhoneNumber:
            let value = try RichTextPhoneNumber(from: decoder)
            self = .richTextPhoneNumber(value)
        case .richTextCustomEmoji:
            let value = try RichTextCustomEmoji(from: decoder)
            self = .richTextCustomEmoji(value)
        case .richTextIcon:
            let value = try RichTextIcon(from: decoder)
            self = .richTextIcon(value)
        case .richTextMathematicalExpression:
            let value = try RichTextMathematicalExpression(from: decoder)
            self = .richTextMathematicalExpression(value)
        case .richTextDiff:
            let value = try RichTextDiff(from: decoder)
            self = .richTextDiff(value)
        case .richTextReference:
            let value = try RichTextReference(from: decoder)
            self = .richTextReference(value)
        case .richTextReferenceLink:
            let value = try RichTextReferenceLink(from: decoder)
            self = .richTextReferenceLink(value)
        case .richTextAnchor:
            let value = try RichTextAnchor(from: decoder)
            self = .richTextAnchor(value)
        case .richTextAnchorLink:
            let value = try RichTextAnchorLink(from: decoder)
            self = .richTextAnchorLink(value)
        case .richTexts:
            let value = try RichTexts(from: decoder)
            self = .richTexts(value)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DtoCodingKeys.self)
        switch self {
        case .richTextPlain(let value):
            try container.encode(Kind.richTextPlain, forKey: .type)
            try value.encode(to: encoder)
        case .richTextBold(let value):
            try container.encode(Kind.richTextBold, forKey: .type)
            try value.encode(to: encoder)
        case .richTextItalic(let value):
            try container.encode(Kind.richTextItalic, forKey: .type)
            try value.encode(to: encoder)
        case .richTextUnderline(let value):
            try container.encode(Kind.richTextUnderline, forKey: .type)
            try value.encode(to: encoder)
        case .richTextStrikethrough(let value):
            try container.encode(Kind.richTextStrikethrough, forKey: .type)
            try value.encode(to: encoder)
        case .richTextSpoiler(let value):
            try container.encode(Kind.richTextSpoiler, forKey: .type)
            try value.encode(to: encoder)
        case .richTextSubscript(let value):
            try container.encode(Kind.richTextSubscript, forKey: .type)
            try value.encode(to: encoder)
        case .richTextSuperscript(let value):
            try container.encode(Kind.richTextSuperscript, forKey: .type)
            try value.encode(to: encoder)
        case .richTextMarked(let value):
            try container.encode(Kind.richTextMarked, forKey: .type)
            try value.encode(to: encoder)
        case .richTextDateTime(let value):
            try container.encode(Kind.richTextDateTime, forKey: .type)
            try value.encode(to: encoder)
        case .richTextMention(let value):
            try container.encode(Kind.richTextMention, forKey: .type)
            try value.encode(to: encoder)
        case .richTextHashtag(let value):
            try container.encode(Kind.richTextHashtag, forKey: .type)
            try value.encode(to: encoder)
        case .richTextCashtag(let value):
            try container.encode(Kind.richTextCashtag, forKey: .type)
            try value.encode(to: encoder)
        case .richTextBankCardNumber(let value):
            try container.encode(Kind.richTextBankCardNumber, forKey: .type)
            try value.encode(to: encoder)
        case .richTextTonAddress(let value):
            try container.encode(Kind.richTextTonAddress, forKey: .type)
            try value.encode(to: encoder)
        case .richTextBotCommand(let value):
            try container.encode(Kind.richTextBotCommand, forKey: .type)
            try value.encode(to: encoder)
        case .richTextFixed(let value):
            try container.encode(Kind.richTextFixed, forKey: .type)
            try value.encode(to: encoder)
        case .richTextMentionName(let value):
            try container.encode(Kind.richTextMentionName, forKey: .type)
            try value.encode(to: encoder)
        case .richTextUrl(let value):
            try container.encode(Kind.richTextUrl, forKey: .type)
            try value.encode(to: encoder)
        case .richTextEmailAddress(let value):
            try container.encode(Kind.richTextEmailAddress, forKey: .type)
            try value.encode(to: encoder)
        case .richTextPhoneNumber(let value):
            try container.encode(Kind.richTextPhoneNumber, forKey: .type)
            try value.encode(to: encoder)
        case .richTextCustomEmoji(let value):
            try container.encode(Kind.richTextCustomEmoji, forKey: .type)
            try value.encode(to: encoder)
        case .richTextIcon(let value):
            try container.encode(Kind.richTextIcon, forKey: .type)
            try value.encode(to: encoder)
        case .richTextMathematicalExpression(let value):
            try container.encode(Kind.richTextMathematicalExpression, forKey: .type)
            try value.encode(to: encoder)
        case .richTextDiff(let value):
            try container.encode(Kind.richTextDiff, forKey: .type)
            try value.encode(to: encoder)
        case .richTextReference(let value):
            try container.encode(Kind.richTextReference, forKey: .type)
            try value.encode(to: encoder)
        case .richTextReferenceLink(let value):
            try container.encode(Kind.richTextReferenceLink, forKey: .type)
            try value.encode(to: encoder)
        case .richTextAnchor(let value):
            try container.encode(Kind.richTextAnchor, forKey: .type)
            try value.encode(to: encoder)
        case .richTextAnchorLink(let value):
            try container.encode(Kind.richTextAnchorLink, forKey: .type)
            try value.encode(to: encoder)
        case .richTexts(let value):
            try container.encode(Kind.richTexts, forKey: .type)
            try value.encode(to: encoder)
        case .unsupported:
            try container.encode("unsupported", forKey: .type)
        }
    }
}

/// A plain text
public struct RichTextPlain: Codable, Equatable, Hashable {

    /// Text
    public let text: String


    public init(text: String) {
        self.text = text
    }
}

/// A bold rich text
public struct RichTextBold: Codable, Equatable, Hashable {

    /// Text
    public let text: RichText


    public init(text: RichText) {
        self.text = text
    }
}

/// An italicized rich text
public struct RichTextItalic: Codable, Equatable, Hashable {

    /// Text
    public let text: RichText


    public init(text: RichText) {
        self.text = text
    }
}

/// An underlined rich text
public struct RichTextUnderline: Codable, Equatable, Hashable {

    /// Text
    public let text: RichText


    public init(text: RichText) {
        self.text = text
    }
}

/// A strikethrough rich text
public struct RichTextStrikethrough: Codable, Equatable, Hashable {

    /// Text
    public let text: RichText


    public init(text: RichText) {
        self.text = text
    }
}

/// A spoilered rich text
public struct RichTextSpoiler: Codable, Equatable, Hashable {

    /// Text
    public let text: RichText


    public init(text: RichText) {
        self.text = text
    }
}

/// A subscript rich text
public struct RichTextSubscript: Codable, Equatable, Hashable {

    /// Text
    public let text: RichText


    public init(text: RichText) {
        self.text = text
    }
}

/// A superscript rich text
public struct RichTextSuperscript: Codable, Equatable, Hashable {

    /// Text
    public let text: RichText


    public init(text: RichText) {
        self.text = text
    }
}

/// A marked rich text
public struct RichTextMarked: Codable, Equatable, Hashable {

    /// Text
    public let text: RichText


    public init(text: RichText) {
        self.text = text
    }
}

/// A date and time
public struct RichTextDateTime: Codable, Equatable, Hashable {

    /// Date and time formatting type; may be null if none and the original text must not be changed
    public let formattingType: DateTimeFormattingType?

    /// Original text
    public let text: RichText

    /// Point in time (Unix timestamp) representing the date and time
    public let unixTime: Int


    public init(
        formattingType: DateTimeFormattingType?,
        text: RichText,
        unixTime: Int
    ) {
        self.formattingType = formattingType
        self.text = text
        self.unixTime = unixTime
    }
}

/// A mention of a Telegram user or chat by a username
public struct RichTextMention: Codable, Equatable, Hashable {

    /// Text
    public let text: RichText

    /// The username
    public let username: String


    public init(
        text: RichText,
        username: String
    ) {
        self.text = text
        self.username = username
    }
}

/// A hashtag
public struct RichTextHashtag: Codable, Equatable, Hashable {

    /// The hashtag
    public let hashtag: String

    /// Text
    public let text: RichText


    public init(
        hashtag: String,
        text: RichText
    ) {
        self.hashtag = hashtag
        self.text = text
    }
}

/// A cashtag
public struct RichTextCashtag: Codable, Equatable, Hashable {

    /// The cashtag
    public let cashtag: String

    /// Text
    public let text: RichText


    public init(
        cashtag: String,
        text: RichText
    ) {
        self.cashtag = cashtag
        self.text = text
    }
}

/// A bank card number
public struct RichTextBankCardNumber: Codable, Equatable, Hashable {

    /// The number of the bank card
    public let bankCardNumber: String

    /// Text
    public let text: RichText


    public init(
        bankCardNumber: String,
        text: RichText
    ) {
        self.bankCardNumber = bankCardNumber
        self.text = text
    }
}

/// An address in the TON blockchain
public struct RichTextTonAddress: Codable, Equatable, Hashable {

    /// The address
    public let address: String

    /// Text
    public let text: RichText


    public init(
        address: String,
        text: RichText
    ) {
        self.address = address
        self.text = text
    }
}

/// A bot command
public struct RichTextBotCommand: Codable, Equatable, Hashable {

    /// The bot command
    public let botCommand: String

    /// Text
    public let text: RichText


    public init(
        botCommand: String,
        text: RichText
    ) {
        self.botCommand = botCommand
        self.text = text
    }
}

/// A fixed-width rich text
public struct RichTextFixed: Codable, Equatable, Hashable {

    /// Text
    public let text: RichText


    public init(text: RichText) {
        self.text = text
    }
}

/// A rich text that serves as a mention of a user
public struct RichTextMentionName: Codable, Equatable, Hashable {

    /// Text
    public let text: RichText

    /// Identifier of the mentioned user
    public let userId: Int64


    public init(
        text: RichText,
        userId: Int64
    ) {
        self.text = text
        self.userId = userId
    }
}

/// A rich text URL link
public struct RichTextUrl: Codable, Equatable, Hashable {

    /// True, if the URL has cached instant view server-side; instant view only
    public let isCached: Bool

    /// Text
    public let text: RichText

    /// URL
    public let url: String


    public init(
        isCached: Bool,
        text: RichText,
        url: String
    ) {
        self.isCached = isCached
        self.text = text
        self.url = url
    }
}

/// A rich text email address
public struct RichTextEmailAddress: Codable, Equatable, Hashable {

    /// Email address
    public let emailAddress: String

    /// Text
    public let text: RichText


    public init(
        emailAddress: String,
        text: RichText
    ) {
        self.emailAddress = emailAddress
        self.text = text
    }
}

/// A rich text phone number
public struct RichTextPhoneNumber: Codable, Equatable, Hashable {

    /// Phone number
    public let phoneNumber: String

    /// Text
    public let text: RichText


    public init(
        phoneNumber: String,
        text: RichText
    ) {
        self.phoneNumber = phoneNumber
        self.text = text
    }
}

/// A custom emoji
public struct RichTextCustomEmoji: Codable, Equatable, Hashable {

    /// Alternative text for the custom emoji
    public let alternativeText: String

    /// Unique identifier of the custom emoji
    public let customEmojiId: TdInt64


    public init(
        alternativeText: String,
        customEmojiId: TdInt64
    ) {
        self.alternativeText = alternativeText
        self.customEmojiId = customEmojiId
    }
}

/// A small image inside the text; instant view only
public struct RichTextIcon: Codable, Equatable, Hashable {

    /// The image represented as a document. The image can be in GIF, JPEG, or PNG format
    public let document: Document

    /// Height of a bounding box in which the image must be shown; 0 if unknown
    public let height: Int

    /// Width of a bounding box in which the image must be shown; 0 if unknown
    public let width: Int


    public init(
        document: Document,
        height: Int,
        width: Int
    ) {
        self.document = document
        self.height = height
        self.width = width
    }
}

/// A mathematical expression
public struct RichTextMathematicalExpression: Codable, Equatable, Hashable {

    /// The expression in LaTeX format
    public let expression: String


    public init(expression: String) {
        self.expression = expression
    }
}

/// A rich text replacing another rich text; not supported in inputRichMessage
public struct RichTextDiff: Codable, Equatable, Hashable {

    /// The old text
    public let oldText: RichText

    /// Text
    public let text: RichText


    public init(
        oldText: RichText,
        text: RichText
    ) {
        self.oldText = oldText
        self.text = text
    }
}

/// A reference
public struct RichTextReference: Codable, Equatable, Hashable {

    /// Reference name
    public let name: String

    /// Text of the reference
    public let text: RichText


    public init(
        name: String,
        text: RichText
    ) {
        self.name = name
        self.text = text
    }
}

/// A link to a reference on the same page
public struct RichTextReferenceLink: Codable, Equatable, Hashable {

    /// The reference name
    public let referenceName: String

    /// The link text
    public let text: RichText

    /// An HTTP URL that opens the reference
    public let url: String


    public init(
        referenceName: String,
        text: RichText,
        url: String
    ) {
        self.referenceName = referenceName
        self.text = text
        self.url = url
    }
}

/// An anchor
public struct RichTextAnchor: Codable, Equatable, Hashable {

    /// Anchor name
    public let name: String


    public init(name: String) {
        self.name = name
    }
}

/// A link to an anchor on the same page
public struct RichTextAnchorLink: Codable, Equatable, Hashable {

    /// The anchor name. If the name is empty, the link must bring back to top
    public let anchorName: String

    /// The link text
    public let text: RichText

    /// An HTTP URL that opens the anchor
    public let url: String


    public init(
        anchorName: String,
        text: RichText,
        url: String
    ) {
        self.anchorName = anchorName
        self.text = text
        self.url = url
    }
}

/// A concatenation of rich texts
public struct RichTexts: Codable, Equatable, Hashable {

    /// Texts
    public let texts: [RichText]


    public init(texts: [RichText]) {
        self.texts = texts
    }
}

