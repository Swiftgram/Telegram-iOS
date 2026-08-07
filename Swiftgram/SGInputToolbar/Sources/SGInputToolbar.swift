import SwiftUI
import Foundation


// MARK: Swiftgram
public enum SGInputToolbarAction {
    case quote
    case spoiler
    case bold
    case italic
    case date
    case monospace
    case link
    case underline
    case strikethrough
    case code
    case newLine
    case clearFormatting
}

public struct ChatToolbarView: View {
    var onAction: (SGInputToolbarAction) -> Void
    var showsDateAction: Bool
    @Binding private var showNewLine: Bool
    
    public init(
        showsDateAction: Bool = false,
        showNewLine: Binding<Bool>,
        onAction: @escaping (SGInputToolbarAction) -> Void
    ) {
        self.onAction = onAction
        self.showsDateAction = showsDateAction
        self._showNewLine = showNewLine
    }
    
    public func setShowNewLine(_ value: Bool) {
        self.showNewLine = value
    }
    
    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                if showNewLine {
                    Button(action: { self.onAction(.newLine) }) {
                        Image(systemName: "return")
                    }
                    .buttonStyle(ToolbarButtonStyle())
                }
                Button(action: { self.onAction(.clearFormatting) }) {
                    Image(systemName: "pencil.slash")
                }
                .buttonStyle(ToolbarButtonStyle())
                Spacer()
                // Quote Button
                Button(action: { self.onAction(.quote) }) {
                    Image(systemName: "text.quote")
                }
                .buttonStyle(ToolbarButtonStyle())
                
                // Spoiler Button
                Button(action: { self.onAction(.spoiler) }) {
                    Image(systemName: "eye.slash")
                }
                .buttonStyle(ToolbarButtonStyle())
                
                // Bold Button
                Button(action: { self.onAction(.bold) }) {
                    Image(systemName: "bold")
                }
                .buttonStyle(ToolbarButtonStyle())
                
                // Italic Button
                Button(action: { self.onAction(.italic) }) {
                    Image(systemName: "italic")
                }
                .buttonStyle(ToolbarButtonStyle())

                if showsDateAction {
                    Button(action: { self.onAction(.date) }) {
                        Image(systemName: "calendar")
                    }
                    .buttonStyle(ToolbarButtonStyle())
                }
                
                // Monospace Button
                Button(action: { self.onAction(.monospace) }) {
                    if #available(iOS 16.4, *) {
                        Text("M").monospaced()
                    } else {
                        Text("M")
                    }
                }
                .buttonStyle(ToolbarButtonStyle())
                
                // Link Button
                Button(action: { self.onAction(.link) }) {
                    Image(systemName: "link")
                }
                .buttonStyle(ToolbarButtonStyle())
                
                // Underline Button
                Button(action: { self.onAction(.underline) }) {
                    Image(systemName: "underline")
                }
                .buttonStyle(ToolbarButtonStyle())
                
                
                // Strikethrough Button
                Button(action: { self.onAction(.strikethrough) }) {
                    Image(systemName: "strikethrough")
                }
                .buttonStyle(ToolbarButtonStyle())
                
                
                // Code Button
                Button(action: { self.onAction(.code) }) {
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
