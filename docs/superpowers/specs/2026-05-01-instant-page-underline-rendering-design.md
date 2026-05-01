# InstantPage underline rendering

## Problem

`layoutTextItemWithString` in `submodules/InstantPageUI/Sources/InstantPageTextItem.swift` does not handle the `NSAttributedString.Key.underlineStyle` attribute. Underline runs are produced upstream by `InstantPageTextStyleStack.textAttributes()` (`InstantPageTextStyleStack.swift:194-202`) for two distinct sources:

1. Explicit `RichText.underline` runs (push at `InstantPageTextItem.swift:607`, plus `:628` and `:657` for related cases).
2. Links whose computed foreground color matches the body-text color — the styleStack falls back to underlining them so they remain distinguishable (`InstantPageTextStyleStack.swift:200-201`).

The attribute lands on the attributed string in both cases, but the per-line attribute enumerator at `InstantPageTextItem.swift:915-938` only branches on `strikethroughStyle`, `InstantPageMarkerColorAttribute`, and `InstantPageAnchorAttribute`. Underline runs are silently dropped during layout, so they never get drawn.

The canonical handling pattern lives in `submodules/Display/Source/TextNode.swift:2061-2066` (collection during layout) and `:2619-2638` (manual draw at draw time). `TextNode` deliberately draws underlines manually (`drawUnderlinesManually = true` at `:216`) rather than letting Core Text render them, because CT's underline rendering has historic positioning, color, and clipping issues across glyph clusters and emoji.

## Goal

Render underlines in InstantPage articles wherever the styleStack emits `underlineStyle`, matching `TextNode.swift` line-for-line so a future reader sees the same shape in both files.

## Non-goals

- Wavy or double underline support — the InstantPage styleStack only emits `NSUnderlineStyle.single`.
- Changes to `InstantPageTextStyleStack` — the attribute it produces is already correct.
- Changes to the existing strikethrough draw's reliance on the context's residual fill color — out of scope, not regressed.
- Changes to `attributesAtPoint` or selection-rect logic — these read attributes directly off `attributedString`, so they already work for underlined ranges.

## Design

### New type

In `InstantPageTextItem.swift`, alongside `InstantPageTextStrikethroughItem`:

```swift
struct InstantPageTextUnderlineItem {
    let frame: CGRect
    let range: NSRange
    let color: UIColor?
}
```

`color` carries an optional `NSAttributedString.Key.underlineColor`. There is no `style` field — `.single` is the only value the styleStack emits. `range` is needed at draw time to look up `foregroundColor` per-range when `underlineColor` is absent.

### Line storage

Add `let underlineItems: [InstantPageTextUnderlineItem]` to `InstantPageTextLine`, with a matching init parameter alongside `strikethroughItems`. There is exactly one construction site for `InstantPageTextLine` (`InstantPageTextItem.swift:970`), so updating the initializer is local.

### Collection (layoutTextItemWithString)

In the `enumerateAttributes` loop currently at `InstantPageTextItem.swift:915-938`, add a parallel branch that mirrors `TextNode.swift:2061-2066`:

```swift
if let _ = attributes[NSAttributedString.Key.underlineStyle] {
    let lowerX = floor(CTLineGetOffsetForStringIndex(line, range.location, nil))
    let upperX = ceil(CTLineGetOffsetForStringIndex(line, range.location + range.length, nil))
    let x = lowerX < upperX ? lowerX : upperX
    underlineItems.append(InstantPageTextUnderlineItem(
        frame: CGRect(x: workingLineOrigin.x + x, y: workingLineOrigin.y, width: abs(upperX - lowerX), height: fontLineHeight),
        range: range,
        color: attributes[NSAttributedString.Key.underlineColor] as? UIColor
    ))
}
```

Geometry is verbatim the strikethrough branch's — same `lowerX`/`upperX` clamp and the same `workingLineOrigin.x + x` offset. The collection is independent of strikethrough; both branches can fire on the same range.

### Draw (drawInTile)

After the strikethrough draw block at `InstantPageTextItem.swift:261-266`, add:

```swift
if !line.underlineItems.isEmpty {
    for item in line.underlineItems {
        var color: UIColor? = item.color
        if color == nil {
            self.attributedString.enumerateAttributes(in: item.range, options: []) { attributes, _, _ in
                if let foreground = attributes[NSAttributedString.Key.foregroundColor] as? UIColor {
                    color = foreground
                }
            }
        }
        if let color {
            context.setFillColor(color.cgColor)
        }
        let itemFrame = item.frame.offsetBy(dx: lineFrame.minX, dy: 0.0)
        context.fill(CGRect(x: itemFrame.minX, y: itemFrame.minY + 1.0, width: itemFrame.size.width, height: 1.0))
    }
}
```

Color resolution order (`underlineColor` → per-range `foregroundColor`) and position rule (`y: minY + 1.0`, `height: 1.0`) match `TextNode.swift:2624-2638` exactly.

The `setFillColor` call is gated on a non-nil resolved color so we do not silently flip an unrelated drawing's fill color if no foreground attribute is found in the range. In practice the attributed string always carries a `foregroundColor` (set unconditionally by the styleStack at `InstantPageTextStyleStack.swift:198-211`), so the gate is defense-in-depth, not a hot path.

## Verification

- Full Bazel build via `Make.py … --configuration=debug_sim_arm64`.
- Manual smoke against an article whose body contains an explicit `<u>` block, and a separate article whose link color matches the body color (the styleStack's link-fallback case).

No unit tests exist in this project (per `CLAUDE.md`).

## Risk

Additive: a new struct, a new optional field on `InstantPageTextLine`, one new branch in the layout enumerator, one new draw block. No public API changes, no signature changes outside `InstantPageTextItem.swift`. Runs without `underlineStyle` are unaffected.
