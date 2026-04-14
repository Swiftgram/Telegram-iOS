# layoutForCharacterCount Implementation

## Goal

Implement `layoutForCharacterCount` and `sizeForCharacterCount` on `InteractiveTextNodeLayout` so that `ChatMessageTextBubbleContentNode` can compute the text frame size and trailing line width during reveal animations.

## File

`submodules/TelegramUI/Components/InteractiveTextComponent/Sources/InteractiveTextComponent.swift`

## Changes

### `layoutForCharacterCount(characterCount:) -> TextNodeLayout.LayoutInfo`

Replace the `preconditionFailure()` stub (keep the commented-out code above it).

Algorithm:

1. Initialize `height` from the first line's `frame.maxY` (same as commented-out code).
2. Walk segments/lines, consuming the character budget. Each line's character count comes from `characterRects?.count` if available, otherwise from the line's `range?.length` (falling back to `CTLineGetStringRange`).
3. For each line:
   - **Fully included** (remaining budget >= line's character count): use `line.frame.width` for that line's width contribution. Consume the line's characters from the budget.
   - **Cut line** (remaining budget > 0 but < line's character count): compute the string index at the cut point as `lineRange.location + remainingCharacters`. Call `CTLineGetOffsetForStringIndex(line.line, cutStringIndex, nil)` for the line width. This is the last contributing line.
   - **Beyond budget** (remaining budget <= 0): skip.
4. Track `height` as the max `line.frame.maxY` across all contributing lines.
5. Compute final values:
   - `width`: if more than one contributing line, use `self.size.width`; otherwise `ceil(maxLineWidth) + insets.left + insets.right`.
   - `height`: add `insets.top + insets.bottom + 2.0`.
   - `trailingLineWidth`: last contributing line's width + `insets.left + insets.right + 4.0`.
6. Return `TextNodeLayout.LayoutInfo(size: CGSize(width: width, height: ceil(height)), trailingLineWidth: trailingLineWidth)`.

### `sizeForCharacterCount(characterCount:) -> CGSize`

Replace the `return CGSize()` stub with:

```swift
return self.layoutForCharacterCount(characterCount: characterCount).size
```

## Non-goals

- Not deleting any commented-out code.
- Not changing `ChatMessageTextBubbleContentNode`.
