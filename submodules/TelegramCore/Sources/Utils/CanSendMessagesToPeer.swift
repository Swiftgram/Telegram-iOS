import Foundation
import Postbox


// Incuding at least one Objective-C class in a swift file ensures that it doesn't get stripped by the linker
private final class LinkHelperClass: NSObject {
}

public func canSendMessagesToPeer(_ peer: EnginePeer, ignoreDefault: Bool = false) -> Bool {
    if case let .user(user) = peer, user.addressName == "replies" {
        return false
    }
    switch peer {
    case .user, .legacyGroup:
        return !peer.isDeleted
    case let .secretChat(secretChat):
        return secretChat.embeddedState == .active
    case let .channel(channel):
        return channel.hasPermission(.sendSomething, ignoreDefault: ignoreDefault)
    }
}
