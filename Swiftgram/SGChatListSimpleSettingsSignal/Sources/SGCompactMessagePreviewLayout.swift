import SGSimpleSettings
import CoreGraphics
import Display

enum SGCompactMessagePreviewLayout {
    static func isEnabled() -> Bool {
        (SGSimpleSettings.ChatListLines(rawValue: SGSimpleSettings.shared.chatListLines) ?? .three) != .three
    }

    static func avatarScaleDivisor(compactChatList: Bool, compactMessagePreview: Bool) -> CGFloat {
        compactChatList ? 1.5 : (compactMessagePreview ? 1.1 : 1.0)
    }

    static func forumTopicIconYOffset(compactMessagePreview: Bool) -> CGFloat {
        compactMessagePreview ? 8.0 : 0.0
    }

    static func badgeOffset(sizeFactor: CGFloat, compactMessagePreview: Bool, compactChatList: Bool) -> CGFloat {
        guard compactMessagePreview && !compactChatList else {
            return 0.0
        }

        let sizeRange: CGFloat = 0.5
        let maxLift: CGFloat = 16.0
        let maxDownshift: CGFloat = 24.0
        let sizeDelta = sizeFactor - 1.0
        let lift: CGFloat
        if sizeDelta >= 0.0 {
            let sizeGrow = min(sizeRange, sizeDelta)
            let sizeGrowFactor = sizeGrow / sizeRange
            lift = maxLift * sizeGrowFactor * sizeGrowFactor * (3.0 - 2.0 * sizeGrowFactor)
        } else {
            let sizeShrink = min(sizeRange, -sizeDelta)
            let sizeShrinkFactor = sizeShrink / sizeRange
            let downshift = maxDownshift * sizeShrinkFactor * sizeShrinkFactor * (3.0 - 2.0 * sizeShrinkFactor)
            lift = -downshift
        }

        return floorToScreenPixels(lift)
    }

    static func textVerticalOffset(sizeFactor: CGFloat, compactMessagePreview: Bool, compactChatList: Bool, hasAuthorLine: Bool) -> CGFloat {
        guard compactMessagePreview && !compactChatList && !hasAuthorLine else {
            return 0.0
        }
        return floorToScreenPixels(6.0 * sizeFactor)
    }

    static func titleTextSpacing(sizeFactor: CGFloat, compactMessagePreview: Bool, compactChatList: Bool, hasAuthorLine: Bool) -> CGFloat {
        guard compactMessagePreview && !compactChatList && !hasAuthorLine else {
            return 0.0
        }
        return floorToScreenPixels(6.0 * sizeFactor)
    }

    static func textBlockOffset(sizeFactor: CGFloat, compactMessagePreview: Bool, compactChatList: Bool, hasAuthorLine: Bool) -> CGFloat {
        textVerticalOffset(sizeFactor: sizeFactor, compactMessagePreview: compactMessagePreview, compactChatList: compactChatList, hasAuthorLine: hasAuthorLine)
        + titleTextSpacing(sizeFactor: sizeFactor, compactMessagePreview: compactMessagePreview, compactChatList: compactChatList, hasAuthorLine: hasAuthorLine)
    }
}
