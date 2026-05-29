# Server-controlled thinking blocks + cross-update view reuse (InstantPage V2)

**Date:** 2026-05-29
**Status:** Approved (design)

## Summary

Render the top-level `InstantPageBlock.thinking(RichText)` block in the InstantPage **V2**
renderer as a dimmed, always-shimmering, reusable block view. The visual treatment matches the
existing `streamingStatusTextNode` + `streamingStatusShimmerView` "Thinking…" header — but driven
by **server-sent** content instead of a hardcoded string, and packaged as a first-class V2 block
item view. The hardcoded header in `ChatMessageRichDataBubbleContentNode` is removed.

This is a **two-part, coupled** design:

- **Part A — Cross-update view reuse.** Stop rebuilding the entire `InstantPageV2View` on every
  streaming chunk (`stableVersion` bump). Reuse item views across page updates; tear a view down
  only when its block is actually removed. This is what lets thinking blocks "come and go" across
  chunks without disturbing the answer content's views or reveal animation.
- **Part B — Thinking block rendering.** Lay out, display, and reveal-animate the thinking block;
  remove the hardcoded header. V1 ignores thinking blocks (no-op).

The two parts are coupled: thinking blocks are explicitly allowed to appear and disappear across
chunks, and the requirement that this "should not affect other blocks" is only meaningful once
views survive across chunks (Part A) and thinking carries a separate id namespace + zero reveal
cost (Part B).

## Motivation / requirements (from the requester)

1. Add layout display of `InstantPageBlock.thinking` in the InstantPage **V2** renderer. V1 may
   ignore them.
2. The built-in hardcoded "Thinking…" implementation at
   `ChatMessageRichDataBubbleContentNode.swift:412` must be **removed** in favor of
   server-controlled thinking blocks.
3. Take care of the message reveal animation.
4. Thinking blocks **may come and go** across chunks, and they must **not** take part in reveal
   cost estimation. Yet they must follow the reveal fade-in *as if* they had a cost position:
   reveal (fade in) when `revealedCount >= the thinking block's index position`.
5. Thinking blocks may appear **only at the top level** of the instant page. There may be **any
   number** of them.
6. Adding or removing thinking blocks must **not affect other blocks**. This implies a **separate
   id assignment** for thinking blocks vs. all other blocks.
7. **Views should not be torn down under any page update unless they were removed. Views should be
   reused whenever possible.**

## Design decisions (confirmed)

- **Visual style:** identical to the existing `streamingStatusTextNode` rendered inside a
  `ShimmeringMaskView` mask — a shimmering text region — refactored into a reusable block item view.
- **Shimmer lifecycle:** the block shimmers **continuously while displayed**, streaming or not.
  The `ShimmeringMaskView` self-animates via its `HierarchyTrackingLayer` whenever in-hierarchy, so
  the view owns its own animation regardless of message state.
- **Base text color:** **dimmed / secondary** (matching the old header's
  `messageTheme.fileDescriptionColor`). RichText keeps its own bold/italic/link/inline-emoji
  formatting on top of this base color.
- **Reveal mechanic:** **zero reveal-cost**; the whole block **alpha-fades in (0.12s)** once the
  reveal cursor reaches its index position; the inner text is drawn **fully** (not char-by-char)
  under the shimmer.
- **Header removal:** **fully remove** the hardcoded header and its `streamingHeaderOffset`
  machinery. **No empty-state fallback** — the bubble is empty until the server sends its first
  block (thinking or answer).
- **Placement:** thinking blocks appear only at the top level; any count; rendered in normal
  block flow exactly where they sit in the sequence.
- **View reuse:** Part A is **in scope** for this task. `InstantPageV2RenderContext` becomes
  updatable to enable it.

---

## Part B — Thinking block rendering

### B.1 Core model (`TelegramCore`)

`InstantPageBlock.thinking(RichText)` already exists (parsing, Postbox + FlatBuffers
serialization, API parse, `apiInputBlock` returns nil = output-only). **No core changes.** The
layout layer is the only thing that needs to learn to render it.

### B.2 Layout (`submodules/InstantPageUI/Sources/InstantPageV2Layout.swift`)

- Add `InstantPageV2LaidOutItem.thinking(InstantPageV2ThinkingItem)`. `InstantPageV2ThinkingItem`
  holds:
  - the inner laid-out text (an `InstantPageTextItem` / sub-text-layout produced like a paragraph
    but using a **secondary/dimmed base color** for the default run color), and
  - its own `frame`.
- Replace the `case .thinking: return []` stub (currently `InstantPageV2Layout.swift:892`) with an
  arm that lays out the RichText (reusing the existing simple-text layout helper) and wraps it in
  the thinking item. Normal inter-block spacing in the top-level flow.
- The dimmed base color is sourced from the existing theme. Reuse the caption/secondary text
  category or pass the dimmed color explicitly; the exact category is an implementation detail to
  match the old header color.

### B.3 View (`submodules/InstantPageUI/Sources/InstantPageRenderer.swift`)

- Add `InstantPageV2ThinkingView: InstantPageItemView`. Structure mirrors
  `InstantPageV2CodeBlockView` (a container hosting an inner text view):
  - hosts a `ShimmeringMaskView(peakAlpha: 0.3, duration: 1.0)`;
  - the shimmer's `contentView` holds the inner `InstantPageV2TextView` (so inline emoji, links,
    bold/italic etc. all work via the standard text view);
  - the shimmer self-animates whenever in-hierarchy → **always shimmering while displayed**;
  - `update(item:theme:...)` refreshes the inner text view and re-runs
    `ShimmeringMaskView.update(size:containerWidth:offsetX:gradientWidth:)`.
- `makeItemView` gains a `.thinking` arm constructing the view.
- `reuse` gains a `.thinking` arm calling the view's `update`.
- `stableId(for:atPosition:)` gains a `.thinking` arm → `.thinking(thinkingIndex)` (see A.3).
- **BUILD:** add `//submodules/TelegramUI/Components/ShimmeringMask:ShimmeringMask` (and its
  transitive `HierarchyTrackingLayer`, `ComponentFlow` is already present) to `InstantPageUI/BUILD`.

### B.4 Reveal cost (`submodules/InstantPageUI/Sources/InstantPageV2RevealCost.swift`)

- Add cost-map entry `.thinking(start: Int)`.
- `computeEntries`: append `.thinking(start: cursor)` and **do not advance `cursor`** (zero cost).
  Consequence: the answer content's cursor positions are identical whether or not thinking blocks
  are present → reveal cursor is stable through thinking churn (**the linchpin** of requirement 4).
- `revealedExtent(entry:item:revealedCount:)`: for `.thinking(start)`, return `item.frame` when
  `revealedCount >= start`, else `nil`. So the block contributes height (grows the bubble) exactly
  when it is revealed. A top thinking block (`start == 0`) contributes height from the first frame.
- `applyRevealEntry(view:entry:revealedCount:animated:)`: for `.thinking(start)`, set the inner
  text view to its **full** character count (fully drawn, never reveal-masked), then
  `applyVisibility(view: thinkingView, visible: revealedCount >= start, animated:)` (the existing
  0.12s alpha cross-fade used for non-text items).
- A top thinking block (`start == 0`) is visible from the start of the reveal; one placed after
  content fades in as the cursor passes its position.

### B.5 V1 (`submodules/InstantPageUI/Sources/InstantPageLayout.swift`)

`.thinking` stays a no-op (`[]`). V1 is unaffected.

---

## Part A — Cross-update view reuse

Today `ensurePageView` (`ChatMessageRichDataBubbleContentNode.swift:104`) rebuilds the
`InstantPageV2View` from scratch whenever `stableVersion` changes, because
`InstantPageV2RenderContext` is constructor-fixed (`let webpage`, closures capturing a
`MessageReference`). Every other update path (theme, width, details expand/collapse) already flows
through `InstantPageV2View.update(layout:)` and reuses item views via the renderer's stable-id
diffing. The **only** thing forcing a wholesale teardown each chunk is the `stableVersion` key.

### A.1 Updatable render context (`InstantPageRenderer.swift`)

Make `InstantPageV2RenderContext` content updatable for same-message chunks: convert `webpage`
(and the captured `MessageReference`) to mutable storage and add an
`updateContent(webpage:messageReference:)` method (or equivalent). The closures
(`imageReference`/`fileReference`) read the current stored `MessageReference` rather than capturing
a fixed snapshot. `context`, `sourceLocation`, and the navigation closures are unchanged across
chunks.

### A.2 `ensurePageView` update-in-place (`ChatMessageRichDataBubbleContentNode.swift`)

- **Same message id, new `stableVersion`** → keep the existing `pageView`, call
  `updateContent(...)` on its render context, and fall through to `pageView.update(layout:)`. No
  teardown.
- **Different message id / recycled bubble with a different webpage** → rebuild as today.
- The reveal seed (`applyReveal(revealedCount: seedCount, animated: false)`) becomes a continuation
  of the live views' existing reveal state instead of a from-scratch re-seed — eliminating the
  brief full-text-then-mask flash at each chunk boundary.

### A.3 Separate stable-id namespaces (`InstantPageRenderer.swift`)

`InstantPageV2StableItemId` gains a `.thinking(Int)` case. In the `update()` walk
(`InstantPageRenderer.swift:215`), maintain **two independent counters**:

- a **content counter** that increments only for non-thinking items; non-thinking items are
  numbered by it (`.positional(kind, contentIndex)`);
- a **thinking counter** that increments only for thinking items; thinking items get
  `.thinking(thinkingIndex)`.

Result: inserting or removing a thinking block no longer renumbers the content blocks' positional
ids, so their views (and their reveal masks/state) are reused and animate smoothly across chunks
(requirement 6).

### A.4 Bubble header removal (`ChatMessageRichDataBubbleContentNode.swift`)

Delete the hardcoded "Thinking…" header and its supporting machinery:

- `streamingStatusTextNode`, `streamingStatusShimmerView` properties and all their apply-time
  wiring (the block around lines 765–820);
- `streamingStatusTextLayout`, `streamingTextLayoutAndApply`, `streamingTextFrame`;
- the hardcoded `NSAttributedString(string: "Thinking...")` (line 413);
- `streamingHeaderOffset` (becomes a constant `0`): remove it from the bubble-height math
  (`boundingSize.height += streamingHeaderOffset`), from the `thinkingMinBubbleWidth` width bump,
  from the status-node `statusAnchorY`/`statusFrameY` shifts, and from `pageView.frame.origin.y`
  (which becomes `0`, matching today's non-streaming position);
- `import ShimmeringMask` from the bubble file (the dependency moves to `InstantPageUI`).

No empty-state placeholder: while `hasDraft` and the page has no blocks yet, the bubble is empty.

---

## Risks / invariants

- **CLAUDE.md updates required.** The "AI streaming animation" section states "The pageView is
  rebuilt on every `stableVersion` bump… each AI chunk creates a brand-new `InstantPageV2View`" and
  "the dict starts fresh each chunk — no orphan/leak across rebuilds." Both invariants flip with
  Part A: views and the inline-emoji/inline-image dicts now **persist across chunks**. Verify the
  existing within-view stale-key pruning in `updateInlineEmoji`/`updateInlineImages` correctly
  removes layers for blocks/emoji that disappear across a chunk (it prunes keys not present in the
  current layout, so cross-chunk removal should be handled — confirm during implementation). The
  header/`streamingHeaderOffset` notes in the "Status node positioning" subsection must be
  rewritten.
- **Reveal cursor stability** depends entirely on thinking being **zero-cost**. If thinking ever
  contributed cost, adding/removing a thinking block mid-stream would jump the answer's reveal
  position. Keep cost at 0.
- **Enum-arity changes are compile-enforced.** Adding `InstantPageV2LaidOutItem.thinking` and
  `InstantPageV2StableItemId.thinking` breaks every exhaustive switch over them (`computeEntries`,
  `revealedExtent`, `applyRevealEntry`, `stableId`, `makeItemView`, `reuse`, and any preview/extent
  walks). The **full Bazel build** is the completeness gate (no per-module build in this repo).
- **Render-context mutability** must not break media reference resolution: media resolves by media
  id within the message, and the message id is stable across chunks, so updating the stored
  `MessageReference` to the latest chunk is safe (and more correct than a stale snapshot).
- **Details/table reuse** already works via stable ids and `update(layout:)`; Part A must not
  regress the existing collapse/expand animation (`finalizePendingCollapse`) — the same-id reuse
  path is unchanged for those views.

## Out of scope

- Sending thinking blocks (the app is output-only for `.thinking`; `apiInputBlock` returns nil).
- V1 rendering of thinking blocks.
- Any change to how the server decides to include/exclude thinking blocks.
- Tappable interaction / collapse-expand for thinking blocks (they are plain shimmering text).

## Verification

- Full Bazel build (`Make.py … --configuration=debug_sim_arm64`) — the enum-arity completeness gate.
- Manual: stream an AI message whose server payload includes one or more top-level `.thinking`
  blocks interleaved with answer content; confirm:
  - thinking blocks shimmer continuously and render in dimmed/secondary color;
  - thinking blocks fade in at their index position and never advance the answer's reveal;
  - across chunks where thinking blocks appear/disappear, answer-content views are reused (no flash,
    no reveal-position jump);
  - the bubble grows to contain revealed thinking blocks and the status node sits correctly with the
    header removed;
  - a finalized message carrying a thinking block still renders it (shimmering).
