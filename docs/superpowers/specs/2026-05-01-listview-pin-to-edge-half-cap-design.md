# ListView pin-to-edge half-area cap — design

## Problem

In `ListViewImpl` (`submodules/Display/Source/ListView.swift`), an item that opts into `pinToEdgeWithInset` is anchored with its `apparentFrame.maxY` at `visibleSize.height − insets.bottom`. When the pinned item is taller than the available area, it dominates the entire visible region — its top extends above the top of the visible area, hiding adjacent content.

The intended UX is that a pinned item never occupies more than half of the visible area, so context above (in list coords) / below (visually, in rotated chats) the pinned item remains visible.

## Goal

When the pinned item's height exceeds `halfArea = (visibleSize.height − insets.top − insets.bottom) / 2`, cap the pinned item's *visible portion* at `halfArea`. The remaining `pinnedHeight − halfArea` extends below the content area (between `visibleSize − insets.bottom` and `visibleSize`), into the bottom-inset region. The list view has `clipsToBounds = true` (line 498), so anything beyond `visibleSize.height` is clipped; in typical usage the bottom-inset region is occluded by overlay UI (chat input panel, tab bar) drawn on top of the list view.

When the pinned item's height is `≤ halfArea`, behavior is identical to the current implementation.

## Non-goals

- No new public API on `ListView` or `ListViewItem`. The cap fraction is `0.5`, hard-coded.
- No changes to consumers (`ChatMessageItemImpl`, etc.).
- No changes to header/accessory layout.

## Approach

A single private helper computes the *bottom extension* — the distance by which the pinned item's bottom edge is pushed below `visibleSize − bottom`:

```
extension = max(0, pinnedHeight − halfArea)
```

When `extension > 0`, the pinned item's `apparentFrame.maxY` is anchored at `visibleSize − bottom + extension`, so its top edge sits at `visibleSize − bottom − halfArea`. The visible portion is exactly `halfArea`.

Three existing sites in `ListView.swift` need to agree on the new anchor; all three use the same helper.

### Helper

Add to `ListViewImpl`:

```swift
private func pinToEdgeBottomExtension(forPinnedHeight pinnedHeight: CGFloat) -> CGFloat {
    let visibleArea = self.visibleSize.height - self.insets.top - self.insets.bottom
    let halfArea = visibleArea * 0.5
    guard halfArea > 0.0 else { return 0.0 }
    return max(0.0, pinnedHeight - halfArea)
}
```

### Call site 1 — `calculatePinToEdgeTopInset()` (around line 1094)

The pinned item's contribution to `totalAboveAndPinned` is capped at `halfArea`. This grows `pinToEdgeTopInset` when the pinned item is too tall, pushing items-above further down so their stack lines up with the new (lowered) pinned-item top edge.

```swift
let visibleArea = self.visibleSize.height - self.insets.top - self.insets.bottom
let halfArea = visibleArea * 0.5

var totalAboveAndPinned: CGFloat = 0.0
var sawIndexZero = false
for itemNode in self.itemNodes {
    guard let index = itemNode.index else { continue }
    if index == 0 { sawIndexZero = true }
    if index < lowestPinnedIndex {
        totalAboveAndPinned += itemNode.apparentBounds.height
    } else if index == lowestPinnedIndex {
        let pinnedHeight = itemNode.apparentBounds.height
        let effectivePinnedHeight = halfArea > 0.0 ? min(pinnedHeight, halfArea) : pinnedHeight
        totalAboveAndPinned += effectivePinnedHeight
    }
}
guard sawIndexZero else { return 0.0 }
return max(0.0, visibleArea - totalAboveAndPinned)
```

### Call site 2 — pin-to-edge-target scroll offset (around line 3127)

```swift
if isPinToEdgeTarget {
    let extensionOffset = self.pinToEdgeBottomExtension(forPinnedHeight: itemNode.apparentBounds.height)
    offset = (self.visibleSize.height - insets.bottom + extensionOffset) - itemNode.apparentFrame.maxY + itemNode.scrollPositioningInsets.bottom
}
```

### Call site 3 — `isStrictlyScrolledToPinToEdgeItem()` (around line 2683)

```swift
for itemNode in self.itemNodes {
    if itemNode.index == targetIndex {
        let extensionOffset = self.pinToEdgeBottomExtension(forPinnedHeight: itemNode.apparentBounds.height)
        let expectedMaxY = (self.visibleSize.height - self.insets.bottom + extensionOffset) + itemNode.scrollPositioningInsets.bottom
        return abs(itemNode.apparentFrame.maxY - expectedMaxY) < 0.5
    }
}
```

All three sites read `apparentBounds.height` for consistency with the rest of the file (which uses post-layout, post-animation heights for pinning math).

## Edge cases

- **`pinnedHeight ≤ halfArea`**: helper returns 0, all three sites compute identical values to the current implementation. No behavioural change in the common case.
- **Multiple items with `pinToEdgeWithInset == true`**: existing semantics select the smallest-indexed one as `lowestPinnedIndex`. The cap applies only to that item. Others sit above as normal items.
- **`visibleSize.height ≤ insets.top + insets.bottom`** (degenerate / unmeasured layout): `halfArea ≤ 0`, helper returns 0, no cap.
- **Inset / size changes**: `pinToEdgeTopInset` and the scroll offset are recomputed on every `snapToBounds` / `replayOperations`, so the cap re-evaluates whenever inputs change.
- **Rotated chats (the actual usage path)**: list-coord-bottom maps to top-of-screen; capping the pinned item's visible portion at `halfArea` in list coords keeps the start of the pinned message visible at the top of the screen with the rest extending above.

## Verification

No unit tests exist for ListView in this project (per CLAUDE.md). Verification is:

1. **Full build** with `--continueOnError`:
   ```
   source ~/.zshrc 2>/dev/null; python3 build-system/Make/Make.py --overrideXcodeVersion \
     --cacheDir ~/telegram-bazel-cache build \
     --configurationPath build-system/appstore-configuration.json \
     --gitCodesigningRepository git@gitlab.com:peter-iakovlev/fastlanematch.git \
     --gitCodesigningType development --gitCodesigningUseCurrent \
     --buildNumber=1 --configuration=debug_sim_arm64 --continueOnError
   ```
2. **Manual smoke test** in a chat with a pinned message:
   - Short pinned message (`< halfArea`): unchanged behavior — pinned message anchored at top of screen, list scrolls under it.
   - Mid-height pinned message (just under `halfArea`): unchanged.
   - Tall pinned message (much taller than `halfArea`): only ~half of the visible area shows the pinned message; the other half remains available for the chat thread.

## Risks

- The pinned item's bottom extends past `visibleSize.height − insets.bottom` when capped, into the bottom-inset region of the list view's bounds. In contexts where the bottom-inset region is *not* covered by overlay UI (e.g., a list with `insets.bottom = 0`, or a list with bottom inset reserved for spacing rather than for an overlay), the overflow tail of the pinned item is briefly visible above the bottom edge of the list view. For the primary consumer (chat with `pinToTop` messages), the input panel is drawn on top and occludes the region. Confirm during manual smoke test on non-chat consumers if any.
- The cap is half hard-coded. If a future feature wants per-item or per-list configuration, this becomes a public knob; for now keep it private.
