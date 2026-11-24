//
//  File.swift
//  tl2swift
//
//  Generated automatically. Any changes will be lost!
//  Based on TDLib 1.8.70-fe61d641-fe61d641
//  https://github.com/tdlib/td/tree/fe61d641
//

import Foundation


/// Represents a file
public struct File: Codable, Equatable, Hashable, Identifiable {

    /// Approximate file size in bytes in case the exact file size is unknown. Can be used to show download/upload progress
    public let expectedSize: Int64

    /// Unique file identifier
    public let id: Int

    /// Information about the local copy of the file
    public let local: LocalFile

    /// Information about the remote copy of the file
    public let remote: RemoteFile

    /// File size, in bytes; 0 if unknown
    public let size: Int64


    public init(
        expectedSize: Int64,
        id: Int,
        local: LocalFile,
        remote: RemoteFile,
        size: Int64
    ) {
        self.expectedSize = expectedSize
        self.id = id
        self.local = local
        self.remote = remote
        self.size = size
    }
}

