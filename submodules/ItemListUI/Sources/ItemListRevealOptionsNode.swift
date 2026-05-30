import Foundation
import UIKit
import AsyncDisplayKit
import Display
import ManagedAnimationNode

public enum ItemListRevealOptionIcon: Equatable {
    case none
    case image(image: UIImage)
    case animation(animation: String, scale: CGFloat, offset: CGFloat, replaceColors: [UInt32]?, flip: Bool)

    public static func ==(lhs: ItemListRevealOptionIcon, rhs: ItemListRevealOptionIcon) -> Bool {
        switch lhs {
        case .none:
            if case .none = rhs {
                return true
            } else {
                return false
            }
        case let .image(lhsImage):
            if case let .image(rhsImage) = rhs, lhsImage == rhsImage {
                return true
            } else {
                return false
            }
        case let .animation(lhsAnimation, lhsScale, lhsOffset, lhsKeysToColor, lhsFlip):
            if case let .animation(rhsAnimation, rhsScale, rhsOffset, rhsKeysToColor, rhsFlip) = rhs, lhsAnimation == rhsAnimation, lhsScale == rhsScale, lhsOffset == rhsOffset, lhsKeysToColor == rhsKeysToColor, lhsFlip == rhsFlip {
                return true
            } else {
                return false
            }
        }
    }
}

public struct ItemListRevealOption: Equatable {
    public let key: Int32
    public let title: String
    public let icon: ItemListRevealOptionIcon
    public let color: UIColor
    public let iconColor: UIColor
    public let textColor: UIColor

    public init(key: Int32, title: String, icon: ItemListRevealOptionIcon, color: UIColor, iconColor: UIColor, textColor: UIColor) {
        self.key = key
        self.title = title
        self.icon = icon
        self.color = color
        self.iconColor = iconColor
        self.textColor = textColor
    }

    public static func ==(lhs: ItemListRevealOption, rhs: ItemListRevealOption) -> Bool {
        if lhs.key != rhs.key {
            return false
        }
        if lhs.title != rhs.title {
            return false
        }
        if !lhs.color.isEqual(rhs.color) {
            return false
        }
        if !lhs.iconColor.isEqual(rhs.iconColor) {
            return false
        }
        if !lhs.textColor.isEqual(rhs.textColor) {
            return false
        }
        if lhs.icon != rhs.icon {
            return false
        }
        return true
    }
}

private let titleFont = Font.regular(11.0)
private let iconlessTitleFont = Font.regular(13.0)

private let optionSpacing: CGFloat = 10.0
private let optionEdgeInset: CGFloat = 10.0
private let optionTitleSpacing: CGFloat = 4.0
private let optionRevealStartOverlap: CGFloat = 12.0
private let optionRevealEndDistance: CGFloat = 10.0
private let optionExpandedActivationWidthFactor: CGFloat = 3.0
private let optionExpandedTransitionDistance: CGFloat = 16.0
private let optionPillTitleHorizontalPadding: CGFloat = 6.0
private let optionIconlessTitleAdditionalHorizontalPadding: CGFloat = 8.0
private let optionIconAnimationResponse: CGFloat = 18.0
private let optionIconAnimationSnapDistance: CGFloat = 0.5

private extension ItemListRevealOptionIcon {
    var hasVisualIcon: Bool {
        switch self {
        case .none:
            return false
        case .image, .animation:
            return true
        }
    }
}

private struct ItemListRevealOptionLayoutMetrics {
    let shapeSize: CGSize
    let slotWidth: CGFloat
    let titleWidth: CGFloat
    let iconMaxSide: CGFloat
    let cornerRadius: CGFloat
    let expandedIconInset: CGFloat

    var contentHeight: CGFloat {
        return self.shapeSize.height + optionTitleSpacing + ceil(titleFont.lineHeight)
    }

    var slotShapeInset: CGFloat {
        return floor((self.slotWidth - self.shapeSize.width) / 2.0)
    }

    static func metrics(for height: CGFloat, hasVisualIcons: Bool) -> ItemListRevealOptionLayoutMetrics {
        let regularShapeSize = CGSize(width: 50.0, height: 50.0)
        let compactShapeSize = CGSize(width: 60.0, height: 32.0)
        let regularContentHeight = regularShapeSize.height + optionTitleSpacing + ceil(titleFont.lineHeight)
        if height < regularContentHeight || !hasVisualIcons {
            return ItemListRevealOptionLayoutMetrics(shapeSize: compactShapeSize, slotWidth: 70.0, titleWidth: 70.0, iconMaxSide: 20.0, cornerRadius: 16.0, expandedIconInset: 16.0)
        } else {
            return ItemListRevealOptionLayoutMetrics(shapeSize: regularShapeSize, slotWidth: 60.0, titleWidth: 60.0, iconMaxSide: 40.0, cornerRadius: 25.0, expandedIconInset: 20.0)
        }
    }

    func withGroupTitleWidth(_ maxTitleWidth: CGFloat) -> ItemListRevealOptionLayoutMetrics {
        if maxTitleWidth <= self.shapeSize.width - optionPillTitleHorizontalPadding {
            return self
        }

        let updatedShapeWidth = ceil(maxTitleWidth + optionPillTitleHorizontalPadding)
        let slotWidthDelta = self.slotWidth - self.shapeSize.width
        return ItemListRevealOptionLayoutMetrics(
            shapeSize: CGSize(width: updatedShapeWidth, height: self.shapeSize.height),
            slotWidth: updatedShapeWidth + slotWidthDelta,
            titleWidth: max(self.titleWidth, updatedShapeWidth - optionPillTitleHorizontalPadding),
            iconMaxSide: self.iconMaxSide,
            cornerRadius: self.cornerRadius,
            expandedIconInset: self.expandedIconInset
        )
    }

    func revealWidth(count: Int) -> CGFloat {
        if count == 0 {
            return 0.0
        }
        return optionEdgeInset * 2.0 + self.shapeSize.width * CGFloat(count) + optionSpacing * CGFloat(count - 1)
    }
}

private func clampToUnitInterval(_ value: CGFloat) -> CGFloat {
    return max(0.0, min(1.0, value))
}

private func frameCenter(_ frame: CGRect) -> CGPoint {
    return CGPoint(x: frame.midX, y: frame.midY)
}

private final class ItemListRevealOptionNode: ASDisplayNode {
    private let contentContainerNode: ASDisplayNode
    private let backgroundNode: ASDisplayNode
    private let highlightNode: ASDisplayNode
    private let titleNode: ASTextNode
    private let iconNode: ASImageNode?
    private let animationNode: SimpleAnimationNode?

    private let enableAnimations: Bool
    private let displaysTitleInsidePill: Bool

    private var animationScale: CGFloat = 1.0
    private var animationNodeOffset: CGFloat = 0.0
    private var animationNodeFlip = false

    private var iconAnimationLink: SharedDisplayLinkDriver.Link?
    private weak var manuallyAnimatedIconNode: ASDisplayNode?
    private var currentIconCenter: CGPoint?
    private var targetIconCenter: CGPoint?

    private var didApplyLayout = false
    var isExpanded: Bool = false

    var hasAppliedLayout: Bool {
        return self.didApplyLayout
    }

    var titleWidthForGroupPillSizing: CGFloat {
        var titleWidth = self.titleNode.measure(CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)).width
        if self.displaysTitleInsidePill {
            titleWidth += optionIconlessTitleAdditionalHorizontalPadding
        }
        return titleWidth
    }

    init(title: String, icon: ItemListRevealOptionIcon, color: UIColor, iconColor: UIColor, textColor: UIColor, enableAnimations: Bool) {
        self.contentContainerNode = ASDisplayNode()
        self.backgroundNode = ASDisplayNode()
        self.highlightNode = ASDisplayNode()

        self.titleNode = ASTextNode()
        self.titleNode.maximumNumberOfLines = 1
        self.titleNode.truncationMode = .byTruncatingTail

        let displaysTitleInsidePill: Bool
        if case .none = icon {
            displaysTitleInsidePill = true
        } else {
            displaysTitleInsidePill = false
        }
        self.displaysTitleInsidePill = displaysTitleInsidePill
        self.titleNode.attributedText = NSAttributedString(string: title, font: displaysTitleInsidePill ? iconlessTitleFont : titleFont, textColor: displaysTitleInsidePill ? iconColor : textColor)

        self.enableAnimations = enableAnimations

        switch icon {
        case let .image(image):
            let iconNode = ASImageNode()
            iconNode.image = generateTintedImage(image: image, color: iconColor)
            self.iconNode = iconNode
            self.animationNode = nil

        case let .animation(animation, scale, offset, replaceColors, flip):
            self.animationScale = scale
            self.iconNode = nil
            var colors: [UInt32: UInt32] = [:]
            if let replaceColors = replaceColors {
                for colorToReplace in replaceColors {
                    colors[colorToReplace] = color.rgb
                }
            }
            self.animationNode = SimpleAnimationNode(animationName: animation, replaceColors: colors, size: CGSize(width: 66.0, height: 66.0), playOnce: true)
            if !enableAnimations {
                self.animationNode!.seekToEnd()
            }
            if flip {
                self.animationNode!.transform = CATransform3DMakeScale(1.0, -1.0, 1.0)
            }
            self.animationNodeOffset = offset
            self.animationNodeFlip = flip
            break

        case .none:
            self.iconNode = nil
            self.animationNode = nil
        }

        super.init()

        self.contentContainerNode.layer.allowsGroupOpacity = true
        self.addSubnode(self.contentContainerNode)
        self.contentContainerNode.addSubnode(self.backgroundNode)
        self.contentContainerNode.addSubnode(self.titleNode)
        if let iconNode = self.iconNode {
            self.contentContainerNode.addSubnode(iconNode)
        } else if let animationNode = self.animationNode {
            self.contentContainerNode.addSubnode(animationNode)
        }
        self.backgroundNode.backgroundColor = color
        self.highlightNode.backgroundColor = color.withMultipliedBrightnessBy(0.9)
    }

    deinit {
        self.stopManualIconAnimation()
    }

    func setHighlighted(_ highlighted: Bool) {
        if highlighted {
            self.contentContainerNode.insertSubnode(self.highlightNode, aboveSubnode: self.backgroundNode)
            self.highlightNode.layer.animate(from: 0.0 as NSNumber, to: 1.0 as NSNumber, keyPath: "opacity", timingFunction: CAMediaTimingFunctionName.easeInEaseOut.rawValue, duration: 0.3)
            self.highlightNode.alpha = 1.0
        } else {
            self.highlightNode.removeFromSupernode()
            self.highlightNode.alpha = 0.0
        }
    }

    func resetAnimation() {
        self.animationNode?.reset()
        self.stopManualIconAnimation()
    }

    private func currentIconPresentationCenter(iconNode: ASDisplayNode) -> CGPoint {
        return iconNode.layer.presentation()?.position ?? iconNode.position
    }

    private func isManualIconAnimationAtTarget(center: CGPoint) -> Bool {
        guard let targetIconCenter = self.targetIconCenter else {
            return true
        }
        let centerDeltaX = targetIconCenter.x - center.x
        let centerDeltaY = targetIconCenter.y - center.y
        let centerDistance = sqrt(centerDeltaX * centerDeltaX + centerDeltaY * centerDeltaY)
        return centerDistance <= optionIconAnimationSnapDistance
    }

    private func stopManualIconAnimation() {
        self.iconAnimationLink?.isPaused = true
        self.iconAnimationLink?.invalidate()
        self.iconAnimationLink = nil
        self.manuallyAnimatedIconNode = nil
        self.currentIconCenter = nil
        self.targetIconCenter = nil
    }

    private func updateManualIconCenter(iconNode: ASDisplayNode, targetCenter: CGPoint, forceImmediate: Bool) {
        iconNode.layer.removeAnimation(forKey: "position")

        if self.manuallyAnimatedIconNode !== iconNode || self.currentIconCenter == nil {
            self.currentIconCenter = self.currentIconPresentationCenter(iconNode: iconNode)
            self.manuallyAnimatedIconNode = iconNode
        }

        self.targetIconCenter = targetCenter

        if forceImmediate {
            iconNode.position = targetCenter
            self.stopManualIconAnimation()
            return
        }

        if let currentIconCenter = self.currentIconCenter, self.isManualIconAnimationAtTarget(center: currentIconCenter) {
            iconNode.position = targetCenter
            self.stopManualIconAnimation()
            return
        }

        if self.iconAnimationLink == nil {
            self.iconAnimationLink = SharedDisplayLinkDriver.shared.add(framesPerSecond: .max, { [weak self] deltaTime in
                self?.tickManualIconAnimation(deltaTime: deltaTime)
            })
            self.iconAnimationLink?.isPaused = false
        }
    }

    private func tickManualIconAnimation(deltaTime: CGFloat) {
        guard let iconNode = self.manuallyAnimatedIconNode, let currentIconCenter = self.currentIconCenter, let targetIconCenter = self.targetIconCenter else {
            self.stopManualIconAnimation()
            return
        }

        let clampedDeltaTime = min(0.05, max(0.0, deltaTime))
        let progress = 1.0 - exp(-clampedDeltaTime * optionIconAnimationResponse)
        let updatedCenter = CGPoint(
            x: currentIconCenter.x + (targetIconCenter.x - currentIconCenter.x) * progress,
            y: currentIconCenter.y + (targetIconCenter.y - currentIconCenter.y) * progress
        )

        if self.isManualIconAnimationAtTarget(center: updatedCenter) {
            iconNode.position = targetIconCenter
            self.stopManualIconAnimation()
        } else {
            self.currentIconCenter = updatedCenter
            iconNode.position = updatedCenter
        }
    }

    func updateLayout(isLeft: Bool, isPrimary: Bool, metrics: ItemListRevealOptionLayoutMetrics, revealProgress: CGFloat, overswipeProgress: CGFloat, expandedProgress: CGFloat, isStretched: Bool, isExpanded: Bool, transition: ContainedViewLayoutTransition) {
        let didApplyLayout = self.didApplyLayout
        let bounds = CGRect(origin: CGPoint(), size: self.bounds.size)
        transition.updateFrame(node: self.contentContainerNode, frame: bounds)

        let titleSize = self.titleNode.measure(CGSize(width: metrics.titleWidth, height: CGFloat.greatestFiniteMagnitude))
        let pillSize = metrics.shapeSize
        let shapeY: CGFloat
        if self.displaysTitleInsidePill {
            shapeY = floor((bounds.height - pillSize.height) / 2.0)
        } else {
            shapeY = floor((bounds.height - metrics.contentHeight) / 2.0)
        }

        let shapeFrameX: CGFloat
        if isStretched {
            shapeFrameX = isLeft ? 0.0 : bounds.width - pillSize.width
        } else {
            shapeFrameX = floor((metrics.slotWidth - pillSize.width) / 2.0)
        }
        let shapeFrame = CGRect(origin: CGPoint(x: shapeFrameX, y: shapeY), size: pillSize)
        let backgroundFrame: CGRect
        if isStretched {
            backgroundFrame = CGRect(origin: CGPoint(x: 0.0, y: shapeY), size: CGSize(width: bounds.width, height: pillSize.height))
        } else {
            backgroundFrame = shapeFrame
        }

        transition.updateFrame(node: self.backgroundNode, frame: backgroundFrame)
        transition.updateFrame(node: self.highlightNode, frame: backgroundFrame)
        transition.updateCornerRadius(node: self.backgroundNode, cornerRadius: metrics.cornerRadius)
        transition.updateCornerRadius(node: self.highlightNode, cornerRadius: metrics.cornerRadius)

        let wasExpanded = self.isExpanded
        self.isExpanded = isExpanded
        self.didApplyLayout = true
        let contentAlpha: CGFloat
        if isPrimary {
            contentAlpha = revealProgress
        } else {
            contentAlpha = revealProgress * (1.0 - 0.3 * overswipeProgress)
        }
        let contentScale = 0.3 + 0.7 * revealProgress
        transition.updateAlpha(node: self.contentContainerNode, alpha: contentAlpha)
        transition.updateTransform(node: self.contentContainerNode, transform: CGAffineTransform(scaleX: contentScale, y: contentScale))

        let titleAlpha: CGFloat = isPrimary && !self.displaysTitleInsidePill ? (1.0 - expandedProgress) : 1.0
        var didApplyManualIconCenter = false

        let centeredIconCenterX = isPrimary ? backgroundFrame.midX : shapeFrame.midX
        let iconCenterX: CGFloat
        if isPrimary && expandedProgress > 0.0 {
            let expandedIconCenterX: CGFloat
            if isLeft {
                expandedIconCenterX = backgroundFrame.maxX - metrics.expandedIconInset
            } else {
                expandedIconCenterX = backgroundFrame.minX + metrics.expandedIconInset
            }
            iconCenterX = centeredIconCenterX + (expandedIconCenterX - centeredIconCenterX) * expandedProgress
        } else {
            iconCenterX = centeredIconCenterX
        }
        let iconCenterY = backgroundFrame.midY

        if let animationNode = self.animationNode {
            var imageSize = CGSize(width: animationNode.size.width * self.animationScale, height: animationNode.size.height * self.animationScale)
            let imageMaxSide = max(imageSize.width, imageSize.height)
            if imageMaxSide > metrics.iconMaxSide {
                let imageScale = metrics.iconMaxSide / imageMaxSide * 1.4
                imageSize = CGSize(width: floorToScreenPixels(imageSize.width * imageScale), height: floorToScreenPixels(imageSize.height * imageScale))
            }
            let iconFrame = CGRect(origin: CGPoint(x: floorToScreenPixels(iconCenterX - imageSize.width / 2.0), y: floorToScreenPixels(iconCenterY - imageSize.height / 2.0) + 6.0 + self.animationNodeOffset), size: imageSize)

            if isPrimary {
                didApplyManualIconCenter = true
                transition.updateBounds(node: animationNode, bounds: CGRect(origin: CGPoint(), size: iconFrame.size))
                let targetCenter = frameCenter(iconFrame)
                if didApplyLayout && wasExpanded != isExpanded && revealProgress >= CGFloat.ulpOfOne {
                    self.updateManualIconCenter(iconNode: animationNode, targetCenter: targetCenter, forceImmediate: false)
                } else if self.manuallyAnimatedIconNode === animationNode && self.iconAnimationLink != nil && revealProgress >= CGFloat.ulpOfOne {
                    self.updateManualIconCenter(iconNode: animationNode, targetCenter: targetCenter, forceImmediate: false)
                } else {
                    self.stopManualIconAnimation()
                    transition.updatePosition(node: animationNode, position: targetCenter)
                }
            } else {
                transition.updateFrame(node: animationNode, frame: iconFrame)
            }
            if self.enableAnimations {
                if revealProgress >= 0.4 {
                    animationNode.play()
                } else if revealProgress < CGFloat.ulpOfOne && !transition.isAnimated {
                    animationNode.reset()
                }
            }
        } else if let iconNode = self.iconNode, let imageSize = iconNode.image?.size {
            var fittedSize = imageSize
            let imageMaxSide = max(fittedSize.width, fittedSize.height)
            if imageMaxSide > metrics.iconMaxSide {
                let imageScale = metrics.iconMaxSide / imageMaxSide
                fittedSize = CGSize(width: floorToScreenPixels(fittedSize.width * imageScale), height: floorToScreenPixels(fittedSize.height * imageScale))
            }
            let iconFrame = CGRect(origin: CGPoint(x: floorToScreenPixels(iconCenterX - fittedSize.width / 2.0), y: floorToScreenPixels(iconCenterY - fittedSize.height / 2.0)), size: fittedSize)
            if isPrimary {
                didApplyManualIconCenter = true
                transition.updateBounds(node: iconNode, bounds: CGRect(origin: CGPoint(), size: iconFrame.size))
                let targetCenter = frameCenter(iconFrame)
                if didApplyLayout && wasExpanded != isExpanded && revealProgress >= CGFloat.ulpOfOne {
                    self.updateManualIconCenter(iconNode: iconNode, targetCenter: targetCenter, forceImmediate: false)
                } else if self.manuallyAnimatedIconNode === iconNode && self.iconAnimationLink != nil && revealProgress >= CGFloat.ulpOfOne {
                    self.updateManualIconCenter(iconNode: iconNode, targetCenter: targetCenter, forceImmediate: false)
                } else {
                    self.stopManualIconAnimation()
                    transition.updatePosition(node: iconNode, position: targetCenter)
                }
            } else {
                transition.updateFrame(node: iconNode, frame: iconFrame)
            }
        }

        if !didApplyManualIconCenter {
            self.stopManualIconAnimation()
        }
        transition.updateAlpha(node: self.titleNode, alpha: titleAlpha)

        let titleFrame: CGRect
        if self.displaysTitleInsidePill {
            titleFrame = CGRect(origin: CGPoint(x: floorToScreenPixels(backgroundFrame.midX - titleSize.width / 2.0), y: floorToScreenPixels(backgroundFrame.midY - titleSize.height / 2.0)), size: titleSize)
        } else {
            let titleCenterX = isPrimary ? backgroundFrame.midX : shapeFrame.midX
            titleFrame = CGRect(origin: CGPoint(x: floorToScreenPixels(titleCenterX - titleSize.width / 2.0), y: shapeFrame.maxY + optionTitleSpacing), size: titleSize)
        }
        transition.updateFrame(node: self.titleNode, frame: titleFrame)
    }

    override func calculateSizeThatFits(_ constrainedSize: CGSize) -> CGSize {
        let metrics = ItemListRevealOptionLayoutMetrics.metrics(for: constrainedSize.height, hasVisualIcons: !self.displaysTitleInsidePill)
        let _ = self.titleNode.measure(CGSize(width: metrics.titleWidth, height: CGFloat.greatestFiniteMagnitude))
        return CGSize(width: metrics.slotWidth, height: constrainedSize.height)
    }
}

public final class ItemListRevealOptionsNode: ASDisplayNode {
    private let optionSelected: (ItemListRevealOption) -> Void
    private let tapticAction: () -> Void
    private let clippingContainerNode: ASDisplayNode
    private let optionsContainerNode: ASDisplayNode

    private var options: [ItemListRevealOption] = []
    private var isLeft: Bool = false

    private var optionNodes: [ItemListRevealOptionNode] = []
    private var revealOffset: CGFloat = 0.0
    private var sideInset: CGFloat = 0.0

    public init(optionSelected: @escaping (ItemListRevealOption) -> Void, tapticAction: @escaping () -> Void) {
        self.optionSelected = optionSelected
        self.tapticAction = tapticAction
        self.clippingContainerNode = ASDisplayNode()
        self.optionsContainerNode = ASDisplayNode()

        super.init()

        self.clippingContainerNode.clipsToBounds = true
        self.addSubnode(self.clippingContainerNode)
        self.clippingContainerNode.addSubnode(self.optionsContainerNode)
    }

    override public func didLoad() {
        super.didLoad()

        let gestureRecognizer = TapLongTapOrDoubleTapGestureRecognizer(target: self, action: #selector(self.tapGesture(_:)))
        gestureRecognizer.highlight = { [weak self] location in
            guard let strongSelf = self, let location = location else {
                return
            }
            for node in strongSelf.optionNodes {
                if node.frame.contains(location) {
                    //node.setHighlighted(true)
                    break
                }
            }
        }
        gestureRecognizer.tapActionAtPoint = { _ in
            return .waitForSingleTap
        }
        self.view.addGestureRecognizer(gestureRecognizer)
    }

    public func setOptions(_ options: [ItemListRevealOption], isLeft: Bool, enableAnimations: Bool) {
        if self.options != options || self.isLeft != isLeft {
            self.options = options
            self.isLeft = isLeft
            for node in self.optionNodes {
                node.removeFromSupernode()
            }
            self.optionNodes = options.map { option in
                return ItemListRevealOptionNode(title: option.title, icon: option.icon, color: option.color, iconColor: option.iconColor, textColor: option.textColor, enableAnimations: enableAnimations)
            }
            if isLeft {
                for node in self.optionNodes.reversed() {
                    self.optionsContainerNode.addSubnode(node)
                }
            } else {
                for node in self.optionNodes {
                    self.optionsContainerNode.addSubnode(node)
                }
            }
            self.invalidateCalculatedLayout()
        }
    }

    private func layoutMetrics(for height: CGFloat) -> ItemListRevealOptionLayoutMetrics {
        let metrics = ItemListRevealOptionLayoutMetrics.metrics(for: height, hasVisualIcons: self.options.contains(where: { $0.icon.hasVisualIcon }))
        let maxTitleWidth = self.optionNodes.reduce(0.0) { result, node in
            return max(result, node.titleWidthForGroupPillSizing)
        }
        return metrics.withGroupTitleWidth(maxTitleWidth)
    }

    override public func calculateSizeThatFits(_ constrainedSize: CGSize) -> CGSize {
        let metrics = self.layoutMetrics(for: constrainedSize.height)
        for node in self.optionNodes {
            let _ = node.measure(constrainedSize)
        }
        return CGSize(width: metrics.revealWidth(count: self.optionNodes.count), height: constrainedSize.height)
    }

    public func updateRevealOffset(offset: CGFloat, sideInset: CGFloat, transition: ContainedViewLayoutTransition) {
        self.revealOffset = offset
        self.sideInset = sideInset
        self.updateNodesLayout(transition: transition)
    }

    private func updateNodesLayout(transition: ContainedViewLayoutTransition) {
        let size = self.bounds.size
        if size.width.isLessThanOrEqualTo(0.0) || self.optionNodes.isEmpty {
            return
        }
        let metrics = self.layoutMetrics(for: size.height)
        let revealedDistance = abs(self.revealOffset)
        let boundedRevealedDistance = min(revealedDistance, size.width)
        let overswipeDistance = max(0.0, revealedDistance - size.width)
        let overswipeProgress = clampToUnitInterval(overswipeDistance / optionExpandedTransitionDistance)
        let expandedActivationDistance = 50.0 * (optionExpandedActivationWidthFactor - 1.0)
        let primaryIndex = self.isLeft ? 0 : self.optionNodes.count - 1
        let stride = metrics.shapeSize.width + optionSpacing

        let clippingFrameX: CGFloat
        if self.isLeft {
            clippingFrameX = max(0.0, size.width - revealedDistance)
        } else {
            clippingFrameX = 0.0
        }
        let clippingFrame = CGRect(origin: CGPoint(x: clippingFrameX, y: 0.0), size: CGSize(width: revealedDistance, height: size.height))
        transition.updateFrame(node: self.clippingContainerNode, frame: clippingFrame)
        transition.updateFrame(node: self.optionsContainerNode, frame: CGRect(origin: CGPoint(x: -clippingFrameX, y: 0.0), size: CGSize(width: max(size.width, revealedDistance), height: size.height)))

        let animated = transition.isAnimated
        var completionCount = self.optionNodes.count
        let intermediateCompletion = {
            if completionCount == 0 && animated && revealedDistance < CGFloat.ulpOfOne {
                for node in self.optionNodes {
                    node.resetAnimation()
                }
            }
        }

        var i = self.isLeft ? (self.optionNodes.count - 1) : 0
        while i >= 0 && i < self.optionNodes.count {
            let node = self.optionNodes[i]
            let isPrimary = i == primaryIndex
            let isStretched = isPrimary && overswipeDistance > CGFloat.ulpOfOne
            let isExpanded = isPrimary && overswipeDistance > expandedActivationDistance
            let expandedProgress: CGFloat = isExpanded ? 1.0 : 0.0
            if node.hasAppliedLayout && node.isExpanded != isExpanded && !transition.isAnimated {
                self.tapticAction()
            }

            let baseCircleFrame: CGRect
            let nodeFrame: CGRect
            let revealProgress: CGFloat

            if self.isLeft {
                let baseCircleLeft = size.width - boundedRevealedDistance + self.sideInset + optionEdgeInset + CGFloat(i) * stride
                baseCircleFrame = CGRect(origin: CGPoint(x: baseCircleLeft, y: 0.0), size: metrics.shapeSize)
                let distanceFromShutterEdge = size.width - baseCircleFrame.maxX
                revealProgress = clampToUnitInterval((distanceFromShutterEdge + optionRevealStartOverlap) / (optionRevealStartOverlap + optionRevealEndDistance))

                if isStretched {
                    let primaryLeft = size.width - boundedRevealedDistance + self.sideInset + optionEdgeInset
                    let primaryRight: CGFloat
                    if self.optionNodes.count > 1 {
                        let neighborLeft = primaryLeft + stride + overswipeDistance
                        primaryRight = max(primaryLeft + metrics.shapeSize.width, neighborLeft - optionSpacing)
                    } else {
                        primaryRight = primaryLeft + metrics.shapeSize.width + overswipeDistance
                    }
                    nodeFrame = CGRect(origin: CGPoint(x: floorToScreenPixels(primaryLeft), y: 0.0), size: CGSize(width: max(metrics.shapeSize.width, primaryRight - primaryLeft), height: size.height))
                } else {
                    let circleLeft = baseCircleLeft + (isPrimary ? 0.0 : overswipeDistance)
                    nodeFrame = CGRect(origin: CGPoint(x: floorToScreenPixels(circleLeft - metrics.slotShapeInset), y: 0.0), size: CGSize(width: metrics.slotWidth, height: size.height))
                }
            } else {
                let baseCircleRight = revealedDistance + self.sideInset - optionEdgeInset - CGFloat(self.optionNodes.count - 1 - i) * stride
                baseCircleFrame = CGRect(origin: CGPoint(x: baseCircleRight - metrics.shapeSize.width, y: 0.0), size: metrics.shapeSize)
                revealProgress = clampToUnitInterval((baseCircleFrame.minX + optionRevealStartOverlap) / (optionRevealStartOverlap + optionRevealEndDistance))

                if isStretched {
                    let primaryRight = revealedDistance + self.sideInset - optionEdgeInset
                    let primaryLeft: CGFloat
                    if self.optionNodes.count > 1 {
                        let neighborRight = primaryRight - stride - overswipeDistance
                        primaryLeft = min(primaryRight - metrics.shapeSize.width, neighborRight + optionSpacing)
                    } else {
                        primaryLeft = primaryRight - metrics.shapeSize.width - overswipeDistance
                    }
                    nodeFrame = CGRect(origin: CGPoint(x: floorToScreenPixels(primaryLeft), y: 0.0), size: CGSize(width: max(metrics.shapeSize.width, primaryRight - primaryLeft), height: size.height))
                } else {
                    let circleLeft = baseCircleFrame.minX - (isPrimary ? 0.0 : overswipeDistance)
                    nodeFrame = CGRect(origin: CGPoint(x: floorToScreenPixels(circleLeft - metrics.slotShapeInset), y: 0.0), size: CGSize(width: metrics.slotWidth, height: size.height))
                }
            }

            transition.updateFrame(node: node, frame: nodeFrame, completion: { _ in
                completionCount -= 1
                intermediateCompletion()
            })

            node.updateLayout(isLeft: self.isLeft, isPrimary: isPrimary, metrics: metrics, revealProgress: revealProgress, overswipeProgress: overswipeProgress, expandedProgress: expandedProgress, isStretched: isStretched, isExpanded: isExpanded, transition: transition)

            if self.isLeft {
                i -= 1
            } else {
                i += 1
            }
        }
    }

    @objc private func tapGesture(_ recognizer: TapLongTapOrDoubleTapGestureRecognizer) {
        if case .ended = recognizer.state, let gesture = recognizer.lastRecognizedGestureAndLocation?.0, case .tap = gesture {
            let location = recognizer.location(in: self.view)
            var selectedOption: Int?

            var i = self.isLeft ? 0 : (self.optionNodes.count - 1)
            while i >= 0 && i < self.optionNodes.count {
                self.optionNodes[i].setHighlighted(false)
                if self.optionNodes[i].frame.contains(location) {
                    selectedOption = i
                    break
                }
                if self.isLeft {
                    i += 1
                } else {
                    i -= 1
                }
            }
            if let selectedOption = selectedOption {
                self.optionSelected(self.options[selectedOption])
            }
        }
    }

    public func isDisplayingExtendedAction() -> Bool {
        return self.optionNodes.contains(where: { $0.isExpanded })
    }
}
