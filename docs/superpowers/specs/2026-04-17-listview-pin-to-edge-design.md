# ListView pin-to-edge first-pinned-item design

## Goal

Give `submodules/Display/Source/ListView.swift` the ability to pin a single "first pinned item" to the bottom edge of the scrolling area. The item's `apparentFrame.maxY` should sit at `visibleSize.height - insets.bottom` when the combined height of items with smaller indices ("items above", in list coordinates) is less than the available scrolling-area height. When items above grow past that threshold, the pinning gracefully disengages and the list scrolls normally.

This produces, in a flipped-chat consumer, the "AI-chat" UX in which a newly-sent outgoing message appears pinned to the visual top of the viewport while later additions fill in toward it.

## Non-goals

- Changes to `ListViewItemLayoutParams.availableHeight` or any item-side sizing API.
- A new per-item inset value. The existing `pinToEdgeWithInset: Bool` protocol property (declared on `ListViewItem`, default `false`, currently unread) is repurposed as the trigger; there is no numeric inset argument.
- Coordinating with `stackFromBottom` or `stackFromBottomInsetItemFactor`. Where both mechanisms contribute a top-inset, the existing `max(effectiveInsets.top, …)` chain combines them without additional logic.
- Defining behavior for items with an index greater than the pinned item's. Consumer contract: when a consumer sets `pinToEdgeWithInset = true` on an item, that item must be the highest-index flagged item (in practice, the last item in the data array). Items beyond the pinned item render at their natural frames; the pinning guarantee applies only relative to items with smaller indices.
- Unit tests. The project has no test harness; verification is via full-project build plus manual exercise in a consumer (see "Verification").

## Mechanism

### Trigger rule

Among materialized item nodes (`self.itemNodes`), find the one with the smallest `index` whose `self.items[index].pinToEdgeWithInset == true`. Call it the pinned node. If there is no such node (no flagged item, or the flagged item is outside the recycling window), pin-to-edge behavior is inert for that frame.

### Adjustment formula

```
visibleArea          = visibleSize.height - self.insets.top - self.insets.bottom
totalAboveAndPinned  = Σ apparentBounds.height for itemNodes with index ≤ lowestPinnedIndex
pinTopAdjustment     = max(0, visibleArea - totalAboveAndPinned)
```

**Height source: `apparentBounds.height`, not `frame.size.height`.** `apparentBounds.height` returns `self.apparentHeight`, which `insertNodeAtIndex` (at [ListView.swift:2439](submodules/Display/Source/ListView.swift:2439)) sets to `0.0` for animated insertions and grows via `addApparentHeightAnimation` over the insertion animation's duration. It is *essential* that the helper use this animated value: the ListView's per-tick `vSync` handler (around [ListView.swift:4842](submodules/Display/Source/ListView.swift:4842)) calls `snapToBounds` after each apparentHeight update, so the pin inset is recomputed with the current animated height every frame. With `apparentBounds.height`:

- **Insertion above pinned** (the critical case): at insertion, new item `X` has `apparentHeight = 0`, so `totalAboveAndPinned` is unchanged, `pinTopAdjustment` is unchanged, `effectiveInsets.top` is unchanged, and the pinned item stays exactly where it was. As `X`'s apparentHeight grows by `dh` per tick, `totalAboveAndPinned` grows by `dh`, `pinTopAdjustment` shrinks by `dh`, and `snapToBounds` shifts items by `-dh` via its `topItemEdge > effectiveInsets.top` clamp; the pinned item's `origin.y` decreases by `dh` while items after `X` (which offsetRanges shifts by `+dh` earlier in the same vSync) are at `pinned.y + dh − dh = pinned.y` — stationary throughout the animation.
- **Initial animated insertion of a pinned item**: `X` starts at `origin.y` = pinned bottom-edge with `apparentHeight = 0` (invisible). As apparentHeight grows by `dh`, `effectiveInsets.top` shrinks by `dh` and `snapToBounds` shifts `origin.y` by `-dh`. `apparentFrame.maxY = origin.y + apparentHeight` stays exactly at the bottom edge for the whole animation; the item appears to grow upward from the bottom edge into its final pinned position.

Using `frame.size.height` would freeze `totalAboveAndPinned` at its final value on the first tick, so `effectiveInsets.top` would jump to its post-animation value immediately. Insertion above pinned would drag the pinned item up by the new item's full real height on frame 0, then the apparentHeight animation would leave it there — breaking the "pinned stays put" invariant. Initial animated layout would land the item at its final `origin.y` with `apparentHeight = 0`, then grow its content downward into a fixed slot instead of upward from the bottom edge, which is the wrong visual.

The formula is built from item *heights*, not positions, so it is idempotent: re-running `snapToBounds` or `updateScroller` after a snap offset has already been applied yields the same `pinTopAdjustment`. (A position-based formula would read the post-snap `maxY` and compute 0 on the next pass, undoing the shift.)

`visibleArea` uses `self.insets`, not `effectiveInsets`, so the threshold at which pinning disengages is purely geometric and is not coupled to other contributors to `effectiveInsets.top` (e.g. `stackFromBottomInsetItemFactor`). Combining with those contributors happens at the application site via `max(…)`.

### Partial-materialization guard

Pinning requires the full height of items `[0, lowestPinnedIndex]` to be known. If items[0] is not materialized (not in `self.itemNodes`), some leading items are off-screen above — which can only happen when the scroll area is already full of content above the pinned item — and pinning is then inert for that frame. The helper therefore returns 0 unless an itemNode with `index == 0` is present among the materialized nodes. `ListView`'s recycling window is a contiguous range of indices, so `items[0]` materialized implies `items[0…lowestPinnedIndex]` all materialized.

### Application

At each call site that computes `effectiveInsets`, after the existing `stackFromBottomInsetItemFactor` branch:

```swift
let pinToEdgeTopInset = self.calculatePinToEdgeTopInset()
if pinToEdgeTopInset > 0.0 {
    effectiveInsets.top = max(effectiveInsets.top, self.insets.top + pinToEdgeTopInset)
}
```

This piggybacks on the virtual-top-inset mechanism that `stackFromBottomInsetItemFactor` already uses: raising `effectiveInsets.top` shifts the scroll content downward by that amount, positioning the pinned item's `maxY` at the bottom edge. When `pinTopAdjustment` is 0 (items above have reached the available area, or the guard tripped), no contribution is made and scrolling is ordinary.

### Inset-transition correction

There is a third integration point, separate from the two `effectiveInsets` call sites: the inset-transition code in `deleteAndInsertItemsTransaction` around [ListView.swift:3167-3188](submodules/Display/Source/ListView.swift:3167). This block runs whenever `updateSizeAndInsets` is non-nil and shifts every item's frame by an `offsetFix` in order to keep the list visually coherent across the inset/size change.

In the "top-inset" branch (the `else` at line 3173), the existing formula is:

```swift
offsetFix = updateSizeAndInsets.insets.top - self.insets.top
```

When pinning is engaged, this is wrong: a change in `self.insets.top` is exactly compensated by an opposite change in `pinTopAdjustment` (since `visibleArea = visibleSize.height - insets.top - insets.bottom` moves in lockstep with `insets.top`), so the *effective* top inset (`insets.top + pinTopAdjustment`) doesn't move. But `offsetFix` uses only the raw top delta, so it shifts every item's frame by `top_delta`. The list visibly jumps by that amount until the next `snapToBounds`/`updateScroller` pass corrects it — a keyboard toggle produces a jitter equal to the keyboard's top-inset contribution.

The correction: capture `self.calculatePinToEdgeTopInset()` before *either* `self.visibleSize` or `self.insets` is reassigned; compute it again after both are updated; and, in the top-inset branch only, add `(updated - previous)` to `offsetFix`. This makes `offsetFix` equal the *effective* top-inset delta rather than the raw one.

**Ordering matters.** The existing code updates `self.visibleSize` on [ListView.swift:3165](submodules/Display/Source/ListView.swift:3165) (right after entering the inset-transition branch) and `self.insets` on [ListView.swift:3183](submodules/Display/Source/ListView.swift:3183) (later, just before the `offsetFix` shift is applied). The `previousPinToEdgeTopInset` measurement must happen before line 3165 — not between 3165 and 3183 — because `calculatePinToEdgeTopInset` reads `self.visibleSize` to form `visibleArea`. Measuring after 3165 captures a hybrid state (new visibleSize, old insets) that never existed; the resulting delta is wrong whenever `visibleSize` changes in the same transaction.

Initial layout is the case that surfaces this: the old `self.visibleSize = CGSize.zero`, so `visibleArea ≤ 0` and the helper correctly returns 0 ("no prior pinning") when measured before line 3165. Measured after line 3165, `visibleArea` is the full new screen size and the helper returns a fake "previous" pin inset roughly equal to the real post-transaction pin inset — delta cancels out, and the sign of `offsetFix` flips negative, shifting items in the wrong direction. `snapToBounds` then pulls them back to the right resting position, but the intermediate `offsetFix` value propagates into `sizeAndInsetsOffset` and the `-completeOffset` animation `fromValue`, producing a visible mis-offset on the first frame.

Rotation (which changes both visibleSize and insets in one transaction) has the same structural issue but is less dramatic because the old visibleSize is non-zero.

The other two branches don't need the correction:

- `snapToBottomInsetUntilFirstInteraction` branch (line 3172): its formula `offsetFix = -(new.bottom - old.bottom)` already coincidentally equals `effective_top_delta` when pin is engaged. Working through it: `effective_top_delta = top_delta + pin_delta = top_delta - (top_delta + bottom_delta) = -bottom_delta`.
- `isTracking` branch (line 3170): intentionally sets `offsetFix = 0` and defers repositioning to `snapToBounds`, which already consults pin-aware `effectiveInsets` via the helper.

### scrollToItem override

`scrollToItem` at [ListView.swift:3058-3104](submodules/Display/Source/ListView.swift:3058) computes an offset from the target item's `apparentFrame` and the raw `self.insets`, then shifts every item's frame by that offset. When the target is the pin-to-edge target, most `ListViewScrollPosition` variants (`.top`, `.center`, `.visible`, and `.bottom(nonzero)`) compute an offset that drags the pinned item away from its pinned position; the subsequent `snapToBounds` at [ListView.swift:3198](submodules/Display/Source/ListView.swift:3198) / [3360](submodules/Display/Source/ListView.swift:3360) re-imposes pinning on the next pass. The net visible effect is a transient shift in the pre-snap direction, spurious `didScrollWithOffset` callbacks with the wrong value, and (for animated scrolls) a wrong starting frame for the insertion/scroll animation.

The override: when the target item is the pin-to-edge target (the smallest-index materialized item with `pinToEdgeWithInset == true`, and pinning is actually engaged per `calculatePinToEdgeTopInset() > 0`), bypass the `switch scrollToItem.position` and compute the offset directly as:

```swift
offset = (self.visibleSize.height - insets.bottom) - itemNode.apparentFrame.maxY + itemNode.scrollPositioningInsets.bottom
```

This matches the existing `.bottom(0)` case shape. `apparentFrame.maxY` is the right value because of the same per-tick invariant that makes the helper use `apparentBounds.height`: throughout the animation, `apparentFrame.maxY = origin.y + apparentHeight` stays at the pinned bottom edge, so the offset is `0` at every tick — no spurious shift during an in-flight animation. Using `frame.maxY` instead would produce a nonzero offset equal to `apparentHeight − real_height` during the animation, which would fight the `vSync` snap logic and break the animation.

For non-pinned targets, or for the pinned target when pinning is disengaged (`calculatePinToEdgeTopInset() == 0`), the existing `switch` runs unchanged.

## Code changes

### New helper on `ListViewImpl`

```swift
private func calculatePinToEdgeTopInset() -> CGFloat {
    // Pass 1: find the smallest-index flagged item among materialized nodes.
    var lowestPinnedIndex: Int = Int.max
    for itemNode in self.itemNodes {
        guard let index = itemNode.index else { continue }
        if index < lowestPinnedIndex && self.items[index].pinToEdgeWithInset {
            lowestPinnedIndex = index
        }
    }
    guard lowestPinnedIndex != Int.max else { return 0.0 }

    // Pass 2: sum heights of items[0 ... lowestPinnedIndex], and require items[0]
    // to be materialized (guarantees items[0 ... lowestPinnedIndex] are all present,
    // since the recycling window is contiguous in index).
    var totalAboveAndPinned: CGFloat = 0.0
    var sawIndexZero = false
    for itemNode in self.itemNodes {
        guard let index = itemNode.index else { continue }
        if index == 0 {
            sawIndexZero = true
        }
        if index <= lowestPinnedIndex {
            totalAboveAndPinned += itemNode.apparentBounds.height
        }
    }
    guard sawIndexZero else { return 0.0 }

    let visibleArea = self.visibleSize.height - self.insets.top - self.insets.bottom
    return max(0.0, visibleArea - totalAboveAndPinned)
}
```

### Call-site diffs

**`snapToBounds(…)` — around [ListView.swift:1181-1185](../../submodules/Display/Source/ListView.swift):**
After the existing `stackFromBottomInsetItemFactor` adjustment of `effectiveInsets.top`, add the `pinToEdgeTopInset` block shown above.

**`updateScroller(…)` — around [ListView.swift:1612-1616](../../submodules/Display/Source/ListView.swift):**
Same diff.

**`deleteAndInsertItemsTransaction(…)` inset-transition block — around [ListView.swift:3162-3188](../../submodules/Display/Source/ListView.swift):**
Capture the pin inset before *either* `self.visibleSize` or `self.insets` is reassigned (i.e., before line 3165 in the current code); track whether the top-inset branch was taken; and after `self.insets` and `self.visibleSize` are updated, add the pin-inset delta to `offsetFix` if the top-inset branch was taken:

```swift
let previousPinToEdgeTopInset = self.calculatePinToEdgeTopInset()
let previousVisibleSize = self.visibleSize
self.visibleSize = updateSizeAndInsets.size

var offsetFix: CGFloat
var offsetFixUsesEffectiveTopInset = false
let insetDeltaOffsetFix: CGFloat = 0.0
if (self.isTracking && !self.allowInsetFixWhileTracking) || isExperimentalSnapToScrollToItem {
    offsetFix = 0.0
} else if self.snapToBottomInsetUntilFirstInteraction {
    offsetFix = -updateSizeAndInsets.insets.bottom + self.insets.bottom
} else {
    offsetFix = updateSizeAndInsets.insets.top - self.insets.top
    offsetFixUsesEffectiveTopInset = true
}

offsetFix += additionalScrollDistance

self.insets = updateSizeAndInsets.insets
self.headerInsets = updateSizeAndInsets.headerInsets ?? self.insets
self.scrollIndicatorInsets = updateSizeAndInsets.scrollIndicatorInsets ?? self.insets
self.itemOffsetInsets = updateSizeAndInsets.itemOffsetInsets
self.ensureTopInsetForOverlayHighlightedItems = updateSizeAndInsets.ensureTopInsetForOverlayHighlightedItems
self.visibleSize = updateSizeAndInsets.size

if offsetFixUsesEffectiveTopInset {
    let updatedPinToEdgeTopInset = self.calculatePinToEdgeTopInset()
    offsetFix += updatedPinToEdgeTopInset - previousPinToEdgeTopInset
}
```

**`scrollToItem` handler — around [ListView.swift:3058-3104](../../submodules/Display/Source/ListView.swift):**
Inside the existing `for itemNode in self.itemNodes { if ... index == scrollToItem.index { ... } }` block, right after `let insets = self.insets` and before the `switch scrollToItem.position`:

```swift
var isPinToEdgeTarget = false
if self.calculatePinToEdgeTopInset() > 0.0,
   index >= 0, index < self.items.count,
   self.items[index].pinToEdgeWithInset {
    isPinToEdgeTarget = true
    for otherNode in self.itemNodes {
        guard let otherIndex = otherNode.index else { continue }
        guard otherIndex >= 0, otherIndex < self.items.count else { continue }
        if otherIndex < index, self.items[otherIndex].pinToEdgeWithInset {
            isPinToEdgeTarget = false
            break
        }
    }
}

var offset: CGFloat
if isPinToEdgeTarget {
    offset = (self.visibleSize.height - insets.bottom) - itemNode.apparentFrame.maxY + itemNode.scrollPositioningInsets.bottom
} else {
    switch scrollToItem.position {
        // … existing .bottom / .top / .center / .visible cases, unchanged …
    }
}
```

The `isPinToEdgeTarget` check re-derives "smallest-index materialized flagged item" rather than factoring a shared helper, to keep the pin-to-edge API surface small (the existing `calculatePinToEdgeTopInset()` helper is the only public-within-file surface). The duplication is ~6 lines.

No other source file is modified. `ListViewItem.pinToEdgeWithInset` stays declared where it already is ([ListViewItem.swift:80](../../submodules/Display/Source/ListViewItem.swift), default `false` via the protocol extension).

## Behavioral consequences

- **Pinning engaged** (items above shorter than available area): the pinned item's `maxY` lands on `visibleSize.height - insets.bottom`; virtual empty space sits above items[0] so the combined content fills the visible area.
- **Pinning disengaging** (items above reach the available area): `totalAboveAndPinned` grows with each insertion above until it meets `visibleArea`; at that point `pinTopAdjustment` is exactly 0 and the list scrolls normally. The transition through the threshold is continuous in `totalAboveAndPinned`, so there is no visual jump.
- **Drag / rubber-band / deceleration**: the pinned item behaves like any other item during gesture-driven scroll; on settle, `snapToBounds` returns the content to its resting position, which (while pinning is engaged) places the pinned item at the bottom edge.
- **Insertion at index 0 while pinning is engaged**: the pinned item's index increments by one; `totalAboveAndPinned` grows by the inserted item's height; `pinTopAdjustment` therefore shrinks by the same amount; and the inflated `effectiveInsets.top` shrinks by the same amount in turn. Working through the arithmetic: the pinned item's final `origin.y = effectiveInsets.top + (totalAboveAndPinned - pinned.height)` stays identical before and after, so the pinned item is visually stationary across the insertion. The newly-inserted item appears above it.
- **Flag toggle on an item**: update/layout path triggers `snapToBounds` and `updateScroller`; the helper recomputes.
- **Multiple flagged items**: only the smallest-index materialized flagged node anchors. Others render normally.
- **`stackFromBottom` + `pinToEdgeWithInset` both active**: both mechanisms contribute to `effectiveInsets.top` via `max(…)`; the larger contribution wins. No coordination logic is added.
- **Flagged item outside recycling window**: helper returns 0 at the `lowestPinnedIndex != Int.max` guard; pinning re-engages when the node re-materializes.
- **items[0] outside recycling window**: helper returns 0 at the `sawIndexZero` guard. This state can only arise when content above the pinned item has already exceeded the available area (pushing leading items out of the recycling window), at which point pinning should be inert anyway — the guard makes that explicit and protects against under-counting heights.
- **Empty list**: no `itemNode` has an `index`; both loops complete with `lowestPinnedIndex == Int.max`; returns 0.

## Verification

No unit tests exist in the project (per CLAUDE.md). Verification path:

1. Full-project build:
   ```
   source ~/.zshrc 2>/dev/null; \
   PATH=/opt/homebrew/opt/ruby/bin:`gem environment gemdir`/bin:$PATH \
     python3 build-system/Make/Make.py --overrideXcodeVersion \
       --cacheDir ~/telegram-bazel-cache build \
       --configurationPath build-system/appstore-configuration.json \
       --gitCodesigningRepository git@gitlab.com:peter-iakovlev/fastlanematch.git \
       --gitCodesigningType development --gitCodesigningUseCurrent \
       --buildNumber 1 --configuration debug_sim_arm64
   ```
2. Manual exercise in a consumer that sets `pinToEdgeWithInset = true` on one item. Confirm: the flagged item sits at the bottom edge; inserting non-flagged items at index 0 keeps the flagged item visually anchored; once items above fill the available area, further scrolling is ordinary.

Because no existing item overrides `pinToEdgeWithInset` from its default `false`, the existing app surface is unaffected; any regression can only appear in a new consumer.

## Risk

The `effectiveInsets.top` contribution has to be computed identically at both call sites. Divergence (for example, `snapToBounds` adding the pin inset but `updateScroller` not) would cause the scroller's `contentSize` / `contentOffset` to disagree with the target scroll position produced by `snapToBounds`, producing scroll jumps. A shared helper — `calculatePinToEdgeTopInset` — and the identical diff applied at both sites is the defense against that.
