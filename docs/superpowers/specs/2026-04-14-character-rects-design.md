# Character Rects in InteractiveTextNodeLine

## Goal

Compute per-line character bounding rects (actual glyph drawn bounds) during the layout pass and store them on `InteractiveTextNodeLine`. This enables `computeRevealedLines` and the reveal animation system to work with precise glyph geometry without recomputing CoreText data at render time.

## File

`submodules/TelegramUI/Components/InteractiveTextComponent/Sources/InteractiveTextComponent.swift`

## Changes

### 1. InteractiveTextNodeLayoutArguments — new flag

Add a `computeCharacterRects: Bool` property (default `false`) to `InteractiveTextNodeLayoutArguments`.

- Add the property declaration, init parameter, and assignment.
- Propagate through `withAttributedString`.

### 2. InteractiveTextNodeLine — replace characterToGlyphMapping with characterRects

Replace:
```swift
let characterToGlyphMapping: [Int]?
```

With:
```swift
let characterRects: [CGRect]?
```

Update the init signature and all construction sites (4 total: title line at ~1619, main line at ~1661, collapsed truncation at ~1720, final truncation at ~1775) to pass `characterRects` instead of `characterToGlyphMapping`.

- When `computeCharacterRects` is `false` in layout arguments, pass `nil`.
- When `true`, compute the array at construction time (see section 3).

### 3. Glyph rect computation

A helper function (or inline logic) that, given a `CTLine` and its `NSRange`, produces `[CGRect]`:

1. Allocate an array of `CGRect.zero` with length equal to the line's string range length.
2. For each `CTRun` in the line:
   a. Get glyphs via `CTRunGetGlyphs`.
   b. Get positions via `CTRunGetPositions` (glyph origins relative to the line).
   c. Get string indices via `CTRunGetStringIndices`.
   d. Get the font from the run's attributes (`kCTFontAttributeName`).
   e. Call `CTFontGetBoundingRectsForGlyphs(.default, glyphs, &boundingRects, glyphCount)` to get per-glyph bounding boxes relative to each glyph's origin.
   f. For each glyph at index `i`:
      - Compute the final rect: `CGRect(x: position.x + bbox.origin.x, y: position.y + bbox.origin.y, width: bbox.width, height: bbox.height)`.
      - Map to the character index: `stringIndices[i] - lineRangeStart`.
      - Store in the output array at that character index.
3. Characters not covered by any glyph (ligature components, zero-width joiners, etc.) retain `.zero`.

### 4. computeRevealedLines — uncomment and adapt

The existing commented-out implementation at ~line 2798 walks CTRuns and uses `CTRunGetAdvances` to compute `revealedWidth`. Update it to use `characterRects` from the line instead:

- The function signature stays the same: `(lines: [InteractiveTextNodeLine], layerSize: CGSize, offset: CGPoint, characterLimit: Int) -> [RevealLineInfo]`.
- Instead of walking CTRuns at call time, consume the pre-computed `characterRects` on each line to determine how many characters are revealed and what width they span.
- `characterLimit` counts characters (one per entry in the `characterRects` arrays across all lines). Walk lines in order, decrementing the remaining character budget by each line's `characterRects.count`. For each line, the revealed width is the max x-extent of the revealed character rects within the budget.
- Lines beyond the budget get `revealedWidth: 0`.

### 5. getCharacterToGlyphMapping — adapt

The public `getCharacterToGlyphMapping() -> [Int]` on `InteractiveTextNode` (line 2263) currently returns `[]`. Update it to derive a flat character count from the per-line `characterRects`:

- Walk all segments/lines, count the total number of character rects (including `.zero` entries for ligature components).
- Return an array of cumulative glyph counts (preserving the existing API contract used by `ChatMessageTextBubbleContentNode` for animation counting).

The commented-out implementation on `InteractiveTextNodeLayout` (lines 1136-1190) stays as-is per user instruction.

## Non-goals

- Not changing `RevealLineInfo` struct shape.
- Not touching `ChatMessageTextBubbleContentNode` in this task.
- Not deleting any commented-out code.
