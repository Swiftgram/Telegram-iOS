import Foundation
import UIKit
import Photos
import Display
import LegacyComponents
import MediaAssetsContext
import SwiftSignalKit
import SSignalKit
import TelegramCore
import Postbox

struct SGQuickAttachMediaItem {
    let asset: PHAsset?
    let image: UIImage
}

private enum SGQuickAttachFanTuning {
    static let xStiffness: CGFloat = 320.0
    static let xDamping: CGFloat = 0.88
    static let yStiffness: CGFloat = 500.0
    static let yDamping: CGFloat = 0.60
    static let birthScale: CGFloat = 0.42
    static let stagger: Double = 0.028
    static let birthYOffset: CGFloat = 0.0
    static let yOvershootStep: CGFloat = 0.06
}

final class SGQuickAttachRecentPhotosProvider {
    static let shared = SGQuickAttachRecentPhotosProvider()

    // Photos and videos alike, the same set the picker shows.
    private let mediaAssetsContext = MediaAssetsContext()
    private let disposable = MetaDisposable()
    private var didRequestMediaAccess = false

    private(set) var items: [SGQuickAttachMediaItem] = []

    private init() {
    }

    deinit {
        self.disposable.dispose()
    }

    func prefetch(count: Int = 3, requestAccess: Bool = false) {
        let count = max(0, count)

        guard count > 0 else {
            self.items = []
            self.disposable.set(nil)
            return
        }

        let authorizationStatus: PHAuthorizationStatus
        if #available(iOS 14.0, *) {
            authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        } else {
            authorizationStatus = PHPhotoLibrary.authorizationStatus()
        }
        if requestAccess && authorizationStatus == .notDetermined && !self.didRequestMediaAccess {
            self.didRequestMediaAccess = true
            self.mediaAssetsContext.requestMediaAccess()
        }

        let mediaAssetsContext = self.mediaAssetsContext
        let scale = min(2.0, UIScreen.main.scale)
        let targetSize = CGSize(width: 128.0 * scale, height: 128.0 * scale)

        let itemsSignal: Signal<[SGQuickAttachMediaItem], NoError> = mediaAssetsContext.mediaAccess()
        |> mapToSignal { status -> Signal<[SGQuickAttachMediaItem], NoError> in
            let hasAccess: Bool
            if #available(iOS 14.0, *) {
                hasAccess = status == .authorized || status == .limited
            } else {
                hasAccess = status == .authorized
            }
            guard hasAccess else {
                return .single([])
            }

            return mediaAssetsContext.recentAssets()
            |> mapToSignal { fetchResult -> Signal<[SGQuickAttachMediaItem], NoError> in
                guard let fetchResult, fetchResult.count > 0 else {
                    return .single([])
                }

                let itemCount = min(count, fetchResult.count)
                let itemSignals: [Signal<SGQuickAttachMediaItem?, NoError>] = (0 ..< itemCount).map { offset in
                    let index = fetchResult.count - offset - 1
                    let asset = fetchResult.object(at: index)
                    return assetImage(
                        fetchResult: fetchResult,
                        index: index,
                        targetSize: targetSize,
                        exact: true,
                        // Not .opportunistic: its first delivery is a degraded thumbnail, and the fan is
                        // often presented before the good one lands.
                        deliveryMode: .highQualityFormat,
                        synchronous: false
                    )
                    |> map { image in
                        return image.flatMap { SGQuickAttachMediaItem(asset: asset, image: $0) }
                    }
                }

                guard !itemSignals.isEmpty else {
                    return .single([])
                }
                return combineLatest(itemSignals)
                |> map { items in
                    return items.compactMap { $0 }
                }
            }
        }

        self.disposable.set((itemsSignal
        |> deliverOnMainQueue).start(next: { [weak self] items in
            self?.items = items
        }))
    }
}

private final class SGQuickAttachCardView: UIView {
    let clippedView = UIView()
    let contentView: UIView

    init(contentView: UIView) {
        self.contentView = contentView
        super.init(frame: .zero)

        self.clipsToBounds = false
        self.layer.masksToBounds = false

        self.clippedView.clipsToBounds = true
        self.clippedView.layer.masksToBounds = true
        self.clippedView.layer.cornerCurve = .continuous
        self.addSubview(self.clippedView)

        self.clippedView.addSubview(contentView)
    }

    required init?(coder: NSCoder) {
        preconditionFailure()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        self.clippedView.frame = self.bounds
        self.contentView.frame = self.clippedView.bounds
    }

    func setCornerRadius(_ cornerRadius: CGFloat) {
        self.clippedView.layer.cornerRadius = cornerRadius
    }

    func freezePresentationState() {
        let currentPosition = self.layer.presentation()?.position
        let currentScale = (self.layer.presentation()?.value(forKeyPath: "transform.scale.x") as? NSNumber).map { CGFloat(truncating: $0) }
        let currentCornerRadius = self.clippedView.layer.presentation()?.cornerRadius

        self.layer.removeAllAnimations()
        self.clippedView.layer.removeAllAnimations()

        if let currentPosition {
            self.layer.position = currentPosition
        }
        if let currentScale {
            self.transform = CGAffineTransform(scaleX: currentScale, y: currentScale)
        }
        if let currentCornerRadius {
            self.setCornerRadius(currentCornerRadius)
        }
    }
}

final class SGQuickAttachFlowOverlayView: UIView {
    private var itemViews: [SGQuickAttachCardView] = []
    private var itemFrames: [CGRect] = []
    private var mediaItems: [SGQuickAttachMediaItem] = []
    private var sourceRect: CGRect = .zero
    private var highlightedIndex: Int?
    private var cancelHighlighted = false

    private let hapticFeedback = HapticFeedback()
    private let highlightedShadowOpacity: Float

    private let itemSide: CGFloat = 68.0
    private let itemSpacing: CGFloat = 9.0
    private let stripBottomGap: CGFloat = 14.0
    private let hitSlop: CGFloat = 14.0

    private(set) var cameraView: TGAttachmentCameraView?

    init(frame: CGRect, isDark: Bool) {
        self.highlightedShadowOpacity = isDark ? 0.38 : 0.25
        super.init(frame: frame)

        self.backgroundColor = .clear
        self.isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        preconditionFailure()
    }

    func present(items: [SGQuickAttachMediaItem], from sourceRect: CGRect) {
        self.cameraView?.stopPreview()
        self.cameraView = nil
        for itemView in self.itemViews {
            itemView.removeFromSuperview()
        }

        self.itemViews.removeAll()
        self.itemFrames.removeAll()
        self.mediaItems = items
        self.sourceRect = sourceRect
        self.highlightedIndex = nil
        self.cancelHighlighted = false

        self.hapticFeedback.impact(.medium)
        self.hapticFeedback.prepareTap()

        let itemCount = items.count + 1
        let stripY = sourceRect.minY - self.stripBottomGap - self.itemSide
        let maxX = self.bounds.width - 8.0 - self.itemSide
        for index in 0 ..< itemCount {
            let x = sourceRect.minX + CGFloat(index) * (self.itemSide + self.itemSpacing)
            self.itemFrames.append(CGRect(x: min(x, maxX), y: stripY, width: self.itemSide, height: self.itemSide))
        }

        let cameraView = TGAttachmentCameraView(forSelfPortrait: false, videoModeByDefault: false)!
        cameraView.clipsToBounds = true
        cameraView.removeCorners()
        cameraView.accessibilityIdentifier = "quickAttach.camera"
        cameraView.startPreview()
        self.cameraView = cameraView

        var itemViews: [SGQuickAttachCardView] = [SGQuickAttachCardView(contentView: cameraView)]
        itemViews.append(contentsOf: items.enumerated().map { index, item in
            let imageView = UIImageView(image: item.image)
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            imageView.accessibilityIdentifier = "quickAttach.photo.\(index)"
            return SGQuickAttachCardView(contentView: imageView)
        })
        self.itemViews = itemViews

        for (index, itemView) in itemViews.enumerated() {
            itemView.layer.removeAllAnimations()
            itemView.clippedView.layer.removeAllAnimations()
            itemView.transform = .identity
            itemView.frame = self.itemFrames[index]
            itemView.alpha = 0.0
            itemView.setCornerRadius(self.itemSide * 0.5)
            self.addSubview(itemView)
        }
        for itemView in itemViews.reversed() {
            self.bringSubviewToFront(itemView)
        }

        let source = CGPoint(x: sourceRect.midX, y: sourceRect.midY)
        for (index, itemView) in itemViews.enumerated() {
            let destination = itemView.center
            let beginTime = CACurrentMediaTime() + Double(index) * SGQuickAttachFanTuning.stagger
            let yDamping = max(0.2, SGQuickAttachFanTuning.yDamping - CGFloat(index) * SGQuickAttachFanTuning.yOvershootStep)

            itemView.layer.add(
                Self.spring(keyPath: "position.x", from: source.x, to: destination.x, stiffness: SGQuickAttachFanTuning.xStiffness, dampingRatio: SGQuickAttachFanTuning.xDamping, beginTime: beginTime),
                forKey: "quickAttachFlightX"
            )
            itemView.layer.add(
                Self.spring(keyPath: "position.y", from: source.y + SGQuickAttachFanTuning.birthYOffset, to: destination.y, stiffness: SGQuickAttachFanTuning.yStiffness, dampingRatio: yDamping, beginTime: beginTime),
                forKey: "quickAttachFlightY"
            )
            itemView.layer.add(
                Self.spring(keyPath: "transform.scale", from: SGQuickAttachFanTuning.birthScale, to: 1.0, stiffness: SGQuickAttachFanTuning.xStiffness, dampingRatio: SGQuickAttachFanTuning.xDamping, beginTime: beginTime),
                forKey: "quickAttachFlightScale"
            )

            let cornerAnimation = Self.spring(
                keyPath: "cornerRadius",
                from: self.itemSide * 0.5,
                to: 14.0,
                stiffness: SGQuickAttachFanTuning.xStiffness,
                dampingRatio: SGQuickAttachFanTuning.xDamping,
                beginTime: beginTime
            )
            itemView.clippedView.layer.add(cornerAnimation, forKey: "quickAttachCorner")
            itemView.setCornerRadius(14.0)

            UIView.animate(
                withDuration: 0.15,
                delay: max(0.0, beginTime - CACurrentMediaTime()),
                options: [.allowUserInteraction, .curveEaseOut]
            ) {
                itemView.alpha = 1.0
            }
        }
    }

    func mediaItem(atSelectedIndex selectedIndex: Int) -> SGQuickAttachMediaItem? {
        guard selectedIndex > 0 else {
            return nil
        }
        let mediaIndex = selectedIndex - 1
        guard self.mediaItems.indices.contains(mediaIndex) else {
            return nil
        }
        return self.mediaItems[mediaIndex]
    }

    func updateTracking(location: CGPoint) {
        let index = self.itemIndex(at: location)
        let isCancel = index == nil && self.sourceRect.insetBy(dx: -self.hitSlop, dy: -self.hitSlop).contains(location)

        if index != self.highlightedIndex {
            if index != nil {
                self.hapticFeedback.tap()
            }
            self.highlightedIndex = index

            for (itemIndex, itemView) in self.itemViews.enumerated() {
                let highlighted = itemIndex == index
                if highlighted {
                    itemView.layer.shadowColor = UIColor.black.cgColor
                    itemView.layer.shadowRadius = 12.0
                    itemView.layer.shadowOffset = CGSize(width: 0.0, height: 6.0)
                    self.bringSubviewToFront(itemView)
                }
                UIView.animate(
                    withDuration: 0.28,
                    delay: 0.0,
                    usingSpringWithDamping: 0.6,
                    initialSpringVelocity: 0.4,
                    options: [.allowUserInteraction, .beginFromCurrentState]
                ) {
                    itemView.transform = highlighted ? CGAffineTransform(scaleX: 1.18, y: 1.18) : .identity
                    itemView.layer.shadowOpacity = highlighted ? self.highlightedShadowOpacity : 0.0
                }
            }
        }

        if isCancel != self.cancelHighlighted {
            self.cancelHighlighted = isCancel
            if isCancel {
                self.hapticFeedback.tap()
            }
        }
    }

    func finishTracking(location: CGPoint) -> Int? {
        return self.itemIndex(at: location)
    }

    func prepareForCameraTransition() {
        for itemView in self.itemViews {
            itemView.freezePresentationState()
        }

        guard let cameraItemView = self.itemViews.first else {
            return
        }
        self.bringSubviewToFront(cameraItemView)

        for itemView in self.itemViews.dropFirst() {
            UIView.animate(withDuration: 0.10, delay: 0.0, options: [.curveEaseOut, .beginFromCurrentState]) {
                itemView.alpha = 0.0
                itemView.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
            }
        }
    }

    func dismiss(selectedIndex: Int?, targetRect: CGRect?, completion: @escaping () -> Void) {
        let validSelectedIndex = selectedIndex.flatMap { index in
            return self.itemViews.indices.contains(index) ? index : nil
        }
        let selectedCamera = validSelectedIndex == 0
        if !selectedCamera {
            self.cameraView?.stopPreview()
        }

        for itemView in self.itemViews {
            itemView.freezePresentationState()
        }

        for (index, itemView) in self.itemViews.enumerated() {
            if index == validSelectedIndex {
                continue
            }

            if validSelectedIndex == nil {
                let target = CGPoint(x: self.sourceRect.midX, y: self.sourceRect.midY + SGQuickAttachFanTuning.birthYOffset)
                let fromPosition = itemView.layer.position
                let fromScale = (itemView.layer.value(forKeyPath: "transform.scale.x") as? NSNumber).map { CGFloat(truncating: $0) } ?? itemView.transform.a
                let currentCornerRadius = itemView.clippedView.layer.cornerRadius
                let beginTime = CACurrentMediaTime() + Double(self.itemViews.count - 1 - index) * SGQuickAttachFanTuning.stagger
                let yDamping = max(0.2, SGQuickAttachFanTuning.yDamping - CGFloat(index) * SGQuickAttachFanTuning.yOvershootStep)

                itemView.layer.position = target
                itemView.transform = CGAffineTransform(scaleX: SGQuickAttachFanTuning.birthScale, y: SGQuickAttachFanTuning.birthScale)
                itemView.layer.add(
                    Self.spring(keyPath: "position.x", from: fromPosition.x, to: target.x, stiffness: SGQuickAttachFanTuning.yStiffness, dampingRatio: yDamping, beginTime: beginTime),
                    forKey: "quickAttachFoldX"
                )
                itemView.layer.add(
                    Self.spring(keyPath: "position.y", from: fromPosition.y, to: target.y, stiffness: SGQuickAttachFanTuning.xStiffness, dampingRatio: SGQuickAttachFanTuning.xDamping, beginTime: beginTime),
                    forKey: "quickAttachFoldY"
                )
                itemView.layer.add(
                    Self.spring(keyPath: "transform.scale", from: fromScale, to: SGQuickAttachFanTuning.birthScale, stiffness: SGQuickAttachFanTuning.xStiffness, dampingRatio: SGQuickAttachFanTuning.xDamping, beginTime: beginTime),
                    forKey: "quickAttachFoldScale"
                )

                let cornerAnimation = Self.spring(
                    keyPath: "cornerRadius",
                    from: currentCornerRadius,
                    to: self.itemSide * 0.5,
                    stiffness: SGQuickAttachFanTuning.xStiffness,
                    dampingRatio: SGQuickAttachFanTuning.xDamping,
                    beginTime: beginTime
                )
                itemView.clippedView.layer.add(cornerAnimation, forKey: "quickAttachCornerFold")
                itemView.setCornerRadius(self.itemSide * 0.5)

                UIView.animate(
                    withDuration: 0.10,
                    delay: max(0.0, beginTime - CACurrentMediaTime()),
                    options: .curveEaseOut
                ) {
                    itemView.alpha = 0.0
                }
            } else {
                UIView.animate(withDuration: 0.10, delay: 0.0, options: [.curveEaseOut, .beginFromCurrentState]) {
                    itemView.alpha = 0.0
                    itemView.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
                }
            }
        }

        if let validSelectedIndex, let targetRect {
            let selectedItemView = self.itemViews[validSelectedIndex]
            self.bringSubviewToFront(selectedItemView)

            if validSelectedIndex > 0 {
                let badge = SGQuickAttachBadge.makeView()
                badge.frame = CGRect(
                    x: selectedItemView.bounds.width - SGQuickAttachBadge.side - SGQuickAttachBadge.inset,
                    y: SGQuickAttachBadge.inset,
                    width: SGQuickAttachBadge.side,
                    height: SGQuickAttachBadge.side
                )
                badge.autoresizingMask = [.flexibleLeftMargin, .flexibleBottomMargin]
                badge.alpha = 0.0
                selectedItemView.addSubview(badge)
                UIView.animate(withDuration: 0.32) {
                    badge.alpha = 1.0
                }
            }

            let currentCornerRadius = selectedItemView.clippedView.layer.cornerRadius
            let cornerAnimation = CABasicAnimation(keyPath: "cornerRadius")
            cornerAnimation.fromValue = currentCornerRadius
            cornerAnimation.toValue = 10.0
            cornerAnimation.duration = 0.25
            selectedItemView.clippedView.layer.add(cornerAnimation, forKey: "quickAttachSelectedCorner")
            selectedItemView.setCornerRadius(10.0)

            UIView.animate(
                withDuration: 0.32,
                delay: 0.0,
                usingSpringWithDamping: 0.82,
                initialSpringVelocity: 0.4,
                options: [.beginFromCurrentState]
            ) {
                selectedItemView.center = targetRect.center
                selectedItemView.bounds = CGRect(origin: .zero, size: targetRect.size)
                selectedItemView.transform = .identity
                selectedItemView.layer.shadowOpacity = 0.0
            } completion: { _ in
                self.removeFromSuperview()
                completion()
            }
        } else if validSelectedIndex != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                self.removeFromSuperview()
                completion()
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                self.removeFromSuperview()
                completion()
            }
        }
    }

    private func itemIndex(at location: CGPoint) -> Int? {
        for (index, frame) in self.itemFrames.enumerated() {
            if frame.insetBy(dx: -self.hitSlop, dy: -self.hitSlop * 2.0).contains(location) {
                return index
            }
        }
        return nil
    }

    private static func spring(
        keyPath: String,
        from: CGFloat,
        to: CGFloat,
        stiffness: CGFloat,
        dampingRatio: CGFloat,
        beginTime: CFTimeInterval
    ) -> CASpringAnimation {
        let animation = CASpringAnimation(keyPath: keyPath)
        animation.fromValue = from
        animation.toValue = to
        animation.mass = 1.0
        animation.stiffness = stiffness
        animation.damping = dampingRatio * 2.0 * sqrt(stiffness)
        animation.duration = animation.settlingDuration
        animation.beginTime = beginTime
        animation.fillMode = .backwards
        return animation
    }
}

enum SGQuickAttachBadge {
    static let side: CGFloat = 22.0
    static let inset: CGFloat = 4.0

    static func makeView() -> UIView {
        let view = UIView()
        view.backgroundColor = UIColor(white: 0.0, alpha: 0.4)
        view.layer.cornerRadius = 11.0

        let icon = UIImageView(image: UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 10.0, weight: .bold)))
        icon.tintColor = .white
        icon.contentMode = .center
        icon.frame = CGRect(x: 0.0, y: 0.0, width: 22.0, height: 22.0)
        icon.isUserInteractionEnabled = false
        view.addSubview(icon)

        return view
    }
}

/// A composer attachment dressed as a picker item, so the upstream selection context and its
/// "selected" grid can hold and lay out media that did not come from the photo library.
final class SGQuickAttachPreviewItem: NSObject, TGMediaSelectableItem, TGMediaEditableItem {
    let identifier: String
    let media: Media?
    let image: UIImage

    init(identifier: String, media: Media?, image: UIImage) {
        self.identifier = identifier
        self.media = media
        self.image = image
        super.init()
    }

    var uniqueIdentifier: String! {
        return self.identifier
    }

    var isVideo: Bool {
        return (self.media as? TelegramMediaFile)?.isVideo ?? false
    }

    var originalSize: CGSize {
        return self.image.size
    }

    func thumbnailImageSignal() -> SSignal! {
        return SSignal.single(self.image)
    }

    func screenImageSignal(_ position: TimeInterval) -> SSignal! {
        return SSignal.single(self.image)
    }

    func originalImageSignal(_ position: TimeInterval) -> SSignal! {
        return SSignal.single(self.image)
    }
}
