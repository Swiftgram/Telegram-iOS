import Foundation
import UIKit
import AsyncDisplayKit
import Display
import TelegramCore
import SwiftSignalKit
import AccountContext
import ChatMessageBubbleContentNode
import ChatMessageDateAndStatusNode
import ChatMessageItemCommon
import ChatControllerInteraction
import InstantPageUI
import TextFormat
import TelegramUIPreferences
import TextLoadingEffect
import TextSelectionNode
import StreamingTextReveal

public class ChatMessageRichDataBubbleContentNode: ChatMessageBubbleContentNode {
    public final class ContainerNode: ASDisplayNode {
    }
    
    private let containerNode: ContainerNode
    public var statusNode: ChatMessageDateAndStatusNode?
    // `init()` may run off the main thread; UIView construction must happen on the main thread.
    // The page view is built lazily inside the apply closure (always main-thread) via ensurePageView().
    private var pageView: InstantPageV2View?
    // Tracks the message (id + stableVersion) baked into the current pageView's render context.
    // The synthesized webpage uses a sentinel id (namespace 0, id 0) shared across all richText
    // messages, so we key cache invalidation on the message itself. When the bubble is recycled
    // with a different message we must discard pageView (render context is constructor-fixed).
    private var pageViewMessageKey: (id: EngineMessage.Id, stableVersion: UInt32)?
    // messageStableVersion is in the cache key because the synthesized instantPage content
    // mutates between streamed AI message chunks (each chunk bumps stableVersion); without
    // this, the cached layout would shadow newly-arrived content during streaming.
    private var currentPageLayout: (boundingWidth: CGFloat,
                                    presentationThemeIdentity: ObjectIdentifier,
                                    expandedDetails: [Int: Bool],
                                    messageStableVersion: UInt32,
                                    layout: InstantPageV2Layout)?
    private var currentExpandedDetails: [Int: Bool] = [:]
    private var linkProgressDisposable: Disposable?
    private var linkProgressRects: [CGRect]?
    private var linkHighlightingNode: LinkHighlightingNode?
    private var linkProgressView: TextLoadingEffectView?
    private var textSelectionAdapter: InstantPageMultiTextAdapter?
    private var textSelectionNode: TextSelectionNode?

    private var textRevealController: TextRevealController?
    private var textRevealLink: SharedDisplayLinkDriver.Link?
    private var currentRevealCostMap: InstantPageV2RevealCostMap?
    // Cursor value pushed into pageView.applyReveal on the prior tick. The display-link tick
    // compares the revealed prefix's height at this cursor vs the new cursor to decide when
    // to request a full bubble re-layout (so the bubble grows with the reveal).
    private var lastAppliedRevealedCount: Int = 0
    private var displayContentsUnderSpoilers: Bool = false

    override public var visibility: ListViewItemNodeVisibility {
        didSet {
            if oldValue != self.visibility {
                self.updatePageViewVisibilityRect()
            }
        }
    }

    // Pushes the current `visibility` sub-rect into `pageView.visibilityRect`, translated into the
    // page view's coordinate space (the page view sits at the top of the bubble; no header offset).
    // Re-invoked from the apply closure after `pageView.frame` is set, because the pageView's
    // y-origin and size can change across streamed chunks (content growth) without a `visibility`
    // change, which would otherwise leave the animation-gating rect stale.
    private func updatePageViewVisibilityRect() {
        guard let pageView = self.pageView else {
            return
        }
        switch self.visibility {
        case .none:
            pageView.visibilityRect = nil
        case let .visible(_, subRect):
            var rect = subRect
            rect.origin.x = 0.0
            rect.size.width = 10000.0
            rect.origin.y -= pageView.frame.minY
            pageView.visibilityRect = rect
        }
    }

    required public init() {
        self.containerNode = ContainerNode()
        self.containerNode.clipsToBounds = true

        super.init()

        self.addSubnode(self.containerNode)
    }

    /// Builds (or reuses) the V2View. Same-message stableVersion bumps (streamed AI chunks) reuse
    /// the existing view, updating only the webpage content in place. The view is rebuilt only when
    /// the bubble is recycled with a different message/webpage (different message id).
    private func ensurePageView(item: ChatMessageBubbleContentItem, webpage: TelegramMediaWebpage) -> InstantPageV2View {
        let key = (id: item.message.id, stableVersion: item.message.stableVersion)
        if let existing = self.pageView, let current = self.pageViewMessageKey, current.id == key.id {
            if current.stableVersion == key.stableVersion {
                return existing
            }
            // Same message, new chunk: reuse the view. Update only the content-bearing webpage on
            // the existing render context; the subsequent pageView.update(layout:) call diffs item
            // views by stable id (content blocks keep their ids, so their views and in-flight
            // reveal state persist; only added/removed blocks change). This replaces the old
            // wholesale rebuild and eliminates the per-chunk full-text-then-mask flash.
            existing.renderContext?.updateContent(webpage: webpage)
            self.pageViewMessageKey = key
            return existing
        }
        self.pageView?.removeFromSuperview()
        self.pageView = nil

        // Capture only the MessageReference (value type) — the closures are retained on the
        // render context which is owned by the V2View, so we must avoid making them retain
        // the bubble (`self`) or the message indirectly via `item`.
        let messageReference = MessageReference(item.message)
        let renderContext = InstantPageV2RenderContext(
            context: item.context,
            webpage: webpage,
            sourceLocation: InstantPageSourceLocation(userLocation: .other, peerType: .channel),
            imageReference: { image in
                return ImageMediaReference.message(message: messageReference, media: image)
            },
            fileReference: { file in
                return FileMediaReference.message(message: messageReference, media: file)
            },
            present: { [weak self] controller, args in
                self?.item?.controllerInteraction.presentController(controller, args)
            },
            push: { [weak self] controller in
                self?.item?.controllerInteraction.navigationController()?.pushViewController(controller)
            },
            openUrl: { [weak self] urlItem in
                self?.openInstantPageUrl(urlItem)
            },
            baseNavigationController: { [weak self] in
                self?.item?.controllerInteraction.navigationController()
            }
        )
        let view = InstantPageV2View(renderContext: renderContext)
        self.pageView = view
        self.pageViewMessageKey = key
        self.containerNode.view.addSubview(view)
        view.detailsTapped = { [weak self] index in
            guard let self else { return }
            let current = self.currentExpandedDetails[index] ?? self.defaultExpanded(forDetailsIndex: index)
            self.currentExpandedDetails[index] = !current
            if let item = self.item {
                item.controllerInteraction.requestMessageUpdate(item.message.id, false, nil)
            }
        }
        return view
    }

    private func defaultExpanded(forDetailsIndex index: Int) -> Bool {
        guard let layout = self.currentPageLayout?.layout else { return false }
        for item in layout.items {
            if case let .details(d) = item, d.index == index {
                return d.defaultExpanded
            }
        }
        return false
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
        let currentExpandedDetails = self.currentExpandedDetails
        let statusLayout = ChatMessageDateAndStatusNode.asyncLayout(self.statusNode)
        // Captured at main-thread, top of asyncLayoutContent. Mirrors TextBubble's
        // `currentMaxGlyphCount` (TextBubble:313). The bubble's bounding size is sized
        // to this revealed prefix during streaming, so it grows with the reveal rather
        // than being final-sized from the first chunk.
        let currentMaxGlyphCount: Int? = self.textRevealController?.currentGlyphCount

        return { [weak self] item, layoutConstants, _, _, _, _ in
            let contentProperties = ChatMessageBubbleContentProperties(hidesSimpleAuthorHeader: false, headerSpacing: 0.0, hidesBackground: .never, forceFullCorners: false, forceAlignment: .none)

            return (contentProperties, nil, CGFloat.greatestFiniteMagnitude, { constrainedSize, position in
                let suggestedBoundingWidth: CGFloat = constrainedSize.width

                var boundingSize = CGSize(width: suggestedBoundingWidth, height: 0.0)

                var pageLayout: InstantPageV2Layout?
                // Built alongside pageLayout so the apply closure can hand it to ensurePageView.
                var pageWebpage: TelegramMediaWebpage?

                // Horizontal text inset baked into the InstantPage layout. The pageView sits at
                // self-x 0 (containerNode at 1, pageView at -1 inside it), so the page's text
                // left edge in the status node's coordinate space is exactly this value. Used as
                // the status node's left edge + side inset, mirroring TextBubble's bubbleInsets.
                let pageHorizontalInset: CGFloat = 11.0

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
                
                let codeBlockBackgroundColor: UIColor
                let codeBlockTitleColor: UIColor
                let codeBlockAccentColor: UIColor
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
                    } else {
                        codeBlockTitleColor = mainColor
                        codeBlockAccentColor = mainColor
                    }
                    
                    codeBlockBackgroundColor = mainColor.withMultipliedAlpha(0.1)
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
                    
                    codeBlockBackgroundColor = mainColor.withMultipliedAlpha(0.1)
                }
                
                let _ = secondaryColor
                let _ = tertiaryColor
                
                let _ = codeBlockTitleColor
                let _ = codeBlockAccentColor
                
                let textCategories = InstantPageTextCategories(
                    kicker: InstantPageTextAttributes(font: InstantPageFont(style: .sans, size: 15.0, lineSpacingFactor: 0.685), color: messageTheme.primaryTextColor),
                    header: InstantPageTextAttributes(font: InstantPageFont(style: .serif, size: 19.0, lineSpacingFactor: 0.685), color: messageTheme.primaryTextColor),
                    subheader: InstantPageTextAttributes(font: InstantPageFont(style: .serif, size: 18.0, lineSpacingFactor: 0.685), color: messageTheme.primaryTextColor),
                    paragraph: InstantPageTextAttributes(font: InstantPageFont(style: .sans, size: 17.0, lineSpacingFactor: 1.0), color: messageTheme.primaryTextColor),
                    caption: InstantPageTextAttributes(font: InstantPageFont(style: .sans, size: 15.0, lineSpacingFactor: 1.0), color: messageTheme.secondaryTextColor),
                    credit: InstantPageTextAttributes(font: InstantPageFont(style: .sans, size: 13.0, lineSpacingFactor: 1.0), color: messageTheme.secondaryTextColor),
                    table: InstantPageTextAttributes(font: InstantPageFont(style: .sans, size: 15.0, lineSpacingFactor: 1.0), color: messageTheme.primaryTextColor),
                    article: InstantPageTextAttributes(font: InstantPageFont(style: .serif, size: 18.0, lineSpacingFactor: 1.0), color: messageTheme.primaryTextColor),
                    codeBlock: InstantPageTextAttributes(font: InstantPageFont(style: .monospace, size: 14.0, lineSpacingFactor: 1.0), color: messageTheme.primaryTextColor),
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
                    overlayPanelColor: isDark ? UIColor(white: 0.0, alpha: 0.13) : UIColor(white: 1.0, alpha: 0.13),
                    separatorColor: isIncoming ? UIColor(white: 0.0, alpha: 0.25): messageTheme.accentControlColor.withMultipliedAlpha(0.25),
                    secondaryControlColor: messageTheme.secondaryTextColor.mixedWith(mainColor.withMultipliedAlpha(0.2), alpha: 0.3)
                )
                
                var hasDraft = false
                if item.message.attributes.contains(where: { $0 is TypingDraftMessageAttribute }) {
                    hasDraft = true
                }
                var hadDraft = false
                if let previousItem, previousItem.message.attributes.contains(where: { $0 is TypingDraftMessageAttribute }) {
                    hadDraft = true
                }

                if let attribute = item.message.richText {
                    #if DEBUG && false
                    let instantPage = InstantPage(blocks: [.thinking(.concat([
                        .textCustomEmoji(fileId: 5384559872899555845, alt: "a"),
                        .plain("Thinking...")
                    ]))], media: [:], isComplete: true, rtl: false, url: "", views: nil)
                    #else
                    let instantPage = attribute.instantPage
                    #endif
                    
                    let webpage = TelegramMediaWebpage(webpageId: EngineMedia.Id(namespace: 0, id: 0), content: .Loaded(TelegramMediaWebpageLoadedContent(
                        url: "",
                        displayUrl: "",
                        hash: 0,
                        type: nil,
                        websiteName: nil,
                        title: nil,
                        text: nil,
                        embedUrl: nil,
                        embedType: nil,
                        embedSize: nil,
                        duration: nil,
                        author: nil,
                        isMediaLargeByDefault: nil,
                        imageIsVideoCover: false,
                        image: nil,
                        file: nil,
                        story: nil,
                        attributes: [],
                        instantPage: instantPage
                    )))
                    pageWebpage = webpage

                    let presentationThemeIdentity = ObjectIdentifier(item.presentationData.theme.theme)
                    let currentMessageStableVersion = item.message.stableVersion
                    if let current = currentPageLayout,
                       current.boundingWidth == suggestedBoundingWidth,
                       current.presentationThemeIdentity == presentationThemeIdentity,
                       current.expandedDetails == currentExpandedDetails,
                       current.messageStableVersion == currentMessageStableVersion {
                        pageLayout = current.layout
                    } else {
                        #if DEBUG && false
                        let instantPage = InstantPage(blocks: [.thinking(.concat([
                            .textCustomEmoji(fileId: 5384559872899555845, alt: "a"),
                            .plain("Thinking...")
                        ]))], media: [:], isComplete: true, rtl: false, url: "", views: nil)
                        #else
                        let instantPage = attribute.instantPage
                        #endif
                        pageLayout = layoutInstantPageV2(
                            webpage: webpage,
                            instantPage: instantPage,
                            userLocation: .other,
                            boundingWidth: suggestedBoundingWidth - 2.0,
                            horizontalInset: pageHorizontalInset,
                            theme: pageTheme,
                            strings: item.presentationData.strings,
                            dateTimeFormat: item.presentationData.dateTimeFormat,
                            cachedMessageSyntaxHighlight: nil,
                            expandedDetails: currentExpandedDetails,
                            fitToWidth: true,
                            computeRevealCharacterRects: hasDraft || hadDraft
                        )
                    }
                }
                
                // Cost map computed here (not in apply) so we can size the bubble to the
                // revealed prefix this layout pass. Mirrors TextBubble's clippedGlyphCountLayout.
                let revealCostMap: InstantPageV2RevealCostMap? = (hasDraft || hadDraft) ? pageLayout?.computeRevealCostMap() : nil
                let revealedGlyphCount: Int? = (hasDraft || hadDraft) ? (currentMaxGlyphCount ?? 0) : nil

                if let pageLayout {
                    let effectiveSize: CGSize
                    if let costMap = revealCostMap, let glyphCount = revealedGlyphCount {
                        effectiveSize = costMap.revealedContentSize(revealedCount: glyphCount, layout: pageLayout)
                    } else {
                        effectiveSize = pageLayout.contentSize
                    }
                    boundingSize.width = effectiveSize.width
                    boundingSize.height = effectiveSize.height + 2.0
                }

                // The hardcoded "Thinking…" header was removed in favor of server-sent
                // InstantPageBlock.thinking blocks (rendered inside the pageView). There is no
                // header strip anymore, so the page content starts at the top of the bubble.
                let streamingHeaderOffset: CGFloat = 0.0

                if hasDraft {
                    // The bubble's bottom inset is supplied by the `statusBottomEdge + 6.0`
                    // max() in the measure closure below — but that branch is gated by
                    // `!hasDraft`, so during streaming the bubble has only its 1pt bottom rim
                    // past `revealedContentSize.height` (= bounds.maxY + closingPad). Without
                    // this, descenders of the last revealed line sit cramped against the
                    // bubble's bottom edge and the bubble visibly grows by 6pt when streaming
                    // ends and the status node fades in. 6pt matches the constant inside the
                    // status max() (which itself tracks `TextBubble`'s `bubbleInsets.bottom`).
                    // `hadDraft && !hasDraft` (the finalize pass) doesn't need this because
                    // `!hasDraft` re-enables the status max(), which supplies the inset for it.
                    boundingSize.height += 6.0
                }

                let message = item.message
                let incoming = isIncoming

                var edited = false
                if item.attributes.updatingMedia != nil {
                    edited = true
                }
                var viewCount: Int?
                var dateReplies = 0
                var starsCount: Int64?
                var dateReactionsAndPeers = mergedMessageReactionsAndPeers(accountPeerId: item.context.account.peerId, accountPeer: item.associatedData.accountPeer, message: item.topMessage)
                if item.message.isRestricted(platform: "ios", contentSettings: item.context.currentContentSettings.with { $0 }) {
                    dateReactionsAndPeers = ([], [])
                }

                for attribute in item.message.attributes {
                    if let attribute = attribute as? EditedMessageAttribute {
                        edited = !attribute.isHidden
                    } else if let attribute = attribute as? ViewCountMessageAttribute {
                        viewCount = attribute.count
                    } else if let attribute = attribute as? ReplyThreadMessageAttribute, case .peer = item.chatLocation {
                        if let channel = item.message.peers[item.message.id.peerId] as? TelegramChannel, case .group = channel.info {
                            dateReplies = Int(attribute.count)
                        }
                    } else if let attribute = attribute as? PaidStarsMessageAttribute, item.message.id.peerId.namespace == Namespaces.Peer.CloudChannel {
                        starsCount = attribute.stars.value
                    }
                }

                let dateFormat: MessageTimestampStatusFormat
                if item.presentationData.isPreview {
                    dateFormat = .full
                } else if let subject = item.associatedData.subject, case .messageOptions = subject {
                    dateFormat = .minimal
                } else {
                    dateFormat = .regular
                }
                let dateText = stringForMessageTimestampStatus(accountPeerId: item.context.account.peerId, message: EngineMessage(item.message), dateTimeFormat: item.presentationData.dateTimeFormat, nameDisplayOrder: item.presentationData.nameDisplayOrder, strings: item.presentationData.strings, format: dateFormat, associatedData: item.associatedData)

                let statusType: ChatMessageDateAndStatusType?
                var displayStatus = false
                switch position {
                case let .linear(_, neighbor):
                    if case .None = neighbor {
                        displayStatus = true
                    } else if case .Neighbour(true, _, _) = neighbor {
                        displayStatus = true
                    }
                default:
                    break
                }
                if case let .customChatContents(contents) = item.associatedData.subject {
                    if case .hashTagSearch = contents.kind {
                        displayStatus = true
                    } else {
                        displayStatus = false
                    }
                } else if !item.presentationData.chatBubbleCorners.hasTails {
                    displayStatus = false
                } else if case let .messageOptions(_, _, info) = item.associatedData.subject, case let .link(link) = info, link.isCentered {
                    displayStatus = false
                }
                
                if displayStatus {
                    if incoming {
                        statusType = .BubbleIncoming
                    } else {
                        if message.flags.contains(.Failed) {
                            statusType = .BubbleOutgoing(.Failed)
                        } else if (message.flags.isSending && !message.isSentOrAcknowledged) || item.attributes.updatingMedia != nil {
                            statusType = .BubbleOutgoing(.Sending)
                        } else {
                            statusType = .BubbleOutgoing(.Sent(read: item.read))
                        }
                    }
                } else {
                    statusType = nil
                }

                // Only trail the status inline with the last text line when the bottom-most page
                // item is itself a text item; otherwise (table/image/etc. last) the status falls
                // through to the contentSize.height anchor and sits below all content.
                let lastTextLine = pageLayout.flatMap(InstantPageUI.lastTextLineFrameIfLastItemIsText(in:))
                let lastTextLineFrame: CGRect? = lastTextLine?.frame
                // Baseline → visible-text-bottom compensation. Applied whether the date trails on
                // the last line or wraps onto its own line below it (0 for attachment-inflated lines,
                // whose maxY already sits at the visible bottom).
                let lastTextLineTrailingPadding: CGFloat = lastTextLine?.trailingBottomPadding ?? 0.0

                var statusSuggestedWidthAndContinue: (CGFloat, (CGFloat) -> (CGSize, (ListViewItemUpdateAnimation) -> ChatMessageDateAndStatusNode))?
                if let statusType = statusType {
                    var isReplyThread = false
                    if case .replyThread = item.chatLocation {
                        isReplyThread = true
                    }

                    // Measure trailing extent from the line's actual visible RIGHT EDGE (after
                    // alignment, in page coords) — not just its intrinsic width. A right-aligned
                    // or RTL last line has `lineWidth` worth of glyphs but sits all the way at
                    // the right text inset (lineFrame.maxX == text.frame.minX + textItem.width).
                    // Feeding the status node just `lineWidth` would let the trail/wrap decision
                    // place the date inline with the line — on top of it. `pageHorizontalInset`
                    // is the offset between page-coords and status-node-local coords (the status
                    // node sits at x=pageHorizontalInset in self, and pageView sits at self-x 0).
                    let trailingWidthToMeasure: CGFloat = lastTextLineFrame.map { $0.maxX - pageHorizontalInset } ?? 10000.0

                    let dateLayoutInput: ChatMessageDateAndStatusNode.LayoutInput = .trailingContent(contentWidth: trailingWidthToMeasure, reactionSettings: ChatMessageDateAndStatusNode.TrailingReactionSettings(displayInline: shouldDisplayInlineDateReactions(message: EngineMessage(item.message), isPremium: item.associatedData.isPremium, forceInline: item.associatedData.forceInlineReactions), preferAdditionalInset: false))

                    statusSuggestedWidthAndContinue = statusLayout(ChatMessageDateAndStatusNode.Arguments(
                        context: item.context,
                        presentationData: item.presentationData,
                        edited: edited && !item.presentationData.isPreview,
                        impressionCount: !item.presentationData.isPreview ? viewCount : nil,
                        dateText: dateText,
                        type: statusType,
                        layoutInput: dateLayoutInput,
                        constrainedSize: CGSize(width: suggestedBoundingWidth, height: .greatestFiniteMagnitude),
                        availableReactions: item.associatedData.availableReactions,
                        savedMessageTags: item.associatedData.savedMessageTags,
                        reactions: item.presentationData.isPreview ? [] : dateReactionsAndPeers.reactions,
                        reactionPeers: dateReactionsAndPeers.peers,
                        displayAllReactionPeers: item.message.id.peerId.namespace == Namespaces.Peer.CloudUser,
                        areReactionsTags: item.topMessage.areReactionsTags(accountPeerId: item.context.account.peerId),
                        areStarReactionsEnabled: item.associatedData.areStarReactionsEnabled,
                        messageEffect: item.topMessage.messageEffect(availableMessageEffects: item.associatedData.availableMessageEffects),
                        replyCount: dateReplies,
                        starsCount: starsCount,
                        isPinned: item.message.tags.contains(.pinned) && (!item.associatedData.isInPinnedListMode || isReplyThread),
                        hasAutoremove: item.message.isSelfExpiring,
                        canViewReactionList: canViewMessageReactionList(message: EngineMessage(item.topMessage)),
                        animationCache: item.controllerInteraction.presentationContext.animationCache,
                        animationRenderer: item.controllerInteraction.presentationContext.animationRenderer
                    ))
                }

                if let statusSuggestedWidthAndContinue, !hasDraft {
                    // Mirrors TextBubble: max(contentWidth, statusWidth + sideInsets), where
                    // sideInsets = left + right text inset (= pageHorizontalInset on each side).
                    boundingSize.width = max(boundingSize.width, statusSuggestedWidthAndContinue.0 + pageHorizontalInset * 2.0)
                }

                return (boundingSize.width, { boundingWidth in
                    // Mirrors TextBubble's `boundingWidth - sideInsets` so the right-aligned date
                    // lands at the right text inset rather than past the bubble's right edge.
                    let statusSizeAndApply = statusSuggestedWidthAndContinue?.1(boundingWidth - pageHorizontalInset * 2.0)
                    if let statusSizeAndApply, !hasDraft {
                        // Status node anchor Y in the content node's space — mirrors the apply
                        // closure below.
                        let statusAnchorY: CGFloat
                        if let lastTextLineFrame {
                            // The renderer draws the baseline at the line frame's maxY, so the
                            // visible text sits `trailingBottomPadding` below it. Apply that pad
                            // whether the date trails on the line OR wraps onto its own line below:
                            // in both cases the date should reference the visible text bottom, not
                            // the baseline (mirrors TextBubble, whose status anchors at the text
                            // frame's maxY). Without it the wrapped date crowded the last line.
                            statusAnchorY = 1.0 + lastTextLineFrame.maxY + lastTextLineTrailingPadding + streamingHeaderOffset
                        } else if let pageLayout {
                            statusAnchorY = 1.0 + pageLayout.contentSize.height + streamingHeaderOffset
                        } else {
                            statusAnchorY = 1.0 + streamingHeaderOffset
                        }
                        // Date's bottom edge: a trailing date sits ~1pt below the anchor; a wrapped
                        // date extends `statusHeight` below it. Leave ~6pt to the bubble's bottom
                        // edge, matching TextBubble's bottom inset.
                        let statusBottomEdge = statusAnchorY + max(1.0, statusSizeAndApply.0.height)
                        boundingSize.height = max(boundingSize.height, statusBottomEdge + 6.0)
                    }

                    return (boundingSize, { animation, _, _ in
                        guard let self else {
                            return
                        }
                        self.item = item

                        animation.animator.updateFrame(layer: self.containerNode.layer, frame: CGRect(origin: CGPoint(x: 1.0, y: 1.0), size: CGSize(width: boundingWidth - 2.0, height: boundingSize.height)), completion: nil)
                        self.containerNode.cornerRadius = layoutConstants.image.defaultCornerRadius

                        if let statusSizeAndApply {
                            // Match TextBubble: anchor the status node's x at the fixed text-block
                            // left edge (not the last line's minX, which is large for nested
                            // content and shoves the right-aligned date off the bubble). The status
                            // node positions the date trailing/below relative to this origin.
                            let statusFrameY: CGFloat
                            if let lastTextLineFrame {
                                // Apply the text-rect pad (baseline → visible text bottom) for both
                                // the trailing and wrapped cases, so the date references the visible
                                // text bottom rather than the baseline. Mirrors the measure closure
                                // and TextBubble. Without it the wrapped date crowded the last line.
                                statusFrameY = 1.0 + lastTextLineFrame.maxY + lastTextLineTrailingPadding
                            } else if let pageLayout {
                                statusFrameY = 1.0 + pageLayout.contentSize.height
                            } else {
                                statusFrameY = 1.0
                            }
                            let statusFrame = CGRect(origin: CGPoint(x: pageHorizontalInset, y: statusFrameY + streamingHeaderOffset), size: statusSizeAndApply.0)
                            let statusNode = statusSizeAndApply.1(self.statusNode == nil ? .None : animation)

                            if self.statusNode !== statusNode {
                                self.statusNode?.removeFromSupernode()
                                self.statusNode = statusNode

                                self.addSubnode(statusNode)

                                statusNode.reactionSelected = { [weak self] _, value, sourceView in
                                    guard let self, let item = self.item else {
                                        return
                                    }
                                    item.controllerInteraction.updateMessageReaction(item.topMessage, .reaction(value), false, sourceView)
                                }
                                statusNode.openReactionPreview = { [weak self] gesture, sourceNode, value in
                                    guard let self, let item = self.item else {
                                        gesture?.cancel()
                                        return
                                    }
                                    item.controllerInteraction.openMessageReactionContextMenu(item.topMessage, sourceNode, gesture, value)
                                }
                                statusNode.frame = statusFrame
                            } else {
                                animation.animator.updatePosition(layer: statusNode.layer, position: statusFrame.center, completion: nil)
                                animation.animator.updateBounds(layer: statusNode.layer, bounds: CGRect(origin: .zero, size: statusFrame.size), completion: nil)
                            }
                        } else if let statusNode = self.statusNode {
                            self.statusNode = nil
                            statusNode.removeFromSupernode()
                        }

                        if let forwardInfo = item.message.forwardInfo, forwardInfo.flags.contains(.isImported), let statusNode = self.statusNode {
                            statusNode.pressed = { [weak self] in
                                guard let self, let statusNode = self.statusNode, let item = self.item else {
                                    return
                                }
                                item.controllerInteraction.displayImportedMessageTooltip(statusNode)
                            }
                        } else {
                            self.statusNode?.pressed = nil
                        }

                        if let pageLayout, let pageWebpage, let _ = item.message.richText {
                            self.currentPageLayout = (
                                suggestedBoundingWidth,
                                ObjectIdentifier(item.presentationData.theme.theme),
                                self.currentExpandedDetails,
                                item.message.stableVersion,
                                pageLayout
                            )
                            let pageView = self.ensurePageView(item: item, webpage: pageWebpage)
                            pageView.update(layout: pageLayout, theme: pageTheme, animation: animation)
                            pageView.frame = CGRect(
                                origin: CGPoint(x: -1.0, y: streamingHeaderOffset),
                                size: pageLayout.contentSize
                            )
                            self.updatePageViewVisibilityRect()
                            if self.displayContentsUnderSpoilers {
                                pageView.setDisplayContentsUnderSpoilers(true, atLocation: nil, animated: false)
                            }
                        } else {
                            self.currentPageLayout = nil
                            self.pageView?.update(
                                layout: InstantPageV2Layout(contentSize: .zero, items: [], detailsIndices: []),
                                theme: pageTheme,
                                animation: animation
                            )
                            self.pageViewMessageKey = nil
                        }

                        // === Streaming state apply ===

                        // 1. Compute / cache the cost map.
                        // Reuse the cost map computed in the layout pass (the bubble's
                        // size depended on it) — don't recompute. Keep the previous map
                        // alive while a reveal/finalize is still in flight: on a post-
                        // streaming pass (hasDraft && hadDraft both false) revealCostMap is
                        // nil, and clobbering it would strand the display-link tick (whose
                        // guard requires a cost map), aborting the finalize before it can
                        // clear the mask and restore the status alpha.
                        if let revealCostMap {
                            self.currentRevealCostMap = revealCostMap
                        } else if self.textRevealController == nil {
                            self.currentRevealCostMap = nil
                        }

                        // 2. Drive the reveal controller.
                        let previousAnimateGlyphCount: Int? = (hasDraft || hadDraft) ? (self.textRevealController?.currentGlyphCount ?? 0) : nil
                        if previousAnimateGlyphCount != nil || self.textRevealController != nil || hasDraft || hadDraft {
                            if hasDraft {
                                self.statusNode?.alpha = 0.0
                            }
                            // Seed the (possibly freshly rebuilt) V2 view to the reveal cursor's
                            // current position so we don't flash full text. Use the live controller
                            // count rather than `previousAnimateGlyphCount`, which is nil — and would
                            // reset the reveal to 0 — on post-streaming finalize passes where the
                            // controller is still animating.
                            let seedCount = self.textRevealController?.currentGlyphCount ?? previousAnimateGlyphCount ?? 0
                            self.pageView?.applyReveal(revealedCount: seedCount,
                                                       costMap: self.currentRevealCostMap,
                                                       animated: false)
                            self.lastAppliedRevealedCount = seedCount
                            self.updateTextRevealAnimation(previousGlyphCount: previousAnimateGlyphCount ?? 0,
                                                           hasDraft: hasDraft,
                                                           hadDraft: hadDraft)
                        }
                    })
                })
            })
        }
    }
    
    private func updateTextRevealAnimation(previousGlyphCount: Int, hasDraft: Bool, hadDraft: Bool) {
        let toCount = self.currentRevealCostMap?.total ?? 0
        let now = CACurrentMediaTime()

        if hasDraft, let controller = self.textRevealController, controller.isFinalizing {
            self.textRevealController = nil
            self.textRevealLink = nil
        }

        if self.textRevealController == nil && (hasDraft || hadDraft) {
            self.textRevealController = TextRevealController(initialRevealedCount: previousGlyphCount, initialLength: toCount, durationMultiplier: 10.0)
        }

        guard let controller = self.textRevealController else { return }

        if hasDraft {
            controller.observeUpdate(latestLength: toCount, at: now)
        } else if hadDraft {
            controller.finalize(finalLength: toCount)
        }

        if controller.isFinalizing && controller.revealedCount >= Double(controller.latestLength) {
            self.textRevealController = nil
            self.textRevealLink = nil
            self.pageView?.applyReveal(revealedCount: nil, costMap: nil, animated: false)
            self.lastAppliedRevealedCount = 0
            // The cursor already caught up at finalize time, so the display-link `isComplete`
            // branch (which normally restores the status alpha) will never run. Restore it
            // here too, mirroring that branch.
            if let item = self.item, let statusNode = self.statusNode,
               !item.message.attributes.contains(where: { $0 is TypingDraftMessageAttribute }) {
                ContainedViewLayoutTransition.animated(duration: 0.2, curve: .easeInOut).updateAlpha(node: statusNode, alpha: 1.0)
            }
            return
        }

        guard toCount > 0 else { return }

        if self.textRevealLink == nil {
            self.textRevealLink = SharedDisplayLinkDriver.shared.add { [weak self] _ in
                guard let self else { return }
                guard let item = self.item else {
                    self.textRevealController = nil
                    self.textRevealLink = nil
                    return
                }
                guard let controller = self.textRevealController, let costMap = self.currentRevealCostMap else {
                    self.textRevealLink = nil
                    return
                }
                let now = CACurrentMediaTime()
                let (revealedGlyphCount, isComplete) = controller.tick(now: now)

                if isComplete {
                    self.textRevealController = nil
                    self.textRevealLink = nil
                    self.pageView?.applyReveal(revealedCount: nil, costMap: nil, animated: false)
                    self.lastAppliedRevealedCount = 0

                    if let statusNode = self.statusNode,
                       !item.message.attributes.contains(where: { $0 is TypingDraftMessageAttribute }) {
                        ContainedViewLayoutTransition.animated(duration: 0.2, curve: .easeInOut).updateAlpha(node: statusNode, alpha: 1.0)
                    }
                    self.requestFullUpdate?(ControlledTransition(duration: 0.15, curve: .easeInOut, interactive: false))
                } else {
                    // If the revealed prefix's bottom y would change at the new cursor (i.e.
                    // crossing a line/item boundary), trigger a full bubble re-layout so the
                    // bubble grows with the reveal. Mirrors TextBubble's
                    // `cachedLayout.sizeForCharacterCount(...)` check at lines 1209-1216.
                    var requestUpdate = false
                    if let pageLayout = self.currentPageLayout?.layout, self.lastAppliedRevealedCount != revealedGlyphCount {
                        let prevHeight = costMap.revealedContentSize(revealedCount: self.lastAppliedRevealedCount, layout: pageLayout).height
                        let newHeight = costMap.revealedContentSize(revealedCount: revealedGlyphCount, layout: pageLayout).height
                        if prevHeight != newHeight {
                            requestUpdate = true
                        }
                    }
                    self.pageView?.applyReveal(revealedCount: revealedGlyphCount, costMap: costMap, animated: true)
                    self.lastAppliedRevealedCount = revealedGlyphCount
                    if requestUpdate {
                        self.requestFullUpdate?(ControlledTransition(duration: 0.15, curve: .easeInOut, interactive: false))
                    }
                }
            }
        }
    }

    override public func animateInsertion(_ currentTimestamp: Double, duration: Double) {
        if let statusNode = self.statusNode, statusNode.alpha != 0.0 {
            statusNode.layer.animateAlpha(from: 0.0, to: statusNode.alpha, duration: 0.2)
        }
    }
    
    override public func animateAdded(_ currentTimestamp: Double, duration: Double) {
        if let statusNode = self.statusNode, statusNode.alpha != 0.0 {
            statusNode.layer.animateAlpha(from: 0.0, to: statusNode.alpha, duration: 0.2)
        }
    }
    
    override public func animateRemoved(_ currentTimestamp: Double, duration: Double) {
        if let statusNode = self.statusNode, statusNode.alpha != 0.0 {
            statusNode.layer.animateAlpha(from: statusNode.alpha, to: 0.0, duration: 0.2, removeOnCompletion: false)
        }
    }
    
    override public func tapActionAtPoint(_ point: CGPoint, gesture: TapLongTapOrDoubleTapGesture, isEstimating: Bool) -> ChatMessageBubbleContentTapAction {
        if case .tap = gesture {
        } else {
            if let item = self.item, let subject = item.associatedData.subject, case .messageOptions = subject {
                return ChatMessageBubbleContentTapAction(content: .none)
            }
        }

        if case .tap = gesture, !self.displayContentsUnderSpoilers, let entityHit = self.entityForTapLocation(point), entityHit.attributes[NSAttributedString.Key(rawValue: TelegramTextAttributes.Spoiler)] != nil {
            return ChatMessageBubbleContentTapAction(content: .custom({ [weak self] in
                self?.revealSpoilers(atContentPoint: point)
            }))
        }

        guard let urlHit = self.urlForTapLocation(point) else {
            if let entityHit = self.entityForTapLocation(point), let content = self.entityTapContent(entityHit.attributes) {
                let rects = self.computeHighlightRects(item: entityHit.item, parentOffset: entityHit.parentOffset, localPoint: entityHit.localPoint)
                return ChatMessageBubbleContentTapAction(
                    content: content,
                    rects: rects,
                    activate: self.makeActivate(item: entityHit.item, parentOffset: entityHit.parentOffset, localPoint: entityHit.localPoint)
                )
            }
            return ChatMessageBubbleContentTapAction(content: .none)
        }

        let split = self.splitAnchor(urlHit.urlItem.url)
        if let webpage = self.currentLoadedWebpage(), webpage.content.url == split.base, let anchor = split.anchor {
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
        guard let pageView = self.pageView else { return nil }
        let local = self.view.convert(location, to: pageView)
        return pageView.textItemAt(point: local)
    }

    private func urlForTapLocation(_ point: CGPoint) -> (item: InstantPageTextItem, urlItem: InstantPageUrlItem, parentOffset: CGPoint, localPoint: CGPoint)? {
        guard let pageView = self.pageView else { return nil }
        let local = self.view.convert(point, to: pageView)
        return pageView.urlItemAt(point: local).map {
            (item: $0.item, urlItem: $0.urlItem, parentOffset: $0.parentOffset, localPoint: $0.localPoint)
        }
    }

    private func entityForTapLocation(_ point: CGPoint) -> (item: InstantPageTextItem, parentOffset: CGPoint, localPoint: CGPoint, attributes: [NSAttributedString.Key: Any])? {
        guard let pageView = self.pageView else { return nil }
        let local = self.view.convert(point, to: pageView)
        guard let hit = pageView.textItemAt(point: local) else { return nil }
        let localPoint = CGPoint(x: local.x - hit.parentOffset.x, y: local.y - hit.parentOffset.y)
        guard let (_, attributes) = hit.item.attributesAtPoint(localPoint, orNearest: false) else { return nil }
        return (item: hit.item, parentOffset: hit.parentOffset, localPoint: localPoint, attributes: attributes)
    }

    private func revealSpoilers(atContentPoint point: CGPoint) {
        guard !self.displayContentsUnderSpoilers, let pageView = self.pageView else {
            return
        }
        self.displayContentsUnderSpoilers = true
        let local = self.view.convert(point, to: pageView)
        pageView.setDisplayContentsUnderSpoilers(true, atLocation: local, animated: true)
    }

    private func entityTapContent(_ attributes: [NSAttributedString.Key: Any]) -> ChatMessageBubbleContentTapAction.Content? {
        if let mention = attributes[NSAttributedString.Key(rawValue: TelegramTextAttributes.PeerMention)] as? TelegramPeerMention {
            return .peerMention(peerId: mention.peerId, mention: mention.mention, openProfile: false)
        } else if let peerName = attributes[NSAttributedString.Key(rawValue: TelegramTextAttributes.PeerTextMention)] as? String {
            return .textMention(peerName)
        } else if let botCommand = attributes[NSAttributedString.Key(rawValue: TelegramTextAttributes.BotCommand)] as? String {
            return .botCommand(botCommand)
        } else if let hashtag = attributes[NSAttributedString.Key(rawValue: TelegramTextAttributes.Hashtag)] as? TelegramHashtag {
            // Cashtags are carried as a Hashtag attribute (no dedicated cashtag key/tap-action exists);
            // the leading "$" in the string distinguishes them, and the chat hashtag handler searches both.
            return .hashtag(hashtag.peerName, hashtag.hashtag)
        } else if let bankCard = attributes[NSAttributedString.Key(rawValue: TelegramTextAttributes.BankCard)] as? String {
            return .bankCard(bankCard)
        }
        return nil
    }

    /// Bridges an InstantPageUrlItem (used by the gallery's caption URL handler) to the
    /// chat layer's URL handler. `concealed: true` matches `tapActionAtPoint` for the same
    /// reason: V2 cannot reliably compare displayed link text to the resolved URL.
    private func openInstantPageUrl(_ url: InstantPageUrlItem) {
        guard let item = self.item else { return }
        item.controllerInteraction.openUrl(ChatControllerInteraction.OpenUrl(
            url: url.url,
            concealed: true,
            allowInlineWebpageResolution: url.webpageId != nil
        ))
    }

    private func computeHighlightRects(item: InstantPageTextItem, parentOffset: CGPoint, localPoint: CGPoint) -> [CGRect] {
        // Text item returns rects in its local coords; translate back into containerNode-local coords.
        // containerNode is offset by (1, 1) from the bubble-content-node, but the highlight overlay lives
        // *inside* containerNode, so we use layout-coords (= containerNode-local) for the rects.
        let originX = parentOffset.x
        let originY = parentOffset.y
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
        if let statusNode = self.statusNode, statusNode.supernode != nil, let result = statusNode.hitTest(self.view.convert(point, to: statusNode.view), with: event) {
            return result
        }
        return super.hitTest(point, with: event)
    }
    
    override public func updateTouchesAtPoint(_ point: CGPoint?) {
        guard let messageItem = self.item else {
            return
        }

        var rects: [CGRect]?
        if let point {
            if let urlHit = self.urlForTapLocation(point) {
                rects = self.computeHighlightRects(item: urlHit.item, parentOffset: urlHit.parentOffset, localPoint: urlHit.localPoint)
            } else if let entityHit = self.entityForTapLocation(point), self.entityTapContent(entityHit.attributes) != nil {
                rects = self.computeHighlightRects(item: entityHit.item, parentOffset: entityHit.parentOffset, localPoint: entityHit.localPoint)
            }
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
                highlightingNode.useModernPathCalculation = true
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
    
    override public func updateSearchTextHighlightState(text: String?, messages: [EngineMessage.Index]?) {
    }
    
    override public func willUpdateIsExtractedToContextPreview(_ value: Bool) {
        if !value, let textSelectionNode = self.textSelectionNode {
            self.textSelectionNode = nil
            self.textSelectionAdapter = nil
            textSelectionNode.highlightAreaNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false)
            textSelectionNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false, completion: { [weak textSelectionNode] _ in
                textSelectionNode?.highlightAreaNode.removeFromSupernode()
                textSelectionNode?.removeFromSupernode()
            })
        }
    }

    override public func updateIsExtractedToContextPreview(_ value: Bool) {
        guard value, self.textSelectionNode == nil, let messageItem = self.item, self.currentPageLayout?.layout != nil, let pageView = self.pageView, let rootNode = messageItem.controllerInteraction.chatControllerNode() else {
            return
        }

        // pageView sits at (-1, 0) inside containerNode; the adapter is placed at
        // containerNode.bounds, so shift each item's page-space origin into
        // containerNode-local coords for the adapter to operate in.
        let pageOrigin = pageView.frame.origin
        let entries = pageView.selectableTextItems()
            .filter { $0.item.selectable && !$0.item.attributedString.string.isEmpty }
            .map { entry in
                InstantPageMultiTextAdapter.Entry(
                    item: entry.item,
                    frameOrigin: CGPoint(
                        x: entry.parentOffset.x + pageOrigin.x,
                        y: entry.parentOffset.y + pageOrigin.y
                    )
                )
            }
        guard !entries.isEmpty else {
            return
        }

        let adapter = InstantPageMultiTextAdapter(entries: entries)
        adapter.frame = self.containerNode.bounds
        self.textSelectionAdapter = adapter
        self.containerNode.addSubnode(adapter)

        let incoming = messageItem.message.effectivelyIncoming(messageItem.context.account.peerId)
        let theme = messageItem.presentationData.theme.theme
        let selectionColor = incoming ? theme.chat.message.incoming.textSelectionColor : theme.chat.message.outgoing.textSelectionColor
        let knobColor = incoming ? theme.chat.message.incoming.textSelectionKnobColor : theme.chat.message.outgoing.textSelectionKnobColor

        let textSelectionNode = TextSelectionNode(
            theme: TextSelectionTheme(selection: selectionColor, knob: knobColor, isDark: theme.overallDarkAppearance),
            strings: messageItem.presentationData.strings,
            textNodeOrView: .node(adapter),
            updateIsActive: { _ in },
            present: { [weak self] c, a in
                guard let self, let item = self.item else {
                    return
                }
                if let subject = item.associatedData.subject, case let .messageOptions(_, _, info) = subject, case .reply = info {
                    item.controllerInteraction.presentControllerInCurrent(c, a)
                } else {
                    item.controllerInteraction.presentGlobalOverlayController(c, a)
                }
            },
            rootView: { [weak rootNode] in
                return rootNode?.view
            },
            performAction: { [weak self] text, action in
                guard let self, let item = self.item else {
                    return
                }
                if case .copy = action,
                   let range = self.textSelectionNode?.getSelection(),
                   range.length > 0,
                   let adapter = self.textSelectionAdapter {
                    let markdown = adapter.markdownForRange(range)
                    if !markdown.isEmpty {
                        item.controllerInteraction.performTextSelectionAction(item.message, true, NSAttributedString(string: markdown), nil, .copy)
                        return
                    }
                }
                item.controllerInteraction.performTextSelectionAction(item.message, true, text, nil, action)
            }
        )

        let enableCopy = (!messageItem.associatedData.isCopyProtectionEnabled && !messageItem.message.isCopyProtected()) || messageItem.message.id.peerId.isVerificationCodes
        textSelectionNode.enableCopy = enableCopy

        var enableOtherActions = true
        if let subject = messageItem.associatedData.subject, case let .messageOptions(_, _, info) = subject, case .reply = info {
            enableOtherActions = false
        }

        textSelectionNode.enableQuote = false
        textSelectionNode.enableTranslate = enableOtherActions
        textSelectionNode.enableShare = enableOtherActions && enableCopy
        textSelectionNode.enableLookup = true
        textSelectionNode.menuSkipCoordnateConversion = !enableOtherActions

        textSelectionNode.frame = self.containerNode.bounds
        textSelectionNode.highlightAreaNode.frame = self.containerNode.bounds
        self.containerNode.insertSubnode(textSelectionNode.highlightAreaNode, at: 0)
        self.containerNode.addSubnode(textSelectionNode)
        self.textSelectionNode = textSelectionNode
    }

    override public func transitionNode(messageId: EngineMessage.Id, media: EngineRawMedia, adjustRect: Bool) -> (ASDisplayNode, CGRect, () -> (UIView?, UIView?))? {
        // V2 V0: media items render as gray placeholders; no transition node is exposed.
        return nil
    }

    override public func updateHiddenMedia(_ media: [EngineRawMedia]?) -> Bool {
        // V2 V0: media items render as gray placeholders; nothing to hide.
        return false
    }

    override public func getAnchorRect(anchor: String) -> CGRect? {
        // V2 V0: anchor resolution lives in the V2 view (text-item anchors). Not yet wired through.
        let _ = anchor
        return nil
    }

    override public func reactionTargetView(value: MessageReaction.Reaction) -> UIView? {
        if let statusNode = self.statusNode, !statusNode.isHidden {
            return statusNode.reactionView(value: value)
        }
        return nil
    }
    
    override public func messageEffectTargetView() -> UIView? {
        if let statusNode = self.statusNode, !statusNode.isHidden {
            return statusNode.messageEffectTargetView()
        }
        return nil
    }
    
    override public func getStatusNode() -> ASDisplayNode? {
        return self.statusNode
    }

    private func splitAnchor(_ url: String) -> (base: String, anchor: String?) {
        if let anchorRange = url.range(of: "#") {
            let anchor = String(url[anchorRange.upperBound...]).removingPercentEncoding
            let base = String(url[..<anchorRange.lowerBound])
            return (base, anchor)
        }
        return (url, nil)
    }

    private func currentLoadedWebpage() -> TelegramMediaWebpage? {
        return nil   // V2 V0: media items are placeholders; no inline webpage resolution.
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
