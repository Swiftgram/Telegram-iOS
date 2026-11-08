import SGSwiftUI
import SwiftUI
import UIKit

/// Content depends only on the SwiftUI palette, never Telegram's PresentationTheme.
struct PlaygroundThemeScreen: View {
    let toggleAccent: () -> Void
    let toggleAppearance: () -> Void
    @Environment(\.sgTheme) private var theme
    @State private var count = 0
    @State private var enabled = true
    @State private var amount = 0.5

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Independent SwiftUI theme").font(.title2.bold())
                    .foregroundColor(theme.primaryTextColor)
                Text("Telegram supplies values; this view knows only SGSwiftUITheme.")
                    .foregroundColor(theme.secondaryTextColor)
                Text(verbatim: "dark=\(theme.overallDarkAppearance);accent=\(playgroundThemeRGB(UIColor(theme.accentColor)));onAccent=\(playgroundThemeRGB(UIColor(theme.accentForegroundColor)))")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(theme.primaryTextColor)
                    .accessibilityIdentifier("theme-values")
                Text("Accent swatch")
                    .padding().frame(maxWidth: .infinity)
                    .background(theme.accentColor).foregroundColor(theme.accentForegroundColor)
                Button("State: \(count)") { count += 1 }
                    .buttonStyle(.borderedProminent)
                    .foregroundColor(theme.accentForegroundColor)
                    .accessibilityIdentifier("theme-increment")
                Toggle(isOn: $enabled) {
                    Text("Native toggle").foregroundColor(theme.primaryTextColor)
                }
                Slider(value: $amount)
                PlaygroundThemeTintSample().frame(height: 28)
                Divider().overlay(theme.separatorColor)
                Button("Change accent only", action: toggleAccent)
                    .accessibilityIdentifier("theme-toggle-accent")
                Button("Change light / dark", action: toggleAppearance)
                    .accessibilityIdentifier("theme-toggle-appearance")
                Text("Destructive color sample").foregroundColor(theme.destructiveColor)
            }
            .padding()
            .background(theme.secondaryBackgroundColor)
            .cornerRadius(12)
            .padding()
        }
        .background(theme.backgroundColor.ignoresSafeArea())
    }
}

private func playgroundThemeRGB(_ color: UIColor) -> String {
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    color.getRed(&red, green: &green, blue: &blue, alpha: nil)
    return String(format: "%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
}

/// Leaves tint unset: verifies UIKit children inherit the hosting boundary's live tint.
private struct PlaygroundThemeTintSample: UIViewRepresentable {
    final class Label: UILabel {
        override func tintColorDidChange() {
            super.tintColorDidChange()
            self.textColor = self.tintColor
            self.accessibilityValue = playgroundThemeRGB(self.tintColor)
        }
    }

    func makeUIView(context: Context) -> Label {
        let label = Label()
        label.text = "Inherited UIKit tint"
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.isAccessibilityElement = true
        label.accessibilityIdentifier = "theme-uikit-tint"
        return label
    }

    func updateUIView(_ view: Label, context: Context) {
        view.tintColorDidChange()
    }
}
