import SwiftUI

/// First-run / fully-empty state: a single "Add account" button.
struct AccountsEmptyView: View {
    @Environment(AccountManager.self) private var manager
    @State private var showDcSheet = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Welcome to tgwatch")
                .font(.headline)
            Text("Add a Telegram account to get started.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let err = manager.lastError {
                Text(err)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("accountManagerError")
            }
            Text("Add account")
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.gray.opacity(0.25), in: Capsule())
                .contentShape(Capsule())
                .onTapGesture {
                    Task { await manager.addAccount(useTestDc: false) }
                }
                .onLongPressGesture(minimumDuration: 0.5) { showDcSheet = true }
                .accessibilityIdentifier("addAccountButton")
        }
        .padding()
        .confirmationDialog(
            "Choose server",
            isPresented: $showDcSheet,
            titleVisibility: .visible
        ) {
            Button("Production") {
                Task { await manager.addAccount(useTestDc: false) }
            }
            Button("Test (developers)") {
                Task { await manager.addAccount(useTestDc: true) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
