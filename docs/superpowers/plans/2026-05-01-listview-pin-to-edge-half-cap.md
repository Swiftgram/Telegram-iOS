# ListView pin-to-edge half-area cap — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cap the visible portion of a `pinToEdgeWithInset` item in `ListViewImpl` at half the visible area, so a tall pinned item can't take over the whole screen.

**Architecture:** Add a single private helper on `ListViewImpl` that returns the *bottom extension* (`max(0, pinnedHeight − halfArea)`). Three existing sites in `ListView.swift` consume the extension to (1) cap the pinned-item contribution to `pinToEdgeTopInset`, (2) lower the pin-to-edge-target scroll anchor, and (3) match the new anchor in `isStrictlyScrolledToPinToEdgeItem`. When `extension == 0`, all three sites compute exactly what they compute today.

**Tech Stack:** Swift, Bazel build via `Make.py`. No tests in this project (per CLAUDE.md) — verification is full build + manual smoke.

**Spec:** `docs/superpowers/specs/2026-05-01-listview-pin-to-edge-half-cap-design.md`

---

## File Structure

All edits in one file: `submodules/Display/Source/ListView.swift`.

| Site | Lines (current) | Change |
|------|-----------------|--------|
| Helper (new) | inserted right after `calculatePinToEdgeTopInset` | new private method `pinToEdgeBottomExtension(forPinnedHeight:)` |
| `calculatePinToEdgeTopInset` | 1094–1119 | cap the pinned item's contribution to `totalAboveAndPinned` at `halfArea` |
| `isStrictlyScrolledToPinToEdgeItem` | 2683 | use `extension` to compute `expectedMaxY` |
| pin-to-edge-target offset | 3127 | use `extension` to compute the target offset |

All four edits must land in a single commit — committing one without the others leaves the inset calculation and the actual anchor inconsistent.

---

### Task 1: Apply the four edits to `ListView.swift`

**Files:**
- Modify: `submodules/Display/Source/ListView.swift` (lines 1094–1119, 2683, 3127, plus new helper)

- [ ] **Step 1: Update `calculatePinToEdgeTopInset()` to cap the pinned item's contribution**

Find the existing function (currently lines 1094–1119):

```swift
    private func calculatePinToEdgeTopInset() -> CGFloat {
        var lowestPinnedIndex: Int = Int.max
        for itemNode in self.itemNodes {
            guard let index = itemNode.index, index >= 0, index < self.items.count else { continue }
            if index < lowestPinnedIndex && self.items[index].pinToEdgeWithInset {
                lowestPinnedIndex = index
            }
        }
        guard lowestPinnedIndex != Int.max else { return 0.0 }

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

Replace with:

```swift
    private func calculatePinToEdgeTopInset() -> CGFloat {
        var lowestPinnedIndex: Int = Int.max
        for itemNode in self.itemNodes {
            guard let index = itemNode.index, index >= 0, index < self.items.count else { continue }
            if index < lowestPinnedIndex && self.items[index].pinToEdgeWithInset {
                lowestPinnedIndex = index
            }
        }
        guard lowestPinnedIndex != Int.max else { return 0.0 }

        let visibleArea = self.visibleSize.height - self.insets.top - self.insets.bottom
        let halfArea = visibleArea * 0.5

        var totalAboveAndPinned: CGFloat = 0.0
        var sawIndexZero = false
        for itemNode in self.itemNodes {
            guard let index = itemNode.index else { continue }
            if index == 0 {
                sawIndexZero = true
            }
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
    }

    private func pinToEdgeBottomExtension(forPinnedHeight pinnedHeight: CGFloat) -> CGFloat {
        let visibleArea = self.visibleSize.height - self.insets.top - self.insets.bottom
        let halfArea = visibleArea * 0.5
        guard halfArea > 0.0 else { return 0.0 }
        return max(0.0, pinnedHeight - halfArea)
    }
```

Key changes:
- `let visibleArea` and `let halfArea` moved up so they're available inside the loop.
- The `if index <= lowestPinnedIndex` branch is split into `< lowestPinnedIndex` (full height) and `== lowestPinnedIndex` (capped height).
- New helper `pinToEdgeBottomExtension(forPinnedHeight:)` added immediately after.

- [ ] **Step 2: Update `isStrictlyScrolledToPinToEdgeItem()` to use the extension**

Find (currently around line 2683):

```swift
        for itemNode in self.itemNodes {
            if itemNode.index == targetIndex {
                let expectedMaxY = (self.visibleSize.height - self.insets.bottom) + itemNode.scrollPositioningInsets.bottom
                return abs(itemNode.apparentFrame.maxY - expectedMaxY) < 0.5
            }
        }
```

Replace with:

```swift
        for itemNode in self.itemNodes {
            if itemNode.index == targetIndex {
                let extensionOffset = self.pinToEdgeBottomExtension(forPinnedHeight: itemNode.apparentBounds.height)
                let expectedMaxY = (self.visibleSize.height - self.insets.bottom + extensionOffset) + itemNode.scrollPositioningInsets.bottom
                return abs(itemNode.apparentFrame.maxY - expectedMaxY) < 0.5
            }
        }
```

- [ ] **Step 3: Update the pin-to-edge-target scroll offset in `replayOperations`**

Find (currently around line 3127, inside `if isPinToEdgeTarget {`):

```swift
                    var offset: CGFloat
                    if isPinToEdgeTarget {
                        offset = (self.visibleSize.height - insets.bottom) - itemNode.apparentFrame.maxY + itemNode.scrollPositioningInsets.bottom
                    } else {
```

Replace with:

```swift
                    var offset: CGFloat
                    if isPinToEdgeTarget {
                        let extensionOffset = self.pinToEdgeBottomExtension(forPinnedHeight: itemNode.apparentBounds.height)
                        offset = (self.visibleSize.height - insets.bottom + extensionOffset) - itemNode.apparentFrame.maxY + itemNode.scrollPositioningInsets.bottom
                    } else {
```

- [ ] **Step 4: Sanity-grep for any other use of the old anchor formula**

Run from repo root:

```bash
grep -nE "visibleSize\.height\s*-\s*insets?\.bottom\s*\)" submodules/Display/Source/ListView.swift
```

Inspect each hit. Sites listed in this plan (now patched) and `else` branches (`.bottom(additionalOffset)`, `.top(additionalOffset)`, `.center`, `.visible` at lines 3131, 3143, 3146, 3154, 3160) are scroll-position offsets for *non-pinned* items — they must NOT change. Confirm the only patched lines are the pin-to-edge-target paths.

- [ ] **Step 5: Run the full Bazel build with `--continueOnError`**

```bash
source ~/.zshrc 2>/dev/null; python3 build-system/Make/Make.py --overrideXcodeVersion \
  --cacheDir ~/telegram-bazel-cache build \
  --configurationPath build-system/appstore-configuration.json \
  --gitCodesigningRepository git@gitlab.com:peter-iakovlev/fastlanematch.git \
  --gitCodesigningType development --gitCodesigningUseCurrent \
  --buildNumber=1 --configuration=debug_sim_arm64 --continueOnError
```

Expected: build completes successfully (no Swift errors). If the build surfaces errors in `submodules/Display/Source/ListView.swift`, re-read the patched sections against Step 1–3 above and fix.

If unrelated errors appear in untouched files, they are pre-existing — note them and continue.

- [ ] **Step 6: Commit**

```bash
git add submodules/Display/Source/ListView.swift
git commit -m "$(cat <<'EOF'
ListView: cap pin-to-edge item visible portion at half area

When a pinToEdgeWithInset item is taller than half of the visible
area, its visible portion is now capped at halfArea. The remaining
height extends below visibleSize - insets.bottom into the
bottom-inset region, where it is occluded by overlay UI (input
panel, tab bar) in typical usage.

Three sites updated to a single helper pinToEdgeBottomExtension:
calculatePinToEdgeTopInset (caps the pinned item's contribution),
the pin-to-edge-target scroll offset in replayOperations, and
isStrictlyScrolledToPinToEdgeItem.

When the pinned item fits within halfArea, extension == 0 and all
three sites compute exactly what they did before.

Spec: docs/superpowers/specs/2026-05-01-listview-pin-to-edge-half-cap-design.md
EOF
)"
```

---

### Task 2: Manual smoke test

The change must be exercised on a real device/simulator because there are no unit tests for ListView in this project.

**Test bench:** any chat that supports `pinToTop` messages (the only consumer of `pinToEdgeWithInset == true` per `ChatMessageItemImpl.swift:280`).

- [ ] **Step 1: Short pinned message — unchanged behavior**

Open a chat with a `pinToTop` message of ~1–3 lines (well under `halfArea`). Confirm:
- Pinned message is anchored at the top of the visible chat area (top of screen, given rotated chat).
- The list scrolls under it as expected.
- No visible difference from the pre-change build.

- [ ] **Step 2: Mid-height pinned message — unchanged behavior**

Open a chat with a `pinToTop` message that is sized just under `halfArea` (roughly 30–40% of the chat area). Confirm same as Step 1 — no behavior change.

- [ ] **Step 3: Tall pinned message — capped behavior**

Open a chat with a `pinToTop` message that is much taller than `halfArea` (e.g., a long text message that would naturally span more than half the visible chat area). Confirm:
- The pinned message occupies at most ~half of the visible chat area at the top of the screen.
- The remaining (lower) half of the chat area shows the regular thread content.
- The portion of the pinned message that "doesn't fit" is not visible — it should be occluded by the input panel / nav bar overlay.
- Scrolling behaves consistently: the pinned message stays anchored at the top edge, the rest of the thread scrolls underneath.

- [ ] **Step 4: Inset / size changes — re-evaluation**

While viewing a chat with a tall pinned message, open and close the keyboard (this changes `insets.bottom`). The cap should re-evaluate on each layout pass — no jumpy or stuck state. The pinned message's visible portion should remain ~half of the new visible area.

If any of Steps 1–4 fails, do NOT call the work done. Re-open the spec, re-read the patched sites in `ListView.swift`, and identify which assumption broke.

---

## Self-review

**Spec coverage:**
- Helper `pinToEdgeBottomExtension(forPinnedHeight:)` → Task 1 Step 1.
- Cap in `calculatePinToEdgeTopInset` → Task 1 Step 1.
- Anchor change in pin-to-edge-target offset → Task 1 Step 3.
- Anchor change in `isStrictlyScrolledToPinToEdgeItem` → Task 1 Step 2.
- Edge cases (`pinnedHeight ≤ halfArea`, multiple pinned items, degenerate inset, dynamic resize, rotated chats) — covered by the helper's `max(0, …)` and the unchanged `lowestPinnedIndex` selection logic; smoke-tested in Task 2 Steps 1, 2, 4.
- Verification (full build, manual smoke) → Task 1 Step 5, Task 2.
- Risks (overflow into bottom-inset region) → Task 2 Step 3 explicitly checks occlusion.

**Type/name consistency:** Helper signature `pinToEdgeBottomExtension(forPinnedHeight pinnedHeight: CGFloat) -> CGFloat` is identical at the declaration (Step 1) and both call sites (Steps 2, 3). Local variable name `extensionOffset` matches in Steps 2 and 3.

**Placeholder scan:** No TBDs, no "implement appropriately", no missing code blocks. Each step's expected commands and outcomes are concrete.
