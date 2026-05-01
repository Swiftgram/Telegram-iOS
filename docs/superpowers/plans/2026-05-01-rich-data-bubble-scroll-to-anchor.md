# Rich-Data Bubble scrollToAnchor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `ChatMessageRichDataBubbleContentNode.scrollToAnchor` actually scroll the chat history so that an in-page anchor's line lands at the top of the visible content area.

**Architecture:** Mirror the existing `getQuoteRect` mechanism. The rich-data bubble exposes `getAnchorRect(anchor:)`, the bubble item node forwards to it. A new `ChatControllerInteraction.scrollToMessageIdWithAnchor` closure walks visible items via `forEachVisibleItemNode` (the bubble is necessarily at least partially visible because the user tapped a link in it), reads the anchor's item-local y, and routes through `ChatHistoryListNode.scrollToMessage(... scrollPosition: .bottom(anchorY))`. `.bottom` places the item so the anchor lands at the visual top of the content area; it works uniformly for short and tall items, where `.center(.custom)` is bypassed for items that fit in the content area.

**Tech Stack:** Swift, Bazel build, AsyncDisplayKit. No unit tests in this project — verification is a full Bazel build.

**Spec:** [docs/superpowers/specs/2026-05-01-rich-data-bubble-scroll-to-anchor-design.md](../specs/2026-05-01-rich-data-bubble-scroll-to-anchor-design.md)

**Build command (run after each task):**

```sh
source ~/.zshrc 2>/dev/null; \
python3 build-system/Make/Make.py --overrideXcodeVersion --cacheDir ~/telegram-bazel-cache build \
  --configurationPath build-system/appstore-configuration.json \
  --gitCodesigningRepository git@gitlab.com:peter-iakovlev/fastlanematch.git \
  --gitCodesigningType development --gitCodesigningUseCurrent \
  --buildNumber=1 --configuration=debug_sim_arm64
```

After Tasks 1–3 the build must be green; the feature is not yet live (no callers use the new methods). After Task 4 the new closure exists and is implemented but the bubble still routes through the old stub. After Task 5 the feature is live.

---

## Task 1: Add base `getAnchorRect` to `ChatMessageBubbleContentNode`

This makes `getAnchorRect(anchor:)` callable on every content node (returns `nil` by default) so the iteration in `ChatMessageBubbleItemNode` doesn't need a type-test.

**Files:**
- Modify: `submodules/TelegramUI/Components/Chat/ChatMessageBubbleContentNode/Sources/ChatMessageBubbleContentNode.swift`

- [ ] **Step 1: Add the base method**

Open the file. Find the existing `open func transitionNode(messageId:media:adjustRect:) -> (...)` definition (around line 261). Add a new method directly after its closing brace:

```swift
open func getAnchorRect(anchor: String) -> CGRect? {
    return nil
}
```

The result is that the file should contain, contiguously:

```swift
open func transitionNode(messageId: MessageId, media: Media, adjustRect: Bool) -> (ASDisplayNode, CGRect, () -> (UIView?, UIView?))? {
    return nil
}

open func getAnchorRect(anchor: String) -> CGRect? {
    return nil
}

open func updateHiddenMedia(_ media: [Media]?) -> Bool {
    return false
}
```

- [ ] **Step 2: Build**

Run the build command at the top of this plan.
Expected: build succeeds.

- [ ] **Step 3: Commit**

```sh
git add submodules/TelegramUI/Components/Chat/ChatMessageBubbleContentNode/Sources/ChatMessageBubbleContentNode.swift
git commit -m "$(cat <<'EOF'
ChatMessageBubbleContentNode: add base getAnchorRect

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Override `getAnchorRect` in `ChatMessageRichDataBubbleContentNode`

Walks the cached instant-page layout and returns the rect of an anchor (in the bubble content node's coordinate space) without triggering any side-effects.

**Files:**
- Modify: `submodules/TelegramUI/Components/Chat/ChatMessageRichDataBubbleContentNode/Sources/ChatMessageRichDataBubbleContentNode.swift`

- [ ] **Step 1: Add the override and recursive helper**

Open the file. Find the existing `private func splitAnchor(_ url: String)` (around line 774). Insert two new methods directly above it (so the new public override comes before the private string helpers but after `findInstantPageMedia`):

```swift
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
```

Note: the existing file already imports `InstantPageUI`, so `InstantPageItem`, `InstantPageAnchorItem`, `InstantPageTextItem`, `InstantPageTableItem`, and `InstantPageDetailsItem` resolve. `InstantPageTextItem.anchors` is typed `[String: (Int, Bool)]`, `InstantPageTableItem.anchors` is `[String: (CGFloat, Bool)]` — destructure accordingly.

- [ ] **Step 2: Build**

Run the build command.
Expected: build succeeds.

- [ ] **Step 3: Commit**

```sh
git add submodules/TelegramUI/Components/Chat/ChatMessageRichDataBubbleContentNode/Sources/ChatMessageRichDataBubbleContentNode.swift
git commit -m "$(cat <<'EOF'
Rich bubble: add getAnchorRect override

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Forward `getAnchorRect` from `ChatMessageBubbleItemNode`

Iterates content nodes and converts the rect to the bubble item node's coordinate space. Mirrors the existing `getQuoteRect` shape exactly.

**Files:**
- Modify: `submodules/TelegramUI/Components/Chat/ChatMessageBubbleItemNode/Sources/ChatMessageBubbleItemNode.swift`

- [ ] **Step 1: Add the public forwarder**

Open the file. Find the existing `public func getQuoteRect(quote: String, offset: Int?) -> CGRect?` (around line 7237). Insert a new method directly after its closing brace, before `public func getInnerReplySubjectRect(...)`:

```swift
public func getAnchorRect(anchor: String) -> CGRect? {
    for contentNode in self.contentNodes {
        if let result = contentNode.getAnchorRect(anchor: anchor) {
            return contentNode.view.convert(result, to: self.view)
        }
    }
    return nil
}
```

- [ ] **Step 2: Build**

Run the build command.
Expected: build succeeds.

- [ ] **Step 3: Commit**

```sh
git add submodules/TelegramUI/Components/Chat/ChatMessageBubbleItemNode/Sources/ChatMessageBubbleItemNode.swift
git commit -m "$(cat <<'EOF'
Bubble item: forward getAnchorRect to content nodes

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Add `scrollToMessageIdWithAnchor` closure (declaration + 7 sites)

Adds the new `(MessageIndex, String) -> Void` closure to `ChatControllerInteraction`, the real implementation in `ChatController.swift`, and no-op stubs at the six other call sites. After this task the build is green and the closure works end-to-end on the chat-controller side; the rich-data bubble still routes through the old stub so the feature is not yet live.

**Files (8 edits):**
- Modify: `submodules/TelegramUI/Components/ChatControllerInteraction/Sources/ChatControllerInteraction.swift` (3 edits: field, init param, assignment)
- Modify: `submodules/TelegramUI/Sources/ChatController.swift` (real implementation)
- Modify: `submodules/BrowserUI/Sources/BrowserBookmarksScreen.swift` (no-op stub)
- Modify: `submodules/TelegramUI/Components/Chat/ChatRecentActionsController/Sources/ChatRecentActionsControllerNode.swift` (no-op stub)
- Modify: `submodules/TelegramUI/Components/Chat/ChatSendAudioMessageContextPreview/Sources/ChatSendAudioMessageContextPreview.swift` (no-op stub)
- Modify: `submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreen.swift` (no-op stub)
- Modify: `submodules/TelegramUI/Sources/OverlayAudioPlayerControllerNode.swift` (no-op stub)
- Modify: `submodules/TelegramUI/Sources/SharedAccountContext.swift` (no-op stub)

- [ ] **Step 1: Add the field on `ChatControllerInteraction`**

In `submodules/TelegramUI/Components/ChatControllerInteraction/Sources/ChatControllerInteraction.swift`, find:

```swift
public let scrollToMessageId: (MessageIndex, CGFloat) -> Void
```

(around line 311). Insert directly after it:

```swift
public let scrollToMessageIdWithAnchor: (MessageIndex, String) -> Void
```

- [ ] **Step 2: Add the init parameter**

In the same file, find the init parameter list (around line 490):

```swift
scrollToMessageId: @escaping (MessageIndex, CGFloat) -> Void,
```

Insert directly after it:

```swift
scrollToMessageIdWithAnchor: @escaping (MessageIndex, String) -> Void,
```

- [ ] **Step 3: Add the init assignment**

In the same file, find (around line 622):

```swift
self.scrollToMessageId = scrollToMessageId
```

Insert directly after it:

```swift
self.scrollToMessageIdWithAnchor = scrollToMessageIdWithAnchor
```

- [ ] **Step 4: Add real implementation in `ChatController.swift`**

In `submodules/TelegramUI/Sources/ChatController.swift`, find (around line 5397):

```swift
}, scrollToMessageId: { [weak self] index, offset in
    self?.chatDisplayNode.historyNode.scrollToMessage(index: index, offset: offset)
}, navigateToStory: { [weak self] message, storyId in
```

Insert a new closure between `scrollToMessageId` and `navigateToStory`:

```swift
}, scrollToMessageId: { [weak self] index, offset in
    self?.chatDisplayNode.historyNode.scrollToMessage(index: index, offset: offset)
}, scrollToMessageIdWithAnchor: { [weak self] index, anchor in
    guard let self else {
        return
    }
    var anchorY: CGFloat?
    self.chatDisplayNode.historyNode.forEachVisibleItemNode { itemNode in
        guard anchorY == nil else {
            return
        }
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
}, navigateToStory: { [weak self] message, storyId in
```

`scrollToMessage(from:to:animated:highlight:scrollPosition:)` is the existing public method on `ChatHistoryListNode` (declared at line 3585 in `ChatHistoryListNode.swift`); `quote`, `subject`, and `setupReply` use their default values. `ChatMessageBubbleItemNode` is already imported at the top of `ChatController.swift`. The `forEachVisibleItemNode` walk is sound because tapping the in-page anchor link requires the bubble to be at least partially visible.

- [ ] **Step 5: Add no-op stub in `BrowserBookmarksScreen.swift`**

In `submodules/BrowserUI/Sources/BrowserBookmarksScreen.swift`, find (around line 183):

```swift
}, scrollToMessageId: { _, _ in
```

Replace with:

```swift
}, scrollToMessageId: { _, _ in
}, scrollToMessageIdWithAnchor: { _, _ in
```

- [ ] **Step 6: Add no-op stub in `ChatRecentActionsControllerNode.swift`**

In `submodules/TelegramUI/Components/Chat/ChatRecentActionsController/Sources/ChatRecentActionsControllerNode.swift`, find (around line 660):

```swift
}, scrollToMessageId: { _, _ in
```

Replace with:

```swift
}, scrollToMessageId: { _, _ in
}, scrollToMessageIdWithAnchor: { _, _ in
```

- [ ] **Step 7: Add no-op stub in `ChatSendAudioMessageContextPreview.swift`**

In `submodules/TelegramUI/Components/Chat/ChatSendAudioMessageContextPreview/Sources/ChatSendAudioMessageContextPreview.swift`, find (around line 507):

```swift
}, scrollToMessageId: { _, _ in
```

Replace with:

```swift
}, scrollToMessageId: { _, _ in
}, scrollToMessageIdWithAnchor: { _, _ in
```

- [ ] **Step 8: Add no-op stub in `PeerInfoScreen.swift`**

In `submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreen.swift`, find (around line 1278):

```swift
}, scrollToMessageId: { _, _ in
```

Replace with:

```swift
}, scrollToMessageId: { _, _ in
}, scrollToMessageIdWithAnchor: { _, _ in
```

- [ ] **Step 9: Add no-op stub in `OverlayAudioPlayerControllerNode.swift`**

In `submodules/TelegramUI/Sources/OverlayAudioPlayerControllerNode.swift`, find (around line 252):

```swift
}, scrollToMessageId: { _, _ in
```

Replace with:

```swift
}, scrollToMessageId: { _, _ in
}, scrollToMessageIdWithAnchor: { _, _ in
```

- [ ] **Step 10: Add no-op stub in `SharedAccountContext.swift`**

In `submodules/TelegramUI/Sources/SharedAccountContext.swift`, find (around line 2565):

```swift
scrollToMessageId: { _, _ in
```

(Note: this site has no leading `}, ` because it is the first argument on its line — verify with `grep -n "scrollToMessageId:" submodules/TelegramUI/Sources/SharedAccountContext.swift`.)

Insert a new closure directly after the closing `}` of the `scrollToMessageId` stub. If the original looks like:

```swift
scrollToMessageId: { _, _ in
},
navigateToStory: { _, _ in
```

it should become:

```swift
scrollToMessageId: { _, _ in
},
scrollToMessageIdWithAnchor: { _, _ in
},
navigateToStory: { _, _ in
```

Match the surrounding indentation and trailing-comma style of the file.

- [ ] **Step 11: Build**

Run the build command.
Expected: build succeeds. Any compile error in this task means a stub site was missed or the closure type was mismatched — search for `scrollToMessageId:` again and confirm every site has a corresponding `scrollToMessageIdWithAnchor:`.

- [ ] **Step 12: Commit**

```sh
git add \
  submodules/TelegramUI/Components/ChatControllerInteraction/Sources/ChatControllerInteraction.swift \
  submodules/TelegramUI/Sources/ChatController.swift \
  submodules/BrowserUI/Sources/BrowserBookmarksScreen.swift \
  submodules/TelegramUI/Components/Chat/ChatRecentActionsController/Sources/ChatRecentActionsControllerNode.swift \
  submodules/TelegramUI/Components/Chat/ChatSendAudioMessageContextPreview/Sources/ChatSendAudioMessageContextPreview.swift \
  submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreen.swift \
  submodules/TelegramUI/Sources/OverlayAudioPlayerControllerNode.swift \
  submodules/TelegramUI/Sources/SharedAccountContext.swift
git commit -m "$(cat <<'EOF'
ChatControllerInteraction: add scrollToMessageIdWithAnchor closure

Routes through ChatHistoryListNode.scrollToMessage with a custom
.center(.custom) callback that asks the bubble item for the anchor
rect's midY. Six existing no-op interaction sites get matching
no-op stubs.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Wire up `scrollToAnchor` in the rich-data bubble

Replace the stub body so that taps on in-page anchor links actually scroll. After this task the feature is live end-to-end.

**Files:**
- Modify: `submodules/TelegramUI/Components/Chat/ChatMessageRichDataBubbleContentNode/Sources/ChatMessageRichDataBubbleContentNode.swift`

- [ ] **Step 1: Replace `scrollToAnchor` body**

In `ChatMessageRichDataBubbleContentNode.swift`, find (around line 796):

```swift
private func scrollToAnchor(_ anchor: String) {
    guard let item = self.item else {
        return
    }
    // 0.0 is offset
    item.controllerInteraction.scrollToMessageId(item.message.index, 0.0)
}
```

Replace with:

```swift
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
```

The empty-anchor branch keeps the existing "scroll to message top" behavior for `#` URLs with no fragment.

- [ ] **Step 2: Build**

Run the build command.
Expected: build succeeds.

- [ ] **Step 3: Manual smoke test**

This project has no unit tests. Smoke-test in the simulator:

1. Launch the app on the iOS simulator.
2. Open a chat that contains a webpage message rendered as a rich-data bubble. Good source: a Wikipedia article URL whose Telegram instant-page render contains in-page section/footnote links (e.g., the "Contents" section or the `[1]`-style citation links).
3. Tap a section/footnote link inside the bubble.
4. Expected: the chat scrolls so that the target line of the bubble is centered in the visible area. If the bubble is partially off-screen, the chat scrolls to bring the line into view.
5. Tap a `#`-only link (no fragment) if you can find one. Expected: chat scrolls to the message top (existing pre-task behavior preserved).

If the scroll doesn't land where expected, double-check the coord conversions in Task 2 (`+1, +1` for `containerNode` inset) and Task 3 (`contentNode.view.convert(rect, to: self.view)`).

- [ ] **Step 4: Commit**

```sh
git add submodules/TelegramUI/Components/Chat/ChatMessageRichDataBubbleContentNode/Sources/ChatMessageRichDataBubbleContentNode.swift
git commit -m "$(cat <<'EOF'
Rich bubble: scrollToAnchor scrolls to anchor's line

Empty anchor keeps the previous scroll-to-message-top behavior.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Done

All five tasks complete leaves:
- Each commit independently builds.
- The feature is live: tapping an in-page anchor link inside a rich-data bubble scrolls the chat to center the target line.
- Reference popups and details expansion are deferred (per spec).
