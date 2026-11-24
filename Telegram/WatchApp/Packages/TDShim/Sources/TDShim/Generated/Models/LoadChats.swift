//
//  LoadChats.swift
//  tl2swift
//
//  Generated automatically. Any changes will be lost!
//  Based on TDLib 1.8.70-fe61d641-fe61d641
//  https://github.com/tdlib/td/tree/fe61d641
//

import Foundation


/// Loads more chats from a chat list. The loaded chats and their positions in the chat list will be sent through updates. Chats are sorted by the pair (chatPosition.order, chat.id) in descending order. Returns a 404 error if all chats have been loaded
public struct LoadChats: Codable, Equatable, Hashable {

    /// The chat list in which to load chats; pass null to load chats from the main chat list
    public let chatList: ChatList?

    /// The maximum number of chats to be loaded. For optimal performance, the number of loaded chats is chosen by TDLib and can be smaller than the specified limit, even if the end of the list is not reached
    public let limit: Int?


    public init(
        chatList: ChatList?,
        limit: Int?
    ) {
        self.chatList = chatList
        self.limit = limit
    }
}

