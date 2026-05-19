import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import AccountContext
import GalleryUI

// MARK: - Stable item identity (for view reuse on re-layouts)

/// Stable identity for an `InstantPageV2LaidOutItem` across `update()` calls. The renderer
/// uses this to harvest existing item views and reuse them when the new layout still has
/// an item with the same id — preventing the media wrappers from torching their fetch
/// signals + image content on every chat-bubble re-apply.
///
/// Media items use their `media.index` (already unique within a page and used as the
/// gallery registry key). Details items use their `details.index`. Other items have no
/// intrinsic identity, so the renderer assigns them a `(case-tag, positional-index-in-items)`
/// pair.
public enum InstantPageV2StableItemId: Hashable {
    case media(Int)                          // media.index (4 media cases share this namespace)
    case details(Int)                        // details.index
    case positional(InstantPageV2ItemKind, Int)  // (caseTag, items-array position)
}

public enum InstantPageV2ItemKind: Hashable {
    case text, codeBlock, divider, listMarker, blockQuoteBar, shape, mediaPlaceholder, table, anchor, formula
}

// MARK: - Render context

/// Bundle of render-time dependencies required to display real media inside an InstantPage V2
/// view. Tied to an `InstantPageV2View` for the view's lifetime — if any field would change
/// (typically because the bubble was recycled with a different webpage), the caller must
/// rebuild the V2View with a fresh render context.
///
/// `renderContext == nil` is permitted: the V2View falls back to grey-placeholder rendering
/// for the four media kinds (image/video/map/coverImage). This keeps the existing zero-arg
/// `InstantPageV2View()` constructor usable.
public final class InstantPageV2RenderContext {
    public let context: AccountContext
    public let webpage: TelegramMediaWebpage
    public let sourceLocation: InstantPageSourceLocation
    public let imageReference: (TelegramMediaImage) -> ImageMediaReference
    public let fileReference: (TelegramMediaFile) -> FileMediaReference
    public let present: (ViewController, Any?) -> Void
    public let push: (ViewController) -> Void
    public let openUrl: (InstantPageUrlItem) -> Void
    public let baseNavigationController: () -> NavigationController?

    public init(
        context: AccountContext,
        webpage: TelegramMediaWebpage,
        sourceLocation: InstantPageSourceLocation,
        imageReference: @escaping (TelegramMediaImage) -> ImageMediaReference,
        fileReference: @escaping (TelegramMediaFile) -> FileMediaReference,
        present: @escaping (ViewController, Any?) -> Void,
        push: @escaping (ViewController) -> Void,
        openUrl: @escaping (InstantPageUrlItem) -> Void,
        baseNavigationController: @escaping () -> NavigationController?
    ) {
        self.context = context
        self.webpage = webpage
        self.sourceLocation = sourceLocation
        self.imageReference = imageReference
        self.fileReference = fileReference
        self.present = present
        self.push = push
        self.openUrl = openUrl
        self.baseNavigationController = baseNavigationController
    }
}

// MARK: - Public renderer

public final class InstantPageV2View: UIView {
    public private(set) var currentLayout: InstantPageV2Layout?
    public private(set) var currentTheme: InstantPageTheme?

    /// Invoked when a details title is tapped. Bubble routes to its expand-state mutation + requestUpdate.
    public var detailsTapped: ((_ index: Int) -> Void)?

    private var itemViews: [InstantPageItemView] = []
    private var itemViewStableIds: [InstantPageV2StableItemId] = []

    public let renderContext: InstantPageV2RenderContext?

    // Weak references to every media wrapper in the tree, keyed by `InstantPageMedia.index`.
    // Used by `transitionArgsFor` and `applyHiddenMedia` so the gallery transition + hidden-source
    // state can find a wrapper without walking the view hierarchy. Nested V2Views (details body,
    // table cells) forward their registrations to the root via `rootMediaRegistryHost`.
    var mediaRegistry: [Int: Weak<UIView>] = [:]

    // Pointer to the root V2View's registry host. The root sets this to `self`; nested views
    // inherit it via `propagateRegistryHost(to:)` in `update(layout:theme:animation:)`.
    weak var rootMediaRegistryHost: InstantPageV2View?

    var effectiveRegistryHost: InstantPageV2View {
        return self.rootMediaRegistryHost ?? self
    }

    /// Walks the `rootMediaRegistryHost` chain transitively until it finds a self-referencing
    /// host (the true root). Necessary because nested details blocks can leave an inner body's
    /// `rootMediaRegistryHost` pointing at an intermediate body rather than the outer root —
    /// `propagateRegistryHost(to:)` only walks one hop, so the chain must be followed at lookup.
    var trueRegistryRoot: InstantPageV2View {
        var host: InstantPageV2View = self
        while let next = host.rootMediaRegistryHost, next !== host {
            host = next
        }
        return host
    }

    public init(renderContext: InstantPageV2RenderContext?) {
        self.renderContext = renderContext
        super.init(frame: .zero)
        self.backgroundColor = .clear
        self.isOpaque = false
        self.rootMediaRegistryHost = self
    }

    public convenience init() {
        self.init(renderContext: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Rebuilds the child view hierarchy from `layout`. The caller is responsible for
    /// sizing `self.frame` to `layout.contentSize`; this method does not touch its own frame.
    ///
    /// Reuse pass: existing item views are harvested into a `[stableId: view]` map keyed
    /// off `itemViewStableIds`. For each new item we look up its stable id; on a hit (and
    /// matching concrete view class) the existing view is reused via its typed
    /// `update(item:theme:[renderContext:])`, on a miss we fall back to `makeItemView`. Un-reused
    /// views are removed from the superview at the end. This preserves the four media wrappers
    /// (and any nested V2Views inside details/table) across chat-bubble re-applies, which would
    /// otherwise torch in-flight image fetches on every list update.
    public func update(
        layout: InstantPageV2Layout,
        theme: InstantPageTheme,
        animation: ListViewItemUpdateAnimation
    ) {
        let _ = animation   // reserved for future per-item animation

        // Build map of existing views by stable id.
        var oldViewsById: [InstantPageV2StableItemId: InstantPageItemView] = [:]
        for (oldIndex, oldId) in self.itemViewStableIds.enumerated() {
            oldViewsById[oldId] = self.itemViews[oldIndex]
        }

        var newItemViews: [InstantPageItemView] = []
        var newStableIds: [InstantPageV2StableItemId] = []
        var reusedIds: Set<InstantPageV2StableItemId> = []

        for (position, item) in layout.items.enumerated() {
            let id = InstantPageV2View.stableId(for: item, atPosition: position)

            if let existing = oldViewsById[id], let reusedView = self.reuse(existingView: existing, for: item, theme: theme) {
                reusedView.frame = InstantPageV2View.actualFrame(forItem: item)   // parent positions child
                newItemViews.append(reusedView)
                newStableIds.append(id)
                reusedIds.insert(id)
                // Already in subviews from the previous update; just keep it.
            } else {
                guard let newView = self.makeItemView(for: item, theme: theme) else { continue }
                newItemViews.append(newView)
                newStableIds.append(id)
                self.addSubview(newView)
                self.propagateRegistryHost(to: newView)
            }
        }

        // Remove views that weren't reused.
        for (id, view) in oldViewsById where !reusedIds.contains(id) {
            view.removeFromSuperview()
        }

        // Z-order: bring the reused views to the front in declaration order so the
        // sublayer/subview stack matches `layout.items` order.
        for view in newItemViews {
            self.bringSubviewToFront(view)
        }

        self.itemViews = newItemViews
        self.itemViewStableIds = newStableIds
        self.currentLayout = layout
        self.currentTheme = theme
    }

    /// Returns the input view typed-updated against `item`, or `nil` if the existing view's
    /// concrete class doesn't match the item's case (e.g. a `text` slot has been replaced by
    /// a `divider` in the new layout). Caller falls back to `makeItemView`.
    private func reuse(existingView: InstantPageItemView, for item: InstantPageV2LaidOutItem, theme: InstantPageTheme) -> InstantPageItemView? {
        switch item {
        case let .text(text):
            guard let v = existingView as? InstantPageV2TextView else { return nil }
            v.update(item: text, theme: theme)
            return v
        case let .codeBlock(block):
            guard let v = existingView as? InstantPageV2CodeBlockView else { return nil }
            v.update(item: block, theme: theme)
            return v
        case let .divider(divider):
            guard let v = existingView as? InstantPageV2DividerView else { return nil }
            v.update(item: divider, theme: theme)
            return v
        case let .listMarker(marker):
            guard let v = existingView as? InstantPageV2ListMarkerView else { return nil }
            v.update(item: marker, theme: theme)
            return v
        case let .blockQuoteBar(bar):
            guard let v = existingView as? InstantPageV2BlockQuoteBarView else { return nil }
            v.update(item: bar, theme: theme)
            return v
        case let .shape(shape):
            guard let v = existingView as? InstantPageV2ShapeView else { return nil }
            v.update(item: shape, theme: theme)
            return v
        case let .mediaPlaceholder(media):
            guard let v = existingView as? InstantPageV2MediaPlaceholderView else { return nil }
            v.update(item: media, theme: theme)
            return v
        case let .details(details):
            guard let v = existingView as? InstantPageV2DetailsView else { return nil }
            v.update(item: details, theme: theme, renderContext: self.renderContext)
            return v
        case let .table(table):
            guard let v = existingView as? InstantPageV2TableView else { return nil }
            v.update(item: table, theme: theme)
            return v
        case let .anchor(anchor):
            guard let v = existingView as? InstantPageV2AnchorView else { return nil }
            v.update(item: anchor, theme: theme)
            return v
        case let .formula(formula):
            guard let v = existingView as? InstantPageV2FormulaView else { return nil }
            v.update(item: formula, theme: theme)
            return v
        case let .mediaImage(media):
            guard let v = existingView as? InstantPageV2MediaImageView, let rc = self.renderContext else { return nil }
            v.update(item: media, theme: theme, renderContext: rc)
            return v
        case let .mediaVideo(media):
            guard let v = existingView as? InstantPageV2MediaVideoView, let rc = self.renderContext else { return nil }
            v.update(item: media, theme: theme, renderContext: rc)
            return v
        case let .mediaMap(media):
            guard let v = existingView as? InstantPageV2MediaMapView, let rc = self.renderContext else { return nil }
            v.update(item: media, theme: theme, renderContext: rc)
            return v
        case let .mediaCoverImage(media):
            guard let v = existingView as? InstantPageV2MediaCoverImageView, let rc = self.renderContext else { return nil }
            v.update(item: media, theme: theme, renderContext: rc)
            return v
        }
    }

    static func stableId(for item: InstantPageV2LaidOutItem, atPosition position: Int) -> InstantPageV2StableItemId {
        switch item {
        case let .mediaImage(m):       return .media(m.media.index)
        case let .mediaVideo(m):       return .media(m.media.index)
        case let .mediaMap(m):         return .media(m.media.index)
        case let .mediaCoverImage(m):  return .media(m.media.index)
        case let .details(d):          return .details(d.index)
        case .text:                    return .positional(.text, position)
        case .codeBlock:               return .positional(.codeBlock, position)
        case .divider:                 return .positional(.divider, position)
        case .listMarker:              return .positional(.listMarker, position)
        case .blockQuoteBar:           return .positional(.blockQuoteBar, position)
        case .shape:                   return .positional(.shape, position)
        case .mediaPlaceholder:        return .positional(.mediaPlaceholder, position)
        case .table:                   return .positional(.table, position)
        case .anchor:                  return .positional(.anchor, position)
        case .formula:                 return .positional(.formula, position)
        }
    }

    private func propagateRegistryHost(to view: InstantPageItemView) {
        let host = self.effectiveRegistryHost
        if let details = view as? InstantPageV2DetailsView {
            details.forEachSubLayoutView { sub in
                sub.rootMediaRegistryHost = host
            }
        }
        if let table = view as? InstantPageV2TableView {
            table.forEachSubLayoutView { sub in
                sub.rootMediaRegistryHost = host
            }
        }
    }

    /// Looks up the wrapper view registered under `media.index` and returns gallery transition
    /// arguments backed by its wrapped `InstantPageImageNode`. Returns `nil` if the wrapper is
    /// not currently registered (e.g. the media is inside a collapsed details block).
    func transitionArgsFor(_ media: InstantPageMedia, addToTransitionSurface: @escaping (UIView) -> Void) -> GalleryTransitionArguments? {
        guard let wrapperBox = self.trueRegistryRoot.mediaRegistry[media.index], let wrapper = wrapperBox.value else {
            return nil
        }
        let imageNode: InstantPageImageNode? =
            (wrapper as? InstantPageV2MediaImageView)?.wrappedNode
            ?? (wrapper as? InstantPageV2MediaVideoView)?.wrappedNode
            ?? (wrapper as? InstantPageV2MediaMapView)?.wrappedNode
            ?? (wrapper as? InstantPageV2MediaCoverImageView)?.wrappedNode
        guard let imageNode else { return nil }
        guard let transitionNode = imageNode.transitionNode(media: media) else { return nil }
        return GalleryTransitionArguments(transitionNode: transitionNode, addToTransitionSurface: addToTransitionSurface)
    }

    /// Forwards a hidden-media tick from the gallery's `hiddenMedia` signal to every registered
    /// wrapper, calling `updateHiddenMedia(media:)` on each wrapped image node.
    func applyHiddenMedia(_ hidden: InstantPageMedia?) {
        for (_, weakBox) in self.trueRegistryRoot.mediaRegistry {
            guard let wrapper = weakBox.value else { continue }
            if let v = wrapper as? InstantPageV2MediaImageView      { v.wrappedNode.updateHiddenMedia(media: hidden) }
            if let v = wrapper as? InstantPageV2MediaVideoView      { v.wrappedNode.updateHiddenMedia(media: hidden) }
            if let v = wrapper as? InstantPageV2MediaMapView        { v.wrappedNode.updateHiddenMedia(media: hidden) }
            if let v = wrapper as? InstantPageV2MediaCoverImageView { v.wrappedNode.updateHiddenMedia(media: hidden) }
        }
    }

    private func makeItemView(for item: InstantPageV2LaidOutItem, theme: InstantPageTheme) -> InstantPageItemView? {
        switch item {
        case let .text(text):
            return InstantPageV2TextView(item: text)
        case let .divider(divider):
            return InstantPageV2DividerView(item: divider)
        case let .anchor(anchor):
            return InstantPageV2AnchorView(item: anchor)
        case let .listMarker(marker):
            return InstantPageV2ListMarkerView(item: marker)
        case let .codeBlock(block):
            return InstantPageV2CodeBlockView(item: block)
        case let .blockQuoteBar(bar):
            return InstantPageV2BlockQuoteBarView(item: bar)
        case let .shape(shape):
            return InstantPageV2ShapeView(item: shape)
        case let .mediaPlaceholder(media):
            return InstantPageV2MediaPlaceholderView(item: media, theme: theme)
        case let .details(details):
            let view = InstantPageV2DetailsView(item: details, theme: theme, renderContext: self.renderContext)
            view.onTitleTapped = { [weak self] index in
                self?.detailsTapped?(index)
            }
            return view
        case let .table(table):
            return InstantPageV2TableView(item: table, theme: theme, renderContext: self.renderContext)
        case let .mediaImage(media):
            if let renderContext = self.renderContext {
                return InstantPageV2MediaImageView(item: media, renderContext: renderContext, theme: theme)
            } else {
                return InstantPageV2MediaPlaceholderView(item: placeholderFallback(for: media), theme: theme)
            }
        case let .mediaVideo(media):
            if let renderContext = self.renderContext {
                return InstantPageV2MediaVideoView(item: media, renderContext: renderContext, theme: theme)
            } else {
                return InstantPageV2MediaPlaceholderView(item: placeholderFallback(for: media), theme: theme)
            }
        case let .mediaMap(media):
            if let renderContext = self.renderContext {
                return InstantPageV2MediaMapView(item: media, renderContext: renderContext, theme: theme)
            } else {
                return InstantPageV2MediaPlaceholderView(item: placeholderFallback(for: media), theme: theme)
            }
        case let .mediaCoverImage(media):
            if let renderContext = self.renderContext {
                return InstantPageV2MediaCoverImageView(item: media, renderContext: renderContext, theme: theme)
            } else {
                return InstantPageV2MediaPlaceholderView(item: placeholderFallback(for: media), theme: theme)
            }
        case let .formula(formula):
            return InstantPageV2FormulaView(item: formula)
        }
    }

    /// Returns the frame the parent should assign to the view for `item`.
    ///
    /// For most item types this is `item.frame`. `InstantPageV2TextView` widens its backing store
    /// by `v2TextViewClippingInset` on every side to accommodate glyph overhang and underline
    /// rendering past the text's logical `maxY` — the same inset its `init` applies when
    /// constructing the view. The reuse path must apply the same expansion so that re-layout
    /// (theme change, bubble resize, etc.) does not clip italic glyphs or underlines.
    ///
    /// Keep this helper aligned with each view class's init-time frame computation.
    private static func actualFrame(forItem item: InstantPageV2LaidOutItem) -> CGRect {
        switch item {
        case let .text(textItem):
            return textItem.frame.insetBy(dx: -v2TextViewClippingInset, dy: -v2TextViewClippingInset)
        default:
            return item.frame
        }
    }
}

// MARK: - Placeholder fallbacks for the four typed media items
//
// Used by `makeItemView` when `renderContext == nil` (the zero-arg V2View constructor):
// we still need to emit a sized grey rectangle for image/video/map/coverImage so the
// surrounding layout doesn't collapse. Each helper synthesizes a placeholder item with
// the same frame + cornerRadius as the typed item, picking the kind that matches the
// closest existing placeholder visual.

private func placeholderFallback(for item: InstantPageV2MediaImageItem) -> InstantPageV2MediaPlaceholderItem {
    return InstantPageV2MediaPlaceholderItem(frame: item.frame, kind: .image, cornerRadius: item.cornerRadius)
}

private func placeholderFallback(for item: InstantPageV2MediaVideoItem) -> InstantPageV2MediaPlaceholderItem {
    return InstantPageV2MediaPlaceholderItem(frame: item.frame, kind: .video, cornerRadius: item.cornerRadius)
}

private func placeholderFallback(for item: InstantPageV2MediaMapItem) -> InstantPageV2MediaPlaceholderItem {
    return InstantPageV2MediaPlaceholderItem(frame: item.frame, kind: .map, cornerRadius: item.cornerRadius)
}

private func placeholderFallback(for item: InstantPageV2MediaCoverImageItem) -> InstantPageV2MediaPlaceholderItem {
    return InstantPageV2MediaPlaceholderItem(frame: item.frame, kind: .webEmbed, cornerRadius: item.cornerRadius)
}

// MARK: - Item view protocol

protocol InstantPageItemView: UIView {
    /// Frame in the parent V2 view's coordinate space (== `item.frame`).
    var itemFrame: CGRect { get }
    /// Recursion hook for nested layouts (details body, table cells, table title).
    var subLayoutView: InstantPageV2View? { get }
}

extension InstantPageItemView {
    var subLayoutView: InstantPageV2View? { return nil }
}

// MARK: - Text view (port of V1 InstantPageTextItem.drawInTile)

/// Per-side padding applied to `InstantPageV2TextView`'s backing store, beyond the
/// item's typographic frame. Marker rounded rects extend ±2pt past their run, italic
/// or accented glyphs can overhang past the line's advance width, and the last line's
/// underline sits 2pt below `lineFrame.maxY`. The view grows by this amount on each
/// side and the draw context translates by the same amount so visual position is
/// unchanged.
private let v2TextViewClippingInset: CGFloat = 4.0

final class InstantPageV2TextView: UIView, InstantPageItemView {
    private(set) var item: InstantPageV2TextItem
    var itemFrame: CGRect { return self.item.frame }

    init(item: InstantPageV2TextItem) {
        self.item = item
        super.init(frame: item.frame.insetBy(dx: -v2TextViewClippingInset, dy: -v2TextViewClippingInset))
        self.backgroundColor = .clear
        self.isOpaque = false
        self.contentMode = .redraw
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(item: InstantPageV2TextItem, theme: InstantPageTheme) {
        let _ = theme
        self.item = item
        self.setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }

        context.saveGState()
        context.textMatrix = CGAffineTransform(scaleX: 1.0, y: -1.0)
        context.translateBy(x: v2TextViewClippingInset, y: v2TextViewClippingInset)

        let textItem = self.item.textItem
        let boundsWidth = textItem.frame.size.width
        let intersectRect = rect.offsetBy(dx: -v2TextViewClippingInset, dy: -v2TextViewClippingInset)

        for line in textItem.lines {
            let lineFrame = v2FrameForLine(line, boundingWidth: boundsWidth, alignment: textItem.alignment)
            if !intersectRect.intersects(lineFrame) {
                continue
            }

            let lineOrigin = lineFrame.origin
            context.textPosition = CGPoint(x: lineOrigin.x, y: lineOrigin.y + lineFrame.size.height)

            if !line.markedItems.isEmpty {
                context.saveGState()
                for item in line.markedItems {
                    let itemFrame = item.frame.offsetBy(dx: lineFrame.minX, dy: 0.0)
                    context.setFillColor(item.color.cgColor)

                    let height = floor(item.frame.size.height * 2.2)
                    let markRect = CGRect(x: itemFrame.minX - 2.0, y: floor(itemFrame.minY + (itemFrame.height - height) / 2.0), width: itemFrame.width + 4.0, height: height)
                    let path = UIBezierPath(roundedRect: markRect, cornerRadius: 3.0)
                    context.addPath(path.cgPath)
                    context.fillPath()
                }
                context.restoreGState()
            }

            if textItem.opaqueBackground {
                context.setBlendMode(.normal)
            }

            let glyphRuns = CTLineGetGlyphRuns(line.line) as NSArray
            if glyphRuns.count != 0 {
                for run in glyphRuns {
                    let run = run as! CTRun
                    let glyphCount = CTRunGetGlyphCount(run)
                    CTRunDraw(run, context, CFRangeMake(0, glyphCount))
                }
            }

            if textItem.opaqueBackground {
                context.setBlendMode(.copy)
            }

            if !line.strikethroughItems.isEmpty {
                for item in line.strikethroughItems {
                    let itemFrame = item.frame.offsetBy(dx: lineFrame.minX, dy: 0.0)
                    context.fill(CGRect(x: itemFrame.minX, y: itemFrame.minY + floor((lineFrame.size.height / 2.0) + 1.0), width: itemFrame.size.width, height: 1.0))
                }
            }

            if !line.underlineItems.isEmpty {
                for item in line.underlineItems {
                    var color: UIColor? = item.color
                    if color == nil {
                        textItem.attributedString.enumerateAttributes(in: item.range, options: []) { attributes, _, _ in
                            if let foreground = attributes[NSAttributedString.Key.foregroundColor] as? UIColor {
                                color = foreground
                            }
                        }
                    }
                    if let color {
                        context.setFillColor(color.cgColor)
                    }
                    let itemFrame = item.frame.offsetBy(dx: lineFrame.minX, dy: 0.0)
                    context.fill(CGRect(x: itemFrame.minX, y: itemFrame.minY + lineFrame.size.height + 2.0, width: itemFrame.size.width, height: 1.0))
                }
            }
        }

        context.restoreGState()
    }
}

// MARK: - Divider view

final class InstantPageV2DividerView: UIView, InstantPageItemView {
    private(set) var item: InstantPageV2DividerItem
    var itemFrame: CGRect { return self.item.frame }

    init(item: InstantPageV2DividerItem) {
        self.item = item
        super.init(frame: item.frame)
        self.backgroundColor = item.color
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(item: InstantPageV2DividerItem, theme: InstantPageTheme) {
        let _ = theme
        self.item = item
        self.backgroundColor = item.color
    }
}

// MARK: - Anchor view (zero-height; nothing to render)

final class InstantPageV2AnchorView: UIView, InstantPageItemView {
    private(set) var item: InstantPageV2AnchorItem
    var itemFrame: CGRect { return self.item.frame }

    init(item: InstantPageV2AnchorItem) {
        self.item = item
        super.init(frame: item.frame)
        self.isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(item: InstantPageV2AnchorItem, theme: InstantPageTheme) {
        let _ = theme
        self.item = item
    }
}

// MARK: - List marker view

final class InstantPageV2ListMarkerView: UIView, InstantPageItemView {
    private(set) var item: InstantPageV2ListMarkerItem
    var itemFrame: CGRect { return self.item.frame }

    init(item: InstantPageV2ListMarkerItem) {
        self.item = item
        super.init(frame: item.frame)
        self.backgroundColor = .clear
        self.isOpaque = false
        self.rebuildContents()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(item: InstantPageV2ListMarkerItem, theme: InstantPageTheme) {
        let _ = theme
        self.item = item
        self.rebuildContents()
    }

    private func rebuildContents() {
        if let sublayers = self.layer.sublayers {
            for sublayer in sublayers {
                sublayer.removeFromSuperlayer()
            }
        }
        for subview in self.subviews {
            subview.removeFromSuperview()
        }

        let item = self.item
        switch item.kind {
        case .bullet:
            let radius: CGFloat = min(item.frame.width, item.frame.height) / 2.0
            let dot = CALayer()
            dot.backgroundColor = item.color.cgColor
            dot.frame = CGRect(
                x: (item.frame.width - radius * 2.0) / 2.0,
                y: (item.frame.height - radius * 2.0) / 2.0,
                width: radius * 2.0,
                height: radius * 2.0
            )
            dot.cornerRadius = radius
            self.layer.addSublayer(dot)
        case let .number(text):
            let label = UILabel()
            label.text = text
            label.textColor = item.color
            label.font = UIFont.systemFont(ofSize: 17.0)
            label.textAlignment = .right
            label.frame = CGRect(origin: .zero, size: item.frame.size)
            self.addSubview(label)
        case let .checklist(checked):
            // V0 placeholder: simple square outline (unchecked) or filled square (checked).
            // The existing V1 InstantPageChecklistMarkerItem artwork can be ported later if needed.
            let outer = CALayer()
            outer.borderColor = item.color.cgColor
            outer.borderWidth = 1.0
            outer.cornerRadius = 3.0
            outer.frame = CGRect(origin: .zero, size: item.frame.size)
            self.layer.addSublayer(outer)
            if checked {
                let fill = CALayer()
                fill.backgroundColor = item.color.cgColor
                fill.cornerRadius = 3.0
                fill.frame = CGRect(origin: .zero, size: item.frame.size).insetBy(dx: 2.0, dy: 2.0)
                self.layer.addSublayer(fill)
            }
        }
    }
}

// MARK: - Quote bar view

final class InstantPageV2BlockQuoteBarView: UIView, InstantPageItemView {
    private(set) var item: InstantPageV2BarItem
    var itemFrame: CGRect { return self.item.frame }

    init(item: InstantPageV2BarItem) {
        self.item = item
        super.init(frame: item.frame)
        self.backgroundColor = item.color
        self.layer.cornerRadius = item.cornerRadius
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(item: InstantPageV2BarItem, theme: InstantPageTheme) {
        let _ = theme
        self.item = item
        self.backgroundColor = item.color
        self.layer.cornerRadius = item.cornerRadius
    }
}

// MARK: - Shape view (for pullQuote line ornaments)

final class InstantPageV2ShapeView: UIView, InstantPageItemView {
    private(set) var item: InstantPageV2ShapeItem
    var itemFrame: CGRect { return self.item.frame }

    init(item: InstantPageV2ShapeItem) {
        self.item = item
        super.init(frame: item.frame)
        self.applyKind()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(item: InstantPageV2ShapeItem, theme: InstantPageTheme) {
        let _ = theme
        self.item = item
        self.applyKind()
    }

    private func applyKind() {
        switch self.item.kind {
        case let .roundedRect(cornerRadius):
            self.backgroundColor = self.item.color
            self.layer.cornerRadius = cornerRadius
        case .line(_):
            self.backgroundColor = self.item.color
            self.layer.cornerRadius = 0.0
        }
    }
}

// MARK: - Media placeholder view (V0: gray rectangle)

final class InstantPageV2MediaPlaceholderView: UIView, InstantPageItemView {
    private(set) var item: InstantPageV2MediaPlaceholderItem
    var itemFrame: CGRect { return self.item.frame }

    init(item: InstantPageV2MediaPlaceholderItem, theme: InstantPageTheme) {
        self.item = item
        super.init(frame: item.frame)
        self.backgroundColor = theme.imageTintColor?.withAlphaComponent(0.2) ?? UIColor(white: 0.85, alpha: 1.0)
        self.layer.cornerRadius = item.cornerRadius
        self.clipsToBounds = item.cornerRadius > 0.0
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(item: InstantPageV2MediaPlaceholderItem, theme: InstantPageTheme) {
        self.item = item
        self.backgroundColor = theme.imageTintColor?.withAlphaComponent(0.2) ?? UIColor(white: 0.85, alpha: 1.0)
        self.layer.cornerRadius = item.cornerRadius
        self.clipsToBounds = item.cornerRadius > 0.0
    }
}

// MARK: - Details view

final class InstantPageV2DetailsView: UIView, InstantPageItemView {
    private(set) var item: InstantPageV2DetailsItem
    var itemFrame: CGRect { return self.item.frame }

    private let titleTextView: InstantPageV2TextView
    private let chevronLayer: CALayer
    private let separator: UIView
    private var bodyView: InstantPageV2View?
    private let titleHitView: UIView

    var onTitleTapped: ((Int) -> Void)?

    var subLayoutView: InstantPageV2View? { return self.bodyView }

    func forEachSubLayoutView(_ body: (InstantPageV2View) -> Void) {
        if let bodyView = self.bodyView { body(bodyView) }
    }

    init(item: InstantPageV2DetailsItem, theme: InstantPageTheme, renderContext: InstantPageV2RenderContext?) {
        self.item = item

        let titleV2Item = InstantPageV2TextItem(
            frame: item.titleTextItem.frame,
            textItem: item.titleTextItem
        )
        self.titleTextView = InstantPageV2TextView(item: titleV2Item)
        self.titleTextView.isUserInteractionEnabled = false

        self.chevronLayer = CALayer()
        // V1 uses a custom-drawn InstantPageDetailsArrowNode; V2 uses a SF Symbol for simplicity.
        // (SF Symbol "chevron.up/down" is iOS 13+ which matches our minimum deployment target.)
        let chevronImage = UIImage(systemName: item.isExpanded ? "chevron.up" : "chevron.down")?
            .withTintColor(theme.textCategories.paragraph.color, renderingMode: .alwaysOriginal)
        self.chevronLayer.contents = chevronImage?.cgImage
        self.chevronLayer.contentsGravity = .resizeAspect

        self.separator = UIView()
        self.separator.backgroundColor = item.separatorColor
        self.separator.isUserInteractionEnabled = false

        self.titleHitView = UIView(frame: item.titleFrame)
        self.titleHitView.backgroundColor = .clear

        super.init(frame: item.frame)
        self.backgroundColor = .clear
        self.clipsToBounds = true

        self.addSubview(self.titleTextView)
        self.layer.addSublayer(self.chevronLayer)
        self.addSubview(self.separator)

        let chevronSize = CGSize(width: 18.0, height: 18.0)
        self.chevronLayer.frame = CGRect(
            x: item.titleFrame.maxX - chevronSize.width - 12.0,
            y: item.titleFrame.midY - chevronSize.height / 2.0,
            width: chevronSize.width,
            height: chevronSize.height
        )

        // V1 (InstantPageDetailsNode.swift:138): separator sits at titleHeight - UIScreenPixel.
        self.separator.frame = CGRect(
            x: 0.0,
            y: item.titleFrame.maxY - 0.5,
            width: item.frame.width,
            height: 0.5
        )

        if item.isExpanded, let innerLayout = item.innerLayout {
            let body = InstantPageV2View(renderContext: renderContext)
            body.update(layout: innerLayout, theme: theme, animation: .None)
            body.frame = CGRect(
                origin: CGPoint(x: 0.0, y: item.titleFrame.maxY),
                size: innerLayout.contentSize
            )
            self.addSubview(body)
            self.bodyView = body
        }

        let tap = UITapGestureRecognizer(target: self, action: #selector(self.titleTapped))
        self.insertSubview(self.titleHitView, at: 0)
        self.titleHitView.addGestureRecognizer(tap)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func titleTapped() {
        self.onTitleTapped?(self.item.index)
    }

    func update(item: InstantPageV2DetailsItem, theme: InstantPageTheme, renderContext: InstantPageV2RenderContext?) {
        let previousIsExpanded = self.item.isExpanded
        self.item = item

        let titleV2Item = InstantPageV2TextItem(
            frame: item.titleTextItem.frame,
            textItem: item.titleTextItem
        )
        self.titleTextView.update(item: titleV2Item, theme: theme)

        let chevronImage = UIImage(systemName: item.isExpanded ? "chevron.up" : "chevron.down")?
            .withTintColor(theme.textCategories.paragraph.color, renderingMode: .alwaysOriginal)
        self.chevronLayer.contents = chevronImage?.cgImage
        let chevronSize = CGSize(width: 18.0, height: 18.0)
        self.chevronLayer.frame = CGRect(
            x: item.titleFrame.maxX - chevronSize.width - 12.0,
            y: item.titleFrame.midY - chevronSize.height / 2.0,
            width: chevronSize.width,
            height: chevronSize.height
        )

        self.separator.backgroundColor = item.separatorColor
        self.separator.frame = CGRect(
            x: 0.0,
            y: item.titleFrame.maxY - 0.5,
            width: item.frame.width,
            height: 0.5
        )

        self.titleHitView.frame = item.titleFrame

        // Body recursion: if both old and new are expanded with a body, forward the update.
        // If the expand state changed, tear down and rebuild (task B refines).
        if previousIsExpanded && item.isExpanded, let innerLayout = item.innerLayout, let existingBody = self.bodyView {
            existingBody.update(layout: innerLayout, theme: theme, animation: .None)
            existingBody.frame = CGRect(
                origin: CGPoint(x: 0.0, y: item.titleFrame.maxY),
                size: innerLayout.contentSize
            )
        } else {
            if let existingBody = self.bodyView {
                existingBody.removeFromSuperview()
                self.bodyView = nil
            }
            if item.isExpanded, let innerLayout = item.innerLayout {
                let body = InstantPageV2View(renderContext: renderContext)
                body.update(layout: innerLayout, theme: theme, animation: .None)
                body.frame = CGRect(
                    origin: CGPoint(x: 0.0, y: item.titleFrame.maxY),
                    size: innerLayout.contentSize
                )
                self.addSubview(body)
                self.bodyView = body
            }
        }
    }
}

// MARK: - Code block view

final class InstantPageV2CodeBlockView: UIView, InstantPageItemView {
    private(set) var item: InstantPageV2CodeBlockItem
    var itemFrame: CGRect { return self.item.frame }

    private let backgroundLayer: CALayer
    private let textView: InstantPageV2TextView

    init(item: InstantPageV2CodeBlockItem) {
        self.item = item

        self.backgroundLayer = CALayer()
        self.backgroundLayer.backgroundColor = item.backgroundColor.cgColor
        self.backgroundLayer.cornerRadius = item.cornerRadius
        self.backgroundLayer.frame = CGRect(origin: .zero, size: item.frame.size)

        // item.textItem.frame is already in code-block content-area coords (x=17, y=backgroundInset).
        let innerV2TextItem = InstantPageV2TextItem(
            frame: item.textItem.frame,
            textItem: item.textItem
        )
        self.textView = InstantPageV2TextView(item: innerV2TextItem)

        super.init(frame: item.frame)
        self.backgroundColor = .clear
        self.layer.addSublayer(self.backgroundLayer)
        self.addSubview(self.textView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(item: InstantPageV2CodeBlockItem, theme: InstantPageTheme) {
        self.item = item
        self.backgroundLayer.backgroundColor = item.backgroundColor.cgColor
        self.backgroundLayer.cornerRadius = item.cornerRadius
        self.backgroundLayer.frame = CGRect(origin: .zero, size: item.frame.size)

        let innerV2TextItem = InstantPageV2TextItem(
            frame: item.textItem.frame,
            textItem: item.textItem
        )
        self.textView.update(item: innerV2TextItem, theme: theme)
    }
}

// MARK: - Table view

final class InstantPageV2TableView: UIView, InstantPageItemView {
    private(set) var item: InstantPageV2TableItem
    var itemFrame: CGRect { return self.item.frame }

    private let scrollView: UIScrollView
    private let contentView: UIView
    private var titleSubView: InstantPageV2View?
    private var cellSubViews: [InstantPageV2View] = []
    private var stripeLayers: [CALayer] = []
    private var lineLayers: [CALayer] = []

    var subLayoutView: InstantPageV2View? { return nil }

    func forEachSubLayoutView(_ body: (InstantPageV2View) -> Void) {
        if let titleView = self.titleSubView { body(titleView) }
        for cellView in self.cellSubViews { body(cellView) }
    }

    init(item: InstantPageV2TableItem, theme: InstantPageTheme, renderContext: InstantPageV2RenderContext?) {
        self.item = item
        self.scrollView = UIScrollView()
        self.contentView = UIView()
        super.init(frame: item.frame)
        self.backgroundColor = .clear

        self.scrollView.frame = self.bounds
        self.scrollView.contentSize = item.contentSize
        self.scrollView.alwaysBounceHorizontal = false
        self.scrollView.alwaysBounceVertical = false
        self.scrollView.showsHorizontalScrollIndicator = item.contentSize.width > item.frame.width
        self.scrollView.showsVerticalScrollIndicator = false
        self.addSubview(self.scrollView)

        self.contentView.frame = CGRect(origin: .zero, size: item.contentSize)
        self.scrollView.addSubview(self.contentView)

        // Title sub-layout (above the grid, inside the scroll view's content).
        if let titleLayout = item.titleSubLayout, let titleFrame = item.titleFrame {
            let v = InstantPageV2View(renderContext: renderContext)
            v.update(layout: titleLayout, theme: theme, animation: .None)
            v.frame = CGRect(x: v2TableCellInsets.left, y: titleFrame.minY + v2TableCellInsets.top,
                             width: titleLayout.contentSize.width, height: titleLayout.contentSize.height)
            self.contentView.addSubview(v)
            self.titleSubView = v
        }

        // Grid origin: shifted down by title height when present.
        let gridOffsetY = item.titleFrame?.height ?? 0.0

        // Cell backgrounds and sub-layouts.
        for cell in item.cells {
            if let bg = cell.backgroundColor {
                let stripe = CALayer()
                stripe.backgroundColor = bg.cgColor
                stripe.frame = cell.frame.offsetBy(dx: 0.0, dy: gridOffsetY)
                self.contentView.layer.insertSublayer(stripe, at: 0)
                self.stripeLayers.append(stripe)
            }
            if let subLayout = cell.subLayout {
                let v = InstantPageV2View(renderContext: renderContext)
                v.update(layout: subLayout, theme: theme, animation: .None)
                // The sub-layout items are already offset by cell insets inside the cell frame.
                v.frame = cell.frame.offsetBy(dx: 0.0, dy: gridOffsetY)
                self.contentView.addSubview(v)
                self.cellSubViews.append(v)
            }
        }

        // Border lines.
        if item.bordered {
            for r in item.horizontalLines + item.verticalLines {
                let line = CALayer()
                line.backgroundColor = item.borderColor.cgColor
                line.frame = r.offsetBy(dx: 0.0, dy: gridOffsetY)
                self.contentView.layer.addSublayer(line)
                self.lineLayers.append(line)
            }
            // Outer border rect (four edges).
            let outerW = v2TableBorderWidth
            let outerRect = CGRect(
                x: outerW / 2.0,
                y: gridOffsetY + outerW / 2.0,
                width: item.contentSize.width - outerW,
                height: item.contentSize.height - outerW
            )
            let outerEdges: [CGRect] = [
                CGRect(x: outerRect.minX, y: outerRect.minY, width: outerRect.width, height: outerW),
                CGRect(x: outerRect.minX, y: outerRect.maxY - outerW, width: outerRect.width, height: outerW),
                CGRect(x: outerRect.minX, y: outerRect.minY, width: outerW, height: outerRect.height),
                CGRect(x: outerRect.maxX - outerW, y: outerRect.minY, width: outerW, height: outerRect.height)
            ]
            for edge in outerEdges {
                let line = CALayer()
                line.backgroundColor = item.borderColor.cgColor
                line.frame = edge
                self.contentView.layer.addSublayer(line)
                self.lineLayers.append(line)
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(item: InstantPageV2TableItem, theme: InstantPageTheme) {
        self.item = item

        self.scrollView.frame = CGRect(origin: .zero, size: item.frame.size)
        self.scrollView.contentSize = item.contentSize
        self.scrollView.showsHorizontalScrollIndicator = item.contentSize.width > item.frame.width
        self.contentView.frame = CGRect(origin: .zero, size: item.contentSize)

        // Forward updates to nested V2 sub-layouts (title + each cell). Recursive update
        // propagation. Cell-count or title-presence changes fall back to rebuild via the
        // V2View's internal `update(layout:theme:animation:)` (task B refines).
        if let titleLayout = item.titleSubLayout, let titleView = self.titleSubView, let titleFrame = item.titleFrame {
            titleView.update(layout: titleLayout, theme: theme, animation: .None)
            titleView.frame = CGRect(
                x: v2TableCellInsets.left,
                y: titleFrame.minY + v2TableCellInsets.top,
                width: titleLayout.contentSize.width,
                height: titleLayout.contentSize.height
            )
        }

        let gridOffsetY = item.titleFrame?.height ?? 0.0
        var cellLayoutIndex = 0
        for cell in item.cells {
            if let subLayout = cell.subLayout, cellLayoutIndex < self.cellSubViews.count {
                let cellView = self.cellSubViews[cellLayoutIndex]
                cellView.update(layout: subLayout, theme: theme, animation: .None)
                cellView.frame = cell.frame.offsetBy(dx: 0.0, dy: gridOffsetY)
                cellLayoutIndex += 1
            }
        }

        // Stripe layers (cell backgrounds) — update color + frame in original order.
        var stripeIndex = 0
        for cell in item.cells {
            if let bg = cell.backgroundColor, stripeIndex < self.stripeLayers.count {
                let stripe = self.stripeLayers[stripeIndex]
                stripe.backgroundColor = bg.cgColor
                stripe.frame = cell.frame.offsetBy(dx: 0.0, dy: gridOffsetY)
                stripeIndex += 1
            }
        }

        // Line layers (borders) — update color in place; frames recomputed in original order.
        for line in self.lineLayers {
            line.backgroundColor = item.borderColor.cgColor
        }
    }
}

// MARK: - Public helpers on InstantPageV2View

public extension InstantPageV2View {
    func lastTextLineFrame() -> CGRect? {
        guard let layout = self.currentLayout else { return nil }
        return InstantPageUI.lastTextLineFrame(in: layout)
    }

    func textItemAt(point: CGPoint) -> (item: InstantPageTextItem, parentOffset: CGPoint)? {
        guard let layout = self.currentLayout else { return nil }
        return findTextItem(in: layout, point: point, accumulatedOffset: .zero)
    }

    func urlItemAt(point: CGPoint) -> (urlItem: InstantPageUrlItem, item: InstantPageTextItem,
                                       parentOffset: CGPoint, localPoint: CGPoint)? {
        guard let hit = self.textItemAt(point: point) else { return nil }
        let localPoint = CGPoint(x: point.x - hit.parentOffset.x, y: point.y - hit.parentOffset.y)
        guard let url = hit.item.urlAttribute(at: localPoint) else { return nil }
        return (urlItem: url, item: hit.item, parentOffset: hit.parentOffset, localPoint: localPoint)
    }

    func selectableTextItems() -> [(item: InstantPageTextItem, parentOffset: CGPoint)] {
        guard let layout = self.currentLayout else { return [] }
        var result: [(InstantPageTextItem, CGPoint)] = []
        collectSelectableTextItems(in: layout, accumulatedOffset: .zero, into: &result)
        return result.map { (item: $0.0, parentOffset: $0.1) }
    }

    func detailsItem(atIndex index: Int) -> (frame: CGRect, titleFrame: CGRect)? {
        guard let layout = self.currentLayout else { return nil }
        for item in layout.items {
            if case let .details(d) = item, d.index == index {
                return (frame: d.frame, titleFrame: d.titleFrame.offsetBy(dx: d.frame.minX, dy: d.frame.minY))
            }
        }
        return nil
    }
}

// MARK: - Private recursion helpers

private func findTextItem(
    in layout: InstantPageV2Layout,
    point: CGPoint,
    accumulatedOffset: CGPoint
) -> (item: InstantPageTextItem, parentOffset: CGPoint)? {
    for item in layout.items {
        let f = item.frame.offsetBy(dx: accumulatedOffset.x, dy: accumulatedOffset.y)
        if !f.contains(point) { continue }
        switch item {
        case let .text(text):
            return (item: text.textItem, parentOffset: CGPoint(x: f.minX, y: f.minY))
        case let .codeBlock(block):
            let textOrigin = CGPoint(
                x: f.minX + block.textItem.frame.minX,
                y: f.minY + block.textItem.frame.minY
            )
            return (item: block.textItem, parentOffset: textOrigin)
        case let .details(details):
            if details.titleFrame.offsetBy(dx: f.minX, dy: f.minY).contains(point) {
                let titleOrigin = CGPoint(
                    x: f.minX + details.titleTextItem.frame.minX,
                    y: f.minY + details.titleTextItem.frame.minY
                )
                return (item: details.titleTextItem, parentOffset: titleOrigin)
            }
            if let inner = details.innerLayout {
                let innerOffset = CGPoint(x: f.minX, y: f.minY + details.titleFrame.maxY)
                if let hit = findTextItem(in: inner, point: point, accumulatedOffset: innerOffset) {
                    return hit
                }
            }
        case let .table(table):
            for cell in table.cells {
                let cellAbs = cell.frame.offsetBy(dx: f.minX, dy: f.minY)
                if !cellAbs.contains(point) { continue }
                if let sub = cell.subLayout {
                    if let hit = findTextItem(in: sub, point: point,
                                              accumulatedOffset: CGPoint(x: cellAbs.minX, y: cellAbs.minY)) {
                        return hit
                    }
                }
            }
            if let titleLayout = table.titleSubLayout, let titleFrame = table.titleFrame {
                let titleAbs = titleFrame.offsetBy(dx: f.minX, dy: f.minY)
                if titleAbs.contains(point) {
                    if let hit = findTextItem(in: titleLayout, point: point,
                                              accumulatedOffset: CGPoint(x: titleAbs.minX, y: titleAbs.minY)) {
                        return hit
                    }
                }
            }
        default:
            continue
        }
    }
    return nil
}

private func collectSelectableTextItems(
    in layout: InstantPageV2Layout,
    accumulatedOffset: CGPoint,
    into result: inout [(InstantPageTextItem, CGPoint)]
) {
    for item in layout.items {
        switch item {
        case let .text(text):
            if text.textItem.selectable && !text.textItem.attributedString.string.isEmpty {
                result.append((text.textItem, CGPoint(
                    x: accumulatedOffset.x + text.frame.minX,
                    y: accumulatedOffset.y + text.frame.minY
                )))
            }
        case let .codeBlock(block):
            if block.textItem.selectable && !block.textItem.attributedString.string.isEmpty {
                result.append((block.textItem, CGPoint(
                    x: accumulatedOffset.x + block.frame.minX + block.textItem.frame.minX,
                    y: accumulatedOffset.y + block.frame.minY + block.textItem.frame.minY
                )))
            }
        case let .details(details):
            if details.titleTextItem.selectable && !details.titleTextItem.attributedString.string.isEmpty {
                result.append((details.titleTextItem, CGPoint(
                    x: accumulatedOffset.x + details.frame.minX + details.titleTextItem.frame.minX,
                    y: accumulatedOffset.y + details.frame.minY + details.titleTextItem.frame.minY
                )))
            }
            if let inner = details.innerLayout {
                let innerOffset = CGPoint(
                    x: accumulatedOffset.x + details.frame.minX,
                    y: accumulatedOffset.y + details.frame.minY + details.titleFrame.maxY
                )
                collectSelectableTextItems(in: inner, accumulatedOffset: innerOffset, into: &result)
            }
        case let .table(table):
            if let titleLayout = table.titleSubLayout, let titleFrame = table.titleFrame {
                let titleOffset = CGPoint(
                    x: accumulatedOffset.x + table.frame.minX + titleFrame.minX,
                    y: accumulatedOffset.y + table.frame.minY + titleFrame.minY
                )
                collectSelectableTextItems(in: titleLayout, accumulatedOffset: titleOffset, into: &result)
            }
            for cell in table.cells {
                if let sub = cell.subLayout {
                    let cellOffset = CGPoint(
                        x: accumulatedOffset.x + table.frame.minX + cell.frame.minX,
                        y: accumulatedOffset.y + table.frame.minY + cell.frame.minY
                    )
                    collectSelectableTextItems(in: sub, accumulatedOffset: cellOffset, into: &result)
                }
            }
        default:
            continue
        }
    }
}

// MARK: - Formula view

/// Renders both block (`InstantPageBlock.formula(latex:)`) and inline (`InstantPageFormulaAttribute`)
/// math, sourcing the pre-rendered Retina image from `InstantPageMathAttachment.rendered`.
///
/// For block formulas wider than the bubble's available width, the layout sets
/// `isScrollable = true`; this view then wraps the image in a horizontal `UIScrollView`
/// matching V1's `InstantPageScrollableNode` (no bounce on non-overflowing content,
/// scroll indicator hidden — appropriate for content embedded inside a chat bubble).
final class InstantPageV2FormulaView: UIView, InstantPageItemView {
    private(set) var item: InstantPageV2FormulaItem
    var itemFrame: CGRect { return self.item.frame }

    init(item: InstantPageV2FormulaItem) {
        self.item = item
        super.init(frame: item.frame)
        self.backgroundColor = .clear
        self.isOpaque = false
        self.buildContents()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(item: InstantPageV2FormulaItem, theme: InstantPageTheme) {
        let _ = theme
        self.item = item

        // Image content and scroll/non-scroll shape may change with width; rebuild.
        for sub in self.subviews { sub.removeFromSuperview() }
        if let sublayers = self.layer.sublayers {
            for layer in sublayers { layer.removeFromSuperlayer() }
        }
        self.buildContents()
    }

    private func buildContents() {
        let item = self.item
        let imageLayer = CALayer()
        imageLayer.contents = item.attachment.rendered.image.cgImage
        imageLayer.contentsScale = item.attachment.rendered.image.scale
        imageLayer.contentsGravity = .resizeAspect
        imageLayer.frame = item.imageFrame

        if item.isScrollable {
            self.clipsToBounds = true
            self.isUserInteractionEnabled = true
            let scroll = UIScrollView(frame: CGRect(origin: .zero, size: item.frame.size))
            scroll.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            scroll.contentSize = item.scrollContentSize
            scroll.showsHorizontalScrollIndicator = false
            scroll.showsVerticalScrollIndicator = false
            scroll.alwaysBounceHorizontal = false
            scroll.alwaysBounceVertical = false
            scroll.contentInsetAdjustmentBehavior = .never
            self.addSubview(scroll)

            // Layers don't autoresize with their superview; host the image layer inside a UIView
            // so the scroll view's content-size growth keeps the image positioned correctly.
            let imageHost = UIView(frame: CGRect(origin: .zero, size: item.scrollContentSize))
            imageHost.layer.addSublayer(imageLayer)
            scroll.addSubview(imageHost)
        } else {
            // Inline and centered-block formulas don't accept touches; the bubble's link/long-press
            // recognizers run against the underlying text view instead.
            self.isUserInteractionEnabled = false
            self.layer.addSublayer(imageLayer)
        }
    }
}
