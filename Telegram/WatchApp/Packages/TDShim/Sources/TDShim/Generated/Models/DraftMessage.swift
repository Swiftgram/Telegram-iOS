//
//  DraftMessage.swift
//  tl2swift
//
//  Generated automatically. Any changes will be lost!
//  Based on TDLib 1.8.70-fe61d641-fe61d641
//  https://github.com/tdlib/td/tree/fe61d641
//

import Foundation


/// Contains information about a message draft
public struct DraftMessage: Codable, Equatable, Hashable {

    /// Content of the message draft
    public let content: DraftMessageContent

    /// Point in time (Unix timestamp) when the draft was created
    public let date: Int

    /// Identifier of the effect to apply to the message when it is sent; 0 if none
    public let effectId: TdInt64

    /// Information about the message to be replied; inputMessageReplyToStory is unsupported; may be null if none
    public let replyTo: InputMessageReplyTo?

    /// Information about the suggested post; may be null if none
    public let suggestedPostInfo: InputSuggestedPostInfo?


    public init(
        content: DraftMessageContent,
        date: Int,
        effectId: TdInt64,
        replyTo: InputMessageReplyTo?,
        suggestedPostInfo: InputSuggestedPostInfo?
    ) {
        self.content = content
        self.date = date
        self.effectId = effectId
        self.replyTo = replyTo
        self.suggestedPostInfo = suggestedPostInfo
    }
}

