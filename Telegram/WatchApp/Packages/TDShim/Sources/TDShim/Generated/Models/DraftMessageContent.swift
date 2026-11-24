//
//  DraftMessageContent.swift
//  tl2swift
//
//  Generated automatically. Any changes will be lost!
//  Based on TDLib 1.8.70-fe61d641-fe61d641
//  https://github.com/tdlib/td/tree/fe61d641
//

import Foundation


/// Content of the message draft
public indirect enum DraftMessageContent: Codable, Equatable, Hashable {

    /// A text message draft
    case draftMessageContentText(DraftMessageContentText)

    /// A video note message draft
    case draftMessageContentVideoNote(DraftMessageContentVideoNote)

    /// A voice note message draft
    case draftMessageContentVoiceNote(DraftMessageContentVoiceNote)

    /// Decoded when the @type is not one of the known cases (forward-compatible).
    case unsupported

    private enum Kind: String, Codable {
        case draftMessageContentText
        case draftMessageContentVideoNote
        case draftMessageContentVoiceNote
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DtoCodingKeys.self)
        let typeString = try container.decode(String.self, forKey: .type)
        guard let type = Kind(rawValue: typeString) else {
            self = .unsupported
            return
        }
        switch type {
        case .draftMessageContentText:
            let value = try DraftMessageContentText(from: decoder)
            self = .draftMessageContentText(value)
        case .draftMessageContentVideoNote:
            let value = try DraftMessageContentVideoNote(from: decoder)
            self = .draftMessageContentVideoNote(value)
        case .draftMessageContentVoiceNote:
            let value = try DraftMessageContentVoiceNote(from: decoder)
            self = .draftMessageContentVoiceNote(value)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DtoCodingKeys.self)
        switch self {
        case .draftMessageContentText(let value):
            try container.encode(Kind.draftMessageContentText, forKey: .type)
            try value.encode(to: encoder)
        case .draftMessageContentVideoNote(let value):
            try container.encode(Kind.draftMessageContentVideoNote, forKey: .type)
            try value.encode(to: encoder)
        case .draftMessageContentVoiceNote(let value):
            try container.encode(Kind.draftMessageContentVoiceNote, forKey: .type)
            try value.encode(to: encoder)
        case .unsupported:
            try container.encode("unsupported", forKey: .type)
        }
    }
}

/// A text message draft
public struct DraftMessageContentText: Codable, Equatable, Hashable {

    /// Options to be used for generation of a link preview; may be null if none; pass null to use default link preview options
    public let linkPreviewOptions: LinkPreviewOptions?

    /// Formatted text to be saved as a draft; 0-getOption("message_text_length_max") characters
    public let text: FormattedText


    public init(
        linkPreviewOptions: LinkPreviewOptions?,
        text: FormattedText
    ) {
        self.linkPreviewOptions = linkPreviewOptions
        self.text = text
    }
}

/// A video note message draft
public struct DraftMessageContentVideoNote: Codable, Equatable, Hashable {

    /// Duration of the video, in seconds; 0-60
    public let duration: Int

    /// Path to the file with the video note
    public let filePath: String

    /// Video width and height; must be positive and not greater than 640
    public let length: Int

    /// Video note self-destruct type; may be null if none; pass null if none; private chats only
    public let selfDestructType: MessageSelfDestructType?


    public init(
        duration: Int,
        filePath: String,
        length: Int,
        selfDestructType: MessageSelfDestructType?
    ) {
        self.duration = duration
        self.filePath = filePath
        self.length = length
        self.selfDestructType = selfDestructType
    }
}

/// A voice note message draft
public struct DraftMessageContentVoiceNote: Codable, Equatable, Hashable {

    /// Duration of the voice note, in seconds
    public let duration: Int

    /// Path to the file with the voice note
    public let filePath: String

    /// Voice note self-destruct type; may be null if none; pass null if none; private chats only
    public let selfDestructType: MessageSelfDestructType?

    /// Waveform representation of the voice note in 5-bit format
    public let waveform: Data


    public init(
        duration: Int,
        filePath: String,
        selfDestructType: MessageSelfDestructType?,
        waveform: Data
    ) {
        self.duration = duration
        self.filePath = filePath
        self.selfDestructType = selfDestructType
        self.waveform = waveform
    }
}

