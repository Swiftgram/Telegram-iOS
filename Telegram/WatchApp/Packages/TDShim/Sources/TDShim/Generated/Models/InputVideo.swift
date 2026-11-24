//
//  InputVideo.swift
//  tl2swift
//
//  Generated automatically. Any changes will be lost!
//  Based on TDLib 1.8.70-fe61d641-fe61d641
//  https://github.com/tdlib/td/tree/fe61d641
//

import Foundation


/// A video to be sent
public struct InputVideo: Codable, Equatable, Hashable {

    /// File identifiers of the stickers added to the video, if applicable
    public let addedStickerFileIds: [Int]

    /// Cover of the video; pass null to skip cover uploading; not supported in secret chats and for self-destructing messages
    public let cover: InputFile?

    /// Duration of the video, in seconds
    public let duration: Int

    /// Video height
    public let height: Int

    /// Timestamp from which the video playing must start, in seconds
    public let startTimestamp: Int

    /// True, if the video is expected to be streamed
    public let supportsStreaming: Bool

    /// Video thumbnail; pass null to skip thumbnail uploading
    public let thumbnail: InputThumbnail?

    /// Video file to be sent. The video is expected to be re-encoded to MPEG4 format with H.264 codec by the sender
    public let video: InputFile

    /// Video width
    public let width: Int


    public init(
        addedStickerFileIds: [Int],
        cover: InputFile?,
        duration: Int,
        height: Int,
        startTimestamp: Int,
        supportsStreaming: Bool,
        thumbnail: InputThumbnail?,
        video: InputFile,
        width: Int
    ) {
        self.addedStickerFileIds = addedStickerFileIds
        self.cover = cover
        self.duration = duration
        self.height = height
        self.startTimestamp = startTimestamp
        self.supportsStreaming = supportsStreaming
        self.thumbnail = thumbnail
        self.video = video
        self.width = width
    }
}

