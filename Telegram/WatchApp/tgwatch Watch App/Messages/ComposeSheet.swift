import SwiftUI

struct ComposeSheet: View {
    let initialText: String
    let onSend: (String) async -> Bool
    let onDismissWithDraft: (String) async -> Void

    @State private var text: String = ""
    @State private var sending: Bool = false
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                TextField("Reply…", text: $text, axis: .vertical)
                    .focused($focused)
                    .accessibilityIdentifier("composeField")
                Button(action: send) {
                    if sending {
                        ProgressView()
                    } else {
                        Label("Send", systemImage: "paperplane.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(sending || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("composeSend")
            }
            .padding(8)
        }
        .task {
            text = initialText
            focused = true
        }
        .onDisappear {
            // If we're sending, the dismiss came from send() — skip the draft write.
            // The send call has clearDraft: true server-side, so the draft is already cleared.
            guard !sending else { return }
            let snapshot = text
            Task { await onDismissWithDraft(snapshot) }
        }
    }

    private func send() {
        let snapshot = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !snapshot.isEmpty else { return }
        sending = true
        Task {
            let success = await onSend(snapshot)
            if success {
                dismiss()
            } else {
                sending = false
            }
        }
    }
}
