//
//  InputVideoNote.swift
//  tl2swift
//
//  Generated automatically. Any changes will be lost!
//  Based on TDLib 1.8.70-fe61d641-fe61d641
//  https://github.com/tdlib/td/tree/fe61d641
//

import Foundation


/// A video note to be sent
public struct InputVideoNote: Codable, Equatable, Hashable {

    /// Duration of the video, in seconds; 0-60
    public let duration: Int

    /// Video width and height; must be positive and not greater than 640
    public let length: Int

    /// Video thumbnail; may be null if empty; pass null to skip thumbnail uploading
    public let thumbnail: InputThumbnail?

    /// Video note file to be sent. The video is expected to be encoded to MPEG4 format with H.264 codec and have no data outside of the visible circle
    public let videoNote: InputFile


    public init(
        duration: Int,
        length: Int,
        thumbnail: InputThumbnail?,
        videoNote: InputFile
    ) {
        self.duration = duration
        self.length = length
        self.thumbnail = thumbnail
        self.videoNote = videoNote
    }
}

