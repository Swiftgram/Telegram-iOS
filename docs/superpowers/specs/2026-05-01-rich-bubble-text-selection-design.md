# Text selection in `ChatMessageRichDataBubbleContentNode`

## Context

`ChatMessageRichDataBubbleContentNode` renders an instant-page preview inline inside a chat bubble using `InstantPageLayout`/`InstantPageTile`/`InstantPageNode`. Users can already tap URLs and tap media (gallery), but cannot select any of the article text inside the preview.

Two reference implementations exist:

- `ChatMessageTextBubbleContentNode` (`submodules/TelegramUI/Components/Chat/ChatMessageTextBubbleContentNode/Sources/...`) — uses `TextSelectionNode` (drag-handle / knob style, action menu via `controllerInteraction.performTextSelectionAction`). Selection is gated on the bubble entering context-preview mode (`updateIsExtractedToContextPreview(true)`). The text-bubble has a single `textNode` so `TextSelectionNode` wraps it directly.
- `InstantPageControllerNode` (`submodules/InstantPageUI/Sources/...`) — paragraph-granularity highlight + `ContextMenuController`. Long-tap on a paragraph selects the whole paragraph; no drag-handles.

The user picked the chat text-bubble model, gated only on context-preview mode. The structural challenge: rich-bubble has **many** `InstantPageTextItem`s spread across tiles, with no per-item rendering node — text is drawn directly into tile contexts via `CTLine`.

## Goal

Wire drag-handle text selection inside `ChatMessageRichDataBubbleContentNode`, available only in context-preview mode, with cross-paragraph selection across all `InstantPageTextItem`s in the visible layout. Action menu integrates Copy / Translate / Share / Speak / Look Up via `controllerInteraction.performTextSelectionAction`. Quote is disabled (the IV preview text is not part of `item.message.text`, which the quote feature references).

Out of scope: nested selection inside `InstantPageDetailsItem` / `InstantPageScrollableItem` (rich-bubble does not expand details or scroll inner content); selection during normal (non-preview) interaction; per-paragraph selection-only mode.

## Design

### Files touched

- **Modify:** `submodules/InstantPageUI/Sources/InstantPageTextItem.swift` — promote three accessors to public so a `TextNodeProtocol` adapter can build on top.
- **Create:** `submodules/InstantPageUI/Sources/InstantPageMultiTextAdapter.swift` — a `TextNodeProtocol`-conforming `ASDisplayNode` that aggregates multiple `InstantPageTextItem`s into a single character-indexed text view.
- **Modify:** `submodules/TelegramUI/Components/Chat/ChatMessageRichDataBubbleContentNode/BUILD` — add `//submodules/TextSelectionNode`.
- **Modify:** `submodules/TelegramUI/Components/Chat/ChatMessageRichDataBubbleContentNode/Sources/ChatMessageRichDataBubbleContentNode.swift` — add the `import`, two new ivars, and lifecycle hooks for entering / leaving context preview.

### API exposure on `InstantPageTextItem`

Three accessors become public:

```swift
public final class InstantPageTextItem: InstantPageItem {
    public let attributedString: NSAttributedString    // was `let` (package-private)
    // ...

    public func attributesAtPoint(_ point: CGPoint, orNearest: Bool) -> (Int, [NSAttributedString.Key: Any])?
    public func textRangeRects(in range: NSRange) -> (rects: [CGRect], start: TextRangeRectEdge, end: TextRangeRectEdge)?
}
```

- The new `attributesAtPoint(_:orNearest:)` extends the existing internal `attributesAtPoint(_:)`. When `orNearest == true` and no line directly contains the point, it picks the line with the smallest vertical distance to the point and runs `CTLineGetStringIndexForPosition` with the X clamped to that line's horizontal range. Mirrors what `TextNode.attributesAtPoint(orNearest:)` does. The existing internal `attributesAtPoint(_:)` is preserved (still used by `urlAttribute(at:)` and `linkSelectionRects(at:)`).
- The new `textRangeRects(in:)` wraps the existing internal `rangeRects(in:)`. It returns `Display.TextRangeRectEdge` (same `(x, y, height: CGFloat)` shape as the IV's local `InstantPageTextRangeRectEdge`). When the inner result has no edges (range maps to no rects), the public version returns `nil`.

The existing internal members are not renamed — only new public surface is added.

### `InstantPageMultiTextAdapter`

A `TextNodeProtocol`-conforming `ASDisplayNode` that aggregates multiple `InstantPageTextItem`s into a single character-indexed text view:

```swift
public final class InstantPageMultiTextAdapter: ASDisplayNode, TextNodeProtocol {
    private struct Entry {
        let item: InstantPageTextItem
        let charOffset: Int        // global char index where this item's text starts
        let frameOrigin: CGPoint   // item.frame.origin, in adapter-local coords
    }

    private let entries: [Entry]
    private let combinedString: NSAttributedString

    public init(items: [InstantPageTextItem])

    // TextNodeProtocol
    public var currentText: NSAttributedString? { combinedString }
    public func attributesAtPoint(_ point: CGPoint, orNearest: Bool) -> (Int, [NSAttributedString.Key: Any])?
    public func textRangeRects(in range: NSRange) -> (rects: [CGRect], start: TextRangeRectEdge, end: TextRangeRectEdge)?
}
```

**Construction.** `init(items:)` walks the list in document order. For each item:
1. Append `item.attributedString` to the running combined string.
2. Record `Entry(item, charOffset: combined.length-before-append, frameOrigin: item.frame.origin)`.
3. Append `"\n\n"` (plain) as a separator between entries (no separator after the last).

The separator chars sit in the global string with no rects in `textRangeRects` (no entry contains them), so visual selection cleanly skips inter-paragraph gaps. They also keep paragraph breaks in the copied text.

**`attributesAtPoint(_:orNearest:)`.**
1. Direct pass: for each entry, compute `localPoint = point - entry.frameOrigin`. If `entry.item.attributesAtPoint(localPoint, orNearest: false)` returns a hit, return `(entry.charOffset + localIndex, attrs)`.
2. Fallback (only when `orNearest == true`): pick the entry whose frame has the smallest vertical distance to `point.y` (zero if `point.y` is in the y-range, otherwise `min(|p.y - frame.minY|, |p.y - frame.maxY|)`), then call its `attributesAtPoint(localPoint, orNearest: true)`. Return `(entry.charOffset + localIndex, attrs)` or `nil` if even the nearest item returns nil.
3. Otherwise return `nil`.

**`textRangeRects(in:)`.** Splits the global range across entries:
1. For each entry whose `[charOffset, charOffset + item.attributedString.length)` intersects the requested range:
   - Compute the local sub-range within the entry.
   - Call `entry.item.textRangeRects(in: localRange)`.
   - Translate each rect by `entry.frameOrigin`.
   - First contributing entry: take its `start` edge translated by `frameOrigin`.
   - Each contributing entry updates `end` to its translated `end` edge.
2. If no entry contributed any rects, return `nil`.
3. Otherwise return `(allRects, start, end)`.

The adapter is invisible — it has no contents and is purely a `TextNodeProtocol` provider. It exists as an `ASDisplayNode` only because the protocol requires it.

### Rich-bubble lifecycle wiring

**New ivars:**

```swift
private var textSelectionAdapter: InstantPageMultiTextAdapter?
private var textSelectionNode: TextSelectionNode?
```

**Imports / BUILD:** add `import TextSelectionNode` and `//submodules/TextSelectionNode` to the rich-bubble's BUILD deps. `TextRangeRectEdge` lives in `Display`, already imported.

**Entering preview** (`updateIsExtractedToContextPreview(true)`):
1. Bail out if `textSelectionNode != nil`, no `item`, no `currentPageLayout`, or no `chatControllerNode`.
2. Filter `currentPageLayout.layout.items` to selectable, non-empty `InstantPageTextItem`s.
3. Construct `InstantPageMultiTextAdapter(items:)`, set its frame to `containerNode.bounds`, add it to `containerNode`.
4. Pick incoming/outgoing `textSelectionColor` and `textSelectionKnobColor` from the presentation theme.
5. Construct `TextSelectionNode` with:
   - `textNodeOrView: .node(adapter)`
   - `present`: routes to `controllerInteraction.presentControllerInCurrent` when `item.associatedData.subject` matches `.messageOptions(_, _, info)` with `case .reply = info`, else `presentGlobalOverlayController` — same branch the text-bubble uses (see `ChatMessageTextBubbleContentNode.swift:1651-1654`).
   - `rootView`: returns the `chatControllerNode` view.
   - `performAction`: routes to `controllerInteraction.performTextSelectionAction(item.message, true, text, nil, action)`.
6. Set flags:
   - `enableCopy = (!associatedData.isCopyProtectionEnabled && !message.isCopyProtected()) || message.id.peerId.isVerificationCodes` — same rule as text-bubble.
   - `enableQuote = false` — quote-replies reference `item.message.text`; IV preview text isn't in there.
   - `enableTranslate = true`, `enableShare = true`, `enableLookup = true`.
7. Set `textSelectionNode.frame` and `textSelectionNode.highlightAreaNode.frame` to `containerNode.bounds`.
8. Add `highlightAreaNode` then `textSelectionNode` to `containerNode`.

**Leaving preview** (`willUpdateIsExtractedToContextPreview(false)`): mirror text-bubble's tear-down — animate alpha 1→0 over 0.2s on both `highlightAreaNode` and the `textSelectionNode` itself, remove from supernode in the completion, clear both ivars synchronously so a subsequent re-entry creates fresh nodes.

**Subnode ordering** inside `containerNode` (bottom → top): tiles → `linkHighlightingNode` (touch state, from earlier task) → `linkProgressView` (in-flight URL shimmer) → adapter (invisible) → `textSelectionNode.highlightAreaNode` → `textSelectionNode`. Order preserved by insertion sequence.

**Coordinate strategy.** Both adapter and `textSelectionNode` use `containerNode.bounds`. The IV layout origin is `(0, 0)` inside `containerNode`, and `InstantPageTextItem.frame` is in that space — so the adapter's local coords line up with item frames directly without a `(1, 1)` translation. (The `(1, 1)` translation only applies to points coming from the bubble-content-node coord space, e.g., in `tapActionAtPoint`.)

## Verification

- Build green: `python3 build-system/Make/Make.py … build … --configuration=debug_sim_arm64`. No automated tests in this project.
- Manual test in simulator:
  1. Find or send a message with a rich-data IV preview (`debugRichText` setting must be on).
  2. Long-press the bubble — it lifts into the context-preview popover, the message context menu appears alongside.
  3. In the lifted preview, select text by tapping and dragging knobs. Selection extends across paragraphs.
  4. Action menu (Copy / Translate / Share / Speak / Look Up) appears anchored on the selection. Confirm Copy puts the selected text on the pasteboard, with `\n\n` between paragraphs.
  5. Quote menu item is **not** present.
  6. Dismiss the context preview — selection overlay and knobs fade out cleanly.

## Open follow-ups (not in this spec)

- Cross-paragraph selection inside expanded `InstantPageDetailsItem` / scrollable `InstantPageScrollableItem` content (rich-bubble doesn't currently expand or scroll those).
- Spoiler awareness on selection (text-bubble has spoiler-aware selection that triggers reveal). IV text items currently don't carry spoiler attributes through `attributedString` in a way that's symmetric with chat text, so deferred.
- Search-text highlighting within the IV preview (`updateSearchTextHighlightState`).
