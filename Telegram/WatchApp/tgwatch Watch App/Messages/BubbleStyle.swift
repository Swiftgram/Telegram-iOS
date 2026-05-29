import SwiftUI

/// Resolved colors for a message-bubble surface. Incoming bubbles are a fixed light (white)
/// surface with dark content; outgoing are the accent surface with white content. Colors are
/// FIXED (non-adaptive) on purpose: watchOS runs this app in permanent dark mode, so `.primary`
/// would resolve to white and vanish on the white incoming surface.
struct BubbleStyle: Equatable {
    let fill: Color
    let content: Color
    let secondary: Color
    let replyBar: Color
    let playFill: Color
    let playIcon: Color

    static let incoming = BubbleStyle(
        fill: .white,
        content: .black,
        secondary: Color.black.opacity(0.5),
        replyBar: .accentColor,
        playFill: .accentColor,
        playIcon: .white
    )
    static let outgoing = BubbleStyle(
        fill: .accentColor,
        content: .white,
        secondary: Color.white.opacity(0.7),
        replyBar: Color.white.opacity(0.7),
        playFill: .white,
        playIcon: .accentColor
    )

    static func resolve(isOutgoing: Bool) -> BubbleStyle { isOutgoing ? .outgoing : .incoming }
}

#if DEBUG
extension View {
    /// Renders a bubble `#Preview` on the device-accurate dark page so the white incoming
    /// surface is visible (SnapshotPreviews defaults to a light background).
    func bubblePreview() -> some View {
        padding()
            .background(Color.black)
            .environment(\.colorScheme, .dark)
    }
}
#endif
