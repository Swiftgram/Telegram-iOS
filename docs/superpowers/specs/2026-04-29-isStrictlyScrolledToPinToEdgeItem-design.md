# `ListViewImpl.isStrictlyScrolledToPinToEdgeItem` — design

## Goal

Implement the public method `isStrictlyScrolledToPinToEdgeItem()` on `ListViewImpl` (in `submodules/Display/Source/ListView.swift`).

The method returns `true` when the list is currently scrolled to the exact resting position of its pin-to-edge target — i.e. the item that lies on the edge of `insets.bottom` is the current pin-to-edge target (the lowest-index item with `pinToEdgeWithInset == true`).

A stub already exists at `submodules/Display/Source/ListView.swift:2674` (uncommitted, in the working tree) and is the slot to fill in.

## Definition of "lies on the edge"

Aligned with the existing pin-to-edge scroll math (`ListView.swift:3115`):

```swift
offset = (self.visibleSize.height - insets.bottom) - itemNode.apparentFrame.maxY + itemNode.scrollPositioningInsets.bottom
```

When that offset has been applied, the target item satisfies:

```
itemNode.apparentFrame.maxY == (visibleSize.height - insets.bottom) + itemNode.scrollPositioningInsets.bottom
```

That equation is the "strictly scrolled" condition.

## Implementation

```swift
public func isStrictlyScrolledToPinToEdgeItem() -> Bool {
    guard let targetIndex = self.items.firstIndex(where: { $0.pinToEdgeWithInset }) else {
        return false
    }
    for itemNode in self.itemNodes {
        if itemNode.index == targetIndex {
            let expectedMaxY = (self.visibleSize.height - self.insets.bottom) + itemNode.scrollPositioningInsets.bottom
            return abs(itemNode.apparentFrame.maxY - expectedMaxY) < 0.5
        }
    }
    return false
}
```

## Behavior table

| Situation | Return value |
|---|---|
| No item in `self.items` has `pinToEdgeWithInset == true` | `false` |
| Pin-to-edge target exists but its `itemNode` is not currently materialized | `false` |
| Pin-to-edge target's `apparentFrame.maxY` differs from the expected resting `maxY` by ≥ 0.5 pt | `false` |
| Pin-to-edge target's `apparentFrame.maxY` differs from the expected resting `maxY` by < 0.5 pt | `true` |

## Design choices

1. **Algorithm shape: target-first, not edge-first.** "Find target, check whether it's at the edge" rather than the user's literal "find item at the edge, check whether it's the target". The two are equivalent in practice (items don't share `maxY` in a stacked list) and target-first is cheaper / clearer.
2. **`apparentFrame`, not the layout frame.** `apparentFrame` already accounts for in-flight animation offsets and matches the property the scroll-target math at line 3115 uses. The result reflects the true visible state, not a possibly-scheduled layout that hasn't taken effect.
3. **Tolerance: 0.5 pt.** Half a logical point — well under any visible misalignment, generous enough for floating-point and pixel-snap noise on 2x/3x displays. No project-wide convention found; 0.5 pt is the chosen default.
4. **Includes `scrollPositioningInsets.bottom`.** Mirrors line 3115 exactly so that an item with non-zero `scrollPositioningInsets.bottom` is reported as "strictly scrolled" at the same position the scroll-to logic would have left it at.

## Out of scope

- No new callers are introduced in this spec. The method is added as public API; consumers will be wired up in subsequent work.
- No changes to `ListViewItem.pinToEdgeWithInset`, `calculatePinToEdgeTopInset`, or any pin-to-edge scroll logic.
- No tests — the codebase has no unit tests and this lives in the rendering layer.

## Verification

Build the full app target with the standard `Make.py` invocation in `CLAUDE.md` to confirm the addition compiles.
