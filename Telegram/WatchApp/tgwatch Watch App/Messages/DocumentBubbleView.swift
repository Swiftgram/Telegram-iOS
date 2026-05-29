import SwiftUI

/// Renders one generic-document bubble: BubbleStyle chrome with a rounded-square doc icon,
/// filename, size, optional caption, and a time footer. Display-only (no download/open on
/// watch in milestone #4).
struct DocumentBubbleView: View {
    let document: DocumentVisual
    let time: String
    let isOutgoing: Bool
    let replyHeader: ReplyHeader?

    @Environment(\.bubbleMetrics) private var metrics
    private var style: BubbleStyle { .resolve(isOutgoing: isOutgoing) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let header = replyHeader {
                ReplyHeaderView(header: header, style: style)
            }
            HStack(spacing: 8) {
                iconSquare
                VStack(alignment: .leading, spacing: 1) {
                    Text(document.fileName)
                        .font(.caption).bold()
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(formatFileSize(document.sizeBytes))
                        .font(.system(size: 9))
                        .foregroundStyle(style.secondary)
                }
                Spacer(minLength: 0)
            }
            if !document.caption.isEmpty {
                Text(document.caption)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 2) {
                Spacer(minLength: 0)
                Text(time).font(.system(size: 8)).foregroundStyle(style.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: metrics.bubbleMaxWidth, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(style.fill))
        .foregroundStyle(style.content)
    }

    private var iconSquare: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(style.playFill)
            Image(systemName: "doc.fill").font(.system(size: 16)).foregroundStyle(style.playIcon)
        }
        .frame(width: 36, height: 36)
    }
}

#if DEBUG
#Preview("Document — incoming") {
    DocumentBubbleView(
        document: DocumentVisual(documentFileId: 1, fileName: "report.pdf",
                                 sizeBytes: 2_400_000, localPath: nil, caption: ""),
        time: "12:34", isOutgoing: false, replyHeader: nil
    ).bubblePreview()
}

#Preview("Document — outgoing, long name") {
    DocumentBubbleView(
        document: DocumentVisual(documentFileId: 2, fileName: "quarterly-financial-summary-2026.xlsx",
                                 sizeBytes: 52_428_800, localPath: nil, caption: ""),
        time: "12:35", isOutgoing: true, replyHeader: nil
    ).bubblePreview()
}

#Preview("Document — with caption") {
    DocumentBubbleView(
        document: DocumentVisual(documentFileId: 3, fileName: "archive.zip",
                                 sizeBytes: 52_428_800, localPath: nil, caption: "here are the files"),
        time: "12:36", isOutgoing: false, replyHeader: nil
    ).bubblePreview()
}

#Preview("Document — with reply") {
    DocumentBubbleView(
        document: DocumentVisual(documentFileId: 4, fileName: "notes.txt",
                                 sizeBytes: 1024, localPath: nil, caption: ""),
        time: "12:37", isOutgoing: false,
        replyHeader: ReplyHeader(senderName: "Bob", snippet: "the doc", minithumbnail: nil, isOutgoing: false)
    ).bubblePreview()
}
#endif
