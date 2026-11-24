//
//  InputAudio.swift
//  tl2swift
//
//  Generated automatically. Any changes will be lost!
//  Based on TDLib 1.8.70-fe61d641-fe61d641
//  https://github.com/tdlib/td/tree/fe61d641
//

import Foundation


/// An audio to be sent
public struct InputAudio: Codable, Equatable, Hashable {

    /// Thumbnail of the cover for the album; pass null to skip thumbnail uploading
    public let albumCoverThumbnail: InputThumbnail?

    /// Audio file to be sent
    public let audio: InputFile

    /// Duration of the audio, in seconds; may be replaced by the server
    public let duration: Int

    /// Performer of the audio; 0-64 characters, may be replaced by the server
    public let performer: String

    /// Title of the audio; 0-64 characters; may be replaced by the server
    public let title: String


    public init(
        albumCoverThumbnail: InputThumbnail?,
        audio: InputFile,
        duration: Int,
        performer: String,
        title: String
    ) {
        self.albumCoverThumbnail = albumCoverThumbnail
        self.audio = audio
        self.duration = duration
        self.performer = performer
        self.title = title
    }
}

