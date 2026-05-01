# Instant-page link handling in `ChatMessageRichDataBubbleContentNode`

## Context

`ChatMessageRichDataBubbleContentNode` renders a webpage's `instantPage` inline inside a chat bubble, by reusing the same `InstantPageLayout`/`InstantPageTile`/`InstantPageNode` machinery the full-screen instant view uses. Today the layout, tiles, and item nodes are wired up correctly, but every interactive callback (`openUrl`, `openPeer`, `openMedia`, …) on the realized item nodes is a commented stub, and `tapActionAtPoint` always returns `.none`. As a result, taps on URLs inside the inline preview do nothing.

The full-screen instant view (`submodules/InstantPageUI/Sources/InstantPageControllerNode.swift`) handles URL taps by walking the layout to find the `InstantPageTextItem` under the tap location, asking it for `urlAttribute(at:)`, and then routing the resulting `InstantPageUrlItem` through its own `openUrl(_:)` resolver. Same-page anchors are handled inline via `scrollToAnchor(_:)`.

Chat text bubbles handle URL taps via `ChatMessageBubbleContentTapAction(content: .url(...), rects:, activate:)`. The `activate` closure returns a `Promise<Bool>` driven by upstream URL resolution; while it's `true` the bubble shows a `LinkHighlightingNode` overlay so users get press-feedback.

## Goal

Wire URL tap handling and link-highlight feedback into `ChatMessageRichDataBubbleContentNode`, plus stubbed handlers for intra-page anchor scrolling. Item-level `openUrl`/`openPeer` callbacks emitted by realized `InstantPageNode`s also route to the chat's `controllerInteraction`.

Out of scope: media taps, pinch preview, embed height updates, details expansion, long-press action-sheet (Open / Copy / Add to Reading List), and the actual implementation of intra-page anchor scrolling — these stay as no-op stubs and can land as follow-ups.

## Design

### File touched

`submodules/TelegramUI/Components/Chat/ChatMessageRichDataBubbleContentNode/Sources/ChatMessageRichDataBubbleContentNode.swift` (only).

### New private state

```
private var linkProgressDisposable: Disposable?
private var linkProgressRects: [CGRect]?
private var linkHighlightingNode: LinkHighlightingNode?
```

`deinit` disposes `linkProgressDisposable`.

### Tap detection

Two private helpers, modelled on `InstantPageControllerNode`:

```
private func textItemAtLocation(_ point: CGPoint) -> (InstantPageTextItem, CGPoint)?
private func urlForTapLocation(_ point: CGPoint)
    -> (item: InstantPageTextItem, urlItem: InstantPageUrlItem, localPoint: CGPoint)?
```

- The incoming `point` is in the bubble-content-node coordinate system. The helpers subtract the `containerNode` offset `(1.0, 1.0)` once on entry, then walk `currentPageLayout?.layout.items`.
- Top-level `InstantPageTextItem`s, `InstantPageScrollableItem` (delegates to its own `textItemAtLocation` accounting for content offset), and `InstantPageDetailsItem` (looks up the realized `InstantPageDetailsNode` via `visibleItemsWithNodes` and queries its nested layout) are all supported — same coverage as the IV.
- `urlForTapLocation` calls `item.urlAttribute(at:)`. Returns the matched item, the `InstantPageUrlItem`, and the item-local point. The local point is what `linkSelectionRects(at:)` consumes when computing highlight rects.

### `tapActionAtPoint` body

Skeleton (existing `messageOptions` early-return is preserved):

```
override public func tapActionAtPoint(...) -> ChatMessageBubbleContentTapAction {
    if case .tap = gesture {
    } else {
        if let item = self.item, let subject = item.associatedData.subject, case .messageOptions = subject {
            return ChatMessageBubbleContentTapAction(content: .none)
        }
    }

    guard let urlHit = self.urlForTapLocation(point) else {
        return ChatMessageBubbleContentTapAction(content: .none)
    }

    let (baseUrl, anchor) = splitAnchor(urlHit.urlItem.url)
    if let webpage = self.currentLoadedWebpage(), webpage.url == baseUrl, let anchor {
        return ChatMessageBubbleContentTapAction(content: .custom({ [weak self] in
            self?.scrollToAnchor(anchor)
        }))
    }

    let concealed = true // see "Concealed flag" note below
    let url = ChatMessageBubbleContentTapAction.Url(url: urlHit.urlItem.url, concealed: concealed)
    let rects = self.computeHighlightRects(item: urlHit.item, localPoint: urlHit.localPoint)
    return ChatMessageBubbleContentTapAction(
        content: .url(url),
        rects: rects,
        activate: self.makeActivate(item: urlHit.item, localPoint: urlHit.localPoint)
    )
}
```

**Concealed flag**: default to `concealed = true` for v1. Reason: `InstantPageTextItem` does not expose a clean "attribute substring with range" API the way the chat text node does, so we cannot easily compare displayed link text to its target URL. `true` is the safer (more disclosure) default — chat will show a confirmation if the visible text and resolved URL differ. If during implementation a clean substring path emerges, switch to `doesUrlMatchText(url:text:fullText:)` analogously to text-bubble.

### Highlight feedback

`makeActivate(item:localPoint:)` mirrors the text-bubble pattern:

```
private func makeActivate(item: InstantPageTextItem, localPoint: CGPoint) -> (() -> Promise<Bool>?)? {
    return { [weak self] in
        guard let self else { return nil }
        let promise = Promise<Bool>()
        self.linkProgressDisposable?.dispose()
        if self.linkProgressRects != nil {
            self.linkProgressRects = nil
            self.updateLinkProgressState()
        }
        self.linkProgressDisposable = (promise.get() |> deliverOnMainQueue).startStrict(next: { [weak self] value in
            guard let self else { return }
            let updated: [CGRect]? = value
                ? self.computeHighlightRects(item: item, localPoint: localPoint)
                : nil
            if self.linkProgressRects != updated {
                self.linkProgressRects = updated
                self.updateLinkProgressState()
            }
        })
        return promise
    }
}
```

`computeHighlightRects(item:localPoint:)`:
- Calls `item.linkSelectionRects(at: localPoint)` — already public on `InstantPageTextItem`, returns the URL run's line rects in item-local coords.
- Translates each rect into `containerNode`-local coords by adding `item.frame.origin` plus any parent offset captured at hit-test time (zero for top-level items; the offset returned by `textItemAtLocation` for items nested under scrollables/details).

`updateLinkProgressState()`:
- If `linkProgressRects` is non-nil and non-empty: lazily create `linkHighlightingNode` (`LinkHighlightingNode(color: incoming-or-outgoing linkHighlightColor)` derived from `self.item?.message.effectivelyIncoming(...)`), inserted into `containerNode` at index 0 (below all tiles). Set its frame to `containerNode.bounds`. Call `updateRects(rects)`.
- Otherwise: fade out the existing `linkHighlightingNode` (alpha 1→0 over 0.18s, remove on completion) and clear the field.

Insertion order: rich-bubble tiles use `backgroundColor: .clear`, so a highlighting node positioned below them is visible through. Tiles are added with `insertSubnode(_, at: 0)` / `aboveSubnode:` — inserting the highlight at index 0 keeps it underneath every tile but inside the same `containerNode` clip region.

### Item-callback wiring (inside `item.node(...)`)

The currently stubbed callbacks become:

```
openMedia: { _ in /* TODO */ },
longPressMedia: { _ in /* TODO */ },
activatePinchPreview: { _ in /* TODO */ },
pinchPreviewFinished: { _ in /* TODO */ },
openPeer: { [weak self] peer in
    guard let self, let item = self.item else { return }
    item.controllerInteraction.openPeer(peer, .chat(textInputState: nil, subject: nil, peekData: nil), nil, .default)
},
openUrl: { [weak self] urlItem in
    guard let self, let item = self.item else { return }
    let (baseUrl, anchor) = splitAnchor(urlItem.url)
    if let webpage = self.currentLoadedWebpage(), webpage.url == baseUrl, let anchor {
        self.scrollToAnchor(anchor)
        return
    }
    item.controllerInteraction.openUrl(ChatControllerInteraction.OpenUrl(
        url: urlItem.url,
        concealed: false,
        message: item.message,
        allowInlineWebpageResolution: urlItem.webpageId != nil
    ))
},
updateWebEmbedHeight: { _ in },
updateDetailsExpanded: { _ in },
```

- `openPeer` matches the IV's default routing — open the chat for the peer.
- `openUrl` honors the same-page-anchor stub, so item-emitted URL taps share the placeholder hook with text-tap routing.
- `urlItem.webpageId != nil` is mapped to `allowInlineWebpageResolution`. `InstantPageUrlItem.webpageId` is the IV's hint that the URL was authored as a referenced webpage, which is the same intent the chat flag captures.

### Helpers

```
private func splitAnchor(_ url: String) -> (base: String, anchor: String?)
private func currentLoadedWebpage() -> TelegramMediaWebpageLoadedContent?
private func scrollToAnchor(_ anchor: String) {
    // TODO: implement intra-page anchor scrolling
}
```

`splitAnchor` extracts the `#fragment` from a URL using the same approach as `InstantPageControllerNode.openUrl` (find `#`, percent-decode the suffix, slice the prefix). `currentLoadedWebpage` pulls `case .Loaded(content)` out of the first `TelegramMediaWebpage` on `self.item?.message.media`.

## Verification

- Build the app with `python3 build-system/Make/Make.py … build … --configuration=debug_sim_arm64` (no unit tests in this project).
- Manual test: send a message containing a t.me link with an instant-view preview. Tap a URL inside the rich-data preview bubble — it should route to the chat's URL handler (open inline webview / external browser / peer chat as appropriate). Long-press should fall through to the existing chat URL long-press menu (the bubble framework provides this for `.url` taps with `hasLongTapAction: true`, the default). Tapping a same-page anchor in the preview should hit the empty `scrollToAnchor` stub (no-op for now).
- Visual: while a URL is resolving, the URL run should be highlighted with a `LinkHighlightingNode` rectangle in the bubble's link-highlight color. The highlight should fade out on completion or cancellation.

## Open follow-ups (not in this spec)

- Implement `scrollToAnchor` (likely "open the full instant view at this anchor", since the inline rich bubble has no scroll view).
- Wire `openMedia` / `longPressMedia` / `activatePinchPreview` / `updateDetailsExpanded` / `updateWebEmbedHeight`.
- Long-press action sheet (Open / Copy / Add to Reading List) for URLs inside the inline preview, mirroring the IV.
