import Foundation
import Postbox
import SwiftSignalKit

/// Local-only log of deleted messages, previous versions of edited messages and self-destructing media
/// (TrollTweaks "Saved Messages").
///
/// Entries are appended as JSON lines to `Documents/TrollArchive/archive.jsonl`; downloaded media is copied to
/// `Documents/TrollArchive/media/`. Nothing is ever sent to the server and the log survives restarts. Only
/// incoming messages are logged. Deleted messages are not restored into the chat: the state sync deletes
/// whatever the server deleted (see `State/CLAUDE.md`), and this log only keeps a copy.
public final class TrollMessageArchive {
    public static let shared = TrollMessageArchive()

    public enum Kind {
        public static let deleted = "deleted"
        public static let edited = "edited"
        public static let selfDestructing = "selfdestruct"
    }

    public struct Entry: Codable {
        public let peerId: Int64
        public let messageId: Int32
        public let date: Int32
        public let authorId: Int64?
        public let text: String
        public let kind: String
        public let savedAt: Int32
        public var peerTitle: String?
        public var authorTitle: String?
        /// File names inside `mediaDirectory`.
        public var media: [String]?
        /// What the media was, for display: "photo", "video", "voice message", a file name.
        public var mediaSummary: String?
    }

    private static let maximumFileSize: Int64 = 100 * 1024 * 1024
    private static let maximumLogSize: Int64 = 16 * 1024 * 1024

    private let queue = DispatchQueue(label: "app.trollgram.ios.archive")
    private let directory: String
    private let logURL: URL
    private let legacyURL: URL
    /// Only touched on `queue`. `nil` until the first append loads the log.
    private var seen: Set<String>?

    private init() {
        let documents = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first ?? NSTemporaryDirectory()
        self.directory = documents + "/TrollArchive"
        try? FileManager.default.createDirectory(atPath: self.directory + "/media", withIntermediateDirectories: true)
        self.logURL = URL(fileURLWithPath: self.directory + "/archive.jsonl")
        self.legacyURL = URL(fileURLWithPath: self.directory + "/messages.json")
    }

    public var mediaDirectory: String {
        return self.directory + "/media"
    }

    // MARK: - Capturing

    /// Logs the incoming messages among `ids` before they are removed. Called inside a postbox transaction: media is
    /// copied here, because a secret chat's files are removed right after, and the log write is asynchronous.
    public func captureDeleted(transaction: Transaction, mediaBox: MediaBox, ids: [MessageId]) {
        var entries: [Entry] = []
        for id in ids {
            guard let message = transaction.getMessage(id), message.flags.contains(.Incoming) else {
                continue
            }
            if let entry = self.makeEntry(message: message, text: message.text, kind: Kind.deleted, mediaBox: mediaBox) {
                entries.append(entry)
            }
        }
        self.append(entries)
    }

    /// Logs the text a message had before an edit replaced it.
    public func captureEdit(previous message: Message) {
        guard message.flags.contains(.Incoming), !message.text.isEmpty else {
            return
        }
        if let entry = self.makeEntry(message: message, text: message.text, kind: Kind.edited, mediaBox: nil) {
            self.append([entry])
        }
    }

    /// Logs a self-destructing message and copies its media, just before it is opened and starts its countdown.
    public func captureSelfDestructing(message: Message, mediaBox: MediaBox) {
        if let entry = self.makeEntry(message: message, text: message.text, kind: Kind.selfDestructing, mediaBox: mediaBox) {
            self.append([entry])
        }
    }

    private func makeEntry(message: Message, text: String, kind: String, mediaBox: MediaBox?) -> Entry? {
        var files: [String] = []
        var summaries: [String] = []
        if let mediaBox {
            (files, summaries) = self.saveMedia(of: message, mediaBox: mediaBox)
        }
        if text.isEmpty && files.isEmpty {
            return nil
        }
        return Entry(
            peerId: message.id.peerId.toInt64(),
            messageId: message.id.id,
            date: message.timestamp,
            authorId: message.author?.id.toInt64(),
            text: text,
            kind: kind,
            savedAt: Int32(CFAbsoluteTimeGetCurrent() + NSTimeIntervalSince1970),
            peerTitle: message.peers[message.id.peerId]?.debugDisplayTitle,
            authorTitle: message.author?.debugDisplayTitle,
            media: files.isEmpty ? nil : files,
            mediaSummary: summaries.isEmpty ? nil : summaries.joined(separator: ", ")
        )
    }

    /// Copies the photos and files of `message` that are fully downloaded; returns the copies and what they are.
    private func saveMedia(of message: Message, mediaBox: MediaBox) -> (files: [String], summaries: [String]) {
        var files: [String] = []
        var summaries: [String] = []
        for (index, media) in message.media.enumerated() {
            var resource: MediaResource?
            var fileExtension = "bin"
            var summary = ""
            if let image = media as? TelegramMediaImage {
                resource = largestImageRepresentation(image.representations)?.resource
                fileExtension = "jpg"
                summary = "photo"
            } else if let file = media as? TelegramMediaFile {
                resource = file.resource
                fileExtension = TrollMessageArchive.fileExtension(fileName: file.fileName, mimeType: file.mimeType)
                if file.isVoice {
                    summary = "voice message"
                } else if file.isInstantVideo {
                    summary = "video message"
                } else if file.isVideo {
                    summary = "video"
                } else {
                    summary = file.fileName ?? "file"
                }
            }
            guard let resource else {
                continue
            }
            summaries.append(summary)
            guard let source = mediaBox.completedResourcePath(resource) else {
                continue
            }
            let size = ((try? FileManager.default.attributesOfItem(atPath: source))?[.size] as? NSNumber)?.int64Value ?? 0
            if size <= 0 || size > TrollMessageArchive.maximumFileSize {
                continue
            }
            let name = "\(message.id.peerId.toInt64())_\(message.id.id)_\(index).\(fileExtension)"
            let destination = self.mediaDirectory + "/" + name
            if FileManager.default.fileExists(atPath: destination) || (try? FileManager.default.copyItem(atPath: source, toPath: destination)) != nil {
                files.append(name)
            }
        }
        return (files, summaries)
    }

    /// Extension of the copy: the file's own when it looks sane, else from the MIME type.
    static func fileExtension(fileName: String?, mimeType: String) -> String {
        if let fileName {
            let candidate = (fileName as NSString).pathExtension.lowercased()
            if !candidate.isEmpty && candidate.count <= 8 && candidate.allSatisfy({ $0.isLetter || $0.isNumber }) {
                return candidate
            }
        }
        let byMimeType: [String: String] = [
            "video/mp4": "mp4", "video/quicktime": "mov", "audio/ogg": "ogg", "audio/mpeg": "mp3", "audio/mp4": "m4a",
            "image/jpeg": "jpg", "image/png": "png", "image/webp": "webp", "image/gif": "gif", "application/pdf": "pdf"
        ]
        return byMimeType[mimeType.lowercased()] ?? "bin"
    }

    // MARK: - Storage

    private static func key(_ entry: Entry) -> String {
        // An edit is a new version of the same message, so its text is part of the key.
        let tail = entry.kind == Kind.edited ? "|" + entry.text : ""
        return "\(entry.kind)|\(entry.peerId)|\(entry.messageId)" + tail
    }

    private func append(_ entries: [Entry]) {
        if entries.isEmpty {
            return
        }
        self.queue.async {
            var seen = self.seen ?? Set(self.readAll().map(TrollMessageArchive.key))
            var data = Data()
            for entry in entries {
                let key = TrollMessageArchive.key(entry)
                if seen.contains(key) {
                    continue
                }
                seen.insert(key)
                if var line = try? JSONEncoder().encode(entry) {
                    line.append(0x0A)
                    data.append(line)
                }
            }
            self.seen = seen
            if data.isEmpty {
                return
            }
            if let handle = try? FileHandle(forWritingTo: self.logURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            } else {
                try? data.write(to: self.logURL)
            }
            self.trimIfNeeded()
        }
    }

    /// Keeps the newest half once the log passes its size limit. Runs on `queue`.
    private func trimIfNeeded() {
        let size = ((try? FileManager.default.attributesOfItem(atPath: self.logURL.path))?[.size] as? NSNumber)?.int64Value ?? 0
        if size <= TrollMessageArchive.maximumLogSize {
            return
        }
        let all = self.readAll()
        var data = Data()
        for entry in all.suffix(all.count / 2) {
            if var line = try? JSONEncoder().encode(entry) {
                line.append(0x0A)
                data.append(line)
            }
        }
        try? data.write(to: self.logURL, options: [.atomic])
        self.seen = nil
    }

    /// Runs on `queue`. Also moves the first version's `messages.json` into the line format.
    private func readAll() -> [Entry] {
        var result: [Entry] = []
        if let data = try? Data(contentsOf: self.legacyURL), let legacy = try? JSONDecoder().decode([Entry].self, from: data) {
            result.append(contentsOf: legacy)
            var lines = Data()
            for entry in legacy {
                if var line = try? JSONEncoder().encode(entry) {
                    line.append(0x0A)
                    lines.append(line)
                }
            }
            if let existing = try? Data(contentsOf: self.logURL) {
                lines.append(existing)
            }
            if (try? lines.write(to: self.logURL, options: [.atomic])) != nil {
                try? FileManager.default.removeItem(at: self.legacyURL)
                result = []
            }
        }
        if let data = try? Data(contentsOf: self.logURL) {
            let decoder = JSONDecoder()
            for line in data.split(separator: 0x0A) {
                if let entry = try? decoder.decode(Entry.self, from: Data(line)) {
                    result.append(entry)
                }
            }
        }
        return result
    }

    /// Every entry, oldest first.
    public func load() -> [Entry] {
        return self.queue.sync { self.readAll() }
    }

    /// Number of logged entries, counted without decoding them.
    public func entryCount() -> Int {
        return self.queue.sync {
            guard let data = try? Data(contentsOf: self.logURL) else {
                return 0
            }
            return data.reduce(0) { $1 == 0x0A ? $0 + 1 : $0 }
        }
    }

    /// Deletes the log and the copied media.
    public func clear() {
        self.queue.sync {
            try? FileManager.default.removeItem(at: self.logURL)
            try? FileManager.default.removeItem(at: self.legacyURL)
            try? FileManager.default.removeItem(atPath: self.mediaDirectory)
            try? FileManager.default.createDirectory(atPath: self.mediaDirectory, withIntermediateDirectories: true)
            self.seen = nil
        }
    }

    public var archivePath: String {
        return self.logURL.path
    }
}
