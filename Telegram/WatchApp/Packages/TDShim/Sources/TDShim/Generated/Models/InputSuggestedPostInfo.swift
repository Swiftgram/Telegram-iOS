//
//  InputSuggestedPostInfo.swift
//  tl2swift
//
//  Generated automatically. Any changes will be lost!
//  Based on TDLib 1.8.70-fe61d641-fe61d641
//  https://github.com/tdlib/td/tree/fe61d641
//

import Foundation


/// Contains information about a post to suggest
public struct InputSuggestedPostInfo: Codable, Equatable, Hashable {

    /// Price of the suggested post; pass null to suggest a post without payment. If the current user isn't an administrator of the channel direct messages chat and doesn't have enough funds to pay for the post, then the error "BALANCE_TOO_LOW" will be returned immediately
    public let price: SuggestedPostPrice?

    /// Point in time (Unix timestamp) when the post is expected to be published; pass 0 if the date isn't restricted. If specified, then the date must be getOption("suggested_post_send_delay_min")-getOption("suggested_post_send_delay_max") seconds in the future
    public let sendDate: Int


    public init(
        price: SuggestedPostPrice?,
        sendDate: Int
    ) {
        self.price = price
        self.sendDate = sendDate
    }
}

