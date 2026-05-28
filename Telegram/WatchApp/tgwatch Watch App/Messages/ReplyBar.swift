import SwiftUI

struct ReplyBar: View {
    let onAttachTap: () -> Void
    let onTextTap: () -> Void

    // Circular "+" button and reply-field capsule share a single pill
    // diameter so they line up vertically and visually mirror the
    // watchOS-26 system nav back chevron. The "+" is inset 11pt from the
    // chat-content's leading edge so that, combined with the ScrollView's
    // outer .padding(.horizontal, 4), it sits 15pt from the screen edge —
    // aligned with the system back-chevron in a pushed view.
    private static let pillHeight: CGFloat = 35

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onAttachTap) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: Self.pillHeight, height: Self.pillHeight)
                    .contentShape(Circle())
                    .glassEffect(in: Circle())
            }
            .buttonStyle(.plain)
            .padding(.leading, 11)
            .accessibilityIdentifier("replyBarAttach")

            Button(action: onTextTap) {
                HStack(spacing: 0) {
                    Text("Reply…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .frame(height: Self.pillHeight)
                .contentShape(Rectangle())
                .glassEffect()
            }
            .buttonStyle(.plain)
            .layoutPriority(1)
            .accessibilityIdentifier("replyBar")
        }
    }
}

#if DEBUG
// Side-by-side reference for the round "+" button. SnapshotPreviews doesn't
// render NavigationStack chrome, so the watchOS-26 system back chevron is
// mocked (same glass-Circle shape) at its in-app position (15pt leading,
// 6pt top) for a direct visual compare against the "+" button at the
// ReplyBar's in-app position (15pt leading, 19pt bottom). Frame matches
// the 46mm canvas (208×248 logical pts).
private struct ReplyBarGeometryPreviewHost: View {
    var body: some View {
        ZStack {
            Color.black

            Image(systemName: "chevron.left")
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 35, height: 35)
                .glassEffect(in: Circle())
                .padding(.leading, 15)
                .padding(.top, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            ReplyBar(onAttachTap: {}, onTextTap: {})
                .padding(.horizontal, 4)
                .padding(.bottom, 19)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .frame(width: 208, height: 248)
    }
}

#Preview("Reply bar vs nav back") { ReplyBarGeometryPreviewHost() }
#endif
