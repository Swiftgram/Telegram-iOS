//
//  MessageForwardInfo.swift
//  tl2swift
//
//  Generated automatically. Any changes will be lost!
//  Based on TDLib 1.8.70-fe61d641-fe61d641
//  https://github.com/tdlib/td/tree/fe61d641
//

import Foundation


/// Contains information about a forwarded message
public struct MessageForwardInfo: Codable, Equatable, Hashable {

    /// Point in time (Unix timestamp) when the message was originally sent
    public let date: Int

    /// Origin of the forwarded message
    public let origin: MessageOrigin

    /// The type of public service announcement for the forwarded message
    public let publicServiceAnnouncementType: String

    /// For messages forwarded to the chat with the current user (Saved Messages), to the Replies bot chat, or to the channel's discussion group, information about the source message from which the message was forwarded last time; may be null for other forwards or if unknown
    public let source: ForwardSource?


    public init(
        date: Int,
        origin: MessageOrigin,
        publicServiceAnnouncementType: String,
        source: ForwardSource?
    ) {
        self.date = date
        self.origin = origin
        self.publicServiceAnnouncementType = publicServiceAnnouncementType
        self.source = source
    }
}

