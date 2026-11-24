//
//  PollOption.swift
//  tl2swift
//
//  Generated automatically. Any changes will be lost!
//  Based on TDLib 1.8.70-fe61d641-fe61d641
//  https://github.com/tdlib/td/tree/fe61d641
//

import Foundation


/// Describes one answer option of a poll
public struct PollOption: Codable, Equatable, Hashable, Identifiable {

    /// Point in time (Unix timestamp) when the option was added; 0 if the option existed from creation of the poll
    public let additionDate: Int

    /// Identifier of the user or chat who added the option; may be null if the option existed from creation of the poll
    public let author: MessageSender?

    /// Unique identifier of the option in the poll; may be empty if yet unassigned
    public let id: String

    /// True, if the option is being chosen by a pending setPollAnswer request
    public let isBeingChosen: Bool

    /// True, if the option was chosen by the user
    public let isChosen: Bool

    /// Option media; may be null if none. If present, currently, can be only of the types pollMediaAnimation, pollMediaLink, pollMediaLocation, pollMediaPhoto, pollMediaSticker, pollMediaVenue, or pollMediaVideo
    public let media: PollMedia?

    /// Identifiers of recent voters for the option, if the poll is non-anonymous and poll results are available
    public let recentVoterIds: [MessageSender]

    /// Option text; 1-100 characters; may contain only custom emoji entities
    public let text: FormattedText

    /// The percentage of votes for this option; 0-100
    public let votePercentage: Int

    /// Number of voters for this option, available only for closed or voted polls, or if the current user is the creator of the poll
    public let voterCount: Int


    public init(
        additionDate: Int,
        author: MessageSender?,
        id: String,
        isBeingChosen: Bool,
        isChosen: Bool,
        media: PollMedia?,
        recentVoterIds: [MessageSender],
        text: FormattedText,
        votePercentage: Int,
        voterCount: Int
    ) {
        self.additionDate = additionDate
        self.author = author
        self.id = id
        self.isBeingChosen = isBeingChosen
        self.isChosen = isChosen
        self.media = media
        self.recentVoterIds = recentVoterIds
        self.text = text
        self.votePercentage = votePercentage
        self.voterCount = voterCount
    }
}

