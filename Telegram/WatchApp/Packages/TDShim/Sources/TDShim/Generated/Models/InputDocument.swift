//
//  InputDocument.swift
//  tl2swift
//
//  Generated automatically. Any changes will be lost!
//  Based on TDLib 1.8.70-fe61d641-fe61d641
//  https://github.com/tdlib/td/tree/fe61d641
//

import Foundation


/// A document (general file) to be sent
public struct InputDocument: Codable, Equatable, Hashable {

    /// Pass true to disable automatic file type detection and send the document as a file. Always true for files sent to secret chats
    public let disableContentTypeDetection: Bool

    /// File to be sent
    public let document: InputFile

    /// Document thumbnail; pass null to skip thumbnail uploading
    public let thumbnail: InputThumbnail?


    public init(
        disableContentTypeDetection: Bool,
        document: InputFile,
        thumbnail: InputThumbnail?
    ) {
        self.disableContentTypeDetection = disableContentTypeDetection
        self.document = document
        self.thumbnail = thumbnail
    }
}

