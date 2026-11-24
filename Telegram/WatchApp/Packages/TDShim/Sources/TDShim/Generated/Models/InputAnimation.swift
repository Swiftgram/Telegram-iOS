//
//  InputAnimation.swift
//  tl2swift
//
//  Generated automatically. Any changes will be lost!
//  Based on TDLib 1.8.70-fe61d641-fe61d641
//  https://github.com/tdlib/td/tree/fe61d641
//

import Foundation


/// An animation to be sent
public struct InputAnimation: Codable, Equatable, Hashable {

    /// File identifiers of the stickers added to the animation, if applicable
    public let addedStickerFileIds: [Int]

    /// Animation file to be sent
    public let animation: InputFile

    /// Duration of the animation, in seconds; may be replaced by the server
    public let duration: Int

    /// Height of the animation; may be replaced by the server
    public let height: Int

    /// Animation thumbnail; pass null to skip thumbnail uploading
    public let thumbnail: InputThumbnail?

    /// Width of the animation; may be replaced by the server
    public let width: Int


    public init(
        addedStickerFileIds: [Int],
        animation: InputFile,
        duration: Int,
        height: Int,
        thumbnail: InputThumbnail?,
        width: Int
    ) {
        self.addedStickerFileIds = addedStickerFileIds
        self.animation = animation
        self.duration = duration
        self.height = height
        self.thumbnail = thumbnail
        self.width = width
    }
}

