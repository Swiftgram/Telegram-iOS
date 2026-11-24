//
//  InputPhoto.swift
//  tl2swift
//
//  Generated automatically. Any changes will be lost!
//  Based on TDLib 1.8.70-fe61d641-fe61d641
//  https://github.com/tdlib/td/tree/fe61d641
//

import Foundation


/// A photo to be sent
public struct InputPhoto: Codable, Equatable, Hashable {

    /// File identifiers of the stickers added to the photo, if applicable
    public let addedStickerFileIds: [Int]

    /// Photo height; may be replaced by the server
    public let height: Int

    /// Photo to be sent. The photo must be at most 10 MB in size. The photo's width and height must not exceed 10000 in total. Width and height ratio must be at most 20
    public let photo: InputFile

    /// Photo thumbnail; pass null to skip thumbnail uploading. The thumbnail is sent to the other party only in secret chats
    public let thumbnail: InputThumbnail?

    /// Video of the live photo; not supported in secret chats; pass null if the photo isn't a live photo
    public let video: InputFile?

    /// Photo width; may be replaced by the server
    public let width: Int


    public init(
        addedStickerFileIds: [Int],
        height: Int,
        photo: InputFile,
        thumbnail: InputThumbnail?,
        video: InputFile?,
        width: Int
    ) {
        self.addedStickerFileIds = addedStickerFileIds
        self.height = height
        self.photo = photo
        self.thumbnail = thumbnail
        self.video = video
        self.width = width
    }
}

