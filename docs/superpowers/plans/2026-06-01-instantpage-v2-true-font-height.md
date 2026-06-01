# InstantPage V2 True Font-Height Line Boxes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a single-line V2 `.text` item measure exactly the true font height (`ascender + |descender|`) instead of the cap box, with the box becoming a true ascent/descent line box, inter-line advance unchanged.

**Architecture:** A 3-line metric change in `layoutTextItem` (shift the line stack down by the ascender headroom `A − L`; pad the returned height by the last line's descender `D`). The rendering path (draw/reveal/decoration/inline-attachment) is byte-identical except for the uniform downward translation, so regressions are confined to a small set of height/frame *consumers* — chiefly the chat-bubble bottom inset — which are re-derived/verified here.

**Tech Stack:** Swift, CoreText, Bazel (`Make.py` wrapper). **No unit tests exist in this project** (per `CLAUDE.md`) and there is no per-module build. The verification gate for every task is therefore: (a) the **full Bazel build** succeeds, and (b) **visual inspection in the iOS simulator** of specific surfaces. "Test" steps below are build + visual-check steps, not unit tests.

**Spec:** `docs/superpowers/specs/2026-06-01-instantpage-v2-true-font-height-design.md`

---

## Conventions used in this plan

- **Notation:** `A = fontAscent`, `D = fontDescentBelowBaseline` (= `max(0, -fontDescent)`), `L = fontLineHeight` (= `floor(fontAscent + fontDescent)`, the cap box). `topInset = A − L`. At 17pt: `A ≈ 16.3`, `D ≈ 3.7`, `L ≈ 12`, `topInset ≈ 4.3`, per-item growth `topInset + D ≈ 8pt`.

- **Full build command** (run from repo root; the controller — not a subagent — must drive this, capturing the real exit code, per the `feedback_subagent_build_execution` note; it is slow, run it in the background and poll):

  ```sh
  source ~/.zshrc 2>/dev/null; python3 build-system/Make/Make.py --overrideXcodeVersion \
   --cacheDir ~/telegram-bazel-cache \
   build \
   --configurationPath build-system/appstore-configuration.json \
   --gitCodesigningRepository git@gitlab.com:peter-iakovlev/fastlanematch.git \
   --gitCodesigningType development --gitCodesigningUseCurrent --buildNumber=1 --configuration=debug_sim_arm64
  ```

- **Visual surfaces** referenced repeatedly:
  - **Article page:** open any full InstantPage V2 article (a multi-paragraph instant-view web page) — exercises paragraphs, headings, lists, blockquotes, tables in the standalone reader.
  - **Chat rich bubble:** send a markdown message that classifies rich (e.g. one containing a `## heading` and a `- list`, or a table) to a chat — renders `ChatMessageRichDataBubbleContentNode`.
  - **Streaming bubble:** an AI/typing-draft rich message (`TypingDraftMessageAttribute`) that reveals progressively.

---

## Task 1: Core metric change in `layoutTextItem`

**Files:**
- Modify: `submodules/InstantPageUI/Sources/InstantPageV2Layout.swift` (function `layoutTextItem`, ~line 2711; the three edits are around lines 2756–2760 and 3098–3101)

- [ ] **Step 1: Capture a pre-change visual reference**

Before editing, build the current `master`-state working tree (if not already built) and screenshot the three visual surfaces (article page, a static chat rich bubble with a heading+list, a streaming bubble). These are the "before" references for later comparison. If a current build artifact already exists, reuse it.

- [ ] **Step 2: Add the `topInset` constant**

In `layoutTextItem`, locate this block (~lines 2754–2757):

```swift
    let fontLineHeight = floor(fontAscent + fontDescent)
    let fontLineSpacing = floor(fontLineHeight * lineSpacingFactor)
    let fontDescentBelowBaseline = max(0.0, -fontDescent)
    let baselineToNextTopSlack = max(0.0, fontLineSpacing - 4.0)
```

Add a `topInset` line immediately after `fontDescentBelowBaseline` so the block reads:

```swift
    let fontLineHeight = floor(fontAscent + fontDescent)
    let fontLineSpacing = floor(fontLineHeight * lineSpacingFactor)
    let fontDescentBelowBaseline = max(0.0, -fontDescent)
    // True font-height line box: shift the whole line stack down by the ascender headroom
    // above the cap line (A − L) and pad the final height by the descender (D) below the last
    // baseline, so a single-line item measures exactly A + D. Exact (not pixel-snapped): this is
    // an intra-item line offset; crispness rides on the item's own pixel-snapped frame origin,
    // and intra-item line positions may already be fractional (e.g. after a non-integral
    // extraDescent). Inter-line advance is unchanged.
    let topInset = max(0.0, fontAscent - fontLineHeight)
    let baselineToNextTopSlack = max(0.0, fontLineSpacing - 4.0)
```

- [ ] **Step 3: Start the line stack at `topInset` instead of the origin**

Locate (~line 2760):

```swift
    var lastIndex: CFIndex = 0
    var currentLineOrigin = CGPoint()
```

Change the second line to:

```swift
    var lastIndex: CFIndex = 0
    var currentLineOrigin = CGPoint(x: 0.0, y: topInset)
```

- [ ] **Step 4: Pad the returned height by the last line's descender**

Locate the final height computation (~lines 3098–3101):

```swift
    var height: CGFloat = 0.0
    if !lines.isEmpty && !(string.string == "\u{200b}" && hasAnchors) {
        height = lines.last!.frame.maxY + extraDescent
    }
```

Change the assignment line to add the descender (keep it inside the existing guard so the `"\u{200b}"`+anchors case still returns `height = 0`):

```swift
    var height: CGFloat = 0.0
    if !lines.isEmpty && !(string.string == "\u{200b}" && hasAnchors) {
        // + fontDescentBelowBaseline: contain the last line's descender below its baseline, so
        // (with the topInset shift) a single-line item measures exactly A + D = true font height.
        height = lines.last!.frame.maxY + extraDescent + fontDescentBelowBaseline
    }
```

- [ ] **Step 5: Full build**

Run the full build command (see Conventions). Expected: build **succeeds** (this is a 3-line change touching one function with no signature change, so no downstream compile breakage is expected).

- [ ] **Step 6: Visual verification — article page line boxes**

Install/run the sim build. Open an article instant page.
Expected: text renders correctly (no clipping, no blur, no overlap); each paragraph's glyphs draw ~4pt lower within their box than before; inter-line spacing within a paragraph is **unchanged**; inter-paragraph/page spacing has **grown** slightly (the accepted "page may grow"). A single-line caption/heading occupies a normal line height rather than a tight cap box.

- [ ] **Step 7: Commit**

```bash
git add submodules/InstantPageUI/Sources/InstantPageV2Layout.swift
git commit -m "InstantPage V2: text items measure true font height (A + D)

Shift the line stack down by the ascender headroom (A - L) and pad the
returned height by the last line's descender (D), so a single-line V2
text item is a true ascent/descent line box measuring exactly A + D
instead of the cap box A - L. Inter-line advance unchanged; formulas
still inflate via lineAscent/extraDescent.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Chat-bubble bottom inset re-derivation

**Context (why this task is narrow):** The bubble height is `max(content-driven, status-driven)`. In the **trailing-date** and **wrapped-date** cases the status term `statusBottomEdge + 6.0` (anchored to the last line's baseline `maxY`/`contentSize`, which translate consistently with Task 1) dominates the content term by ~19pt, so the last item's new `+D` never wins — those cases are unaffected. The bottom only grows in two cases where the content term governs: **status hidden** (`statusType == nil` → `contentSize.height + 2`) and **streaming** (`hasDraft` → `contentSize.height + 2 + 6`). The streaming `+6.0` is an explicit "descenders sit cramped against the bubble's bottom" hack (per its own comment) that the now-contained descender makes partly redundant — that is the one constant to re-tune. The fix is a single-constant change confirmed visually; **no signature changes**, to keep surface area minimal.

**Files:**
- Modify: `submodules/TelegramUI/Components/Chat/ChatMessageRichDataBubbleContentNode/Sources/ChatMessageRichDataBubbleContentNode.swift` (the `hasDraft` bottom-inset block, ~lines 407–419)

- [ ] **Step 1: Visual baseline — the streaming finalize transition**

With the Task 1 build, watch a **streaming bubble** mid-reveal and across the moment it finalizes (the status node fades in). Compare against the Task-1 Step-1 pre-change reference, watching specifically for: (a) the bottom gap below the last revealed line's descenders, and (b) any **shrink/grow pop** at finalize. Also glance at a **status-hidden** rich bubble's bottom.

Expected observation to confirm before changing code: during streaming the bottom gap is now ~`D` (~3.7pt) larger than intended because the descender is contained *and* the `+6.0` still applies (total ≈ `D + 6` below the baseline), and finalize may show a small shrink-pop as the bubble settles onto the status-driven height.

- [ ] **Step 2: Re-tune the streaming descender hack**

Locate the `hasDraft` block (~lines 407–419):

```swift
                if hasDraft {
                    // The bubble's bottom inset is supplied by the `statusBottomEdge + 6.0`
                    // max() in the measure closure below — but that branch is gated by
                    // `!hasDraft`, so during streaming the bubble has only its 1pt bottom rim
                    // past `revealedContentSize.height` (= bounds.maxY + closingPad). Without
                    // this, descenders of the last revealed line sit cramped against the
                    // bubble's bottom edge and the bubble visibly grows by 6pt when streaming
                    // ends and the status node fades in. 6pt matches the constant inside the
                    // status max() (which itself tracks `TextBubble`'s `bubbleInsets.bottom`).
                    // `hadDraft && !hasDraft` (the finalize pass) doesn't need this because
                    // `!hasDraft` re-enables the status max(), which supplies the inset for it.
                    boundingSize.height += 6.0
                }
```

Reduce the constant so the streaming bottom room (now `D` from the contained descender + this constant) again totals ~6pt, and rewrite the comment to reflect the new line-box geometry. The body font is 17pt (`D ≈ 3.7`), so the residual top-up is ~2pt; the exact value is confirmed in Step 4:

```swift
                if hasDraft {
                    // The bubble's bottom inset during streaming is supplied here (the
                    // `statusBottomEdge + 6.0` max() below is gated by `!hasDraft`). V2 text items
                    // now contain their last line's descender (true font-height line box), so
                    // `revealedContentSize.height` already includes ~D (~3.7pt at the 17pt body
                    // font) of room below the last baseline. We only need to top that up to the
                    // ~6pt the finalized (status) bubble leaves — hence ~2pt here, not 6pt.
                    // Without this retune the streaming bubble carried 6 + D of bottom room and
                    // shrink-popped onto the status-driven height at finalize.
                    boundingSize.height += 2.0
                }
```

- [ ] **Step 3: Full build**

Run the full build command. Expected: **succeeds** (a single literal change in one file).

- [ ] **Step 4: Visual verification — all four bubble cases**

In the sim:
1. **Static, trailing date** (rich bubble ending in a text line, status shown): the date trails the last line exactly as before; bottom breathing room **unchanged**. (Status term governs.)
2. **Static, wrapped date** (a long last line that pushes the date to its own row): date below the last line, ~6pt to the bubble bottom — unchanged.
3. **Static, status hidden:** descenders contained, with ~2pt rim below them; the bubble is ~`D` taller than pre-change. **This is accepted** (the descender is now correctly contained instead of cramped against the 2pt rim — an improvement, consistent with "page may grow"). Make **no** change here.
4. **Streaming:** descenders not cramped; bottom gap ≈ 6pt (not `6 + D`); **no shrink-pop** at finalize. If the gap is still visibly off, adjust the `2.0` in Step 2 until the streaming bottom matches the finalized (status-shown) bottom, then rebuild.

- [ ] **Step 5: Commit**

```bash
git add submodules/TelegramUI/Components/Chat/ChatMessageRichDataBubbleContentNode/Sources/ChatMessageRichDataBubbleContentNode.swift
git commit -m "Rich bubble: re-tune streaming bottom inset for true font-height items

V2 text items now contain their last line's descender, so the streaming
'descenders are cramped' +6.0 hack double-counted ~D of bottom room and
shrink-popped onto the status-driven height at finalize. Reduce it to
~2pt so the streaming bubble keeps ~6pt total bottom room. Trailing/
wrapped-date (status-driven) and status-hidden cases are unchanged.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Broad consumer verification (tables, lists, blockquotes, formulas, reveal mask, title)

**Context:** These consumers reference line frames / item heights that all translate consistently with Task 1, so no code change is *expected*. This task confirms that, and applies one gated fix (table cell insets) only if verification shows it is needed.

**Files (only if a gated fix is triggered):**
- Modify: `submodules/InstantPageUI/Sources/InstantPageV2Layout.swift` (`v2TableCellInsets`)

- [ ] **Step 1: Verify decorations & inline content (article page + rich bubble)**

In the sim, view content exercising: bold/italic/strikethrough/underline runs, an inline custom emoji line, an inline image line, an inline/block formula.
Expected: strikethrough/underline bars still cross the glyphs correctly (they are positioned at `lineAscent − fontLineHeight` relative to the shifted line origin); inline emoji/image stay centered on the line and do not overlap the next line; a formula line still inflates the box (its `lineAscent`/`extraDescent` path is unchanged). No clipping or blur.

- [ ] **Step 2: Verify the streaming reveal mask**

In the sim, watch a streaming bubble reveal.
Expected: the reveal mask wipes glyphs cleanly with no edge clipping (the mask is line-frame-relative, `y = minY + lineAscent − rect.maxY`, and translates with the shift); inline emoji pop in correctly; the `containerNode` still clips all content (no bleed past the clip); no flash-of-full-text. Cross-check the reveal *pace* is unchanged (cost is width-based, height-agnostic).

- [ ] **Step 3: Verify list markers / checkboxes**

In the sim, view an unordered list, an ordered list, and a task list (`- [ ]` / `- [x]`).
Expected: bullets/numbers/checkboxes remain vertically aligned to the **mid of the first text line** of their item (markers are positioned relative to the first line frame, which translates with the text). The marker→text horizontal gap is unchanged.

- [ ] **Step 4: Verify blockquotes**

In the sim, view a single-paragraph blockquote and a nested/multi-paragraph blockquote.
Expected: the italicized body and the quote bar render correctly; the fixed 10pt child spacing for nested children is visually unchanged; the quote bar height tracks the (now slightly taller) content.

- [ ] **Step 5: Verify tables (the one gated fix)**

In the sim, view a table (article page and/or rich bubble) with header row, striped rows, and mixed vertical alignments if available.
Expected: rows are ~8pt taller per text line of content; **stripe corner rounding** still lands on the correct grid corners (detection is grid-relative); the **title** (if present) stays vertically centered; `.middle`/`.bottom` cell alignment still reads correctly.

Gated fix — **only if** top-aligned cells now look top-heavy (too much space above the text because the cell text box gained `topInset` of headroom above its caps): reduce the top cell inset to absorb the headroom. The definition is at `InstantPageV2Layout.swift:1054`:

```swift
let v2TableCellInsets: UIEdgeInsets = {
    return UIEdgeInsets(top: 15.0, left: 13.0, bottom: 15.0, right: 13.0)
}()
```

If needed, reduce `top` by `~4.0` (one ascender-headroom unit at the table body font size), leaving the other sides untouched:

```swift
let v2TableCellInsets: UIEdgeInsets = {
    return UIEdgeInsets(top: 11.0, left: 13.0, bottom: 15.0, right: 13.0)
}()
```

If cells look fine (the accepted "page may grow" outcome), make **no** change.

- [ ] **Step 6: Full build (only if Step 5 changed code)**

If the table inset was changed, run the full build. Expected: succeeds. If no code changed in this task, skip.

- [ ] **Step 7: Commit (only if Step 5 changed code)**

```bash
git add submodules/InstantPageUI/Sources/InstantPageV2Layout.swift
git commit -m "InstantPage V2 table: trim top cell inset for true font-height items

Top-aligned cell text gained ascender headroom above its caps under the
true font-height line box; reduce v2TableCellInsets.top to keep cells
visually balanced.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Acceptance pass (spec verification checklist)

**Files:** none (verification only).

- [ ] **Step 1: Run the full spec verification checklist**

Confirm each item from the spec's Verification plan in the sim, against the pre-change references:

1. Article instant page (multi-block) — line boxes correct, inter-line spacing unchanged, page grown.
2. Static chat rich bubble — date placement and bubble bottom inset (no extra gap in the trailing/wrapped cases).
3. Streaming chat rich bubble — reveal-mask alignment, clip, no flash, no finalize shrink-pop.
4. Table — cell heights, vertical alignment, stripe corners, title centering.
5. Lists / checkboxes — marker alignment to first line.
6. Blockquote (nested) — child spacing.
7. Formula / inline-emoji line — line still inflates correctly.

- [ ] **Step 2: Confirm a single-line item measures `A + D`**

Sanity-check (lldb or a temporary log, removed before commit) that a known single-line text item's returned height equals `fontAscent + fontDescentBelowBaseline` for its font (exactly, since `topInset` is not snapped). Remove any temporary instrumentation.

- [ ] **Step 3: Final review**

Re-read the diff across all touched files. Confirm: only the three intended edits in `layoutTextItem`, the helper signature + the bubble bottom block in Task 2, and (only if triggered) the table inset. No stray changes; the pre-existing WIP in these files (present before this branch) is not accidentally reverted or duplicated.

---

## Self-review notes (author)

- **Spec coverage:** Core change → Task 1. Auto-correct consumers (block stacking, lastTextLineFrame, decorations, inline content, reveal mask, list markers) → Task 3 Steps 1–4 (+ implicit in Task 1 Step 6). Re-derivation consumers: chat-bubble height/status + streaming clip → Task 2; table cells → Task 3 Step 5; title centering → Task 3 Step 5; reveal cost → Task 3 Step 2. Pixel-crispness (exact `topInset`) → Task 1 Step 2 comment + Task 4 Step 2. Out-of-scope V1 → untouched (no task). All spec sections mapped.
- **No placeholders:** every code edit shows the exact before/after; conditional fixes (Task 2 Step 4 streaming-constant tweak, Task 3 Step 5 table inset) are visual-gated, not vague — each provides the concrete code/value to apply.
- **Type consistency:** Task 2 is a single-constant change (`6.0` → `2.0`) with no signature changes, so there are no cross-task type dependencies introduced. `topInset` / `fontDescentBelowBaseline` used in Task 1 are local to `layoutTextItem`. The Task 3 table fix touches only the `v2TableCellInsets` literal.
