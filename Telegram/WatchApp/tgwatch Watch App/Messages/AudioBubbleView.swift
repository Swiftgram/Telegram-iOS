import SwiftUI

/// Renders one music/audio bubble: gray-incoming / accent-outgoing rounded
/// chrome containing a 36pt album-art square (with a play/pause/spinner/error
/// glyph overlay), a bold title, an optional performer line, and a duration
/// label that becomes "elapsed / total" during playback. Optional reply header
/// sits inside the chrome above the row; caption (when non-empty) below.
///
/// Drives priority-1 viewport download via `.onScrollVisibilityChange`. Tap goes
/// through `ChatHistoryStore.toggleAudioPlayback(_:)`, which tears down any voice
/// playback, kicks a priority-2 download if needed, and routes to the
/// `AudioPlaybackController`.
struct AudioBubbleView: View {
    let audio: AudioVisual
    let caption: String
    let time: String
    let isOutgoing: Bool
    let replyHeader: ReplyHeader?
    let sendingState: SendingState

    @Environment(ChatHistoryStore.self) private var store
    @Environment(\.bubbleMetrics) private var metrics

    private var style: BubbleStyle { .resolve(isOutgoing: isOutgoing) }
    private var glyph: AudioGlyph { store.audioPlayback.glyph(for: audio.audioFileId) }
    private var isActive: Bool { store.audioPlayback.isActive(audio.audioFileId) }
    private var durationText: String {
        if isActive {
            let e = store.audioPlayback.elapsed(for: audio.audioFileId)
            return "\(formatDuration(e)) / \(formatDuration(audio.duration))"
        }
        return formatDuration(audio.duration)
    }

    var body: some View {
        chrome
            .onScrollVisibilityChange(threshold: 0.01) { visible in
                if visible {
                    store.requestFileDownload(fileId: audio.audioFileId)
                } else {
                    store.cancelFileDownload(fileId: audio.audioFileId)
                }
            }
    }

    private var chrome: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let header = replyHeader {
                ReplyHeaderView(header: header, style: BubbleStyle.resolve(isOutgoing: isOutgoing))
            }
            HStack(spacing: 8) {
                artSquare
                VStack(alignment: .leading, spacing: 1) {
                    Text(audio.title)
                        .font(.caption).bold()
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if !audio.performer.isEmpty {
                        Text(audio.performer)
                            .font(.system(size: 9))
                            .foregroundStyle(style.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Text(durationText)
                        .font(.system(size: 9))
                        .foregroundStyle(style.secondary)
                }
                Spacer(minLength: 0)
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
        .onTapGesture { store.toggleAudioPlayback(audio) }
    }

    private var artSquare: some View {
        ZStack {
            if let data = audio.albumArt, let img = UIImage(data: data) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                Circle().fill(style.playFill)
            }
            glyphView
        }
        .frame(width: 36, height: 36)
        .clipShape(Circle())
    }

    @ViewBuilder
    private var glyphView: some View {
        Group {
            switch glyph {
            case .play:    Image(systemName: "play.fill").font(.system(size: 14))
            case .pause:   Image(systemName: "pause.fill").font(.system(size: 14))
            case .spinner:
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.7)
            case .error:   Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 14)).foregroundStyle(.red)
            }
        }
        .foregroundStyle(audio.albumArt != nil ? .white : style.playIcon)
        .shadow(radius: audio.albumArt != nil ? 1 : 0)
    }

    // Time + send-state inline at the bottom-right inside the chrome, matching the
    // text-bubble convention (and VoiceNoteBubbleView).
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

private struct AudioPreviewNoopLoader: ChatHistoryLoader {
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
        loader: AudioPreviewNoopLoader()
    )
}

private func previewAudio(
    id: Int = 1,
    title: String = "Bohemian Rhapsody",
    performer: String = "Queen"
) -> AudioVisual {
    AudioVisual(
        audioFileId: id, duration: 272, title: title,
        performer: performer, albumArt: nil, caption: "", localPath: nil
    )
}

#Preview("Audio — incoming, idle") {
    AudioBubbleView(
        audio: previewAudio(), caption: "",
        time: "12:34", isOutgoing: false,
        replyHeader: nil, sendingState: .sent
    )
    .bubblePreview()
    .environment(previewStore())
}

#Preview("Audio — outgoing, idle") {
    AudioBubbleView(
        audio: previewAudio(id: 2), caption: "",
        time: "12:35", isOutgoing: true,
        replyHeader: nil, sendingState: .sent
    )
    .bubblePreview()
    .environment(previewStore())
}

#Preview("Audio — long title (truncates)") {
    AudioBubbleView(
        audio: previewAudio(id: 3, title: "A Very Long Track Title That Will Truncate", performer: "Some Long Performer Name"),
        caption: "",
        time: "12:36", isOutgoing: false,
        replyHeader: nil, sendingState: .sent
    )
    .bubblePreview()
    .environment(previewStore())
}

#Preview("Audio — no performer") {
    AudioBubbleView(
        audio: previewAudio(id: 4, title: "Untitled", performer: ""),
        caption: "",
        time: "12:37", isOutgoing: false,
        replyHeader: nil, sendingState: .sent
    )
    .bubblePreview()
    .environment(previewStore())
}

#Preview("Audio — incoming with caption") {
    AudioBubbleView(
        audio: previewAudio(id: 5),
        caption: "this song goes hard",
        time: "12:38", isOutgoing: false,
        replyHeader: nil, sendingState: .sent
    )
    .bubblePreview()
    .environment(previewStore())
}

#Preview("Audio — incoming with reply") {
    AudioBubbleView(
        audio: previewAudio(id: 6), caption: "",
        time: "12:39", isOutgoing: false,
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
#endif
