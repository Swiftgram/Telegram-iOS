import Foundation
import TelegramCore
import SGTrollPrivacy

/// Mirrors TrollGram privacy flags into TelegramCore.
///
/// The flags live in the local `app.trollgram.ios.privacy` suite and are read
/// here directly, so the UI module only needs `SGTrollPrivacy` for the rows.
public enum TrollPrivacyBootstrap {
    private static var activated = false

    public static func flag(_ key: String) -> Bool {
        return TrollPrivacyOptions.flag(key)
    }

    /// Call once at launch, before the network is started.
    public static func activate() {
        guard !activated else {
            return
        }
        activated = true
        mirror()
    }

    /// Re-reads every flag and pushes it into TelegramCore.
    public static func mirror() {
        typealias Key = TrollPrivacyOptions.Key
        TrollPrivacyRuntime.apply(
            ghostMode: flag(Key.ghostMode),
            hideOnline: flag(Key.ghostHideOnline),
            hideReadReceipts: flag(Key.ghostHideRead),
            hideTyping: flag(Key.ghostHideTyping),
            hideUploading: flag(Key.ghostHideUpload),
            allowCopyProtectedPeers: flag(Key.allowCopy),
            removeSponsoredMessages: flag(Key.removeSponsored),
            viewOnceMediaUnlocked: flag(Key.viewOnce)
        )
        TrollPrivacyRuntime.setArchiveFlags(
            antiDelete: flag(Key.antiDelete),
            editHistory: flag(Key.editHistory),
            saveSelfDestructingMedia: flag(Key.saveSelfDestructing)
        )
        TrollPrivacyRuntime.setGhostViewFlags(
            hideStoryViews: flag(Key.ghostHideStories),
            hideChannelViews: flag(Key.ghostHideChannelViews)
        )
    }
}
