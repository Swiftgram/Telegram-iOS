import Foundation
import UIKit
import AsyncDisplayKit
import Display
import TelegramCore
import Postbox
import SwiftSignalKit
import AccountContext
import ChatMessageBubbleContentNode
import ChatMessageItemCommon
import ChatControllerInteraction
import InstantPageUI
import TelegramUIPreferences
import TextLoadingEffect

public class ChatMessageRichDataBubbleContentNode: ChatMessageBubbleContentNode {
    public final class ContainerNode: ASDisplayNode {
    }
    
    private let containerNode: ContainerNode
    private var currentLayoutTiles: [InstantPageTile] = []
    private var visibleTiles: [Int: InstantPageTileNode] = [:]
    private var visibleItemsWithNodes: [Int: InstantPageNode] = [:]
    private var currentPageLayout: (boundingWidth: CGFloat, layout: InstantPageLayout)?
    private var pageTheme: InstantPageTheme?
    private var distanceThresholdGroupCount: [Int: Int] = [:]
    private var currentLayoutItemsWithNodes: [InstantPageItem] = []
    private var currentExpandedDetails: [Int : Bool]?
    private var linkProgressDisposable: Disposable?
    private var linkProgressRects: [CGRect]?
    private var linkHighlightingNode: LinkHighlightingNode?
    private var linkProgressView: TextLoadingEffectView?
    
    override public var visibility: ListViewItemNodeVisibility {
        didSet {
            if oldValue != self.visibility {
                self.updateVisibility()
            }
        }
    }
    
    required public init() {
        self.containerNode = ContainerNode()
        self.containerNode.clipsToBounds = true
        
        super.init()
        
        self.addSubnode(self.containerNode)
    }

    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        self.linkProgressDisposable?.dispose()
    }
    
    override public func asyncLayoutContent() -> (_ item: ChatMessageBubbleContentItem, _ layoutConstants: ChatMessageItemLayoutConstants, _ preparePosition: ChatMessageBubblePreparePosition, _ messageSelection: Bool?, _ constrainedSize: CGSize, _ avatarInset: CGFloat) -> (ChatMessageBubbleContentProperties, CGSize?, CGFloat, (CGSize, ChatMessageBubbleContentPosition) -> (CGFloat, (CGFloat) -> (CGSize, (ListViewItemUpdateAnimation, Bool, ListViewItemApply?) -> Void))) {
        let previousItem = self.item
        let currentPageLayout = self.currentPageLayout
        let previousCurrentLayoutTiles = self.currentLayoutTiles
        
        return { [weak self] item, layoutConstants, _, _, _, _ in
            let contentProperties = ChatMessageBubbleContentProperties(hidesSimpleAuthorHeader: false, headerSpacing: 0.0, hidesBackground: .never, forceFullCorners: false, forceAlignment: .none)
            
            return (contentProperties, nil, CGFloat.greatestFiniteMagnitude, { constrainedSize, position in
                let suggestedBoundingWidth: CGFloat = constrainedSize.width
                
                return (suggestedBoundingWidth, { boundingWidth in
                    var boundingSize = CGSize(width: boundingWidth, height: 0.0)
                    
                    var pageLayout: InstantPageLayout?
                    var currentLayoutTiles: [InstantPageTile] = []
                    
                    let isDark = item.presentationData.theme.theme.overallDarkAppearance
                    let isIncoming = item.message.effectivelyIncoming(item.context.account.peerId)
                    let messageTheme = isIncoming ? item.presentationData.theme.theme.chat.message.incoming : item.presentationData.theme.theme.chat.message.outgoing
                    
                    var underlineLinks = true
                    if !messageTheme.primaryTextColor.isEqual(messageTheme.linkTextColor) {
                        underlineLinks = false
                    }
                    let _ = underlineLinks
                    
                    let author = item.message.author
                    let mainColor: UIColor
                    var secondaryColor: UIColor? = nil
                    var tertiaryColor: UIColor? = nil
                    
                    let nameColors: PeerNameColors.Colors?
                    switch author?.nameColor {
                    case let .preset(nameColor):
                        nameColors = item.context.peerNameColors.get(nameColor, dark: item.presentationData.theme.theme.overallDarkAppearance)
                    case let .collectible(collectibleColor):
                        nameColors = collectibleColor.peerNameColors(dark: item.presentationData.theme.theme.overallDarkAppearance)
                    default:
                        nameColors = nil
                    }
                    
                    let codeBlockTitleColor: UIColor
                    let codeBlockAccentColor: UIColor
                    let codeBlockBackgroundColor: UIColor
                    if !isIncoming {
                        mainColor = messageTheme.accentTextColor
                        if let _ = nameColors?.secondary {
                            secondaryColor = .clear
                        }
                        if let _ = nameColors?.tertiary {
                            tertiaryColor = .clear
                        }
                        
                        if item.presentationData.theme.theme.overallDarkAppearance {
                            codeBlockTitleColor = .white
                            codeBlockAccentColor = UIColor(white: 1.0, alpha: 0.5)
                            codeBlockBackgroundColor = UIColor(white: 0.0, alpha: 0.25)
                        } else {
                            codeBlockTitleColor = mainColor
                            codeBlockAccentColor = mainColor
                            codeBlockBackgroundColor = mainColor.withMultipliedAlpha(0.1)
                        }
                    } else {
                        let authorNameColor = nameColors?.main
                        secondaryColor = nameColors?.secondary
                        tertiaryColor = nameColors?.tertiary
                        
                        if let authorNameColor {
                            mainColor = authorNameColor
                        } else {
                            mainColor = messageTheme.accentTextColor
                        }
                        
                        codeBlockTitleColor = mainColor
                        codeBlockAccentColor = mainColor
                        
                        if item.presentationData.theme.theme.overallDarkAppearance {
                            codeBlockBackgroundColor = UIColor(white: 0.0, alpha: 0.65)
                        } else {
                            codeBlockBackgroundColor = UIColor(white: 0.0, alpha: 0.05)
                        }
                    }
                    
                    let _ = secondaryColor
                    let _ = tertiaryColor
                    
                    let _ = codeBlockTitleColor
                    let _ = codeBlockAccentColor
                    
                    let textCategories = InstantPageTextCategories(
                        kicker: InstantPageTextAttributes(font: InstantPageFont(style: .sans, size: 15.0, lineSpacingFactor: 0.685), color: messageTheme.primaryTextColor),
                        header: InstantPageTextAttributes(font: InstantPageFont(style: .serif, size: 24.0, lineSpacingFactor: 0.685), color: messageTheme.primaryTextColor),
                        subheader: InstantPageTextAttributes(font: InstantPageFont(style: .serif, size: 19.0, lineSpacingFactor: 0.685), color: messageTheme.primaryTextColor),
                        paragraph: InstantPageTextAttributes(font: InstantPageFont(style: .sans, size: 17.0, lineSpacingFactor: 1.0), color: messageTheme.primaryTextColor),
                        caption: InstantPageTextAttributes(font: InstantPageFont(style: .sans, size: 15.0, lineSpacingFactor: 1.0), color: messageTheme.secondaryTextColor),
                        credit: InstantPageTextAttributes(font: InstantPageFont(style: .sans, size: 13.0, lineSpacingFactor: 1.0), color: messageTheme.secondaryTextColor),
                        table: InstantPageTextAttributes(font: InstantPageFont(style: .sans, size: 15.0, lineSpacingFactor: 1.0), color: messageTheme.primaryTextColor),
                        article: InstantPageTextAttributes(font: InstantPageFont(style: .serif, size: 18.0, lineSpacingFactor: 1.0), color: messageTheme.primaryTextColor)
                    )
                    let pageTheme = InstantPageTheme(
                        type: isDark ? .dark : .light,
                        pageBackgroundColor: .clear,
                        textCategories: textCategories,
                        serif: false,
                        codeBlockBackgroundColor: codeBlockBackgroundColor,
                        linkColor: messageTheme.linkTextColor,
                        textHighlightColor: messageTheme.accentTextColor.withMultipliedAlpha(0.1),
                        linkHighlightColor: messageTheme.linkTextColor.withMultipliedAlpha(0.1),
                        markerColor: UIColor(rgb: 0xfef3bc),
                        panelBackgroundColor: messageTheme.accentControlColor.withMultipliedAlpha(0.1),
                        panelHighlightedBackgroundColor: messageTheme.accentControlColor.withMultipliedAlpha(0.25),
                        panelPrimaryColor: messageTheme.primaryTextColor,
                        panelSecondaryColor: messageTheme.secondaryTextColor,
                        panelAccentColor: messageTheme.accentTextColor,
                        tableBorderColor: isDark || !isIncoming ? messageTheme.accentControlColor.withMultipliedAlpha(0.25) : UIColor(white: 0.0, alpha: 0.1),
                        tableHeaderColor: isDark || !isIncoming ? messageTheme.accentControlColor.withMultipliedAlpha(0.1) : UIColor(white: 0.0, alpha: 0.05),
                        controlColor: messageTheme.accentControlColor,
                        imageTintColor: nil,
                        overlayPanelColor: isDark ? UIColor(white: 0.0, alpha: 0.13) : UIColor(white: 1.0, alpha: 0.13)
                    )
                    
                    if let webpage = item.message.media.first(where: { $0 is TelegramMediaWebpage }) as? TelegramMediaWebpage, case let .Loaded(content) = webpage.content, let instantPage = content.instantPage {
                        if let current = currentPageLayout, current.boundingWidth == boundingSize.width, previousItem?.presentationData.theme.theme === item.presentationData.theme.theme {
                            pageLayout = current.layout
                            currentLayoutTiles = previousCurrentLayoutTiles
                        } else {
                            pageLayout = instantPageLayoutForWebPage(webpage, instantPage: instantPage._parse(), userLocation: .other, boundingWidth: boundingWidth - 2.0, sideInset: 10.0, safeInset: 0.0, strings: item.presentationData.strings, theme: pageTheme, dateTimeFormat: item.presentationData.dateTimeFormat, webEmbedHeights: [:], addFeedback: false)
                            if let pageLayout {
                                currentLayoutTiles = instantPageTilesFromLayout(pageLayout, boundingWidth: boundingWidth)
                            }
                        }
                    }
                    
                    if let pageLayout {
                        boundingSize.height = pageLayout.contentSize.height + 2.0
                    }
                    
                    return (boundingSize, { animation, synchronousLoads, itemApply in
                        guard let self else {
                            return
                        }
                        self.item = item
                        self.pageTheme = pageTheme
                        
                        self.containerNode.frame = CGRect(origin: CGPoint(x: 1.0, y: 1.0), size: CGSize(width: boundingSize.width - 2.0, height: boundingSize.height - 2.0))
                        
                        if let pageLayout {
                            self.currentPageLayout = (boundingSize.width, pageLayout)
                            self.currentLayoutTiles = currentLayoutTiles

                            var currentLayoutItemsWithNodes: [InstantPageItem] = []
                            var distanceThresholdGroupCount: [Int : Int] = [:]

                            for item in pageLayout.items {
                                if item.wantsNode {
                                    currentLayoutItemsWithNodes.append(item)

                                    if let group = item.distanceThresholdGroup() {
                                        let count: Int
                                        if let currentCount = distanceThresholdGroupCount[Int(group)] {
                                            count = currentCount
                                        } else {
                                            count = 0
                                        }
                                        distanceThresholdGroupCount[Int(group)] = count + 1
                                    }
                                }
                            }

                            self.currentLayoutItemsWithNodes = currentLayoutItemsWithNodes
                            self.distanceThresholdGroupCount = distanceThresholdGroupCount
                        } else {
                            self.currentPageLayout = nil
                            self.currentLayoutTiles = []
                            self.currentLayoutItemsWithNodes = []
                            self.distanceThresholdGroupCount = [:]
                        }
                        
                        self.updateVisibility()
                    })
                })
            })
        }
    }
    
    private func effectiveFrameForTile(_ tile: InstantPageTile) -> CGRect {
        let layoutOrigin = tile.frame.origin
        let origin = layoutOrigin
        return CGRect(origin: origin, size: tile.frame.size)
    }
    
    private func updateVisibility() {
        switch self.visibility {
        case .none:
            self.updateVisibleItems(visibleBounds: CGRect(), animated: false)
        case let .visible(_, subRect):
            self.updateVisibleItems(visibleBounds: subRect, animated: false)
        }
    }
    
    private func updateVisibleItems(visibleBounds: CGRect, animated: Bool = false) {
        guard let messageItem = self.item, let pageTheme = self.pageTheme else {
            return
        }
        let sourceLocation = InstantPageSourceLocation(userLocation: .other, peerType: .otherPrivate)
        
        var visibleTileIndices = Set<Int>()
        var visibleItemIndices = Set<Int>()
        
        var topNode: ASDisplayNode?
        let topTileNode = topNode
        if let containerSubnodes = self.containerNode.subnodes {
            for node in containerSubnodes.reversed() {
                if let node = node as? InstantPageTileNode {
                    topNode = node
                    break
                }
            }
        }
        
        var collapseOffset: CGFloat = 0.0
        collapseOffset = 0.0
        let transition: ContainedViewLayoutTransition
        if animated {
            transition = .animated(duration: 0.3, curve: .spring)
        } else {
            transition = .immediate
        }
        
        var itemIndex = -1
        var embedIndex = -1
        var detailsIndex = -1
        
        var previousDetailsNode: InstantPageDetailsNode?
        
        for item in self.currentLayoutItemsWithNodes {
            itemIndex += 1
            if item is InstantPageWebEmbedItem {
                embedIndex += 1
            }
            if let imageItem = item as? InstantPageImageItem, case .webpage = imageItem.media.media {
                embedIndex += 1
            }
            if item is InstantPageDetailsItem {
                detailsIndex += 1
            }
    
            var itemThreshold: CGFloat = 0.0
            if let group = item.distanceThresholdGroup() {
                var count: Int = 0
                if let currentCount = self.distanceThresholdGroupCount[group] {
                    count = currentCount
                }
                itemThreshold = item.distanceThresholdWithGroupCount(count)
            }
            
            let itemFrame = item.frame.offsetBy(dx: 0.0, dy: -collapseOffset)
            var thresholdedItemFrame = itemFrame
            thresholdedItemFrame.origin.y -= itemThreshold
            thresholdedItemFrame.size.height += itemThreshold * 2.0
            
            if visibleBounds.intersects(thresholdedItemFrame) {
                visibleItemIndices.insert(itemIndex)
                
                var itemNode = self.visibleItemsWithNodes[itemIndex]
                if let currentItemNode = itemNode {
                    if !item.matchesNode(currentItemNode) {
                        currentItemNode.removeFromSupernode()
                        self.visibleItemsWithNodes.removeValue(forKey: itemIndex)
                        itemNode = nil
                    }
                }
                
                if itemNode == nil {
                    let itemIndex = itemIndex
                    //let embedIndex = embedIndex
                    //let detailsIndex = detailsIndex
                    if let newNode = item.node(context: messageItem.context, strings: messageItem.presentationData.strings, nameDisplayOrder: messageItem.presentationData.nameDisplayOrder, theme: pageTheme, sourceLocation: sourceLocation, openMedia: { [weak self] media in
                        guard let self, let item = self.item, let mediaId = media.media.id else {
                            return
                        }
                        let _ = item.controllerInteraction.openMessage(item.message, OpenMessageParams(mode: .default, mediaSubject: .instantPageMedia(mediaId)))
                    }, longPressMedia: { _ in
                        // TODO
                    }, activatePinchPreview: { _ in
                        // TODO
                    }, pinchPreviewFinished: { _ in
                        // TODO
                    }, openPeer: { [weak self] peer in
                        guard let self, let item = self.item else {
                            return
                        }
                        item.controllerInteraction.openPeer(peer, .chat(textInputState: nil, subject: nil, peekData: nil), nil, .default)
                    }, openUrl: { [weak self] urlItem in
                        guard let self, let item = self.item else {
                            return
                        }
                        let split = self.splitAnchor(urlItem.url)
                        if let webpage = self.currentLoadedWebpage(), webpage.url == split.base, let anchor = split.anchor {
                            self.scrollToAnchor(anchor)
                            return
                        }
                        item.controllerInteraction.openUrl(ChatControllerInteraction.OpenUrl(
                            url: urlItem.url,
                            concealed: false,
                            message: item.message,
                            allowInlineWebpageResolution: urlItem.webpageId != nil
                        ))
                    }, updateWebEmbedHeight: { _ in
                        // TODO
                    }, updateDetailsExpanded: { _ in
                        // TODO
                    }, currentExpandedDetails: self.currentExpandedDetails, getPreloadedResource: { _ in return nil }) {
                        newNode.frame = itemFrame
                        newNode.updateLayout(size: itemFrame.size, transition: transition)
                        if let topNode = topNode {
                            self.containerNode.insertSubnode(newNode, aboveSubnode: topNode)
                        } else {
                            self.containerNode.insertSubnode(newNode, at: 0)
                        }
                        topNode = newNode
                        self.visibleItemsWithNodes[itemIndex] = newNode
                        itemNode = newNode
                        
                        if let itemNode = itemNode as? InstantPageDetailsNode {
                            itemNode.requestLayoutUpdate = { [weak self] animated in
                                let _ = self
                                /*if let strongSelf = self {
                                    strongSelf.updateVisibleItems(visibleBounds: strongSelf.scrollNode.view.bounds, animated: animated)
                                }*/
                            }
                            
                            if let previousDetailsNode = previousDetailsNode {
                                if itemNode.frame.minY - previousDetailsNode.frame.maxY < 1.0 {
                                    itemNode.previousNode = previousDetailsNode
                                }
                            }
                            previousDetailsNode = itemNode
                        }
                    }
                } else {
                    if let itemNode = itemNode, itemNode.frame != itemFrame {
                        transition.updateFrame(node: itemNode, frame: itemFrame)
                        itemNode.updateLayout(size: itemFrame.size, transition: transition)
                    }
                }
                
                if let itemNode = itemNode as? InstantPageDetailsNode {
                    itemNode.updateVisibleItems(visibleBounds: visibleBounds.offsetBy(dx: -itemNode.frame.minX, dy: -itemNode.frame.minY), animated: animated)
                }
            }
        }
        
        topNode = topTileNode
        
        var tileIndex = -1
        for tile in self.currentLayoutTiles {
            tileIndex += 1
            
            let tileFrame = effectiveFrameForTile(tile)
            var tileVisibleFrame = tileFrame
            tileVisibleFrame.origin.y -= 400.0
            tileVisibleFrame.size.height += 400.0 * 2.0
            if tileVisibleFrame.intersects(visibleBounds) {
                visibleTileIndices.insert(tileIndex)
                
                if self.visibleTiles[tileIndex] == nil {
                    let tileNode = InstantPageTileNode(tile: tile, backgroundColor: .clear)
                    tileNode.frame = tileFrame
                    if let topNode = topNode {
                        self.containerNode.insertSubnode(tileNode, aboveSubnode: topNode)
                    } else {
                        self.containerNode.insertSubnode(tileNode, at: 0)
                    }
                    topNode = tileNode
                    self.visibleTiles[tileIndex] = tileNode
                } else {
                    if let tileNode = self.visibleTiles[tileIndex] {
                        tileNode.update(tile: tile, backgroundColor: .clear)
                        if tileNode.frame != tileFrame {
                            transition.updateFrame(node: tileNode, frame: tileFrame)
                        }
                    }
                }
            }
        }
        
        var removeTileIndices: [Int] = []
        for (index, tileNode) in self.visibleTiles {
            if !visibleTileIndices.contains(index) {
                removeTileIndices.append(index)
                tileNode.removeFromSupernode()
            }
        }
        for index in removeTileIndices {
            self.visibleTiles.removeValue(forKey: index)
        }
        
        var removeItemIndices: [Int] = []
        for (index, itemNode) in self.visibleItemsWithNodes {
            if !visibleItemIndices.contains(index) {
                removeItemIndices.append(index)
                itemNode.removeFromSupernode()
            } else {
                var itemFrame = itemNode.frame
                let itemThreshold: CGFloat = 200.0
                itemFrame.origin.y -= itemThreshold
                itemFrame.size.height += itemThreshold * 2.0
                itemNode.updateIsVisible(visibleBounds.intersects(itemFrame))
            }
        }
        for index in removeItemIndices {
            self.visibleItemsWithNodes.removeValue(forKey: index)
        }
    }
    
    override public func animateInsertion(_ currentTimestamp: Double, duration: Double) {
        /*self.textNode.textNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
        if let statusNode = self.statusNode, statusNode.alpha != 0.0 {
            statusNode.layer.animateAlpha(from: 0.0, to: statusNode.alpha, duration: 0.2)
        }*/
    }
    
    override public func animateAdded(_ currentTimestamp: Double, duration: Double) {
        /*self.textNode.textNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
        if let statusNode = self.statusNode, statusNode.alpha != 0.0 {
            statusNode.layer.animateAlpha(from: 0.0, to: statusNode.alpha, duration: 0.2)
        }*/
    }
    
    override public func animateRemoved(_ currentTimestamp: Double, duration: Double) {
        /*self.textNode.textNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false)
        if let statusNode = self.statusNode, statusNode.alpha != 0.0 {
            statusNode.layer.animateAlpha(from: statusNode.alpha, to: 0.0, duration: 0.2, removeOnCompletion: false)
        }*/
    }
    
    override public func tapActionAtPoint(_ point: CGPoint, gesture: TapLongTapOrDoubleTapGesture, isEstimating: Bool) -> ChatMessageBubbleContentTapAction {
        if case .tap = gesture {
        } else {
            if let item = self.item, let subject = item.associatedData.subject, case .messageOptions = subject {
                return ChatMessageBubbleContentTapAction(content: .none)
            }
        }

        guard let urlHit = self.urlForTapLocation(point) else {
            return ChatMessageBubbleContentTapAction(content: .none)
        }

        let split = self.splitAnchor(urlHit.urlItem.url)
        if let webpage = self.currentLoadedWebpage(), webpage.url == split.base, let anchor = split.anchor {
            return ChatMessageBubbleContentTapAction(content: .custom({ [weak self] in
                self?.scrollToAnchor(anchor)
            }))
        }

        // Default to concealed=true: InstantPageTextItem does not expose a clean
        // "attribute substring with displayed range" API, so we cannot compare
        // displayed text to the resolved URL the way the chat text bubble does.
        // The chat URL handler will show a confirmation when concealed is true
        // and the visible text differs from the destination — safer default.
        let concealed = true
        let url = ChatMessageBubbleContentTapAction.Url(url: urlHit.urlItem.url, concealed: concealed, allowInlineWebpageResolution: urlHit.urlItem.webpageId != nil)
        let rects = self.computeHighlightRects(item: urlHit.item, parentOffset: urlHit.parentOffset, localPoint: urlHit.localPoint)
        
        if let webpageId = urlHit.urlItem.webpageId {
            let split = self.splitAnchor(url.url)
            return ChatMessageBubbleContentTapAction(
                content: .externalInstantPage(url: url, webpageId: webpageId, anchor: split.anchor),
                rects: rects,
                activate: self.makeActivate(item: urlHit.item, parentOffset: urlHit.parentOffset, localPoint: urlHit.localPoint)
            )
        } else {
            return ChatMessageBubbleContentTapAction(
                content: .url(url),
                rects: rects,
                activate: self.makeActivate(item: urlHit.item, parentOffset: urlHit.parentOffset, localPoint: urlHit.localPoint)
            )
        }
    }

    private func textItemAtLocation(_ location: CGPoint) -> (item: InstantPageTextItem, parentOffset: CGPoint)? {
        guard let layout = self.currentPageLayout?.layout else {
            return nil
        }
        // Translate from bubble-content-node coords to container-/layout-local coords.
        let layoutLocation = location.offsetBy(dx: -1.0, dy: -1.0)
        for item in layout.items {
            let itemFrame = item.frame
            if itemFrame.contains(layoutLocation) {
                if let item = item as? InstantPageTextItem, item.selectable {
                    return (item, CGPoint(x: itemFrame.minX - item.frame.minX, y: itemFrame.minY - item.frame.minY))
                } else if let item = item as? InstantPageScrollableItem {
                    let contentOffset = CGPoint.zero
                    if let (textItem, parentOffset) = item.textItemAtLocation(layoutLocation.offsetBy(dx: -itemFrame.minX + contentOffset.x, dy: -itemFrame.minY)) {
                        return (textItem, itemFrame.origin.offsetBy(dx: parentOffset.x - contentOffset.x, dy: parentOffset.y))
                    }
                } else if let item = item as? InstantPageDetailsItem {
                    for (_, itemNode) in self.visibleItemsWithNodes {
                        if let itemNode = itemNode as? InstantPageDetailsNode, itemNode.item === item {
                            if let (textItem, parentOffset) = itemNode.textItemAtLocation(layoutLocation.offsetBy(dx: -itemFrame.minX, dy: -itemFrame.minY)) {
                                return (textItem, itemFrame.origin.offsetBy(dx: parentOffset.x, dy: parentOffset.y))
                            }
                        }
                    }
                }
            }
        }
        return nil
    }

    private func urlForTapLocation(_ point: CGPoint) -> (item: InstantPageTextItem, urlItem: InstantPageUrlItem, parentOffset: CGPoint, localPoint: CGPoint)? {
        guard let (item, parentOffset) = self.textItemAtLocation(point) else {
            return nil
        }
        // Translate bubble-content-node point → text-item-local point.
        // (bubble-coords → layout-coords) is `- (1, 1)`; (layout → item-local) is `- item.frame.origin - parentOffset`.
        let layoutPoint = point.offsetBy(dx: -1.0, dy: -1.0)
        let localPoint = layoutPoint.offsetBy(dx: -item.frame.minX - parentOffset.x, dy: -item.frame.minY - parentOffset.y)
        guard let urlItem = item.urlAttribute(at: localPoint) else {
            return nil
        }
        return (item, urlItem, parentOffset, localPoint)
    }

    private func computeHighlightRects(item: InstantPageTextItem, parentOffset: CGPoint, localPoint: CGPoint) -> [CGRect] {
        // Text item returns rects in its local coords; translate back into containerNode-local coords.
        // containerNode is offset by (1, 1) from the bubble-content-node, but the highlight overlay lives
        // *inside* containerNode, so we use layout-coords (= containerNode-local) for the rects.
        let originX = item.frame.minX + parentOffset.x
        let originY = item.frame.minY + parentOffset.y
        return item.linkSelectionRects(at: localPoint).map { rect in
            rect.offsetBy(dx: originX, dy: originY)
        }
    }

    private func makeActivate(item: InstantPageTextItem, parentOffset: CGPoint, localPoint: CGPoint) -> (() -> Promise<Bool>?)? {
        return { [weak self, weak item] in
            guard let self else {
                return nil
            }
            let promise = Promise<Bool>()
            self.linkProgressDisposable?.dispose()
            if self.linkProgressRects != nil {
                self.linkProgressRects = nil
                self.updateLinkProgressState()
            }
            self.linkProgressDisposable = (promise.get() |> deliverOnMainQueue).startStrict(next: { [weak self] value in
                guard let self else {
                    return
                }
                let updated: [CGRect]?
                if value, let item {
                    updated = self.computeHighlightRects(item: item, parentOffset: parentOffset, localPoint: localPoint)
                } else {
                    updated = nil
                }
                let changed: Bool
                if let lhs = self.linkProgressRects, let rhs = updated {
                    changed = lhs != rhs
                } else {
                    changed = (self.linkProgressRects == nil) != (updated == nil)
                }
                if changed {
                    self.linkProgressRects = updated
                    self.updateLinkProgressState()
                }
            })
            return promise
        }
    }

    private func updateLinkProgressState() {
        guard let messageItem = self.item else {
            return
        }
        if let rects = self.linkProgressRects, !rects.isEmpty {
            let linkProgressView: TextLoadingEffectView
            if let current = self.linkProgressView {
                linkProgressView = current
            } else {
                linkProgressView = TextLoadingEffectView(frame: CGRect())
                self.linkProgressView = linkProgressView
                self.containerNode.view.addSubview(linkProgressView)
            }
            linkProgressView.frame = self.containerNode.bounds

            let progressColor: UIColor = messageItem.message.effectivelyIncoming(messageItem.context.account.peerId)
                ? messageItem.presentationData.theme.theme.chat.message.incoming.linkHighlightColor
                : messageItem.presentationData.theme.theme.chat.message.outgoing.linkHighlightColor

            linkProgressView.update(color: progressColor, size: self.containerNode.bounds.size, rects: rects)
        } else if let linkProgressView = self.linkProgressView {
            self.linkProgressView = nil
            linkProgressView.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false, completion: { [weak linkProgressView] _ in
                linkProgressView?.removeFromSuperview()
            })
        }
    }

    override public func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        return super.hitTest(point, with: event)
    }
    
    override public func updateTouchesAtPoint(_ point: CGPoint?) {
        guard let messageItem = self.item else {
            return
        }

        var rects: [CGRect]?
        if let point, let urlHit = self.urlForTapLocation(point) {
            rects = self.computeHighlightRects(item: urlHit.item, parentOffset: urlHit.parentOffset, localPoint: urlHit.localPoint)
        }

        if let rects, !rects.isEmpty {
            let highlightingNode: LinkHighlightingNode
            if let current = self.linkHighlightingNode {
                highlightingNode = current
            } else {
                let color: UIColor = messageItem.message.effectivelyIncoming(messageItem.context.account.peerId)
                    ? messageItem.presentationData.theme.theme.chat.message.incoming.linkHighlightColor
                    : messageItem.presentationData.theme.theme.chat.message.outgoing.linkHighlightColor
                highlightingNode = LinkHighlightingNode(color: color)
                self.linkHighlightingNode = highlightingNode
                self.containerNode.insertSubnode(highlightingNode, at: 0)
            }
            highlightingNode.frame = self.containerNode.bounds
            highlightingNode.updateRects(rects)
        } else if let highlightingNode = self.linkHighlightingNode {
            self.linkHighlightingNode = nil
            highlightingNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.18, removeOnCompletion: false, completion: { [weak highlightingNode] _ in
                highlightingNode?.removeFromSupernode()
            })
        }
    }
    
    override public func updateSearchTextHighlightState(text: String?, messages: [MessageIndex]?) {
    }
    
    override public func willUpdateIsExtractedToContextPreview(_ value: Bool) {
    }
    
    override public func updateIsExtractedToContextPreview(_ value: Bool) {
    }

    override public func transitionNode(messageId: MessageId, media: Media, adjustRect: Bool) -> (ASDisplayNode, CGRect, () -> (UIView?, UIView?))? {
        guard let item = self.item, item.message.id == messageId else {
            return nil
        }
        guard let mediaId = media.id, let layout = self.currentPageLayout?.layout else {
            return nil
        }
        guard let match = self.findInstantPageMedia(in: layout.items, mediaId: mediaId) else {
            return nil
        }
        for (_, itemNode) in self.visibleItemsWithNodes {
            if let transition = itemNode.transitionNode(media: match) {
                return transition
            }
        }
        return nil
    }

    override public func updateHiddenMedia(_ media: [Media]?) -> Bool {
        var hiddenMedia: InstantPageMedia?
        if let media, !media.isEmpty, let layout = self.currentPageLayout?.layout {
            for raw in media {
                if let id = raw.id, let match = self.findInstantPageMedia(in: layout.items, mediaId: id) {
                    hiddenMedia = match
                    break
                }
            }
        }
        for (_, itemNode) in self.visibleItemsWithNodes {
            itemNode.updateHiddenMedia(media: hiddenMedia)
        }
        return hiddenMedia != nil
    }

    private func findInstantPageMedia(in items: [InstantPageItem], mediaId: MediaId) -> InstantPageMedia? {
        for item in items {
            if let detailsItem = item as? InstantPageDetailsItem {
                if let found = self.findInstantPageMedia(in: detailsItem.items, mediaId: mediaId) {
                    return found
                }
            }
            for itemMedia in item.medias {
                if itemMedia.media.id == mediaId {
                    return itemMedia
                }
            }
        }
        return nil
    }

    override public func getAnchorRect(anchor: String) -> CGRect? {
        guard let layout = self.currentPageLayout?.layout else {
            return nil
        }
        if let rect = self.anchorRect(in: layout.items, anchor: anchor, baseY: 0.0) {
            // Translate from layout/containerNode coords to bubble-content-node coords.
            // containerNode is offset by (1, 1) from the bubble content node.
            return rect.offsetBy(dx: 1.0, dy: 1.0)
        }
        return nil
    }

    private func anchorRect(in items: [InstantPageItem], anchor: String, baseY: CGFloat) -> CGRect? {
        for item in items {
            if let item = item as? InstantPageAnchorItem, item.anchor == anchor {
                return CGRect(x: item.frame.minX, y: baseY + item.frame.minY, width: 1.0, height: 1.0)
            } else if let item = item as? InstantPageTextItem {
                if let (lineIndex, _) = item.anchors[anchor] {
                    let lineFrame = item.lines[lineIndex].frame
                    return CGRect(x: item.frame.minX + lineFrame.minX, y: baseY + item.frame.minY + lineFrame.minY, width: lineFrame.width, height: lineFrame.height)
                }
            } else if let item = item as? InstantPageTableItem {
                if let (offset, _) = item.anchors[anchor] {
                    return CGRect(x: item.frame.minX, y: baseY + item.frame.minY + offset, width: item.frame.width, height: 1.0)
                }
            } else if let item = item as? InstantPageDetailsItem {
                // Inner items are laid out below the title bar, so the recursive base
                // must include titleHeight (mirrors InstantPageDetailsNode.linkSelectionRects).
                if let rect = self.anchorRect(in: item.items, anchor: anchor, baseY: baseY + item.frame.minY + item.titleHeight) {
                    return rect
                }
            }
        }
        return nil
    }

    override public func reactionTargetView(value: MessageReaction.Reaction) -> UIView? {
        /*if let statusNode = self.statusNode, !statusNode.isHidden {
            return statusNode.reactionView(value: value)
        }*/
        return nil
    }
    
    override public func messageEffectTargetView() -> UIView? {
        /*if let statusNode = self.statusNode, !statusNode.isHidden {
            return statusNode.messageEffectTargetView()
        }*/
        return nil
    }
    
    override public func getStatusNode() -> ASDisplayNode? {
        return nil
        //return self.statusNode
    }

    private func splitAnchor(_ url: String) -> (base: String, anchor: String?) {
        if let anchorRange = url.range(of: "#") {
            let anchor = String(url[anchorRange.upperBound...]).removingPercentEncoding
            let base = String(url[..<anchorRange.lowerBound])
            return (base, anchor)
        }
        return (url, nil)
    }

    private func currentLoadedWebpage() -> TelegramMediaWebpageLoadedContent? {
        guard let item = self.item else {
            return nil
        }
        guard let webpage = item.message.media.first(where: { $0 is TelegramMediaWebpage }) as? TelegramMediaWebpage else {
            return nil
        }
        if case let .Loaded(content) = webpage.content {
            return content
        }
        return nil
    }

    private func scrollToAnchor(_ anchor: String) {
        guard let item = self.item else {
            return
        }
        if anchor.isEmpty {
            item.controllerInteraction.scrollToMessageId(item.message.index, 0.0)
        } else {
            item.controllerInteraction.scrollToMessageIdWithAnchor(item.message.index, anchor)
        }
    }
}
