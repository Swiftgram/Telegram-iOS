import Foundation

/// TrollTweaks toggles: the keys, their defaults and how the TrollTweaks screen groups them.
///
/// Storage is the local `app.trollgram.ios.privacy` suite. The privacy protections ship enabled, so an unset key
/// reads as `true` unless `defaultValues` says otherwise. `TrollPrivacyBootstrap` mirrors the values into TelegramCore.
public enum TrollPrivacyOptions {
    public enum Key {
        public static let antiDelete = "tg_privacy_anti_delete"
        public static let editHistory = "tg_privacy_edit_history"
        public static let saveSelfDestructing = "tg_privacy_save_selfdestruct"
        public static let viewOnce = "tg_privacy_view_once"
        public static let ghostMode = "tg_privacy_ghost_mode"
        public static let ghostHideOnline = "tg_privacy_ghost_hide_online"
        public static let ghostHideRead = "tg_privacy_ghost_hide_read"
        public static let ghostHideTyping = "tg_privacy_ghost_hide_typing"
        public static let ghostHideUpload = "tg_privacy_ghost_hide_upload"
        public static let ghostHideStories = "tg_privacy_ghost_hide_stories"
        public static let ghostHideChannelViews = "tg_privacy_ghost_hide_views"
        public static let allowCopy = "tg_privacy_allow_copy"
        public static let removeSponsored = "tg_privacy_remove_sponsored"
    }

    /// Keys whose default is not `true`. None today: every TrollTweaks feature ships enabled.
    public static let defaultValues: [String: Bool] = [:]

    public static var defaults: UserDefaults {
        return UserDefaults(suiteName: "app.trollgram.ios.privacy") ?? .standard
    }

    public static func flag(_ key: String) -> Bool {
        if defaults.object(forKey: key) == nil {
            return defaultValues[key] ?? true
        }
        return defaults.bool(forKey: key)
    }

    public static func setFlag(_ key: String, _ value: Bool) {
        defaults.set(value, forKey: key)
        defaults.synchronize()
    }

    public struct Row {
        public let key: String
        public let title: String
        /// Greyed out while Ghost Mode is off (the sub-switches only act inside it).
        public let requiresGhostMode: Bool
    }

    public struct Group {
        public let title: String
        public let footer: String
        /// Show the saved-messages log (open, clear) under this group.
        public let showsArchive: Bool
        public let rows: [Row]
    }

    public static let groups: [Group] = [
        Group(
            title: "GHOST MODE",
            footer: "While Ghost Mode is on, Telegram is not told about the activity you switch off here, so others cannot see it. Chats you read this way can keep showing as unread on your other devices.",
            showsArchive: false,
            rows: [
                Row(key: Key.ghostMode, title: "Ghost Mode", requiresGhostMode: false),
                Row(key: Key.ghostHideOnline, title: "Hide Online Status", requiresGhostMode: true),
                Row(key: Key.ghostHideRead, title: "Hide Read Receipts", requiresGhostMode: true),
                Row(key: Key.ghostHideTyping, title: "Hide Typing Status", requiresGhostMode: true),
                Row(key: Key.ghostHideUpload, title: "Hide Uploading Status", requiresGhostMode: true),
                Row(key: Key.ghostHideStories, title: "Hide Story Views", requiresGhostMode: true),
                Row(key: Key.ghostHideChannelViews, title: "Hide Channel Post Views", requiresGhostMode: true)
            ]
        ),
        Group(
            title: "SAVED MESSAGES",
            footer: "Copies are kept in a log on this device only; nothing is sent anywhere and deleted messages do not come back into the chat. Media is saved only if it was already downloaded. Messages you delete yourself are logged too, until you clear the log.",
            showsArchive: true,
            rows: [
                Row(key: Key.antiDelete, title: "Save Deleted Messages", requiresGhostMode: false),
                Row(key: Key.editHistory, title: "Save Edit History", requiresGhostMode: false),
                Row(key: Key.saveSelfDestructing, title: "Save Self-Destructing Media", requiresGhostMode: false),
                Row(key: Key.viewOnce, title: "Keep Self-Destructing Media Replayable", requiresGhostMode: false)
            ]
        ),
        Group(
            title: "CONTENT",
            footer: "",
            showsArchive: false,
            rows: [
                Row(key: Key.removeSponsored, title: "Remove Sponsored Messages", requiresGhostMode: false),
                Row(key: Key.allowCopy, title: "Copy Protected Content", requiresGhostMode: false)
            ]
        )
    ]
}
