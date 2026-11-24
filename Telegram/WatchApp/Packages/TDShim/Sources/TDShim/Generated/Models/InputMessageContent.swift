//
//  InputMessageContent.swift
//  tl2swift
//
//  Generated automatically. Any changes will be lost!
//  Based on TDLib 1.8.70-fe61d641-fe61d641
//  https://github.com/tdlib/td/tree/fe61d641
//

import Foundation


/// The content of a message to send
/// This Swift enum is recursive.
public indirect enum InputMessageContent: Codable, Equatable, Hashable {

    /// A text message
    case inputMessageText(InputMessageText)

    /// An animation message (GIF-style).
    case inputMessageAnimation(InputMessageAnimation)

    /// An audio message
    case inputMessageAudio(InputMessageAudio)

    /// A document message (general file)
    case inputMessageDocument(InputMessageDocument)

    /// A message with paid media; can be used only in channel chats with supergroupFullInfo.has_paid_media_allowed
    case inputMessagePaidMedia(InputMessagePaidMedia)

    /// A photo message
    case inputMessagePhoto(InputMessagePhoto)

    /// A sticker message
    case inputMessageSticker(InputMessageSticker)

    /// A video message
    case inputMessageVideo(InputMessageVideo)

    /// A video note message
    case inputMessageVideoNote(InputMessageVideoNote)

    /// A voice note message
    case inputMessageVoiceNote(InputMessageVoiceNote)

    /// A message with a live location
    case inputMessageLiveLocation(InputMessageLiveLocation)

    /// A message with a location
    case inputMessageLocation(InputMessageLocation)

    /// A message with information about a venue
    case inputMessageVenue(InputMessageVenue)

    /// A message containing a user contact
    case inputMessageContact(InputMessageContact)

    /// A dice message
    case inputMessageDice(InputMessageDice)

    /// A message with a game; not supported for channels or secret chats
    case inputMessageGame(InputMessageGame)

    /// A message with an invoice; can be used only by bots
    case inputMessageInvoice(InputMessageInvoice)

    /// A message with a poll. Polls can't be sent to secret chats and channel direct messages chats. Polls can be sent to a private chat only if the chat is a chat with a bot or the Saved Messages chat
    case inputMessagePoll(InputMessagePoll)

    /// A stake dice message
    case inputMessageStakeDice(InputMessageStakeDice)

    /// A message with a forwarded story. Stories can't be forwarded to secret chats. A story can be forwarded only if story.can_be_forwarded
    case inputMessageStory(InputMessageStory)

    /// A message with a checklist. Checklists can't be sent to secret chats, channel chats and channel direct messages chats; for Telegram Premium users only
    case inputMessageChecklist(InputMessageChecklist)

    /// A message with an HTML widget; for bots only
    case inputMessageWidget(InputMessageWidget)

    /// A message with an existing shared widget; for bots only
    case inputMessageSharedWidget(InputMessageSharedWidget)

    /// A forwarded message
    case inputMessageForwarded(InputMessageForwarded)

    /// Decoded when the @type is not one of the known cases (forward-compatible).
    case unsupported

    private enum Kind: String, Codable {
        case inputMessageText
        case inputMessageAnimation
        case inputMessageAudio
        case inputMessageDocument
        case inputMessagePaidMedia
        case inputMessagePhoto
        case inputMessageSticker
        case inputMessageVideo
        case inputMessageVideoNote
        case inputMessageVoiceNote
        case inputMessageLiveLocation
        case inputMessageLocation
        case inputMessageVenue
        case inputMessageContact
        case inputMessageDice
        case inputMessageGame
        case inputMessageInvoice
        case inputMessagePoll
        case inputMessageStakeDice
        case inputMessageStory
        case inputMessageChecklist
        case inputMessageWidget
        case inputMessageSharedWidget
        case inputMessageForwarded
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DtoCodingKeys.self)
        let typeString = try container.decode(String.self, forKey: .type)
        guard let type = Kind(rawValue: typeString) else {
            self = .unsupported
            return
        }
        switch type {
        case .inputMessageText:
            let value = try InputMessageText(from: decoder)
            self = .inputMessageText(value)
        case .inputMessageAnimation:
            let value = try InputMessageAnimation(from: decoder)
            self = .inputMessageAnimation(value)
        case .inputMessageAudio:
            let value = try InputMessageAudio(from: decoder)
            self = .inputMessageAudio(value)
        case .inputMessageDocument:
            let value = try InputMessageDocument(from: decoder)
            self = .inputMessageDocument(value)
        case .inputMessagePaidMedia:
            let value = try InputMessagePaidMedia(from: decoder)
            self = .inputMessagePaidMedia(value)
        case .inputMessagePhoto:
            let value = try InputMessagePhoto(from: decoder)
            self = .inputMessagePhoto(value)
        case .inputMessageSticker:
            let value = try InputMessageSticker(from: decoder)
            self = .inputMessageSticker(value)
        case .inputMessageVideo:
            let value = try InputMessageVideo(from: decoder)
            self = .inputMessageVideo(value)
        case .inputMessageVideoNote:
            let value = try InputMessageVideoNote(from: decoder)
            self = .inputMessageVideoNote(value)
        case .inputMessageVoiceNote:
            let value = try InputMessageVoiceNote(from: decoder)
            self = .inputMessageVoiceNote(value)
        case .inputMessageLiveLocation:
            let value = try InputMessageLiveLocation(from: decoder)
            self = .inputMessageLiveLocation(value)
        case .inputMessageLocation:
            let value = try InputMessageLocation(from: decoder)
            self = .inputMessageLocation(value)
        case .inputMessageVenue:
            let value = try InputMessageVenue(from: decoder)
            self = .inputMessageVenue(value)
        case .inputMessageContact:
            let value = try InputMessageContact(from: decoder)
            self = .inputMessageContact(value)
        case .inputMessageDice:
            let value = try InputMessageDice(from: decoder)
            self = .inputMessageDice(value)
        case .inputMessageGame:
            let value = try InputMessageGame(from: decoder)
            self = .inputMessageGame(value)
        case .inputMessageInvoice:
            let value = try InputMessageInvoice(from: decoder)
            self = .inputMessageInvoice(value)
        case .inputMessagePoll:
            let value = try InputMessagePoll(from: decoder)
            self = .inputMessagePoll(value)
        case .inputMessageStakeDice:
            let value = try InputMessageStakeDice(from: decoder)
            self = .inputMessageStakeDice(value)
        case .inputMessageStory:
            let value = try InputMessageStory(from: decoder)
            self = .inputMessageStory(value)
        case .inputMessageChecklist:
            let value = try InputMessageChecklist(from: decoder)
            self = .inputMessageChecklist(value)
        case .inputMessageWidget:
            let value = try InputMessageWidget(from: decoder)
            self = .inputMessageWidget(value)
        case .inputMessageSharedWidget:
            let value = try InputMessageSharedWidget(from: decoder)
            self = .inputMessageSharedWidget(value)
        case .inputMessageForwarded:
            let value = try InputMessageForwarded(from: decoder)
            self = .inputMessageForwarded(value)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DtoCodingKeys.self)
        switch self {
        case .inputMessageText(let value):
            try container.encode(Kind.inputMessageText, forKey: .type)
            try value.encode(to: encoder)
        case .inputMessageAnimation(let value):
            try container.encode(Kind.inputMessageAnimation, forKey: .type)
            try value.encode(to: encoder)
        case .inputMessageAudio(let value):
            try container.encode(Kind.inputMessageAudio, forKey: .type)
            try value.encode(to: encoder)
        case .inputMessageDocument(let value):
            try container.encode(Kind.inputMessageDocument, forKey: .type)
            try value.encode(to: encoder)
        case .inputMessagePaidMedia(let value):
            try container.encode(Kind.inputMessagePaidMedia, forKey: .type)
            try value.encode(to: encoder)
        case .inputMessagePhoto(let value):
            try container.encode(Kind.inputMessagePhoto, forKey: .type)
            try value.encode(to: encoder)
        case .inputMessageSticker(let value):
            try container.encode(Kind.inputMessageSticker, forKey: .type)
            try value.encode(to: encoder)
        case .inputMessageVideo(let value):
            try container.encode(Kind.inputMessageVideo, forKey: .type)
            try value.encode(to: encoder)
        case .inputMessageVideoNote(let value):
            try container.encode(Kind.inputMessageVideoNote, forKey: .type)
            try value.encode(to: encoder)
        case .inputMessageVoiceNote(let value):
            try container.encode(Kind.inputMessageVoiceNote, forKey: .type)
            try value.encode(to: encoder)
        case .inputMessageLiveLocation(let value):
            try container.encode(Kind.inputMessageLiveLocation, forKey: .type)
            try value.encode(to: encoder)
        case .inputMessageLocation(let value):
            try container.encode(Kind.inputMessageLocation, forKey: .type)
            try value.encode(to: encoder)
        case .inputMessageVenue(let value):
            try container.encode(Kind.inputMessageVenue, forKey: .type)
            try value.encode(to: encoder)
        case .inputMessageContact(let value):
            try container.encode(Kind.inputMessageContact, forKey: .type)
            try value.encode(to: encoder)
        case .inputMessageDice(let value):
            try container.encode(Kind.inputMessageDice, forKey: .type)
            try value.encode(to: encoder)
        case .inputMessageGame(let value):
            try container.encode(Kind.inputMessageGame, forKey: .type)
            try value.encode(to: encoder)
        case .inputMessageInvoice(let value):
            try container.encode(Kind.inputMessageInvoice, forKey: .type)
            try value.encode(to: encoder)
        case .inputMessagePoll(let value):
            try container.encode(Kind.inputMessagePoll, forKey: .type)
            try value.encode(to: encoder)
        case .inputMessageStakeDice(let value):
            try container.encode(Kind.inputMessageStakeDice, forKey: .type)
            try value.encode(to: encoder)
        case .inputMessageStory(let value):
            try container.encode(Kind.inputMessageStory, forKey: .type)
            try value.encode(to: encoder)
        case .inputMessageChecklist(let value):
            try container.encode(Kind.inputMessageChecklist, forKey: .type)
            try value.encode(to: encoder)
        case .inputMessageWidget(let value):
            try container.encode(Kind.inputMessageWidget, forKey: .type)
            try value.encode(to: encoder)
        case .inputMessageSharedWidget(let value):
            try container.encode(Kind.inputMessageSharedWidget, forKey: .type)
            try value.encode(to: encoder)
        case .inputMessageForwarded(let value):
            try container.encode(Kind.inputMessageForwarded, forKey: .type)
            try value.encode(to: encoder)
        case .unsupported:
            try container.encode("unsupported", forKey: .type)
        }
    }
}

/// A text message
public struct InputMessageText: Codable, Equatable, Hashable {

    /// Pass true to delete message draft in the chat
    public let clearDraft: Bool

    /// Options to be used for generation of a link preview; may be null if none; pass null to use default link preview options
    public let linkPreviewOptions: LinkPreviewOptions?

    /// Formatted text to be sent; 0-getOption("message_text_length_max") characters. Only Bold, Italic, Underline, Strikethrough, Spoiler, CustomEmoji, BlockQuote, ExpandableBlockQuote, Code, Pre, PreCode, TextUrl, MentionName, and DateTime entities are allowed to be specified manually
    public let text: FormattedText


    public init(
        clearDraft: Bool,
        linkPreviewOptions: LinkPreviewOptions?,
        text: FormattedText
    ) {
        self.clearDraft = clearDraft
        self.linkPreviewOptions = linkPreviewOptions
        self.text = text
    }
}

/// An animation message (GIF-style).
public struct InputMessageAnimation: Codable, Equatable, Hashable {

    /// The animation to be sent
    public let animation: InputAnimation

    /// Animation caption; pass null to use an empty caption; 0-getOption("message_caption_length_max") characters
    public let caption: FormattedText?

    /// True, if the animation preview must be covered by a spoiler animation; not supported in secret chats
    public let hasSpoiler: Bool

    /// True, if the caption must be shown above the animation; otherwise, the caption must be shown below the animation; not supported in secret chats
    public let showCaptionAboveMedia: Bool


    public init(
        animation: InputAnimation,
        caption: FormattedText?,
        hasSpoiler: Bool,
        showCaptionAboveMedia: Bool
    ) {
        self.animation = animation
        self.caption = caption
        self.hasSpoiler = hasSpoiler
        self.showCaptionAboveMedia = showCaptionAboveMedia
    }
}

/// An audio message
public struct InputMessageAudio: Codable, Equatable, Hashable {

    /// Audio to be sent
    public let audio: InputAudio

    /// Audio caption; pass null to use an empty caption; 0-getOption("message_caption_length_max") characters
    public let caption: FormattedText?


    public init(
        audio: InputAudio,
        caption: FormattedText?
    ) {
        self.audio = audio
        self.caption = caption
    }
}

/// A document message (general file)
public struct InputMessageDocument: Codable, Equatable, Hashable {

    /// Document caption; pass null to use an empty caption; 0-getOption("message_caption_length_max") characters
    public let caption: FormattedText?

    /// Document to be sent
    public let document: InputDocument


    public init(
        caption: FormattedText?,
        document: InputDocument
    ) {
        self.caption = caption
        self.document = document
    }
}

/// A message with paid media; can be used only in channel chats with supergroupFullInfo.has_paid_media_allowed
public struct InputMessagePaidMedia: Codable, Equatable, Hashable {

    /// Message caption; pass null to use an empty caption; 0-getOption("message_caption_length_max") characters
    public let caption: FormattedText?

    /// The content of the paid media
    public let paidMedia: [InputPaidMedia]

    /// Bot-provided data for the paid media; bots only
    public let payload: String

    /// True, if the caption must be shown above the media; otherwise, the caption must be shown below the media; not supported in secret chats
    public let showCaptionAboveMedia: Bool

    /// The number of Telegram Stars that must be paid to see the media; 1-getOption("paid_media_message_star_count_max")
    public let starCount: Int64


    public init(
        caption: FormattedText?,
        paidMedia: [InputPaidMedia],
        payload: String,
        showCaptionAboveMedia: Bool,
        starCount: Int64
    ) {
        self.caption = caption
        self.paidMedia = paidMedia
        self.payload = payload
        self.showCaptionAboveMedia = showCaptionAboveMedia
        self.starCount = starCount
    }
}

/// A photo message
public struct InputMessagePhoto: Codable, Equatable, Hashable {

    /// Photo caption; pass null to use an empty caption; 0-getOption("message_caption_length_max") characters
    public let caption: FormattedText?

    /// True, if the photo preview must be covered by a spoiler animation; not supported in secret chats
    public let hasSpoiler: Bool

    /// Photo to be sent
    public let photo: InputPhoto

    /// Photo self-destruct type; pass null if none; private chats only
    public let selfDestructType: MessageSelfDestructType?

    /// True, if the caption must be shown above the photo; otherwise, the caption must be shown below the photo; not supported in secret chats
    public let showCaptionAboveMedia: Bool


    public init(
        caption: FormattedText?,
        hasSpoiler: Bool,
        photo: InputPhoto,
        selfDestructType: MessageSelfDestructType?,
        showCaptionAboveMedia: Bool
    ) {
        self.caption = caption
        self.hasSpoiler = hasSpoiler
        self.photo = photo
        self.selfDestructType = selfDestructType
        self.showCaptionAboveMedia = showCaptionAboveMedia
    }
}

/// A sticker message
public struct InputMessageSticker: Codable, Equatable, Hashable {

    /// Emoji used to choose the sticker
    public let emoji: String

    /// Sticker to be sent
    public let sticker: InputSticker


    public init(
        emoji: String,
        sticker: InputSticker
    ) {
        self.emoji = emoji
        self.sticker = sticker
    }
}

/// A video message
public struct InputMessageVideo: Codable, Equatable, Hashable {

    /// Video caption; pass null to use an empty caption; 0-getOption("message_caption_length_max") characters
    public let caption: FormattedText?

    /// True, if the video preview must be covered by a spoiler animation; not supported in secret chats
    public let hasSpoiler: Bool

    /// Video self-destruct type; pass null if none; private chats only
    public let selfDestructType: MessageSelfDestructType?

    /// True, if the caption must be shown above the video; otherwise, the caption must be shown below the video; not supported in secret chats
    public let showCaptionAboveMedia: Bool

    /// Video to be sent
    public let video: InputVideo


    public init(
        caption: FormattedText?,
        hasSpoiler: Bool,
        selfDestructType: MessageSelfDestructType?,
        showCaptionAboveMedia: Bool,
        video: InputVideo
    ) {
        self.caption = caption
        self.hasSpoiler = hasSpoiler
        self.selfDestructType = selfDestructType
        self.showCaptionAboveMedia = showCaptionAboveMedia
        self.video = video
    }
}

/// A video note message
public struct InputMessageVideoNote: Codable, Equatable, Hashable {

    /// Video note self-destruct type; may be null if none; pass null if none; private chats only
    public let selfDestructType: MessageSelfDestructType?

    /// Video note to be sent
    public let videoNote: InputVideoNote


    public init(
        selfDestructType: MessageSelfDestructType?,
        videoNote: InputVideoNote
    ) {
        self.selfDestructType = selfDestructType
        self.videoNote = videoNote
    }
}

/// A voice note message
public struct InputMessageVoiceNote: Codable, Equatable, Hashable {

    /// Voice note caption; pass null to use an empty caption; 0-getOption("message_caption_length_max") characters
    public let caption: FormattedText?

    /// Voice note self-destruct type; may be null if none; pass null if none; private chats only
    public let selfDestructType: MessageSelfDestructType?

    /// Voice note to be sent
    public let voiceNote: InputVoiceNote


    public init(
        caption: FormattedText?,
        selfDestructType: MessageSelfDestructType?,
        voiceNote: InputVoiceNote
    ) {
        self.caption = caption
        self.selfDestructType = selfDestructType
        self.voiceNote = voiceNote
    }
}

/// A message with a live location
public struct InputMessageLiveLocation: Codable, Equatable, Hashable {

    /// Initial state of the live location to be sent. Live period must be equal to 0x7FFFFFFF for permanent live locations, or between 60 and 86400
    public let location: LiveLocation


    public init(location: LiveLocation) {
        self.location = location
    }
}

/// A message with a location
public struct InputMessageLocation: Codable, Equatable, Hashable {

    /// Location to be sent
    public let location: Location


    public init(location: Location) {
        self.location = location
    }
}

/// A message with information about a venue
public struct InputMessageVenue: Codable, Equatable, Hashable {

    /// Venue to send
    public let venue: Venue


    public init(venue: Venue) {
        self.venue = venue
    }
}

/// A message containing a user contact
public struct InputMessageContact: Codable, Equatable, Hashable {

    /// Contact to send
    public let contact: Contact


    public init(contact: Contact) {
        self.contact = contact
    }
}

/// A dice message
public struct InputMessageDice: Codable, Equatable, Hashable {

    /// Pass true to delete message draft in the chat
    public let clearDraft: Bool

    /// Emoji on which the dice throw animation is based
    public let emoji: String


    public init(
        clearDraft: Bool,
        emoji: String
    ) {
        self.clearDraft = clearDraft
        self.emoji = emoji
    }
}

/// A message with a game; not supported for channels or secret chats
public struct InputMessageGame: Codable, Equatable, Hashable {

    /// User identifier of the bot that owns the game
    public let botUserId: Int64

    /// Short name of the game
    public let gameShortName: String


    public init(
        botUserId: Int64,
        gameShortName: String
    ) {
        self.botUserId = botUserId
        self.gameShortName = gameShortName
    }
}

/// A message with an invoice; can be used only by bots
public struct InputMessageInvoice: Codable, Equatable, Hashable {

    public let description: String

    /// Invoice
    public let invoice: Invoice

    /// The content of paid media attached to the invoice; pass null if none
    public let paidMedia: InputPaidMedia?

    /// Paid media caption; pass null to use an empty caption; 0-getOption("message_caption_length_max") characters
    public let paidMediaCaption: FormattedText?

    /// The invoice payload
    public let payload: Data

    /// Product photo height
    public let photoHeight: Int

    /// Product photo size
    public let photoSize: Int

    /// Product photo URL; optional
    public let photoUrl: String

    /// Product photo width
    public let photoWidth: Int

    /// JSON-encoded data about the invoice, which will be shared with the payment provider
    public let providerData: String

    /// Payment provider token; may be empty for payments in Telegram Stars
    public let providerToken: String

    /// Unique invoice bot deep link parameter for the generation of this invoice. If empty, it would be possible to pay directly from forwards of the invoice message
    public let startParameter: String

    /// Product title; 1-32 characters
    public let title: String


    public init(
        description: String,
        invoice: Invoice,
        paidMedia: InputPaidMedia?,
        paidMediaCaption: FormattedText?,
        payload: Data,
        photoHeight: Int,
        photoSize: Int,
        photoUrl: String,
        photoWidth: Int,
        providerData: String,
        providerToken: String,
        startParameter: String,
        title: String
    ) {
        self.description = description
        self.invoice = invoice
        self.paidMedia = paidMedia
        self.paidMediaCaption = paidMediaCaption
        self.payload = payload
        self.photoHeight = photoHeight
        self.photoSize = photoSize
        self.photoUrl = photoUrl
        self.photoWidth = photoWidth
        self.providerData = providerData
        self.providerToken = providerToken
        self.startParameter = startParameter
        self.title = title
    }
}

/// A message with a poll. Polls can't be sent to secret chats and channel direct messages chats. Polls can be sent to a private chat only if the chat is a chat with a bot or the Saved Messages chat
public struct InputMessagePoll: Codable, Equatable, Hashable {

    /// True, if multiple answer options can be chosen simultaneously
    public let allowsMultipleAnswers: Bool

    /// True, if the poll can be answered multiple times
    public let allowsRevoting: Bool

    /// Point in time (Unix timestamp) when the poll will automatically be closed; must be 0-getOption("poll_open_period_max") seconds in the future; pass 0 if not specified
    public let closeDate: Int

    /// The list of two-letter ISO 3166-1 alpha-2 codes of countries, users from which will be able to vote; for channel chats only. If empty, then all users can participate in the poll. There can be up to getOption("poll_country_count_max") chosen countries
    public let countryCodes: [String]

    public let description: FormattedText

    /// True, if the poll results will appear only after the poll closes
    public let hideResultsUntilCloses: Bool

    /// True, if the poll voters are anonymous. Non-anonymous polls can't be sent or forwarded to channels
    public let isAnonymous: Bool

    /// True, if the poll needs to be sent already closed; for bots only
    public let isClosed: Bool

    /// Media attached to the poll; pass null if none. Must be one of the following types: inputPollMediaAnimation, inputPollMediaAudio, inputPollMediaDocument, inputPollMediaLocation, inputPollMediaPhoto, inputPollMediaVenue, or inputPollMediaVideo without caption
    public let media: InputPollMedia?

    /// True, if only the users that are members of the chat for more than a day will be able to vote; for channel chats only
    public let membersOnly: Bool

    /// Amount of time the poll will be active after creation, in seconds; 0-getOption("poll_open_period_max"); pass 0 if not specified
    public let openPeriod: Int

    /// List of poll answer options; 1-getOption("poll_answer_count_max") options
    public let options: [InputPollOption]

    /// Poll question; 1-255 characters (up to 300 characters for bots). Only custom emoji entities are allowed to be added and only by Premium users
    public let question: FormattedText

    /// True, if poll options must be shown in a fixed random order
    public let shuffleOptions: Bool

    /// Type of the poll
    public let type: InputPollType


    public init(
        allowsMultipleAnswers: Bool,
        allowsRevoting: Bool,
        closeDate: Int,
        countryCodes: [String],
        description: FormattedText,
        hideResultsUntilCloses: Bool,
        isAnonymous: Bool,
        isClosed: Bool,
        media: InputPollMedia?,
        membersOnly: Bool,
        openPeriod: Int,
        options: [InputPollOption],
        question: FormattedText,
        shuffleOptions: Bool,
        type: InputPollType
    ) {
        self.allowsMultipleAnswers = allowsMultipleAnswers
        self.allowsRevoting = allowsRevoting
        self.closeDate = closeDate
        self.countryCodes = countryCodes
        self.description = description
        self.hideResultsUntilCloses = hideResultsUntilCloses
        self.isAnonymous = isAnonymous
        self.isClosed = isClosed
        self.media = media
        self.membersOnly = membersOnly
        self.openPeriod = openPeriod
        self.options = options
        self.question = question
        self.shuffleOptions = shuffleOptions
        self.type = type
    }
}

/// A stake dice message
public struct InputMessageStakeDice: Codable, Equatable, Hashable {

    /// Pass true to delete message draft in the chat
    public let clearDraft: Bool

    /// The TON Gram amount that will be staked; in the smallest units of the currency. Must be in the range getOption("stake_dice_stake_amount_min")-getOption("stake_dice_stake_amount_max")
    public let stakeGramAmount: Int64

    /// Hash of the stake dice state. The state hash can be used only if it was received recently enough. Otherwise, a new state must be requested using getStakeDiceState
    public let stateHash: String


    public init(
        clearDraft: Bool,
        stakeGramAmount: Int64,
        stateHash: String
    ) {
        self.clearDraft = clearDraft
        self.stakeGramAmount = stakeGramAmount
        self.stateHash = stateHash
    }
}

/// A message with a forwarded story. Stories can't be forwarded to secret chats. A story can be forwarded only if story.can_be_forwarded
public struct InputMessageStory: Codable, Equatable, Hashable {

    /// Story identifier
    public let storyId: Int

    /// Identifier of the chat that posted the story
    public let storyPosterChatId: Int64


    public init(
        storyId: Int,
        storyPosterChatId: Int64
    ) {
        self.storyId = storyId
        self.storyPosterChatId = storyPosterChatId
    }
}

/// A message with a checklist. Checklists can't be sent to secret chats, channel chats and channel direct messages chats; for Telegram Premium users only
public struct InputMessageChecklist: Codable, Equatable, Hashable {

    /// The checklist to send
    public let checklist: InputChecklist


    public init(checklist: InputChecklist) {
        self.checklist = checklist
    }
}

/// A message with an HTML widget; for bots only
public struct InputMessageWidget: Codable, Equatable, Hashable {

    /// Pass true to allow the widget to send queries to the bot
    public let allowQueries: Bool

    /// Widget caption; pass null to use an empty caption; 0-getOption("message_caption_length_max") characters
    public let caption: FormattedText?

    /// Data of the widget, which is specific to the chat
    public let chatData: String

    /// Height of the widget; 0 if the height of the widget isn't fixed
    public let height: Int

    /// HTML code of the widget; 1-32768 bytes; must not exceed 4096 bytes when compressed by zlib with the maximal compression level
    public let html: String

    /// Pass true to create a shared widget, which can be sent again by its identifier
    public let isShared: Bool

    /// Public data of the widget, which will be available in copies and forwards of the message
    public let publicData: String

    /// True, if the caption must be shown above the widget; otherwise, the caption must be shown below the widget
    public let showCaptionAboveMedia: Bool

    /// Width of the widget; 0 if the widget must occupy the whole width of the message bubble
    public let width: Int


    public init(
        allowQueries: Bool,
        caption: FormattedText?,
        chatData: String,
        height: Int,
        html: String,
        isShared: Bool,
        publicData: String,
        showCaptionAboveMedia: Bool,
        width: Int
    ) {
        self.allowQueries = allowQueries
        self.caption = caption
        self.chatData = chatData
        self.height = height
        self.html = html
        self.isShared = isShared
        self.publicData = publicData
        self.showCaptionAboveMedia = showCaptionAboveMedia
        self.width = width
    }
}

/// A message with an existing shared widget; for bots only
public struct InputMessageSharedWidget: Codable, Equatable, Hashable {

    /// Widget caption; pass null to use an empty caption; 0-getOption("message_caption_length_max") characters
    public let caption: FormattedText?

    /// Data of the widget, which is specific to the chat
    public let chatData: String

    /// True, if the caption must be shown above the widget; otherwise, the caption must be shown below the widget
    public let showCaptionAboveMedia: Bool

    /// Identifier of the shared widget
    public let widgetId: TdInt64


    public init(
        caption: FormattedText?,
        chatData: String,
        showCaptionAboveMedia: Bool,
        widgetId: TdInt64
    ) {
        self.caption = caption
        self.chatData = chatData
        self.showCaptionAboveMedia = showCaptionAboveMedia
        self.widgetId = widgetId
    }
}

/// A forwarded message
public struct InputMessageForwarded: Codable, Equatable, Hashable {

    /// Options to be used to copy content of the message without reference to the original sender; pass null to forward the message as usual
    public let copyOptions: MessageCopyOptions?

    /// Identifier for the chat this forwarded message came from
    public let fromChatId: Int64

    /// Pass true if a game message is being shared from a launched game; applies only to game messages
    public let inGameShare: Bool

    /// Identifier of the message to forward. A message can be forwarded only if messageProperties.can_be_forwarded
    public let messageId: Int64

    /// The new video start timestamp; ignored if replace_video_start_timestamp == false
    public let newVideoStartTimestamp: Int

    /// Pass true to replace video start timestamp in the forwarded message
    public let replaceVideoStartTimestamp: Bool


    public init(
        copyOptions: MessageCopyOptions?,
        fromChatId: Int64,
        inGameShare: Bool,
        messageId: Int64,
        newVideoStartTimestamp: Int,
        replaceVideoStartTimestamp: Bool
    ) {
        self.copyOptions = copyOptions
        self.fromChatId = fromChatId
        self.inGameShare = inGameShare
        self.messageId = messageId
        self.newVideoStartTimestamp = newVideoStartTimestamp
        self.replaceVideoStartTimestamp = replaceVideoStartTimestamp
    }
}

