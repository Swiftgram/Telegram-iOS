# Rich-bubble instant-page link handling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire URL tap routing and link-highlight feedback into `ChatMessageRichDataBubbleContentNode`, plus stubbed handlers for intra-page anchor scrolling.

**Architecture:** All changes land in a single Swift file (`ChatMessageRichDataBubbleContentNode.swift`) plus its BUILD file. Tap detection mirrors `InstantPageControllerNode.textItemAtLocation` / `urlForTapLocation` scoped to the bubble's already-built `currentPageLayout`. URL hits return a standard `ChatMessageBubbleContentTapAction(.url(...), rects:, activate:)` which the bubble framework routes through `controllerInteraction.openUrl`. Highlight feedback uses a `LinkHighlightingNode` overlay inside `containerNode`, driven by the `activate` `Promise<Bool>` exactly like the chat text bubble. Same-page-anchor URLs short-circuit into a no-op `scrollToAnchor(_:)` placeholder for later implementation.

**Tech Stack:** Swift, AsyncDisplayKit, Bazel (`build-system/Make/Make.py`), modules `Display`, `InstantPageUI`, `ChatControllerInteraction`, `ChatMessageBubbleContentNode`, `TelegramCore`, `SwiftSignalKit`.

**Reference spec:** `docs/superpowers/specs/2026-05-01-rich-bubble-instant-page-link-handling-design.md`

**Project context:** No automated tests exist (per `CLAUDE.md`). Per-task verification is "build green" using:

```sh
source ~/.zshrc 2>/dev/null; python3 build-system/Make/Make.py --overrideXcodeVersion \
  --cacheDir ~/telegram-bazel-cache \
  build \
  --configurationPath build-system/appstore-configuration.json \
  --gitCodesigningRepository git@gitlab.com:peter-iakovlev/fastlanematch.git \
  --gitCodesigningType development --gitCodesigningUseCurrent --buildNumber=1 --configuration=debug_sim_arm64 \
  --continueOnError
```

Final manual smoke test runs the app and exercises the feature in the simulator.

---

## File map

- **Modified:** `submodules/TelegramUI/Components/Chat/ChatMessageRichDataBubbleContentNode/Sources/ChatMessageRichDataBubbleContentNode.swift` — adds tap detection helpers, link-highlight state and overlay management, real `openPeer`/`openUrl` item callbacks, anchor stub, and a populated `tapActionAtPoint`.
- **Modified:** `submodules/TelegramUI/Components/Chat/ChatMessageRichDataBubbleContentNode/BUILD` — adds `//submodules/TelegramUI/Components/ChatControllerInteraction` to `deps`.

No other files change.

---

### Task 1: Add `ChatControllerInteraction` BUILD dep + import

The rich-bubble currently does not have access to `ChatControllerInteraction` as an importable module. Sibling modules (e.g. `ChatMessageWebpageBubbleContentNode`) list it explicitly in BUILD deps and import it. We follow the same pattern.

**Files:**
- Modify: `submodules/TelegramUI/Components/Chat/ChatMessageRichDataBubbleContentNode/BUILD`
- Modify: `submodules/TelegramUI/Components/Chat/ChatMessageRichDataBubbleContentNode/Sources/ChatMessageRichDataBubbleContentNode.swift:1-12`

- [ ] **Step 1: Add the dep to BUILD**

In `submodules/TelegramUI/Components/Chat/ChatMessageRichDataBubbleContentNode/BUILD`, add the new dep line at the end of the existing `deps` list (alphabetical order is not enforced in this repo's BUILD files; place it after `ChatMessageItemCommon`):

Replace:
```
    deps = [
        "//submodules/AsyncDisplayKit",
        "//submodules/Display",
        "//submodules/TelegramCore",
        "//submodules/Postbox",
        "//submodules/SSignalKit/SwiftSignalKit",
        "//submodules/AccountContext",
        "//submodules/InstantPageUI",
        "//submodules/TelegramUI/Components/Chat/ChatMessageBubbleContentNode",
        "//submodules/TelegramUI/Components/Chat/ChatMessageItemCommon",
        "//submodules/TelegramUIPreferences",
    ],
```

With:
```
    deps = [
        "//submodules/AsyncDisplayKit",
        "//submodules/Display",
        "//submodules/TelegramCore",
        "//submodules/Postbox",
        "//submodules/SSignalKit/SwiftSignalKit",
        "//submodules/AccountContext",
        "//submodules/InstantPageUI",
        "//submodules/TelegramUI/Components/Chat/ChatMessageBubbleContentNode",
        "//submodules/TelegramUI/Components/Chat/ChatMessageItemCommon",
        "//submodules/TelegramUI/Components/ChatControllerInteraction",
        "//submodules/TelegramUIPreferences",
    ],
```

- [ ] **Step 2: Add the import**

At the top of `submodules/TelegramUI/Components/Chat/ChatMessageRichDataBubbleContentNode/Sources/ChatMessageRichDataBubbleContentNode.swift`, after `import ChatMessageItemCommon` add `import ChatControllerInteraction`:

Replace:
```swift
import ChatMessageBubbleContentNode
import ChatMessageItemCommon
import InstantPageUI
import TelegramUIPreferences
```

With:
```swift
import ChatMessageBubbleContentNode
import ChatMessageItemCommon
import ChatControllerInteraction
import InstantPageUI
import TelegramUIPreferences
```

- [ ] **Step 3: Build to verify**

```sh
source ~/.zshrc 2>/dev/null; python3 build-system/Make/Make.py --overrideXcodeVersion --cacheDir ~/telegram-bazel-cache build --configurationPath build-system/appstore-configuration.json --gitCodesigningRepository git@gitlab.com:peter-iakovlev/fastlanematch.git --gitCodesigningType development --gitCodesigningUseCurrent --buildNumber=1 --configuration=debug_sim_arm64 --continueOnError
```

Expected: build succeeds. The new import is unused; Swift does not warn on unused module imports, so `-warnings-as-errors` is fine.

- [ ] **Step 4: Commit**

```sh
git add submodules/TelegramUI/Components/Chat/ChatMessageRichDataBubbleContentNode/BUILD submodules/TelegramUI/Components/Chat/ChatMessageRichDataBubbleContentNode/Sources/ChatMessageRichDataBubbleContentNode.swift
git commit -m "Rich bubble: add ChatControllerInteraction dep and import"
```

---

### Task 2: Add link-progress state, deinit cleanup, and helper stubs

Before introducing tap-detection or item-callback logic, add the supporting plumbing: progress state, the empty `scrollToAnchor` placeholder, the URL-anchor splitter, and a `currentLoadedWebpage()` accessor. These are private helpers that future tasks will consume — Swift does not warn on unused private functions, so the build stays green.

**Files:**
- Modify: `submodules/TelegramUI/Components/Chat/ChatMessageRichDataBubbleContentNode/Sources/ChatMessageRichDataBubbleContentNode.swift`

- [ ] **Step 1: Add the new ivars**

Locate the existing block of stored properties around lines 18–25:

```swift
    private let containerNode: ContainerNode
    private var currentLayoutTiles: [InstantPageTile] = []
    private var visibleTiles: [Int: InstantPageTileNode] = [:]
    private var visibleItemsWithNodes: [Int: InstantPageNode] = [:]
    private var currentPageLayout: (boundingWidth: CGFloat, layout: InstantPageLayout)?
    private var distanceThresholdGroupCount: [Int: Int] = [:]
    private var currentLayoutItemsWithNodes: [InstantPageItem] = []
    private var currentExpandedDetails: [Int : Bool]?
```

Append the three highlight-related fields immediately after `currentExpandedDetails`:

```swift
    private let containerNode: ContainerNode
    private var currentLayoutTiles: [InstantPageTile] = []
    private var visibleTiles: [Int: InstantPageTileNode] = [:]
    private var visibleItemsWithNodes: [Int: InstantPageNode] = [:]
    private var currentPageLayout: (boundingWidth: CGFloat, layout: InstantPageLayout)?
    private var distanceThresholdGroupCount: [Int: Int] = [:]
    private var currentLayoutItemsWithNodes: [InstantPageItem] = []
    private var currentExpandedDetails: [Int : Bool]?
    private var linkProgressDisposable: Disposable?
    private var linkProgressRects: [CGRect]?
    private var linkHighlightingNode: LinkHighlightingNode?
```

- [ ] **Step 2: Update `deinit` to dispose the link-progress signal**

Locate the existing empty `deinit` (around line 48):

```swift
    deinit {
    }
```

Replace with:

```swift
    deinit {
        self.linkProgressDisposable?.dispose()
    }
```

- [ ] **Step 3: Add helper methods at the end of the class**

Locate the closing brace of the class (the last `}` in the file). Immediately before it, add the four helpers (anchor split, current-loaded-webpage accessor, anchor-scroll stub, and a small TODO note):

```swift
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
        // TODO: implement intra-page anchor scrolling
        let _ = anchor
    }
```

The `let _ = anchor` line silences any "unused parameter" lint while keeping the parameter name visible. (Required because `-warnings-as-errors` is enabled on this module.)

- [ ] **Step 4: Build to verify**

```sh
source ~/.zshrc 2>/dev/null; python3 build-system/Make/Make.py --overrideXcodeVersion --cacheDir ~/telegram-bazel-cache build --configurationPath build-system/appstore-configuration.json --gitCodesigningRepository git@gitlab.com:peter-iakovlev/fastlanematch.git --gitCodesigningType development --gitCodesigningUseCurrent --buildNumber=1 --configuration=debug_sim_arm64 --continueOnError
```

Expected: build succeeds. Private functions (even unused) and disposable ivars compile cleanly under `-warnings-as-errors`.

- [ ] **Step 5: Commit**

```sh
git add submodules/TelegramUI/Components/Chat/ChatMessageRichDataBubbleContentNode/Sources/ChatMessageRichDataBubbleContentNode.swift
git commit -m "Rich bubble: add link-progress state and anchor-scroll stub"
```

---

### Task 3: Wire item-level `openPeer` and `openUrl` callbacks

Replace the stubbed item-callback closures inside the `item.node(...)` invocation. Item nodes themselves emit URL/peer taps via their callback parameters; we route these to `controllerInteraction.openUrl` / `controllerInteraction.openPeer`. `openMedia`, `longPressMedia`, `activatePinchPreview`, `pinchPreviewFinished`, `updateWebEmbedHeight`, and `updateDetailsExpanded` remain explicit no-ops (per spec — out of scope for this change).

**Files:**
- Modify: `submodules/TelegramUI/Components/Chat/ChatMessageRichDataBubbleContentNode/Sources/ChatMessageRichDataBubbleContentNode.swift` (the `item.node(...)` call inside `updateVisibleItems`, currently at lines ~233–278)

- [ ] **Step 1: Replace the `item.node(...)` callback block**

Locate the existing call (the entire block from `if let newNode = item.node(context: ...` through the matching `currentExpandedDetails: ..., getPreloadedResource: { _ in return nil }) {` line). Replace ONLY the trailing-closure callback parameters — keep `context:`, `strings:`, `nameDisplayOrder:`, `theme:`, `sourceLocation:`, `currentExpandedDetails:`, and `getPreloadedResource:` intact.

Replace the existing block:

```swift
                    if let newNode = item.node(context: messageItem.context, strings: messageItem.presentationData.strings, nameDisplayOrder: messageItem.presentationData.nameDisplayOrder, theme: pageTheme, sourceLocation: sourceLocation, openMedia: { [weak self] media in
                        let _ = self
                        //self?.openMedia(media)
                    }, longPressMedia: { [weak self] media in
                        //self?.longPressMedia(media)
                        let _ = self
                    }, activatePinchPreview: { [weak self] sourceNode in
                        /*guard let strongSelf = self, let controller = strongSelf.controller else {
                            return
                        }
                        let pinchController = makePinchController(sourceNode: sourceNode, getContentAreaInScreenSpace: {
                            guard let strongSelf = self else {
                                return CGRect()
                            }

                            let localRect = CGRect(origin: CGPoint(x: 0.0, y: strongSelf.navigationBar.frame.maxY), size: CGSize(width: strongSelf.bounds.width, height: strongSelf.bounds.height - strongSelf.navigationBar.frame.maxY))
                            return strongSelf.view.convert(localRect, to: nil)
                        })
                        controller.window?.presentInGlobalOverlay(pinchController)*/
                        let _ = self
                    }, pinchPreviewFinished: { [weak self] itemNode in
                        /*guard let strongSelf = self else {
                            return
                        }
                        for (_, listItemNode) in strongSelf.visibleItemsWithNodes {
                            if let listItemNode = listItemNode as? InstantPagePeerReferenceNode {
                                if listItemNode.frame.intersects(itemNode.frame) && listItemNode.frame.maxY <= itemNode.frame.maxY + 2.0 {
                                    listItemNode.layer.animateAlpha(from: 0.0, to: listItemNode.alpha, duration: 0.25)
                                    break
                                }
                            }
                        }*/
                        let _ = self
                    }, openPeer: { [weak self] peerId in
                        let _ = self
                        //self?.openPeer(peerId)
                    }, openUrl: { [weak self] url in
                        let _ = self
                        //self?.openUrl(url)
                    }, updateWebEmbedHeight: { [weak self] height in
                        let _ = self
                        //self?.updateWebEmbedHeight(embedIndex, height)
                    }, updateDetailsExpanded: { [weak self] expanded in
                        let _ = self
                        //self?.updateDetailsExpanded(detailsIndex, expanded)
                    }, currentExpandedDetails: self.currentExpandedDetails, getPreloadedResource: { _ in return nil }) {
```

With:

```swift
                    if let newNode = item.node(context: messageItem.context, strings: messageItem.presentationData.strings, nameDisplayOrder: messageItem.presentationData.nameDisplayOrder, theme: pageTheme, sourceLocation: sourceLocation, openMedia: { _ in
                        // TODO: media handling — out of scope for link wiring
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
```

Notes on this block:
- `openPeer` parameter is `(EnginePeer) -> Void` (verified against `InstantPageItem.swift:18`) — name it `peer`, not `peerId`.
- `openUrl` parameter is `(InstantPageUrlItem) -> Void` — name it `urlItem` to disambiguate from the outer URL string.
- The same-page-anchor short-circuit calls the empty `scrollToAnchor` stub so future implementation is single-point.
- `urlItem.webpageId != nil` is mapped to `allowInlineWebpageResolution` because the IV's `webpageId` hint signals "this URL was authored as a referenced webpage" — the same intent as the chat flag.
- `concealed: false` for item-emitted URLs (item nodes only emit clearly-typed link items, not free-form anchor-text mismatches). The text-tap path in Task 4 uses `concealed: true` per spec.

- [ ] **Step 2: Build to verify**

```sh
source ~/.zshrc 2>/dev/null; python3 build-system/Make/Make.py --overrideXcodeVersion --cacheDir ~/telegram-bazel-cache build --configurationPath build-system/appstore-configuration.json --gitCodesigningRepository git@gitlab.com:peter-iakovlev/fastlanematch.git --gitCodesigningType development --gitCodesigningUseCurrent --buildNumber=1 --configuration=debug_sim_arm64 --continueOnError
```

Expected: build succeeds. If a closure-parameter type mismatch is reported, re-check `InstantPageItem.swift:18` for the canonical signature.

- [ ] **Step 3: Commit**

```sh
git add submodules/TelegramUI/Components/Chat/ChatMessageRichDataBubbleContentNode/Sources/ChatMessageRichDataBubbleContentNode.swift
git commit -m "Rich bubble: route item-level openPeer/openUrl to controllerInteraction"
```

---

### Task 4: Implement URL tap detection, highlight feedback, and `tapActionAtPoint`

Add the tap-detection helpers, the rect-translation helper, the `makeActivate` factory, and the `updateLinkProgressState` view-state applier. Then rewrite `tapActionAtPoint` to use them. This is the largest task; it must land atomically because the helpers and the rewritten `tapActionAtPoint` reference each other.

**Files:**
- Modify: `submodules/TelegramUI/Components/Chat/ChatMessageRichDataBubbleContentNode/Sources/ChatMessageRichDataBubbleContentNode.swift`

- [ ] **Step 1: Replace `tapActionAtPoint` and add tap-detection helpers**

Locate the existing `tapActionAtPoint` (around lines 403–442 with its commented-out `makeActivate` block) and replace the entire method. Then add the new helpers immediately afterward (so they live alongside the related logic).

Replace the existing method body:

```swift
    override public func tapActionAtPoint(_ point: CGPoint, gesture: TapLongTapOrDoubleTapGesture, isEstimating: Bool) -> ChatMessageBubbleContentTapAction {
        if case .tap = gesture {
        } else {
            if let item = self.item, let subject = item.associatedData.subject, case .messageOptions = subject {
                return ChatMessageBubbleContentTapAction(content: .none)
            }
        }
        
        /*func makeActivate(_ urlRange: NSRange?) -> (() -> Promise<Bool>?)? {
            return { [weak self] in
                guard let self else {
                    return nil
                }
                
                let promise = Promise<Bool>()
                
                self.linkProgressDisposable?.dispose()
                
                if self.linkProgressRange != nil {
                    self.linkProgressRange = nil
                    self.updateLinkProgressState()
                }
                
                self.linkProgressDisposable = (promise.get() |> deliverOnMainQueue).startStrict(next: { [weak self] value in
                    guard let self else {
                        return
                    }
                    let updatedRange: NSRange? = value ? urlRange : nil
                    if self.linkProgressRange != updatedRange {
                        self.linkProgressRange = updatedRange
                        self.updateLinkProgressState()
                    }
                })
                
                return promise
            }
        }*/
        
        return ChatMessageBubbleContentTapAction(content: .none)
    }
```

With:

```swift
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
        let url = ChatMessageBubbleContentTapAction.Url(url: urlHit.urlItem.url, concealed: concealed)
        let rects = self.computeHighlightRects(item: urlHit.item, parentOffset: urlHit.parentOffset, localPoint: urlHit.localPoint)
        return ChatMessageBubbleContentTapAction(
            content: .url(url),
            rects: rects,
            activate: self.makeActivate(item: urlHit.item, parentOffset: urlHit.parentOffset, localPoint: urlHit.localPoint)
        )
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
```

Notes:
- Coordinate translation: incoming `point` is bubble-content-node-local. The bubble's `containerNode.frame.origin` is `(1, 1)` (set in the `apply` closure around line 96). Subtracting `(1, 1)` once gives container-local = layout-local coordinates. The layout origin is `(0, 0)` inside the container.
- `InstantPageScrollableItem`'s realized node would be the source of truth for content-offset, but the rich-bubble does not surface scroll state and chat instant-pages rarely contain scrollable items. Pass `CGPoint.zero` for v1; if a chat preview ever uses a scrollable, the tap detection will be slightly off but URL-hit will still resolve when the scroll is at top. (Out of scope for this change; document as a follow-up if it becomes user-visible.)
- `[weak item]` in the activate closure avoids retaining the InstantPageTextItem across asynchronous URL resolution. If layout reflows during resolution and the original item is gone, the highlight simply falls back to clearing.
- The `changed` comparison for `[CGRect]?` is spelled out longhand because optional `Equatable` conformance for `[CGRect]?` requires the explicit nil-vs-non-nil discrimination to satisfy `-warnings-as-errors` cleanly.

- [ ] **Step 2: Build to verify**

```sh
source ~/.zshrc 2>/dev/null; python3 build-system/Make/Make.py --overrideXcodeVersion --cacheDir ~/telegram-bazel-cache build --configurationPath build-system/appstore-configuration.json --gitCodesigningRepository git@gitlab.com:peter-iakovlev/fastlanematch.git --gitCodesigningType development --gitCodesigningUseCurrent --buildNumber=1 --configuration=debug_sim_arm64 --continueOnError
```

Expected: build succeeds.

Common likely errors and fixes:
- "Cannot find type `InstantPageTextItem` / `InstantPageScrollableItem` / `InstantPageDetailsItem` / `InstantPageDetailsNode` / `InstantPageUrlItem`" → all are public in `InstantPageUI`, already imported; rebuild without `--continueOnError` and re-check the exact error.
- "Cannot find `LinkHighlightingNode`" → it lives in `Display`, already imported.
- "`Promise` is ambiguous" → `Promise<Bool>` is from `SwiftSignalKit`, already imported.
- A `linkHighlightColor` access that errors with optional unwrap → the type is non-optional `UIColor` on `MessageBubbleColorComponents`; this should compile cleanly. If the compiler reports a different type, drop back to `?? UIColor.clear` and document.

- [ ] **Step 3: Commit**

```sh
git add submodules/TelegramUI/Components/Chat/ChatMessageRichDataBubbleContentNode/Sources/ChatMessageRichDataBubbleContentNode.swift
git commit -m "Rich bubble: implement URL tap detection and link-highlight feedback"
```

---

### Task 5: Manual smoke verification

There are no automated tests for chat UI in this codebase. The final task is a hands-on smoke test in the simulator.

**Files:** none modified. Verification only.

- [ ] **Step 1: Launch the app in the simulator**

The build command run in earlier tasks produces the app binary; launch via Xcode (open `Telegram-iOS.xcworkspace` if needed) or the Bazel-produced run target. Sign in to a real test account.

- [ ] **Step 2: Find or send a message with an instant-view preview**

In a chat, send a Telegram URL that has a rich instant-view preview (e.g. a Telegraph article URL: `https://telegra.ph/Test-page-12-31`, or any t.me link that produces an inline IV preview). The preview should render inside the chat bubble using the rich-data layout (multiple text/image tiles inside one bubble).

- [ ] **Step 3: Tap a URL inside the inline IV preview**

A standard URL link inside the preview text:
- Should highlight (semi-transparent rounded rectangle in the bubble's link-highlight color) for the duration of URL resolution.
- Should then route through the chat's URL handler — opening an in-app webview, an external browser, or a peer/chat depending on the URL.

- [ ] **Step 4: Tap a same-page anchor (if available)**

Some IV pages contain intra-page anchors like `#section-1`. Tapping such a link should fire the empty `scrollToAnchor` stub — observable as: no navigation, no error, no highlight, no external browser. (The TODO is logged for future work.)

- [ ] **Step 5: Long-press a URL**

A long-press on a URL inside the inline preview should trigger the chat's default URL long-press menu (Open / Copy / Share via the standard `controllerInteraction.longTap` path provided by the bubble framework for `.url` taps). The bubble's own custom long-press action sheet is out of scope for this change.

- [ ] **Step 6: Sign-off**

If steps 3–5 behave as described, the change is complete. If a step fails, capture: the URL used, observed behavior, and any console output. Common deviations:
- Highlight not appearing → confirm `containerNode` insertion order; the highlight node sits at index 0 below tiles, and tile background must be `.clear` (verify in `InstantPageTileNode`).
- URL resolves to nothing → confirm the upstream chat is correctly forwarding `controllerInteraction.openUrl` (this is the same wiring used by every other chat bubble).
- Anchor tap routes externally → confirm `currentLoadedWebpage()?.url == split.base` is matching; instant-page URLs sometimes carry trailing slashes in source vs. anchor links.

---

## Self-review

**Spec coverage:**
- Spec §"New private state" → Task 2 Step 1.
- Spec §"deinit disposes" → Task 2 Step 2.
- Spec §"Tap detection" → Task 4 Step 1 (textItemAtLocation, urlForTapLocation).
- Spec §"`tapActionAtPoint` body" → Task 4 Step 1 (full rewrite).
- Spec §"Concealed flag" default `true` → Task 4 Step 1 inline comment.
- Spec §"Highlight feedback" (`makeActivate`, `computeHighlightRects`, `updateLinkProgressState`) → Task 4 Step 1.
- Spec §"Item-callback wiring" → Task 3 Step 1.
- Spec §"Helpers" (`splitAnchor`, `currentLoadedWebpage`, `scrollToAnchor`) → Task 2 Step 3.
- Spec §"Verification" → Task 5 (manual smoke).
- Spec §"Out of scope" stays out of scope; no tasks added.

All sections covered.

**Placeholder scan:** TODO markers exist *only* inside the generated stub callbacks (intentional, per spec) and in the body of `scrollToAnchor` (intentional placeholder). No "TBD"/"fill in details"/"similar to Task N" present.

**Type consistency:**
- `InstantPageTextItem`, `InstantPageUrlItem`, `InstantPageScrollableItem`, `InstantPageDetailsItem`, `InstantPageDetailsNode` — all referenced consistently across tasks.
- `EnginePeer` — implicit via `openPeer` callback signature (verified against `InstantPageItem.swift:18`).
- `ChatControllerInteraction.OpenUrl` initializer parameters (`url:concealed:external:message:allowInlineWebpageResolution:progress:`) — verified against `ChatControllerInteraction.swift:151`.
- `LinkHighlightingNode(color:)` and `updateRects(_:color:)` — verified against `Display/Source/LinkHighlightingNode.swift:334,346`.
- `splitAnchor` returns `(base: String, anchor: String?)`; consumers in Task 3 Step 1 and Task 4 Step 1 destructure with `let split = self.splitAnchor(...)` then access `split.base` / `split.anchor` — consistent.
- `currentLoadedWebpage()` returns `TelegramMediaWebpageLoadedContent?`; consumers use `webpage.url` which is a property of that type — consistent with the existing usage pattern at line 67 of the file.
- `urlForTapLocation` return tuple labels: `(item, urlItem, parentOffset, localPoint)`. Consumed by `tapActionAtPoint` via `urlHit.item`, `urlHit.urlItem`, `urlHit.parentOffset`, `urlHit.localPoint` — consistent.
- `computeHighlightRects` and `makeActivate` both take `(item:parentOffset:localPoint:)` — consistent.
