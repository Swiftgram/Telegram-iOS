import Foundation
import Observation
import TDShim

/// Single source of truth for `[userId: firstName]` resolved from TDLib's
/// `updateUser` events. Owned by `TDClient`; injected into `ChatListStore`
/// and `ChatHistoryStore` at construction. Lifetime tied to the active
/// `TDClient` — account switch rebuilds it.
///
/// Stores `firstName` (matches the existing single-field shape used
/// by `senderName(...)`, `senderPrefix(...)`, `replyPreview(...)`,
/// `serviceActor(...)`).
@Observable @MainActor
final class UserNamesStore {
    private(set) var names: [Int64: String] = [:]
    // MARK: Swiftgram
    private(set) var avatars: [Int64: AvatarVisual] = [:]
    //

    /// Absorbs `.updateUser` events. Other update kinds are ignored. Idempotent.
    func handle(_ update: Update) {
        if case .updateUser(let upd) = update {
            names[upd.user.id] = upd.user.firstName
            // MARK: Swiftgram
            avatars[upd.user.id] = AvatarVisual(
                kind: .normal,
                initials: avatarInitials(from: upd.user.firstName),
                colorIndex: paletteIndex(for: upd.user.id),
                photoFileId: upd.user.profilePhoto?.small.id,
                photoLocalPath: nil,
                mini: upd.user.profilePhoto?.minithumbnail?.data
            )
            //
        }
    }
}
