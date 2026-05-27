import SwiftUI

struct ReplyBar: View {
    let onAttachTap: () -> Void
    let onTextTap: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onAttachTap) {
                Image(systemName: "plus")
                    .font(.system(size: 14))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                    .glassEffect()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("replyBarAttach")

            Button(action: onTextTap) {
                HStack(spacing: 0) {
                    Text("Reply…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
                .glassEffect()
            }
            .buttonStyle(.plain)
            .layoutPriority(1)
            .accessibilityIdentifier("replyBar")
        }
    }
}
