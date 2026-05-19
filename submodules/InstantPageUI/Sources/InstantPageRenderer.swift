import Foundation
import UIKit
import Display
import TelegramCore
import TelegramPresentationData

// MARK: - Public renderer

public final class InstantPageV2View: UIView {
    public private(set) var currentLayout: InstantPageV2Layout?
    public private(set) var currentTheme: InstantPageTheme?

    /// Invoked when a details title is tapped. Bubble routes to its expand-state mutation + requestUpdate.
    public var detailsTapped: ((_ index: Int) -> Void)?

    private var itemViews: [InstantPageItemView] = []

    public override init(frame: CGRect) {
        super.init(frame: frame)
        self.backgroundColor = .clear
        self.isOpaque = false
    }

    public convenience init() {
        self.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Rebuilds the child view hierarchy from `layout`. The caller is responsible for
    /// sizing `self.frame` to `layout.contentSize`; this method does not touch its own frame.
    public func update(
        layout: InstantPageV2Layout,
        theme: InstantPageTheme,
        animation: ListViewItemUpdateAnimation
    ) {
        for view in self.itemViews {
            view.removeFromSuperview()
        }
        self.itemViews.removeAll()

        self.currentLayout = layout
        self.currentTheme = theme
        let _ = animation   // reserved for future per-item animation

        for item in layout.items {
            guard let view = self.makeItemView(for: item, theme: theme) else { continue }
            self.addSubview(view)
            self.itemViews.append(view)
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
            let view = InstantPageV2DetailsView(item: details, theme: theme)
            view.onTitleTapped = { [weak self] index in
                self?.detailsTapped?(index)
            }
            return view
        case let .table(table):
            return InstantPageV2TableView(item: table, theme: theme)
        }
    }
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
    let item: InstantPageV2TextItem
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
    let item: InstantPageV2DividerItem
    var itemFrame: CGRect { return self.item.frame }

    init(item: InstantPageV2DividerItem) {
        self.item = item
        super.init(frame: item.frame)
        self.backgroundColor = item.color
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

// MARK: - Anchor view (zero-height; nothing to render)

final class InstantPageV2AnchorView: UIView, InstantPageItemView {
    let item: InstantPageV2AnchorItem
    var itemFrame: CGRect { return self.item.frame }

    init(item: InstantPageV2AnchorItem) {
        self.item = item
        super.init(frame: item.frame)
        self.isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

// MARK: - List marker view

final class InstantPageV2ListMarkerView: UIView, InstantPageItemView {
    let item: InstantPageV2ListMarkerItem
    var itemFrame: CGRect { return self.item.frame }

    init(item: InstantPageV2ListMarkerItem) {
        self.item = item
        super.init(frame: item.frame)
        self.backgroundColor = .clear
        self.isOpaque = false

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
            outer.frame = self.bounds
            self.layer.addSublayer(outer)
            if checked {
                let fill = CALayer()
                fill.backgroundColor = item.color.cgColor
                fill.cornerRadius = 3.0
                fill.frame = self.bounds.insetBy(dx: 2.0, dy: 2.0)
                self.layer.addSublayer(fill)
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

// MARK: - Quote bar view

final class InstantPageV2BlockQuoteBarView: UIView, InstantPageItemView {
    let item: InstantPageV2BarItem
    var itemFrame: CGRect { return self.item.frame }

    init(item: InstantPageV2BarItem) {
        self.item = item
        super.init(frame: item.frame)
        self.backgroundColor = item.color
        self.layer.cornerRadius = item.cornerRadius
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

// MARK: - Shape view (for pullQuote line ornaments)

final class InstantPageV2ShapeView: UIView, InstantPageItemView {
    let item: InstantPageV2ShapeItem
    var itemFrame: CGRect { return self.item.frame }

    init(item: InstantPageV2ShapeItem) {
        self.item = item
        super.init(frame: item.frame)
        switch item.kind {
        case let .roundedRect(cornerRadius):
            self.backgroundColor = item.color
            self.layer.cornerRadius = cornerRadius
        case .line(_):
            self.backgroundColor = item.color
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

// MARK: - Media placeholder view (V0: gray rectangle)

final class InstantPageV2MediaPlaceholderView: UIView, InstantPageItemView {
    let item: InstantPageV2MediaPlaceholderItem
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
}

// MARK: - Details view

final class InstantPageV2DetailsView: UIView, InstantPageItemView {
    let item: InstantPageV2DetailsItem
    var itemFrame: CGRect { return self.item.frame }

    private let titleTextView: InstantPageV2TextView
    private let chevronLayer: CALayer
    private let separator: UIView
    private var bodyView: InstantPageV2View?

    var onTitleTapped: ((Int) -> Void)?

    var subLayoutView: InstantPageV2View? { return self.bodyView }

    init(item: InstantPageV2DetailsItem, theme: InstantPageTheme) {
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
            let body = InstantPageV2View()
            body.update(layout: innerLayout, theme: theme, animation: .None)
            body.frame = CGRect(
                origin: CGPoint(x: 0.0, y: item.titleFrame.maxY),
                size: innerLayout.contentSize
            )
            self.addSubview(body)
            self.bodyView = body
        }

        let tap = UITapGestureRecognizer(target: self, action: #selector(self.titleTapped))
        let titleHitView = UIView(frame: item.titleFrame)
        titleHitView.backgroundColor = .clear
        self.insertSubview(titleHitView, at: 0)
        titleHitView.addGestureRecognizer(tap)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func titleTapped() {
        self.onTitleTapped?(self.item.index)
    }
}

// MARK: - Code block view

final class InstantPageV2CodeBlockView: UIView, InstantPageItemView {
    let item: InstantPageV2CodeBlockItem
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
}

// MARK: - Table view

final class InstantPageV2TableView: UIView, InstantPageItemView {
    let item: InstantPageV2TableItem
    var itemFrame: CGRect { return self.item.frame }

    private let scrollView: UIScrollView
    private let contentView: UIView
    private var titleSubView: InstantPageV2View?
    private var cellSubViews: [InstantPageV2View] = []
    private var stripeLayers: [CALayer] = []
    private var lineLayers: [CALayer] = []

    var subLayoutView: InstantPageV2View? { return nil }

    init(item: InstantPageV2TableItem, theme: InstantPageTheme) {
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
            let v = InstantPageV2View()
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
                let v = InstantPageV2View()
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
