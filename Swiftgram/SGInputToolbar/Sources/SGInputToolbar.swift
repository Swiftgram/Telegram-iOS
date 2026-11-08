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
    private let hasInputSelection: () -> Bool
    @State private var actionGeneration = UUID()
    @Binding private var showNewLine: Bool
    
    public init(
        showsDateAction: Bool = false,
        showNewLine: Binding<Bool>,
        hasInputSelection: @escaping () -> Bool = { true },
        onAction: @escaping (SGInputToolbarAction) -> Void
    ) {
        self.onAction = onAction
        self.hasInputSelection = hasInputSelection
        self.showsDateAction = showsDateAction
        self._showNewLine = showNewLine
    }
    
    public func setShowNewLine(_ value: Bool) {
        self.showNewLine = value
    }

    private func performAction(_ action: SGInputToolbarAction) {
        let needsAutoSelection: Bool
        switch action {
        case .newLine, .clearFormatting:
            needsAutoSelection = false
        default:
            needsAutoSelection = !self.hasInputSelection()
        }
        guard #available(iOS 26.0, *), needsAutoSelection else {
            self.onAction(action)
            return
        }
        // Auto-selecting text makes SwiftUI's glass button animation lag. Delay the action by
        // 300 ms to let the animation settle smoothly before selection updates the input field.
        // Read selection at tap time, not a cached SwiftUI value; existing selections stay immediate.
        let generation = self.actionGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard self.actionGeneration == generation else { return }
            self.onAction(action)
        }
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                if showNewLine {
                    Button(action: { self.performAction(.newLine) }) {
                        Image(systemName: "return")
                    }
                    .buttonStyle(ToolbarButtonStyle())
                }
                Button(action: { self.performAction(.clearFormatting) }) {
                    Image(systemName: "pencil.slash")
                }
                .buttonStyle(ToolbarButtonStyle())
                Spacer()
                // Quote Button
                Button(action: { self.performAction(.quote) }) {
                    Image(systemName: "text.quote")
                }
                .buttonStyle(ToolbarButtonStyle())
                
                // Spoiler Button
                Button(action: { self.performAction(.spoiler) }) {
                    Image(systemName: "eye.slash")
                }
                .buttonStyle(ToolbarButtonStyle())
                
                // Bold Button
                Button(action: { self.performAction(.bold) }) {
                    Image(systemName: "bold")
                }
                .buttonStyle(ToolbarButtonStyle())
                
                // Italic Button
                Button(action: { self.performAction(.italic) }) {
                    Image(systemName: "italic")
                }
                .buttonStyle(ToolbarButtonStyle())

                if showsDateAction {
                    Button(action: { self.performAction(.date) }) {
                        Image(systemName: "calendar")
                    }
                    .buttonStyle(ToolbarButtonStyle())
                }
                
                // Monospace Button
                Button(action: { self.performAction(.monospace) }) {
                    if #available(iOS 16.4, *) {
                        Text("M").monospaced()
                    } else {
                        Text("M")
                    }
                }
                .buttonStyle(ToolbarButtonStyle())
                
                // Link Button
                Button(action: { self.performAction(.link) }) {
                    Image(systemName: "link")
                }
                .buttonStyle(ToolbarButtonStyle())
                
                // Underline Button
                Button(action: { self.performAction(.underline) }) {
                    Image(systemName: "underline")
                }
                .buttonStyle(ToolbarButtonStyle())
                
                
                // Strikethrough Button
                Button(action: { self.performAction(.strikethrough) }) {
                    Image(systemName: "strikethrough")
                }
                .buttonStyle(ToolbarButtonStyle())
                
                
                // Code Button
                Button(action: { self.performAction(.code) }) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                }
                .buttonStyle(ToolbarButtonStyle())
            }
            .modifier(ToolbarGlassContainer())
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .background(Color.clear)
        .onDisappear { self.actionGeneration = UUID() }
    }
}


private struct ToolbarGlassContainer: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            // Keep the circles separate while sharing one glass rendering container.
            GlassEffectContainer(spacing: 0.0) {
                content
            }
        } else {
            content
        }
    }
}

// UIKit blur for light appearance
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
struct Glass: View {
    var cornerRadius: CGFloat?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isDark = colorScheme == .dark

        Group {
            if !isDark {
                BlurView(style: .extraLight)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Circle()
                            .fill(
                                Color.white.opacity(0.02)
                            )
                    )
            }
        }
        .overlay(
            Circle()
                .stroke(Color.white.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(isDark ? 0.12 : 0.04), radius: 6, x: 0, y: 3)
    }

}

// Button style
struct ToolbarButtonStyle: ButtonStyle {
    var size: CGFloat = 39
    @Environment(\.isEnabled) private var isEnabled

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        if #available(iOS 26.0, *) {
            configuration.label
                .frame(width: size, height: size)
                .contentShape(Circle())
                .glassEffect(.regular.interactive(isEnabled), in: Circle())
        } else {
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
}
