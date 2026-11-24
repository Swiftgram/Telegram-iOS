//
//  LiveLocation.swift
//  tl2swift
//
//  Generated automatically. Any changes will be lost!
//  Based on TDLib 1.8.70-fe61d641-fe61d641
//  https://github.com/tdlib/td/tree/fe61d641
//

import Foundation


/// A live location
public struct LiveLocation: Codable, Equatable, Hashable {

    /// The direction in which the location moves, in degrees; 1-360; 0 if unknown
    public let heading: Int

    /// Time relative to the message send date, for which the location can be updated, in seconds; if 0x7FFFFFFF, then location can be updated forever
    public let livePeriod: Int

    /// The current location
    public let location: Location

    /// The maximum distance to another chat member for proximity alerts, in meters (0-100000). 0 if the notification is disabled. Can't be enabled in direct messages chats, channels and Saved Messages. Available only to the message sender
    public let proximityAlertRadius: Int


    public init(
        heading: Int,
        livePeriod: Int,
        location: Location,
        proximityAlertRadius: Int
    ) {
        self.heading = heading
        self.livePeriod = livePeriod
        self.location = location
        self.proximityAlertRadius = proximityAlertRadius
    }
}

