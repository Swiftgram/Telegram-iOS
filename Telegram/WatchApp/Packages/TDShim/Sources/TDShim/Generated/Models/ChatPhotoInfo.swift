//
//  ChatPhotoInfo.swift
//  tl2swift
//
//  Generated automatically. Any changes will be lost!
//  Based on TDLib 1.8.70-fe61d641-fe61d641
//  https://github.com/tdlib/td/tree/fe61d641
//

import Foundation


/// Contains basic information about the photo of a chat
public struct ChatPhotoInfo: Codable, Equatable, Hashable {

    /// A big (640x640) chat photo variant in JPEG format. The file can be downloaded only before the photo is changed
    public let big: File

    /// True, if the photo has animated variant
    public let hasAnimation: Bool

    /// True, if the photo is visible only for the current user
    public let isPersonal: Bool

    /// Chat photo minithumbnail; may be null
    public let minithumbnail: Minithumbnail?

    /// A small (160x160) chat photo variant in JPEG format. The file can be downloaded only before the photo is changed
    public let small: File


    public init(
        big: File,
        hasAnimation: Bool,
        isPersonal: Bool,
        minithumbnail: Minithumbnail?,
        small: File
    ) {
        self.big = big
        self.hasAnimation = hasAnimation
        self.isPersonal = isPersonal
        self.minithumbnail = minithumbnail
        self.small = small
    }
}

