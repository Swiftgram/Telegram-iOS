//
//  InputPollMedia.swift
//  tl2swift
//
//  Generated automatically. Any changes will be lost!
//  Based on TDLib 1.8.70-fe61d641-fe61d641
//  https://github.com/tdlib/td/tree/fe61d641
//

import Foundation


/// The content of a poll media to send
public indirect enum InputPollMedia: Codable, Equatable, Hashable {

    /// An animation
    case inputPollMediaAnimation(InputPollMediaAnimation)

    /// An audio
    case inputPollMediaAudio(InputPollMediaAudio)

    /// A document (general file)
    case inputPollMediaDocument(InputPollMediaDocument)

    /// A link
    case inputPollMediaLink(InputPollMediaLink)

    /// A location
    case inputPollMediaLocation(InputPollMediaLocation)

    /// A photo
    case inputPollMediaPhoto(InputPollMediaPhoto)

    /// A sticker
    case inputPollMediaSticker(InputPollMediaSticker)

    /// A venue
    case inputPollMediaVenue(InputPollMediaVenue)

    /// A video
    case inputPollMediaVideo(InputPollMediaVideo)

    /// Decoded when the @type is not one of the known cases (forward-compatible).
    case unsupported

    private enum Kind: String, Codable {
        case inputPollMediaAnimation
        case inputPollMediaAudio
        case inputPollMediaDocument
        case inputPollMediaLink
        case inputPollMediaLocation
        case inputPollMediaPhoto
        case inputPollMediaSticker
        case inputPollMediaVenue
        case inputPollMediaVideo
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DtoCodingKeys.self)
        let typeString = try container.decode(String.self, forKey: .type)
        guard let type = Kind(rawValue: typeString) else {
            self = .unsupported
            return
        }
        switch type {
        case .inputPollMediaAnimation:
            let value = try InputPollMediaAnimation(from: decoder)
            self = .inputPollMediaAnimation(value)
        case .inputPollMediaAudio:
            let value = try InputPollMediaAudio(from: decoder)
            self = .inputPollMediaAudio(value)
        case .inputPollMediaDocument:
            let value = try InputPollMediaDocument(from: decoder)
            self = .inputPollMediaDocument(value)
        case .inputPollMediaLink:
            let value = try InputPollMediaLink(from: decoder)
            self = .inputPollMediaLink(value)
        case .inputPollMediaLocation:
            let value = try InputPollMediaLocation(from: decoder)
            self = .inputPollMediaLocation(value)
        case .inputPollMediaPhoto:
            let value = try InputPollMediaPhoto(from: decoder)
            self = .inputPollMediaPhoto(value)
        case .inputPollMediaSticker:
            let value = try InputPollMediaSticker(from: decoder)
            self = .inputPollMediaSticker(value)
        case .inputPollMediaVenue:
            let value = try InputPollMediaVenue(from: decoder)
            self = .inputPollMediaVenue(value)
        case .inputPollMediaVideo:
            let value = try InputPollMediaVideo(from: decoder)
            self = .inputPollMediaVideo(value)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DtoCodingKeys.self)
        switch self {
        case .inputPollMediaAnimation(let value):
            try container.encode(Kind.inputPollMediaAnimation, forKey: .type)
            try value.encode(to: encoder)
        case .inputPollMediaAudio(let value):
            try container.encode(Kind.inputPollMediaAudio, forKey: .type)
            try value.encode(to: encoder)
        case .inputPollMediaDocument(let value):
            try container.encode(Kind.inputPollMediaDocument, forKey: .type)
            try value.encode(to: encoder)
        case .inputPollMediaLink(let value):
            try container.encode(Kind.inputPollMediaLink, forKey: .type)
            try value.encode(to: encoder)
        case .inputPollMediaLocation(let value):
            try container.encode(Kind.inputPollMediaLocation, forKey: .type)
            try value.encode(to: encoder)
        case .inputPollMediaPhoto(let value):
            try container.encode(Kind.inputPollMediaPhoto, forKey: .type)
            try value.encode(to: encoder)
        case .inputPollMediaSticker(let value):
            try container.encode(Kind.inputPollMediaSticker, forKey: .type)
            try value.encode(to: encoder)
        case .inputPollMediaVenue(let value):
            try container.encode(Kind.inputPollMediaVenue, forKey: .type)
            try value.encode(to: encoder)
        case .inputPollMediaVideo(let value):
            try container.encode(Kind.inputPollMediaVideo, forKey: .type)
            try value.encode(to: encoder)
        case .unsupported:
            try container.encode("unsupported", forKey: .type)
        }
    }
}

/// An animation
public struct InputPollMediaAnimation: Codable, Equatable, Hashable {

    /// The animation to be sent
    public let animation: InputAnimation


    public init(animation: InputAnimation) {
        self.animation = animation
    }
}

/// An audio
public struct InputPollMediaAudio: Codable, Equatable, Hashable {

    /// The audio to be sent
    public let audio: InputAudio


    public init(audio: InputAudio) {
        self.audio = audio
    }
}

/// A document (general file)
public struct InputPollMediaDocument: Codable, Equatable, Hashable {

    /// The document to be sent
    public let document: InputDocument


    public init(document: InputDocument) {
        self.document = document
    }
}

/// A link
public struct InputPollMediaLink: Codable, Equatable, Hashable {

    /// URL of the link
    public let url: String


    public init(url: String) {
        self.url = url
    }
}

/// A location
public struct InputPollMediaLocation: Codable, Equatable, Hashable {

    /// Location to be sent
    public let location: Location


    public init(location: Location) {
        self.location = location
    }
}

/// A photo
public struct InputPollMediaPhoto: Codable, Equatable, Hashable {

    /// Photo to be sent
    public let photo: InputPhoto


    public init(photo: InputPhoto) {
        self.photo = photo
    }
}

/// A sticker
public struct InputPollMediaSticker: Codable, Equatable, Hashable {

    /// Sticker to be sent
    public let sticker: InputSticker


    public init(sticker: InputSticker) {
        self.sticker = sticker
    }
}

/// A venue
public struct InputPollMediaVenue: Codable, Equatable, Hashable {

    /// Venue to send
    public let venue: Venue


    public init(venue: Venue) {
        self.venue = venue
    }
}

/// A video
public struct InputPollMediaVideo: Codable, Equatable, Hashable {

    /// The video to be sent
    public let video: InputVideo


    public init(video: InputVideo) {
        self.video = video
    }
}

