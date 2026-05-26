import SwiftUI

struct MessageBubbleView: View {
    let bubble: MessageBubble
    let onPhotoTap: (PhotoVisual) -> Void
    let onVideoTap: (VideoVisual) -> Void
    let onVideoNoteTap: (VideoNoteVisual) -> Void
    let onPollTap: (Int64, PollVisual) -> Void

    private var style: BubbleStyle { .resolve(isOutgoing: bubble.isOutgoing) }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if bubble.isOutgoing { Spacer(minLength: 16) }
            VStack(alignment: bubble.isOutgoing ? .trailing : .leading, spacing: 1) {
                if let name = bubble.senderName, !bubble.isOutgoing, bubble.sticker == nil {
                    Text(name)
                        .font(.caption2)
                        .foregroundStyle(bubble.senderColorIndex.map { avatarPalette[$0] } ?? .secondary)
                        .padding(.leading, 8)
                }
                if let sticker = bubble.sticker {
                    StickerBubbleView(
                        sticker: sticker,
                        senderName: bubble.senderName,
                        senderColorIndex: bubble.senderColorIndex,
                        time: bubble.time,
                        isOutgoing: bubble.isOutgoing,
                        replyHeader: bubble.replyHeader
                    )
                } else if let photo = bubble.photo {
                    PhotoBubbleView(
                        photo: photo,
                        caption: bubble.body,
                        time: bubble.time,
                        isOutgoing: bubble.isOutgoing,
                        replyHeader: bubble.replyHeader,
                        onTap: onPhotoTap
                    )
                } else if let video = bubble.video {
                    VideoBubbleView(
                        video: video,
                        caption: bubble.body,
                        time: bubble.time,
                        isOutgoing: bubble.isOutgoing,
                        replyHeader: bubble.replyHeader,
                        onTap: { onVideoTap(video) }
                    )
                } else if let note = bubble.videoNote {
                    VideoNoteBubbleView(
                        note: note,
                        time: bubble.time,
                        isOutgoing: bubble.isOutgoing,
                        replyHeader: bubble.replyHeader,
                        onTap: { onVideoNoteTap(note) }
                    )
                } else if let voice = bubble.voiceNote {
                    VoiceNoteBubbleView(
                        note: voice,
                        caption: bubble.body,
                        time: bubble.time,
                        isOutgoing: bubble.isOutgoing,
                        replyHeader: bubble.replyHeader,
                        sendingState: bubble.sendingState
                    )
                } else if let audio = bubble.audio {
                    AudioBubbleView(
                        audio: audio,
                        caption: bubble.body,
                        time: bubble.time,
                        isOutgoing: bubble.isOutgoing,
                        replyHeader: bubble.replyHeader,
                        sendingState: bubble.sendingState
                    )
                } else if let document = bubble.document {
                    DocumentBubbleView(
                        document: document,
                        time: bubble.time,
                        isOutgoing: bubble.isOutgoing,
                        replyHeader: bubble.replyHeader
                    )
                } else if let location = bubble.location {
                    LocationBubbleView(
                        location: location,
                        time: bubble.time,
                        isOutgoing: bubble.isOutgoing,
                        replyHeader: bubble.replyHeader
                    )
                } else if let poll = bubble.poll {
                    PollBubbleView(
                        poll: poll,
                        time: bubble.time,
                        isOutgoing: bubble.isOutgoing,
                        replyHeader: bubble.replyHeader,
                        onVote: { onPollTap(bubble.messageId, poll) }
                    )
                } else if bubble.replyHeader == nil, let emojiCount = emojiOnlyCount(bubble.body) {
                    Text(bubble.body)
                        .font(.system(size: jumboEmojiSize(for: emojiCount)))
                } else {
                    textBubbleContent
                }
            }
            .overlay(alignment: .bottomLeading) {
                if bubble.isUnreadOutgoing {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 7, height: 7)
                        .offset(x: -11)
                }
            }
            if !bubble.isOutgoing { Spacer(minLength: 16) }
        }
        .accessibilityIdentifier("bubble.\(bubble.messageId)")
    }

    private func jumboEmojiSize(for count: Int) -> CGFloat {
        switch count {
        case 1:  return 52
        case 2:  return 40
        default: return 32
        }
    }

    private var textBubbleContent: some View {
        VStack(alignment: bubble.isOutgoing ? .trailing : .leading, spacing: 2) {
            if let header = bubble.replyHeader {
                ReplyHeaderView(header: header, style: BubbleStyle.resolve(isOutgoing: bubble.isOutgoing))
            }
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(bubble.body)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 2) {
                    Text(bubble.time)
                        .font(.system(size: 8))
                        .foregroundStyle(style.secondary)
                    if bubble.isOutgoing {
                        sendStateGlyph
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(style.fill)
        )
        .foregroundStyle(style.content)
    }

    @ViewBuilder
    private var sendStateGlyph: some View {
        switch bubble.sendingState {
        case .sent:
            EmptyView()
        case .pending:
            Image(systemName: "clock")
                .font(.system(size: 8))
                .foregroundStyle(Color.white.opacity(0.7))
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 8))
                .foregroundStyle(.red)
        }
    }
}

#if DEBUG
private let previewSampleBubble = MessageBubble(
    messageId: 1, isOutgoing: false, senderName: "Alice",
    body: "this is a reply to text",
    time: "12:34",
    photo: nil, video: nil, videoNote: nil, voiceNote: nil, audio: nil, document: nil, sticker: nil, location: nil, poll: nil,
    sendingState: .sent,
    replyHeader: ReplyHeader(
        senderName: "Bob",
        snippet: "anchor message earlier in the chat",
        minithumbnail: nil, isOutgoing: false
    )
)

#Preview("Text bubble — with reply (incoming, group)") {
    MessageBubbleView(
        bubble: previewSampleBubble,
        onPhotoTap: { _ in },
        onVideoTap: { _ in },
        onVideoNoteTap: { _ in },
        onPollTap: { _, _ in }
    )
    .bubblePreview()
}

#Preview("Text bubble — with reply (outgoing)") {
    MessageBubbleView(
        bubble: MessageBubble(
            messageId: 2, isOutgoing: true, senderName: nil,
            body: "ok",
            time: "12:35",
            photo: nil, video: nil, videoNote: nil, voiceNote: nil, audio: nil, document: nil, sticker: nil, location: nil, poll: nil,
            sendingState: .sent,
            replyHeader: ReplyHeader(
                senderName: "Bob",
                snippet: "anchor",
                minithumbnail: nil, isOutgoing: true
            )
        ),
        onPhotoTap: { _ in },
        onVideoTap: { _ in },
        onVideoNoteTap: { _ in },
        onPollTap: { _, _ in }
    )
    .bubblePreview()
}

#Preview("Text bubble — colored sender (incoming, group)") {
    MessageBubbleView(
        bubble: MessageBubble(
            messageId: 3, isOutgoing: false, senderName: "Alice",
            body: "colored name above me",
            time: "12:36",
            photo: nil, video: nil, videoNote: nil, voiceNote: nil, audio: nil, document: nil, sticker: nil, location: nil, poll: nil,
            sendingState: .sent,
            replyHeader: nil,
            senderColorIndex: paletteIndex(for: 200)
        ),
        onPhotoTap: { _ in },
        onVideoTap: { _ in },
        onVideoNoteTap: { _ in },
        onPollTap: { _, _ in }
    )
    .bubblePreview()
}

#Preview("Emoji only — incoming 1") {
    MessageBubbleView(
        bubble: MessageBubble(
            messageId: 10, isOutgoing: false, senderName: nil, body: "🥰", time: "12:40",
            photo: nil, video: nil, videoNote: nil, voiceNote: nil, audio: nil, document: nil,
            sticker: nil, location: nil, poll: nil, sendingState: .sent, replyHeader: nil
        ),
        onPhotoTap: { _ in }, onVideoTap: { _ in }, onVideoNoteTap: { _ in }, onPollTap: { _, _ in }
    )
    .bubblePreview()
}

#Preview("Unread outgoing") {
    MessageBubbleView(
        bubble: MessageBubble(
            messageId: 12, isOutgoing: true, senderName: nil,
            body: "delivered but not yet read",
            time: "12:42",
            photo: nil, video: nil, videoNote: nil, voiceNote: nil, audio: nil, document: nil,
            sticker: nil, location: nil, poll: nil, sendingState: .sent, replyHeader: nil,
            isUnreadOutgoing: true
        ),
        onPhotoTap: { _ in }, onVideoTap: { _ in }, onVideoNoteTap: { _ in }, onPollTap: { _, _ in }
    )
    .bubblePreview()
}

#Preview("Emoji only — outgoing 3") {
    MessageBubbleView(
        bubble: MessageBubble(
            messageId: 11, isOutgoing: true, senderName: nil, body: "😀🎉🥰", time: "12:41",
            photo: nil, video: nil, videoNote: nil, voiceNote: nil, audio: nil, document: nil,
            sticker: nil, location: nil, poll: nil, sendingState: .sent, replyHeader: nil
        ),
        onPhotoTap: { _ in }, onVideoTap: { _ in }, onVideoNoteTap: { _ in }, onPollTap: { _, _ in }
    )
    .bubblePreview()
}
#endif
