# ChatMessageRichDataBubbleContentNode.scrollToAnchor

## Background

`ChatMessageRichDataBubbleContentNode` renders a webpage's `instantPage` inline inside a chat message bubble (the same layout/tile machinery as `InstantPageControllerNode`, but embedded as a content node of `ChatMessageBubbleItemNode`).

The bubble already detects in-page anchor links (URL with a `#fragment`) when its base URL matches the current loaded webpage and routes them to a private `scrollToAnchor(_ anchor: String)`. That method is a stub today:

```swift
private func scrollToAnchor(_ anchor: String) {
    guard let item = self.item else { return }
    item.controllerInteraction.scrollToMessageId(item.message.index, 0.0)
}
```

`ChatHistoryListNode.scrollToMessage(index:offset:)` ignores the offset, so the anchor name is dropped and the bubble simply scrolls to the message top. Tapping a footnote / section link inside a long instant-page bubble does nothing useful when the target is below the fold.

## Goal

When an in-page anchor inside a rich-data bubble is tapped, scroll the chat history so the anchor's line lands at the top of the visible content area.

## Non-goals (explicitly deferred)

- **Reference popup**: `InstantPageControllerNode.scrollToAnchor` shows `InstantPageReferenceController` as an overlay when the anchor is a footnote-style "reference" (text item, non-empty anchor text). We will simply scroll to the line containing the reference instead. No popup.
- **Collapsed details expansion**: The bubble already no-ops `updateDetailsExpanded`, so the runtime never toggles `InstantPageDetailsItem` state. We compute the rect for anchors inside details items as if they were expanded; no expansion side-effect is performed. Worst case for a layout-collapsed details anchor is a slightly-off scroll target — acceptable for v1.

## Approach

Add a `getAnchorRect(anchor:)` resolver on the bubble (mirrors `getQuoteRect`'s shape: base no-op, rich-data override walks the layout, bubble item forwards to content nodes). The chat controller then uses `forEachVisibleItemNode` to find the bubble being scrolled to (it is by definition partially visible — the user tapped a link in it), reads the anchor's item-local y, and dispatches `historyNode.scrollToMessage(... scrollPosition: .bottom(anchorY))`. `.bottom(additionalOffset)` places the item so its frame.maxY lands at `(visibleSize.height - insets.bottom) + additionalOffset`; with `additionalOffset = anchorY` (item-local-y of the anchor's top edge), the anchor renders at the visual top of the chat's content area regardless of whether the item is short or tall. (`.center(.custom)` was the original pick but is bypassed for items that fit in the content area, and the rotation maps "list-coord low" to "visual bottom" in chat lists, so `.bottom` is the more uniform primitive here.)

### Components

#### 1. `ChatMessageBubbleContentNode.getAnchorRect(anchor:)` — base, default `nil`

Add an `open func getAnchorRect(anchor: String) -> CGRect? { return nil }` to the base class so callers don't need to type-test every content node.

#### 2. `ChatMessageRichDataBubbleContentNode.getAnchorRect(anchor:)` — override

Walk `self.currentPageLayout?.layout.items`, mirroring the cases in `InstantPageControllerNode.findAnchorItem`:
- `InstantPageAnchorItem` with matching `anchor` → return a 1pt rect at the item's `frame.origin`.
- `InstantPageTextItem`, `item.anchors[anchor] == (lineIndex, _)` → return the rect of `item.lines[lineIndex].frame`, offset by `item.frame.origin`.
- `InstantPageTableItem`, `item.anchors[anchor] == (offset, _)` → return a 1pt-tall row-width rect at `item.frame.origin + (0, offset)`.
- `InstantPageDetailsItem` → recurse into `item.items` with `baseY` increased by `item.frame.minY + item.titleHeight` (inner items live below the title bar; mirrors `InstantPageDetailsNode.linkSelectionRects`). Per non-goal #2, no expand side-effect.

The walk returns coordinates in *layout space* (= `containerNode`-local). The bubble's `containerNode` is offset `(1, 1)` from the bubble content node, so add `(1, 1)` before returning. The returned rect is in `ChatMessageRichDataBubbleContentNode`'s own coordinate space (its `view`).

If no anchor matches anywhere in the tree, return `nil`.

#### 3. `ChatMessageBubbleItemNode.getAnchorRect(anchor:)` — public

Add next to the existing `getQuoteRect(quote:offset:)`. Iterate `self.contentNodes`; for each, call `contentNode.getAnchorRect(anchor:)` and, if non-nil, return `contentNode.view.convert(rect, to: self.view)`. Return `nil` if no content node knows the anchor.

#### 4. `ChatControllerInteraction.scrollToMessageIdWithAnchor` — new closure

Add a new public closure on `ChatControllerInteraction`:

```swift
public let scrollToMessageIdWithAnchor: (MessageIndex, String) -> Void
```

Wire through the initializer (parameter, assignment) alongside the existing `scrollToMessageId`. The existing `scrollToMessageId(MessageIndex, CGFloat)` closure stays untouched — its 7 callers (incl. 6 no-op stubs) need no signature change.

Add no-op stubs `scrollToMessageIdWithAnchor: { _, _ in }` at the six existing no-op sites:
- `BrowserUI/Sources/BrowserBookmarksScreen.swift`
- `Components/Chat/ChatRecentActionsController/Sources/ChatRecentActionsControllerNode.swift`
- `Components/Chat/ChatSendAudioMessageContextPreview/Sources/ChatSendAudioMessageContextPreview.swift`
- `Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreen.swift`
- `TelegramUI/Sources/OverlayAudioPlayerControllerNode.swift`
- `TelegramUI/Sources/SharedAccountContext.swift`

#### 5. Real implementation in `ChatController.swift`

Next to the existing `scrollToMessageId:` argument in the `ChatControllerInteraction(...)` construction, add:

```swift
scrollToMessageIdWithAnchor: { [weak self] index, anchor in
    guard let self else { return }
    var anchorY: CGFloat?
    self.chatDisplayNode.historyNode.forEachVisibleItemNode { itemNode in
        guard anchorY == nil else { return }
        if let itemNode = itemNode as? ChatMessageBubbleItemNode,
           itemNode.item?.message.id == index.id,
           let rect = itemNode.getAnchorRect(anchor: anchor) {
            anchorY = rect.minY
        }
    }
    if let anchorY {
        self.chatDisplayNode.historyNode.scrollToMessage(
            from: index, to: index,
            animated: true, highlight: false,
            scrollPosition: .bottom(anchorY)
        )
    } else {
        self.chatDisplayNode.historyNode.scrollToMessage(index: index)
    }
}
```

`ChatHistoryListNode.scrollToMessage(from:to:animated:highlight:quote:subject:scrollPosition:setupReply:)` already accepts `scrollPosition` and routes it through `MessageHistoryScrollToSubject` → `ListViewScrollToItem.position`. The `.bottom(additionalOffset)` formula sets `frame.maxY' = (visibleSize.height - insets.bottom) + additionalOffset`; with `additionalOffset = anchorY` (the anchor's item-local y in pre-transform coords), the chat list — rotated 180° at the layer — renders the anchor at the visual top of the content area. The `forEachVisibleItemNode` walk is safe because tapping the in-page anchor link requires the bubble to be at least partially visible.

#### 6. Replace the `scrollToAnchor` stub

In `ChatMessageRichDataBubbleContentNode.swift`:

```swift
private func scrollToAnchor(_ anchor: String) {
    guard let item = self.item else { return }
    if anchor.isEmpty {
        item.controllerInteraction.scrollToMessageId(item.message.index, 0.0)
    } else {
        item.controllerInteraction.scrollToMessageIdWithAnchor(item.message.index, anchor)
    }
}
```

Empty anchor (the `#` with no fragment case) keeps the existing "scroll to message top" behavior.

## Files touched

| File | Change |
|---|---|
| `submodules/TelegramUI/Components/Chat/ChatMessageBubbleContentNode/Sources/ChatMessageBubbleContentNode.swift` | Add `open func getAnchorRect(anchor:) -> CGRect?` returning `nil`. |
| `submodules/TelegramUI/Components/Chat/ChatMessageRichDataBubbleContentNode/Sources/ChatMessageRichDataBubbleContentNode.swift` | Override `getAnchorRect`; rewrite `scrollToAnchor` body. |
| `submodules/TelegramUI/Components/Chat/ChatMessageBubbleItemNode/Sources/ChatMessageBubbleItemNode.swift` | Add public `getAnchorRect(anchor:)`. |
| `submodules/TelegramUI/Components/ChatControllerInteraction/Sources/ChatControllerInteraction.swift` | New `scrollToMessageIdWithAnchor` field + init param + assignment. |
| `submodules/TelegramUI/Sources/ChatController.swift` | Real implementation of the closure. |
| 6 no-op stub sites | Add `scrollToMessageIdWithAnchor: { _, _ in }` next to existing stub. |

## What is *not* changed

- No new types in `Display/`, `AccountContext/`, or `TelegramCore/`.
- No changes to `MessageHistoryScrollToSubject` or `ChatHistoryLocation`.
- No changes to `InstantPageUI/` (the layout-walking logic is replicated in the rich-data bubble file rather than exported, since it's both small and specialized for the embedded layout).
- No changes to the existing `scrollToMessageId(_, CGFloat)` closure or its 7 call sites' signatures.

## Verification

There are no unit tests in this project. Verification is a full Bazel build:

```sh
source ~/.zshrc 2>/dev/null; \
python3 build-system/Make/Make.py --overrideXcodeVersion --cacheDir ~/telegram-bazel-cache build \
  --configurationPath build-system/appstore-configuration.json \
  --gitCodesigningRepository git@gitlab.com:peter-iakovlev/fastlanematch.git \
  --gitCodesigningType development --gitCodesigningUseCurrent \
  --buildNumber=1 --configuration=debug_sim_arm64
```

Manual smoke test in the simulator: open a chat that contains a webpage message rendered as a rich-data bubble with an instant page that has internal anchors (e.g., a Wikipedia article with section links or footnote references). Tap a section link or footnote link; the chat should scroll so that the target line lands at the top of the visible content area.
