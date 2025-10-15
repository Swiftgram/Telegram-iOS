import SwiftUI
import Foundation


// MARK: Swiftgram
public struct ChatToolbarView: View {
    var onQuote: () -> Void
    var onSpoiler: () -> Void
    var onBold: () -> Void
    var onItalic: () -> Void
    var onMonospace: () -> Void
    var onLink: () -> Void
    var onStrikethrough: () -> Void
    var onUnderline: () -> Void
    var onCode: () -> Void
    
    var onNewLine: () -> Void
    @Binding private var showNewLine: Bool
    
    var onClearFormatting: () -> Void
    
    public init(
        onQuote: @escaping () -> Void,
        onSpoiler: @escaping () -> Void,
        onBold: @escaping () -> Void,
        onItalic: @escaping () -> Void,
        onMonospace: @escaping () -> Void,
        onLink: @escaping () -> Void,
        onStrikethrough: @escaping () -> Void,
        onUnderline: @escaping () -> Void,
        onCode: @escaping () -> Void,
        onNewLine: @escaping () -> Void,
        showNewLine: Binding<Bool>,
        onClearFormatting: @escaping () -> Void
    ) {
        self.onQuote = onQuote
        self.onSpoiler = onSpoiler
        self.onBold = onBold
        self.onItalic = onItalic
        self.onMonospace = onMonospace
        self.onLink = onLink
        self.onStrikethrough = onStrikethrough
        self.onUnderline = onUnderline
        self.onCode = onCode
        self.onNewLine = onNewLine
        self._showNewLine = showNewLine
        self.onClearFormatting = onClearFormatting
    }
    
    public func setShowNewLine(_ value: Bool) {
        self.showNewLine = value
    }
    
    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                if showNewLine {
                    Button(action: onNewLine) {
                        Image(systemName: "return")
                    }
                    .buttonStyle(ToolbarButtonStyle())
                }
                Button(action: onClearFormatting) {
                    Image(systemName: "pencil.slash")
                }
                .buttonStyle(ToolbarButtonStyle())
                Spacer()
                // Quote Button
                Button(action: onQuote) {
                    Image(systemName: "text.quote")
                }
                .buttonStyle(ToolbarButtonStyle())
                
                // Spoiler Button
                Button(action: onSpoiler) {
                    Image(systemName: "eye.slash")
                }
                .buttonStyle(ToolbarButtonStyle())
                
                // Bold Button
                Button(action: onBold) {
                    Image(systemName: "bold")
                }
                .buttonStyle(ToolbarButtonStyle())
                
                // Italic Button
                Button(action: onItalic) {
                    Image(systemName: "italic")
                }
                .buttonStyle(ToolbarButtonStyle())
                
                // Monospace Button
                Button(action: onMonospace) {
                    if #available(iOS 16.4, *) {
                        Text("M").monospaced()
                    } else {
                        Text("M")
                    }
                }
                .buttonStyle(ToolbarButtonStyle())
                
                // Link Button
                Button(action: onLink) {
                    Image(systemName: "link")
                }
                .buttonStyle(ToolbarButtonStyle())
                
                // Underline Button
                Button(action: onUnderline) {
                    Image(systemName: "underline")
                }
                .buttonStyle(ToolbarButtonStyle())
                
                
                // Strikethrough Button
                Button(action: onStrikethrough) {
                    Image(systemName: "strikethrough")
                }
                .buttonStyle(ToolbarButtonStyle())
                
                
                // Code Button
                Button(action: onCode) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                }
                .buttonStyle(ToolbarButtonStyle())
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .background(Color(UIColor.clear))
    }
}


// iOS 13–14 blur fallback
@available(iOS 13.0, *)
struct BlurView: UIViewRepresentable {
    let style: UIBlurEffect.Style
    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: style))
    }
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: style)
    }
}

// Simple glass background (now supports round + adaptive brightness)
@available(iOS 13.0, *)
struct Glass: View {
    var cornerRadius: CGFloat?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isDark = colorScheme == .dark

        Group {
            if #available(iOS 15.0, *) {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Circle()
                            .fill(
                                Color.white.opacity(isDark ? 0.05 : 0.25)
                            )
                    )
            } else {
                Circle()
                    .fill(Color.clear)
                    .background(
                        BlurView(style: .systemThinMaterial)
                            .clipShape(Circle())
                    )
                    .overlay(
                        Circle()
                            .fill(
                                Color.white.opacity(isDark ? 0.05 : 0.25)
                            )
                    )
            }
        }
        .overlay(
            Circle()
                .stroke(Color.white.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 3)
    }

}

// Button style
@available(iOS 13.0, *)
struct ToolbarButtonStyle: ButtonStyle {
    var size: CGFloat = 39

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: size, height: size)
            .contentShape(Circle())
            .background(Glass())
            .overlay(
                Circle()
                    .fill(Color.black.opacity(configuration.isPressed ? 0.08 : 0))
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(nil, value: configuration.isPressed)
    }
}

