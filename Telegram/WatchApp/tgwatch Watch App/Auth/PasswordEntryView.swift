import SwiftUI

struct PasswordEntryView: View {
    let info: PasswordInfo

    @Environment(TDClient.self) private var client
    @State private var password = ""
    @State private var submitting = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("2-step verification")
                    .font(.headline)
                if !info.hint.isEmpty {
                    Text("Hint: \(info.hint)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Enter your cloud password")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .accessibilityIdentifier("passwordField")
                Button(action: submit) {
                    if submitting {
                        ProgressView()
                    } else {
                        Text("Continue")
                    }
                }
                .disabled(password.isEmpty || submitting)
                .accessibilityIdentifier("passwordContinue")
                if let err = client.lastError {
                    Text(err)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("passwordError")
                }
            }
            .padding()
        }
        .onAppear {
#if DEBUG
            if password.isEmpty,
               let preset = ProcessInfo.processInfo.environment["TGWATCH_PASSWORD"],
               !preset.isEmpty {
                password = preset
                submit()
            }
#endif
        }
        .accountSwitcherSheet(presentation: .sheet, logoutAffordance: .suppressed)
    }

    private func submit() {
        let passwordCopy = password
        submitting = true
        Task {
            await client.submitPassword(passwordCopy)
            submitting = false
        }
    }
}
