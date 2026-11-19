import Foundation

/// Process-wide privacy overrides.
///
/// Lives in TelegramCore because the gates sit inside the networking layer
/// (read receipts, typing, presence). The UI writes the values through
/// `TrollPrivacySettings` and mirrors them here on every change.
public enum TrollPrivacyRuntime {
    private static let lock = NSLock()
    private static var _ghostMode = false
    private static var _hideReadReceipts = false
    private static var _hideTyping = false
    private static var _hideUploading = false
    private static var _hideOnline = false
    private static var _allowCopyProtectedPeers = false
    private static var _removeSponsoredMessages = false
    private static var _viewOnceMediaUnlocked = false
    private static var _antiDeleteEnabled = false
    private static var _editHistoryEnabled = false
    private static var _saveSelfDestructingMedia = false
    private static var _hideStoryViews = false
    private static var _hideChannelViews = false

    public static func apply(ghostMode: Bool, hideOnline: Bool, hideReadReceipts: Bool, hideTyping: Bool, hideUploading: Bool, allowCopyProtectedPeers: Bool = false, removeSponsoredMessages: Bool = false, viewOnceMediaUnlocked: Bool = false) {
        self.lock.lock()
        self._ghostMode = ghostMode
        self._hideOnline = hideOnline
        self._hideReadReceipts = hideReadReceipts
        self._hideTyping = hideTyping
        self._hideUploading = hideUploading
        self._allowCopyProtectedPeers = allowCopyProtectedPeers
        self._removeSponsoredMessages = removeSponsoredMessages
        self._viewOnceMediaUnlocked = viewOnceMediaUnlocked
        self.lock.unlock()
    }

    public static func setArchiveFlags(antiDelete: Bool, editHistory: Bool, saveSelfDestructingMedia: Bool = false) {
        self.lock.lock()
        self._antiDeleteEnabled = antiDelete
        self._editHistoryEnabled = editHistory
        self._saveSelfDestructingMedia = saveSelfDestructingMedia
        self.lock.unlock()
    }

    public static func setGhostViewFlags(hideStoryViews: Bool, hideChannelViews: Bool) {
        self.lock.lock()
        self._hideStoryViews = hideStoryViews
        self._hideChannelViews = hideChannelViews
        self.lock.unlock()
    }

    /// Keep a copy of self-destructing media when it is opened.
    public static var saveSelfDestructingMedia: Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self._saveSelfDestructingMedia
    }

    /// Do not mark stories as seen (no `stories.readStories` / `incrementStoryViews`).
    public static var suppressStoryViews: Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self._ghostMode && self._hideStoryViews
    }

    /// Ask `messages.getMessagesViews` for counts without incrementing them.
    public static var suppressChannelViews: Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self._ghostMode && self._hideChannelViews
    }

    /// Keep a local copy of deleted messages.
    public static var antiDeleteEnabled: Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self._antiDeleteEnabled
    }

    /// Keep a local copy of previous versions of edited messages.
    public static var editHistoryEnabled: Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self._editHistoryEnabled
    }

    /// Never expire / never start the countdown of self-destructing media.
    public static var viewOnceMediaUnlocked: Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self._viewOnceMediaUnlocked
    }

    /// Treat `noforwards` peers as ordinary ones (copying/forwarding enabled).
    public static var allowCopyProtectedPeers: Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self._allowCopyProtectedPeers
    }

    /// Drop sponsored messages from channel feeds.
    public static var removeSponsoredMessages: Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self._removeSponsoredMessages
    }

    /// Suppress any read-receipt push (cloud, secret chats and channels).
    public static var suppressReadReceipts: Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self._ghostMode && self._hideReadReceipts
    }

    /// Suppress `messages.setTyping` for text and voice-note activities.
    public static var suppressTyping: Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self._ghostMode && self._hideTyping
    }

    /// Suppress "uploading photo/video/voice" activities.
    public static var suppressUploading: Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self._ghostMode && (self._hideUploading || self._hideTyping)
    }

    /// Keep the account offline (`account.updateStatus(offline: true)`).
    public static var stayOffline: Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self._ghostMode && self._hideOnline
    }
}
