# Modern path calculation fixes — issues #3 and #7

`submodules/Display/Source/LinkHighlightingNode.swift`, in the `useModernPathCalculation` branch of `drawRectsImageContent`.

## Issue #3 — X-edge snap never fires after the midY snap

The snap loop at lines 75–113 has two passes per `i`:
1. midY snap (lines 78–84) — splits any vertically-overlapping rects at `midY`, leaving `rects[i].maxY == rects[i+1].minY`.
2. X-edge snap (lines 85–108) — guards on `rects[i].insetBy(dx: 0.0, dy: 1.0).intersects(rects[i+1])`. With positive `dy`, this *shrinks* `rects[i]`, so after the midY snap they no longer intersect — the guard is unreachable for the canonical multi-line link case.

**Fix:** flip the inset to `dy: -1.0` so the guard *grows* `rects[i]` by 1 px on each Y edge. After the midY snap the touching edges are at the same y; growing rect[i] by 1 makes it overlap rect[i+1] by 1 px, satisfying `CGRect.intersects` (which requires positive-area intersection). The X-snap then runs on every adjacent pair the algorithm intended to handle.

Why `-1.0` and not `0.0`: `CGRect.intersects` returns `false` for shared-edge-only contact, so a non-zero grow is required.

## Issue #7 — `nextRadius`/`prevRadius` can be 0 when X edges differ by less than 2 px

Line 127: `nextRadius = min(outerRadius, floor(abs(rect.maxX - next.maxX) * 0.5))`. When `|Δx| < 2`, `floor` produces 0 and the call to `addArc` is a no-op (the corner stays unsmoothed). Same pattern at line 154 for `prevRadius` on the left edge.

**Fix:** replace `floor` with `ceil`, and keep `min(outerRadius, …)` as the upper bound. With `ceil`, any non-zero gap rounds up to at least 1 px, which is what the corner needs visually. (Subpixel `Δx == 0` is the "edges already aligned" case and the unmodified `else` branch above each conditional already handles it with a straight `addLine`.)

After fixing #3, the typical multi-line case should snap edges to common min/max when `|Δx| < minRadius (= 2.0)`, so #7 mostly handles the residual fractional-pixel case post-snap and any case where `|Δx| ≥ minRadius` but the floor would still drop to 0 (only possible at exactly `|Δx| = 2`, where `floor(1.0) = 1` is already fine — so #7 primarily covers `|Δx|` in `(0, 2)` *not* caught by snap, e.g., when `minX` and `maxX` deltas have different sub-pixel splits across an adjacent pair).

## Out of scope

- Issue #1 (single-rect path ignores `inset`) — separate change.
- Issues #2, #4 (innerRadius, dy direction in the *same* line as #3 — note: #3's fix IS the dy direction change, so #4 is subsumed), #5 (no closePath), #6 (.copy blend mode), #8 (snap loop bound).

## Validation

No tests exist in this repo (per CLAUDE.md). Validation is by full project build (`Make.py … --configuration=debug_sim_arm64`) and visual inspection of multi-line link highlights in chat — exercised by the change just made to `ChatMessageRichDataBubbleContentNode` (which now sets `useModernPathCalculation = true`).

## Risk

`drawRectsImageContent`'s modern branch is reachable from many call sites (`ChatMessageUnlockMediaNode`, `ChatEmptyNode`, `ShimmeringLinkNode`, `ChatListItem`, `TextLoadingEffect` once it's uncommented, etc.). The fix only changes how multi-rect highlights look — single-rect is untouched. Typical visual change: cleaner stair-step joins between adjacent line rects with near-aligned X edges.
