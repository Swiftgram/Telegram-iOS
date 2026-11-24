//
//  PollMedia.swift
//  tl2swift
//
//  Generated automatically. Any changes will be lost!
//  Based on TDLib 1.8.70-fe61d641-fe61d641
//  https://github.com/tdlib/td/tree/fe61d641
//

import Foundation


/// Contains the media in a poll
public indirect enum PollMedia: Codable, Equatable, Hashable {

    /// An animation
    case pollMediaAnimation(PollMediaAnimation)

    /// An audio
    case pollMediaAudio(PollMediaAudio)

    /// A document (general file)
    case pollMediaDocument(PollMediaDocument)

    /// A link
    case pollMediaLink(PollMediaLink)

    /// A location
    case pollMediaLocation(PollMediaLocation)

    /// A photo
    case pollMediaPhoto(PollMediaPhoto)

    /// A sticker
    case pollMediaSticker(PollMediaSticker)

    /// A venue
    case pollMediaVenue(PollMediaVenue)

    /// A video
    case pollMediaVideo(PollMediaVideo)

    /// Decoded when the @type is not one of the known cases (forward-compatible).
    case unsupported

    private enum Kind: String, Codable {
        case pollMediaAnimation
        case pollMediaAudio
        case pollMediaDocument
        case pollMediaLink
        case pollMediaLocation
        case pollMediaPhoto
        case pollMediaSticker
        case pollMediaVenue
        case pollMediaVideo
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DtoCodingKeys.self)
        let typeString = try container.decode(String.self, forKey: .type)
        guard let type = Kind(rawValue: typeString) else {
            self = .unsupported
            return
        }
        switch type {
        case .pollMediaAnimation:
            let value = try PollMediaAnimation(from: decoder)
            self = .pollMediaAnimation(value)
        case .pollMediaAudio:
            let value = try PollMediaAudio(from: decoder)
            self = .pollMediaAudio(value)
        case .pollMediaDocument:
            let value = try PollMediaDocument(from: decoder)
            self = .pollMediaDocument(value)
        case .pollMediaLink:
            let value = try PollMediaLink(from: decoder)
            self = .pollMediaLink(value)
        case .pollMediaLocation:
            let value = try PollMediaLocation(from: decoder)
            self = .pollMediaLocation(value)
        case .pollMediaPhoto:
            let value = try PollMediaPhoto(from: decoder)
            self = .pollMediaPhoto(value)
        case .pollMediaSticker:
            let value = try PollMediaSticker(from: decoder)
            self = .pollMediaSticker(value)
        case .pollMediaVenue:
            let value = try PollMediaVenue(from: decoder)
            self = .pollMediaVenue(value)
        case .pollMediaVideo:
            let value = try PollMediaVideo(from: decoder)
            self = .pollMediaVideo(value)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DtoCodingKeys.self)
        switch self {
        case .pollMediaAnimation(let value):
            try container.encode(Kind.pollMediaAnimation, forKey: .type)
            try value.encode(to: encoder)
        case .pollMediaAudio(let value):
            try container.encode(Kind.pollMediaAudio, forKey: .type)
            try value.encode(to: encoder)
        case .pollMediaDocument(let value):
            try container.encode(Kind.pollMediaDocument, forKey: .type)
            try value.encode(to: encoder)
        case .pollMediaLink(let value):
            try container.encode(Kind.pollMediaLink, forKey: .type)
            try value.encode(to: encoder)
        case .pollMediaLocation(let value):
            try container.encode(Kind.pollMediaLocation, forKey: .type)
            try value.encode(to: encoder)
        case .pollMediaPhoto(let value):
            try container.encode(Kind.pollMediaPhoto, forKey: .type)
            try value.encode(to: encoder)
        case .pollMediaSticker(let value):
            try container.encode(Kind.pollMediaSticker, forKey: .type)
            try value.encode(to: encoder)
        case .pollMediaVenue(let value):
            try container.encode(Kind.pollMediaVenue, forKey: .type)
            try value.encode(to: encoder)
        case .pollMediaVideo(let value):
            try container.encode(Kind.pollMediaVideo, forKey: .type)
            try value.encode(to: encoder)
        case .unsupported:
            try container.encode("unsupported", forKey: .type)
        }
    }
}

/// An animation
public struct PollMediaAnimation: Codable, Equatable, Hashable {

    /// The animation
    public let animation: Animation


    public init(animation: Animation) {
        self.animation = animation
    }
}

/// An audio
public struct PollMediaAudio: Codable, Equatable, Hashable {

    /// The audio
    public let audio: Audio


    public init(audio: Audio) {
        self.audio = audio
    }
}

/// A document (general file)
public struct PollMediaDocument: Codable, Equatable, Hashable {

    /// The document
    public let document: Document


    public init(document: Document) {
        self.document = document
    }
}

/// A link
public struct PollMediaLink: Codable, Equatable, Hashable {

    /// Preview of the link; may be null if unknown
    public let linkPreview: LinkPreview?

    /// URL of the link
    public let url: String


    public init(
        linkPreview: LinkPreview?,
        url: String
    ) {
        self.linkPreview = linkPreview
        self.url = url
    }
}

/// A location
public struct PollMediaLocation: Codable, Equatable, Hashable {

    /// The location
    public let location: Location


    public init(location: Location) {
        self.location = location
    }
}

/// A photo
public struct PollMediaPhoto: Codable, Equatable, Hashable {

    /// The photo
    public let photo: Photo

    /// The video representing the live photo; may be null if the photo is static
    public let video: Video?


    public init(
        photo: Photo,
        video: Video?
    ) {
        self.photo = photo
        self.video = video
    }
}

/// A sticker
public struct PollMediaSticker: Codable, Equatable, Hashable {

    /// The sticker
    public let sticker: Sticker


    public init(sticker: Sticker) {
        self.sticker = sticker
    }
}

/// A venue
public struct PollMediaVenue: Codable, Equatable, Hashable {

    /// The venue
    public let venue: Venue


    public init(venue: Venue) {
        self.venue = venue
    }
}

/// A video
public struct PollMediaVideo: Codable, Equatable, Hashable {

    /// Alternative qualities of the video
    public let alternativeVideos: [AlternativeVideo]

    /// Cover of the video; may be null if none
    public let cover: Photo?

    /// Timestamp from which the video playing must start, in seconds
    public let startTimestamp: Int

    /// Available storyboards for the video
    public let storyboards: [VideoStoryboard]

    /// The video description
    public let video: Video


    public init(
        alternativeVideos: [AlternativeVideo],
        cover: Photo?,
        startTimestamp: Int,
        storyboards: [VideoStoryboard],
        video: Video
    ) {
        self.alternativeVideos = alternativeVideos
        self.cover = cover
        self.startTimestamp = startTimestamp
        self.storyboards = storyboards
        self.video = video
    }
}

