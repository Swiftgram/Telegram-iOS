import SwiftUI
import Foundation


// MARK: Swiftgram
@available(iOS 13.0, *)
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
    var preferredColorScheme: ColorScheme?
    
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
        onClearFormatting: @escaping () -> Void,
        preferredColorScheme: ColorScheme? = nil
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
        self.preferredColorScheme = preferredColorScheme // TODO(swiftgram): Does not work for buttons :(
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
                    .buttonStyle(ToolbarButtonStyle(preferredColorScheme: preferredColorScheme))
                    .preferredColorScheme(preferredColorScheme)
                }
                Button(action: onClearFormatting) {
                    Image(systemName: "pencil.slash")
                }
                .buttonStyle(ToolbarButtonStyle(preferredColorScheme: preferredColorScheme))
                .preferredColorScheme(preferredColorScheme)
                Spacer()
                // Quote Button
                Button(action: onQuote) {
                    Image(systemName: "text.quote")
                }
                .buttonStyle(ToolbarButtonStyle(preferredColorScheme: preferredColorScheme))
                .preferredColorScheme(preferredColorScheme)
                
                // Spoiler Button
                Button(action: onSpoiler) {
                    Image(systemName: "eye.slash")
                }
                .buttonStyle(ToolbarButtonStyle(preferredColorScheme: preferredColorScheme))
                .preferredColorScheme(preferredColorScheme)
                
                // Bold Button
                Button(action: onBold) {
                    Image(systemName: "bold")
                }
                .buttonStyle(ToolbarButtonStyle(preferredColorScheme: preferredColorScheme))
                .preferredColorScheme(preferredColorScheme)
                
                // Italic Button
                Button(action: onItalic) {
                    Image(systemName: "italic")
                }
                .buttonStyle(ToolbarButtonStyle(preferredColorScheme: preferredColorScheme))
                .preferredColorScheme(preferredColorScheme)
                
                // Monospace Button
                Button(action: onMonospace) {
                    if #available(iOS 16.4, *) {
                        Text("M").monospaced()
                    } else {
                        Text("M")
                    }
                }
                .buttonStyle(ToolbarButtonStyle(preferredColorScheme: preferredColorScheme))
                .preferredColorScheme(preferredColorScheme)
                
                // Link Button
                Button(action: onLink) {
                    Image(systemName: "link")
                }
                .buttonStyle(ToolbarButtonStyle(preferredColorScheme: preferredColorScheme))
                .preferredColorScheme(preferredColorScheme)
                
                // Underline Button
                Button(action: onUnderline) {
                    Image(systemName: "underline")
                }
                .buttonStyle(ToolbarButtonStyle(preferredColorScheme: preferredColorScheme))
                .preferredColorScheme(preferredColorScheme)
                
                
                // Strikethrough Button
                Button(action: onStrikethrough) {
                    Image(systemName: "strikethrough")
                }
                .buttonStyle(ToolbarButtonStyle(preferredColorScheme: preferredColorScheme))
                .preferredColorScheme(preferredColorScheme)
                
                
                // Code Button
                Button(action: onCode) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                }
                .buttonStyle(ToolbarButtonStyle(preferredColorScheme: preferredColorScheme))
                .preferredColorScheme(preferredColorScheme)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .background(Color(UIColor.clear))
        .preferredColorScheme(preferredColorScheme)
    }
}

@available(iOS 13.0, *)
struct ToolbarButtonStyle: ButtonStyle {
    
    var preferredColorScheme: ColorScheme? = nil
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17))
            .frame(width: 36, height: 36, alignment: .center)
            .background(Color(UIColor.tertiarySystemBackground))
            .cornerRadius(8)
            // TODO(swiftgram): Does not work for fast taps (like mine)
            .opacity(configuration.isPressed ? 0.4 : 1.0)
            .preferredColorScheme(preferredColorScheme)
    }
}
