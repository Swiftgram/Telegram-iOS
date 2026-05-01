# InstantPage table borders: stop drawing shared edges twice

## Problem

`submodules/InstantPageUI/Sources/InstantPageTableItem.swift` draws table borders per cell: each cell strokes its full perimeter (either via `context.stroke(bounds)` for interior cells, or via `context.drawPath(.stroke)` on a rounded path for the four table-corner cells). Every interior grid line is the boundary between two adjacent cells, so it is stroked twice.

This was visually invisible while `tableBorderColor` was opaque. With the in-flight change in `submodules/TelegramUI/Components/Chat/ChatMessageRichDataBubbleContentNode/Sources/ChatMessageRichDataBubbleContentNode.swift` setting `tableBorderColor: messageTheme.accentControlColor.withMultipliedAlpha(0.25)`, double-stroked interior lines composite to ~44% alpha while the once-stroked outer perimeter shows at the intended 25%. The grid looks darker than the frame.

## Goal

Each border line — interior dividers and the outer perimeter — is stroked exactly once.

## Non-goals

- No change to `cell.adjacentSides`, `TableSide`, `tableCornerRadius`, `tableBorderWidth`, or any frame-layout code in `layoutTableItem`.
- No public API change.
- No change to fill behavior (header rows, striped rows, rounded corners on outer cells).
- No change anywhere outside `InstantPageTableItem.swift`.

## Design

`drawInTile(context:)` is restructured into two passes.

### Pass 1: per cell (existing loop)

The current early `if cell.cell.text == nil { continue }` is removed — empty cells must still contribute border lines (see "Empty cells preserve divider continuity" below). Each piece of per-cell work is gated explicitly instead:

For each cell, in order:

1. **Fill.** If `cell.filled && cell.cell.text != nil` (the `text != nil` gate preserves today's behavior of not filling empty cells, including in striped/header rows):
   - If `cell.adjacentSides` is non-empty, fill with the rounded path (built from `byRoundingCorners: cell.adjacentSides.uiRectCorner`, `cornerRadii: tableCornerRadius`). This preserves the rounded fill on the four table-corner cells.
   - Otherwise, `context.fill(bounds)`.
2. **Interior dividers.** If `self.borderWidth > 0.0` (no `text != nil` gate — empty cells still draw their dividers):
   - If `!cell.adjacentSides.contains(.top)`, stroke the cell's top edge — a line from `(0, 0)` to `(cell.frame.width, 0)` in cell-local coordinates.
   - If `!cell.adjacentSides.contains(.left)`, stroke the cell's left edge — a line from `(0, 0)` to `(0, cell.frame.height)` in cell-local coordinates.
   - No `.right` or `.bottom` line is drawn per cell; both are owned by Pass 2.
3. **Text.** `cell.textItem?.drawInTile(context: context)`, unchanged. Already gated on `textItem` being non-nil.

The `context.translateBy` / `saveGState` / `restoreGState` wrapper around each cell stays the same; the line strokes happen inside the per-cell translation, in cell-local coordinates.

#### Empty cells preserve divider continuity

Today, `cell.cell.text == nil` cells are skipped entirely. Under the existing "stroke whole bounds" model that's harmless — adjacent non-empty cells stroke their full perimeters and cover the dividers around the empty cell with their own bottom/right strokes.

Under the new "always top+left, never bottom+right" convention, an empty cell's omitted top would leave a gap in the divider between it and the row above (the row-above's bottom is no longer stroked, and the empty cell isn't there to stroke its top). Symmetric for left. So Pass 1's divider-line block must run for empty cells too. Fill and text remain gated to preserve existing visuals — the only behavior change for empty cells is that their top/left dividers are now drawn explicitly, restoring continuity that was previously provided incidentally by adjacent cells' overdraw.

### Pass 2: outer border (new, runs once after the loop)

If `self.borderWidth > 0.0`:

```swift
let outerRect = CGRect(
    x: self.borderWidth / 2.0,
    y: self.borderWidth / 2.0,
    width: self.totalWidth - self.borderWidth,
    height: self.frame.height - self.borderWidth
)
let outerPath = UIBezierPath(roundedRect: outerRect, cornerRadius: tableCornerRadius)
context.addPath(outerPath.cgPath)
context.strokePath()
```

Coordinates: `drawInTile`'s context is in the table-content coordinate space (origin at the table's top-left, size `totalWidth × frame.height`), matching `InstantPageScrollableContentNode`'s draw setup. Cells in `layoutTableItem` start at `origin = (borderWidth/2, borderWidth/2)`, so the outer rect inset by `borderWidth/2` aligns the stroke center exactly on the cells' outer perimeter.

### Stroke setup

`context.setStrokeColor(self.theme.tableBorderColor.cgColor)` and `context.setLineWidth(self.borderWidth)` are set once at the top of `drawInTile`, before the per-cell loop, instead of being re-set on every iteration. They are invariant per table. `context.setFillColor(self.theme.tableHeaderColor.cgColor)` is set once at the top for the same reason. (Each cell's `saveGState` / `restoreGState` would otherwise discard and re-set these every iteration; hoisting is functionally identical and simpler.)

### Draw order

Outer border is stroked **after** every cell's fill. With a semi-transparent border this means the border composites on top of any underlying header/striped fill at the four rounded corners, matching today's `.fillStroke` semantics where the stroke draws after the fill.

## Why this gives every line exactly once

- **Interior horizontal divider between rows R and R+1.** This is the top edge of every cell starting in row R+1. Cells in row R+1 do not have `.top ∈ adjacentSides` (only row 0 does), so they all draw it. Cells in row R do not draw their bottom edge in this pass.
- **Interior vertical divider between columns C and C+1.** Symmetric: drawn as the left edge of every cell starting in column C+1.
- **Outer top edge.** Row 0 cells have `.top ∈ adjacentSides`, so they skip their top edge in Pass 1. The outer rounded rect stroke draws it once in Pass 2.
- **Outer left / right / bottom edges.** Same — Pass 1 never draws right or bottom; Pass 1 skips left when `.left ∈ adjacentSides`; Pass 2's outer stroke draws all four perimeter sides.

### colspan / rowspan

`adjacentSides` already encodes "this cell touches the table's outer boundary on this side" for the layout code's existing semantics. The new drawing logic depends only on `.top` and `.left`, both of which are computed from the cell's *starting* row/column (`i == 0` and `k == 0` checks in `layoutTableItem`). Spanning cells therefore behave correctly:

- A colspan>1 cell starting at column 0 has `.left ∈ adjacentSides` → skips its left in Pass 1 (the outer border draws it).
- The next cell to its right starts at the column where the spanning cell ends; that next cell draws its own left edge, which is the spanning cell's right boundary.
- Inside the spanning cell's footprint there is no other cell to draw an internal divider, so no internal divider is drawn — correct.
- Same logic in the rowspan dimension via `.top`.

The existing quirk where a rowspan>1 cell starting at the last row has `.bottom ∈ adjacentSides` (instead of computing on its end row) does not affect Pass 1, which never reads `.bottom`.

### Edge cases

- **No border (`borderWidth == 0`)**: Pass 1's interior-divider block is skipped; Pass 2 is skipped. Fill behavior unchanged.
- **Single-row table**: every cell has `.top ∈ adjacentSides`. Pass 1 draws no top edges (correct — no interior horizontal divider to draw). Outer border draws all four sides.
- **Single-column table**: every cell has `.left ∈ adjacentSides`. Pass 1 draws no left edges. Outer border draws all four sides.
- **1×1 table**: one cell with all four sides in `adjacentSides`. Pass 1 draws nothing. Pass 2 draws the outer rounded rect.
- **Cells without `cell.text`**: see "Empty cells preserve divider continuity" above. The early continue is removed; fill and text remain gated on `text != nil` (preserving today's no-fill behavior for empty cells); dividers run unconditionally so divider continuity is preserved.
- **Empty `cells`**: `totalWidth` is 0 in this case (`InstantPageTableItem(frame: CGRect(), totalWidth: 0.0, ...)` from the `rows.count == 0` early return in `layoutTableItem`). The outer rect would have negative width if `borderWidth > 0`. Guard Pass 2 with `self.totalWidth > 0` (or skip the whole `drawInTile` body when the cell list is empty — same effect).

## File to modify

- `submodules/InstantPageUI/Sources/InstantPageTableItem.swift`, function `drawInTile(context:)` only.

## Verification

This is a visual change with no tests. Verification path:

1. Full Bazel build per CLAUDE.md, `--continueOnError`, `--configuration=debug_sim_arm64`.
2. Open an Instant View page that contains a table inside the rich-data chat bubble (where `tableBorderColor.withMultipliedAlpha(0.25)` is in effect) and visually confirm interior gridlines and outer perimeter are the same alpha. Also open a non-bubble Instant View page (where `tableBorderColor` is opaque) and confirm no visual regression.
