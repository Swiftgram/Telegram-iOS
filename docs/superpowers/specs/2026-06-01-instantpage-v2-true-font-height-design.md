# InstantPage V2 — text items as true font-height line boxes

**Date:** 2026-06-01
**Status:** Design (approved for spec review)
**Scope:** Shared V2 layout (`layoutTextItem` in `InstantPageV2Layout.swift`) — affects both the full InstantPage V2 article reading view and the chat rich-data bubbles. V1 (`InstantPageLayout.swift`) is out of scope.

## Problem

A V2 `.text` layout item's contributed height is currently the **cap box**, not a normal line height. Per line:

```swift
let fontLineHeight = floor(fontAscent + fontDescent)   // descender is NEGATIVE → floor(A − D)
let height = lineAscent                                 // == fontLineHeight for a plain line
```

with `fontAscent = A` (≈16.3 @17pt), `fontDescent` negative, `D = |fontDescent|` (≈3.7), so `fontLineHeight = L = floor(A − D)` (≈12). The renderer draws the baseline at the line frame's `maxY`, so the box brackets **baseline → cap-tops**: the first line's ascenders bleed *above* the box and the last line's descenders bleed *below* it, into the surrounding block spacing. A single-line item therefore measures ≈`A − D` (~12pt) instead of the true font line height `A + D` (~20pt).

## Goal

A single-line `.text` item should measure **exactly the true font height** (`A + D`), unless it contains inline content (formulas / tall attachments) that inflates it — that inflation stays. The **inter-line advance is unchanged**. The box becomes a true line box that brackets the font's ascent and descent (ascenders contained under the top edge). Per-item text is not hacked into place; the page is allowed to grow as boxes absorb the former bleed.

This was chosen (Approach 2) over a bottom-padding-only variant (Approach 1) that would have kept glyphs byte-identical but left the box geometrically un-centered. The trade-off accepted: glyphs draw ~`A − L` (~4pt) lower within their box across all V2 instant pages, and line frames move, so a handful of geometry consumers need re-derivation.

## Core change — `layoutTextItem` (`InstantPageV2Layout.swift`)

Three edits, all within the one function. Notation: `A = fontAscent`, `D = fontDescentBelowBaseline`, `L = fontLineHeight`.

1. **Compute the top inset** (ascender headroom above the cap line). It is an *intra-item* line offset, not the item's on-screen position, so it is **not** pixel-snapped — see Pixel crispness:

   ```swift
   let topInset = max(0.0, fontAscent - fontLineHeight)   // = A − L, exact
   ```

2. **Start the line stack shifted down** by `topInset` instead of at the origin:

   ```swift
   var currentLineOrigin = CGPoint(x: 0.0, y: topInset)   // was CGPoint()
   ```

3. **Pad the returned height** with the last line's descender below the baseline:

   ```swift
   // was: height = lines.last!.frame.maxY + extraDescent
   height = lines.last!.frame.maxY + extraDescent + fontDescentBelowBaseline
   ```

### Why this is the safe shape

- **Per-line frames keep `height = lineAscent` (the cap box).** Only the stack's starting origin moves and the returned total is padded. Therefore:
  - the baseline is still drawn at each line frame's `maxY`;
  - the inter-line advance `lineAscent + fontLineSpacing + extraDescent` is untouched;
  - the reveal mask (renderer: `y = minY + lineAscent − rect.maxY`), decorations (`workingLineOrigin.y + (lineAscent − fontLineHeight)`), inline emoji/image/formula placement (`baselineY = workingLineOrigin.y + lineAscent`), and `characterRects` (baseline-relative, line-local) all reference the line frame / line origin and translate **consistently** with the shift.
- **Single line:** `topInset + L + D = (A − L) + L + D = A + D` = **exactly** the true font height. ✓
- **Formulas / tall attachments still inflate** via `lineAscent` (grows the line frame) and `extraDescent` (grows below) — unchanged.
- **Preserve** the `string.string == "\u{200b}" && hasAnchors` → `height = 0` special case: only pad inside the existing `if`, so an anchor-only line still returns 0.

### Net effect

Every V2 text item (paragraph, heading, title, caption/credit, list body, blockquote child, code, table cell, thinking block) grows by ~`(A − L) + D` (~8pt @17pt) and its glyphs draw ~`A − L` (~4pt) lower within their box.

## Consumers

### Auto-correct — verify only

These stay correct because line frames keep cap-box geometry (baseline at `maxY`, `height = fontLineHeight`), merely translated:

- **Block stacking / `spacingBetweenBlocks` / `contentSize`** — items taller → page grows (intended).
- **`lastTextLineFrame` / `lastTextLineFrameIfLastItemIsText` + `trailingBottomPadding = 5`** — the `maxY = baseline` relationship and the `isInflatedByAttachment = lineFrame.height > ascent + descent + 1` test are unchanged (line-frame height is still `L`), so the chat-bubble date still trails the last line correctly.
- **Decorations** (strikethrough/underline/marker/spoiler), **inline emoji/image/formula**, **`characterRects`**, **reveal mask**, **list markers** (`markerFrameFor`, mid-of-first-line alignment) — all translate with the stack.

### Re-derivation — constant tweaks + verify

1. **Chat-bubble height + status node** (`ChatMessageRichDataBubbleContentNode.swift`). The last line's descender is now *inside* the item's content height instead of bleeding into the bubble's bottom inset. The bubble-height formula `boundingSize.height = max(boundingSize.height, statusBottomEdge + 6.0)` and the `revealedContentSize.height + 2` / `+6.0` constants risk leaving an extra ~`D` gap below the date. **Re-derive so the bubble's bottom breathing room is visually unchanged** (likely: account for the now-contained descender in the content-driven max, or subtract it where the content height feeds the bubble bottom). The `hasDraft` streaming `+6.0` term and the `statusAnchorY`/`statusFrameY` mirror must stay in lockstep (existing invariant).
2. **Streaming clip** (`containerNode` sized to `revealedItemsMaxY`; `revealedContentSize`). Taller items change the clip height. Confirm the streaming reveal still clips at the right place with no flash/gap, and that `containerNode` (not the pageView) still does all the clipping.
3. **Table cells** (`finalizeCell` vertical alignment, `v2TableCellInsets`). Cells grow ~8pt; `cellHeight = ceil(subLayoutHeight) + insets`. A `.top`-aligned cell gains ~`topInset` of effective top padding (the text box now has headroom above the caps). Decide accept-vs-compensate (see Open Decisions). Verify `.middle`/`.bottom` alignment still reads correctly, and that stripe-corner detection (`gridHeight = contentSize.height − gridOffsetY`; `frame.maxY >= gridHeight − …`) still selects the right corners with taller rows (it is grid-relative, so expected to hold).
4. **Table title centering** (`titleTextItem.frame.origin.y = floorToScreenPixels((titleHeight − titleTextItem.frame.height) * 0.5)`). Both `titleHeight` (`titleLayout.contentSize.height + insets`) and `titleTextItem.frame.height` grow together; confirm the title stays centered.
5. **`InstantPageV2RevealCost`** (`InstantPageV2View.applyReveal`, `charCountForWidthBudget`). Reveal cost is width-based (height-agnostic), but per-item visibility / table-row pop-in keys off frames/`maxY`. Verify no regression.

### Out of scope

- **V1 `InstantPageLayout.swift`** (`layoutTextItemWithString`) — untouched; no V1/V2 parity requirement for this change.

## Pixel crispness

`topInset` is the exact `A − L` and is **not** snapped. Crispness is handled at item-position granularity — the item's frame origin is pixel-snapped (`floorToScreenPixels`) where it is placed in the page — not at the intra-item line offset. Line positions inside an item may already be fractional today (e.g. after a line whose `extraDescent` is non-integral), so a fractional `topInset` introduces nothing new, and the single-line height stays exactly `A + D`.

## Verification plan

Full Bazel build (`Make.py … build … --configuration=debug_sim_arm64`; per `CLAUDE.md`, prefix with `source ~/.zshrc`). The enum/signature surface is small, so the build is a correctness gate only for the touched files. Then visual passes:

1. An article instant page (multi-block) — line boxes and inter-block spacing.
2. A static chat rich-data bubble — date placement and bubble bottom inset (no extra gap).
3. A streaming chat rich-data bubble — reveal-mask alignment, clip, no flash-of-full-text.
4. A table — cell heights, vertical alignment, stripe corners, title centering.
5. Lists / checkboxes — marker alignment to first line.
6. A blockquote (nested) — child spacing.
7. A formula / inline-emoji line — line still inflates correctly.

## Open decisions

- **Crispness vs. exactness:** RESOLVED — `topInset` is exact (not snapped); crispness is handled by the item's own pixel-snapped frame origin, and intra-item line positions may be fractional (already true today). Single-line height is exactly `A + D`.
- **Tables & bubble bottom:** CONFIRMED — compensate the bubble bottom (in scope: keep its bottom breathing room unchanged by accounting for the now-contained descender) and accept the table growth (consistent with "page may grow"), reducing `v2TableCellInsets` only if verification shows it looks off.

## Risk notes

- Blast radius is every V2 instant page; the change is a 3-line metric shift but the verification surface is broad. The mitigation is that the rendering path (draw/reveal/decoration/attachment) is byte-identical except for the uniform translation, so regressions are confined to the height/frame *consumers* enumerated above.
- The two most fragile consumers are the chat-bubble bottom-inset math and table cell vertical alignment; both have tuned constants documented in `CLAUDE.md`.
