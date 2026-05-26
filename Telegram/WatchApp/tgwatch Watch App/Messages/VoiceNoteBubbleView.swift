import SwiftUI

/// Renders one voice-note bubble: rounded chrome (gray incoming / accent
/// outgoing) containing a play/pause glyph + 32-bar waveform + duration
/// label. Optional reply header sits inside the chrome above the row.
/// Caption (when non-empty) renders below the waveform inside the chrome.
/// Time footer renders below the chrome.
///
/// Drives priority-1 viewport download via `.onScrollVisibilityChange`.
/// Tap goes through `ChatHistoryStore.togglePlayback(_:)`; the store kicks
/// a priority-2 download if the file isn't ready and routes the toggle to
/// the active `VoicePlaybackController`.
struct VoiceNoteBubbleView: View {
    let note: VoiceNoteVisual
    let caption: String
    let time: String
    let isOutgoing: Bool
    let replyHeader: ReplyHeader?
    let sendingState: SendingState

    @Environment(ChatHistoryStore.self) private var store
    @Environment(\.bubbleMetrics) private var metrics

    private var style: BubbleStyle { .resolve(isOutgoing: isOutgoing) }
    private var amplitudes: [Float] { unpackWaveform(note.waveform) }
    private var glyph: VoiceGlyph { store.voicePlayback.glyph(for: note.voiceFileId) }
    private var progress: Double { store.voicePlayback.progress(for: note.voiceFileId) }
    private var preparingProgress: Int? {
        if case .preparing(let id, let p) = store.voicePlayback.state, id == note.voiceFileId {
            return Int(p * 100)
        }
        return nil
    }

    var body: some View {
        chrome
            .onScrollVisibilityChange(threshold: 0.01) { visible in
                if visible {
                    store.requestFileDownload(fileId: note.voiceFileId)
                } else {
                    store.cancelFileDownload(fileId: note.voiceFileId)
                }
            }
    }

    private var chrome: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let header = replyHeader {
                ReplyHeaderView(header: header, style: BubbleStyle.resolve(isOutgoing: isOutgoing))
            }
            HStack(spacing: 6) {
                glyphView
                WaveformBarsView(amplitudes: amplitudes, progress: progress, isOutgoing: isOutgoing)
                trailing
            }
            if !caption.isEmpty {
                Text(caption)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            timeRow
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: metrics.bubbleMaxWidth, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(style.fill)
        )
        .foregroundStyle(style.content)
        .contentShape(Rectangle())
        .onTapGesture { store.togglePlayback(note) }
    }

    @ViewBuilder
    private var glyphView: some View {
        // Fixed 32pt slot keeps the waveform width stable across glyph states.
        switch glyph {
        case .error:
            // Edge state — keep the red failure signal, no circle.
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 18)).foregroundStyle(.red)
                .frame(width: 32, height: 32)
        case .play, .pause, .spinner:
            ZStack {
                Circle().fill(style.playFill)
                Group {
                    switch glyph {
                    case .play:  Image(systemName: "play.fill").font(.system(size: 13))
                    case .pause: Image(systemName: "pause.fill").font(.system(size: 13))
                    default:     ProgressView().controlSize(.mini).scaleEffect(0.7).tint(style.playIcon)
                    }
                }
                .foregroundStyle(style.playIcon)
            }
            .frame(width: 32, height: 32)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        VStack(alignment: .trailing, spacing: 1) {
            if let pct = preparingProgress {
                Text("\(pct)%")
                    .font(.system(size: 8))
                    .foregroundStyle(style.secondary)
            } else {
                Text(formatDuration(note.duration))
                    .font(.system(size: 9))
                    .foregroundStyle(style.secondary)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    // Time + send-state inline at the bottom-right inside the chrome, matching the
    // text-bubble convention.
    private var timeRow: some View {
        HStack(spacing: 2) {
            Spacer(minLength: 0)
            Text(time)
                .font(.system(size: 8))
                .foregroundStyle(style.secondary)
            if isOutgoing { sendStateGlyph }
        }
    }

    @ViewBuilder
    private var sendStateGlyph: some View {
        switch sendingState {
        case .sent:    EmptyView()
        case .pending: Image(systemName: "clock").font(.system(size: 8))
            .foregroundStyle(Color.white.opacity(0.7))
        case .failed:  Image(systemName: "exclamationmark.circle.fill").font(.system(size: 8))
            .foregroundStyle(.red)
        }
    }
}

#if DEBUG
import TDLibKit

private struct VoiceNotePreviewNoopLoader: ChatHistoryLoader {
    func openChat(chatId: Int64) async throws {}
    func closeChat(chatId: Int64) async throws {}
    func loadHistory(chatId: Int64, fromMessageId: Int64, offset: Int, limit: Int) async throws -> [TDLibKit.Message] { [] }
    func downloadFile(fileId: Int, priority: Int) async throws -> TDLibKit.File { throw CancellationError() }
    func cancelDownloadFile(fileId: Int) async throws {}
    func sendText(chatId: Int64, text: String) async throws -> TDLibKit.Message { throw CancellationError() }
    func sendVoiceNote(chatId: Int64, fileURL: URL, duration: Int, waveform: Data) async throws -> TDLibKit.Message { throw CancellationError() }
    func setChatDraftMessage(chatId: Int64, draftText: String) async throws {}
    func viewMessages(chatId: Int64, messageIds: [Int64], forceRead: Bool) async throws {}
    func setPollAnswer(chatId: Int64, messageId: Int64, optionIds: [Int]) async throws {}
    func sendSticker(chatId: Int64, remoteFileId: String, emoji: String, width: Int, height: Int) async throws -> TDLibKit.Message {
        throw CancellationError()
    }
    func sendLocation(chatId: Int64, latitude: Double, longitude: Double) async throws -> TDLibKit.Message { throw CancellationError() }
}

@MainActor
private func previewStore() -> ChatHistoryStore {
    ChatHistoryStore(
        chatId: 0,
        chatType: .chatTypePrivate(ChatTypePrivate(userId: 0)),
        lastReadInboxMessageId: 0, unreadCount: 0, lastMessageId: nil,
        loader: VoiceNotePreviewNoopLoader()
    )
}

private func previewVoice(id: Int = 1) -> VoiceNoteVisual {
    VoiceNoteVisual(
        voiceFileId: id, duration: 18, mimeType: "audio/ogg",
        waveform: Data((0..<63).map { _ in UInt8.random(in: 0...255) }),
        caption: "", localPath: nil
    )
}

#Preview("Voice — incoming, idle") {
    VoiceNoteBubbleView(
        note: previewVoice(), caption: "",
        time: "12:34", isOutgoing: false,
        replyHeader: nil, sendingState: .sent
    )
    .bubblePreview()
    .environment(previewStore())
}

#Preview("Voice — outgoing, idle") {
    VoiceNoteBubbleView(
        note: previewVoice(id: 2), caption: "",
        time: "12:35", isOutgoing: true,
        replyHeader: nil, sendingState: .sent
    )
    .bubblePreview()
    .environment(previewStore())
}

#Preview("Voice — incoming with reply") {
    VoiceNoteBubbleView(
        note: previewVoice(id: 3), caption: "",
        time: "12:36", isOutgoing: false,
        replyHeader: ReplyHeader(
            senderName: "Bob",
            snippet: "anchor message earlier in the chat",
            minithumbnail: nil, isOutgoing: false
        ),
        sendingState: .sent
    )
    .bubblePreview()
    .environment(previewStore())
}

#Preview("Voice — incoming with caption") {
    VoiceNoteBubbleView(
        note: previewVoice(id: 4),
        caption: "Listen to this part carefully",
        time: "12:37", isOutgoing: false,
        replyHeader: nil, sendingState: .sent
    )
    .bubblePreview()
    .environment(previewStore())
}

#Preview("Voice — incoming, empty waveform") {
    VoiceNoteBubbleView(
        note: VoiceNoteVisual(
            voiceFileId: 5, duration: 5, mimeType: "audio/ogg",
            waveform: Data(), caption: "", localPath: nil
        ),
        caption: "", time: "12:38", isOutgoing: false,
        replyHeader: nil, sendingState: .sent
    )
    .bubblePreview()
    .environment(previewStore())
}
#endif
