//
//  Thumbnail.swift
//  tl2swift
//
//  Generated automatically. Any changes will be lost!
//  Based on TDLib 1.8.70-fe61d641-fe61d641
//  https://github.com/tdlib/td/tree/fe61d641
//

import Foundation


/// Represents a thumbnail
public struct Thumbnail: Codable, Equatable, Hashable {

    /// The thumbnail
    public let file: File

    /// Thumbnail format
    public let format: ThumbnailFormat

    /// Thumbnail height
    public let height: Int

    /// Thumbnail width
    public let width: Int


    public init(
        file: File,
        format: ThumbnailFormat,
        height: Int,
        width: Int
    ) {
        self.file = file
        self.format = format
        self.height = height
        self.width = width
    }
}

