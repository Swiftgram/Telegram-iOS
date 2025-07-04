import Foundation

extension Window1 {
    func sgAppBadgeOffset(_ defaultOffset: CGFloat) -> CGFloat {
        var additionalOffset: CGFloat = 0.0
        additionalOffset += 30.0
        return defaultOffset + additionalOffset
    }
}
