# Character Rects Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Compute per-line glyph bounding rects during layout and store them on `InteractiveTextNodeLine`, enabling `computeRevealedLines` and reveal animations to use pre-computed geometry.

**Architecture:** Replace `characterToGlyphMapping: [Int]?` on `InteractiveTextNodeLine` with `characterRects: [CGRect]?`. Add a `computeCharacterRects` flag to `InteractiveTextNodeLayoutArguments` that gates the computation. A new helper function computes actual glyph bounding boxes via `CTFontGetBoundingRectsForGlyphs`. Thread the flag through both `calculateLayout` and `calculateLayoutV2`, and update `computeRevealedLines` and `getCharacterToGlyphMapping` to consume the new data.

**Tech Stack:** Swift, CoreText (CTRun, CTFont, CTLine)

**File:** `submodules/TelegramUI/Components/InteractiveTextComponent/Sources/InteractiveTextComponent.swift`

---

### Task 1: Add `computeCharacterRects` flag to `InteractiveTextNodeLayoutArguments`

**Files:**
- Modify: `submodules/TelegramUI/Components/InteractiveTextComponent/Sources/InteractiveTextComponent.swift:281-362`

- [ ] **Step 1: Add the property declaration**

After line 299 (`public let expandedBlocks: Set<Int>`), add:

```swift
    public let computeCharacterRects: Bool
```

- [ ] **Step 2: Add the init parameter**

In the `init` at line 301, after `expandedBlocks: Set<Int> = Set()`, add:

```swift
        computeCharacterRects: Bool = false
```

- [ ] **Step 3: Add the assignment**

In the init body, after `self.expandedBlocks = expandedBlocks` (line 338), add:

```swift
        self.computeCharacterRects = computeCharacterRects
```

- [ ] **Step 4: Propagate through `withAttributedString`**

In the `withAttributedString` method (line 341), add after `expandedBlocks: self.expandedBlocks` (line 360):

```swift
            computeCharacterRects: self.computeCharacterRects
```

- [ ] **Step 5: Commit**

```bash
git add submodules/TelegramUI/Components/InteractiveTextComponent/Sources/InteractiveTextComponent.swift
git commit -m "feat: add computeCharacterRects flag to InteractiveTextNodeLayoutArguments"
```

---

### Task 2: Replace `characterToGlyphMapping` with `characterRects` on `InteractiveTextNodeLine`

**Files:**
- Modify: `submodules/TelegramUI/Components/InteractiveTextComponent/Sources/InteractiveTextComponent.swift:113-151`

- [ ] **Step 1: Replace the property declaration**

Change line 130 from:

```swift
    let characterToGlyphMapping: [Int]?
```

to:

```swift
    let characterRects: [CGRect]?
```

- [ ] **Step 2: Update the init signature**

In the init at line 132, replace `characterToGlyphMapping: [Int]?` with `characterRects: [CGRect]?`.

- [ ] **Step 3: Update the init body**

Change line 149 from:

```swift
        self.characterToGlyphMapping = characterToGlyphMapping
```

to:

```swift
        self.characterRects = characterRects
```

- [ ] **Step 4: Commit**

```bash
git add submodules/TelegramUI/Components/InteractiveTextComponent/Sources/InteractiveTextComponent.swift
git commit -m "feat: replace characterToGlyphMapping with characterRects on InteractiveTextNodeLine"
```

---

### Task 3: Add `computeCharacterRects` helper function

**Files:**
- Modify: `submodules/TelegramUI/Components/InteractiveTextComponent/Sources/InteractiveTextComponent.swift` (insert before the `InteractiveTextNodeLine` class or after `addAttachment`, around line 1270)

- [ ] **Step 1: Write the helper function**

Insert a private free function near the other free helper functions (after `addAttachment` at ~line 1270):

```swift
private func computeCharacterRectsForLine(line: CTLine, lineRange: NSRange) -> [CGRect] {
    var result = [CGRect](repeating: CGRect.zero, count: lineRange.length)

    let glyphRuns = CTLineGetGlyphRuns(line) as NSArray
    for run in glyphRuns {
        let run = run as! CTRun
        let glyphCount = CTRunGetGlyphCount(run)
        if glyphCount == 0 {
            continue
        }

        var glyphs = [CGGlyph](repeating: 0, count: glyphCount)
        CTRunGetGlyphs(run, CFRangeMake(0, glyphCount), &glyphs)

        var positions = [CGPoint](repeating: CGPoint.zero, count: glyphCount)
        CTRunGetPositions(run, CFRangeMake(0, glyphCount), &positions)

        var stringIndices = [CFIndex](repeating: 0, count: glyphCount)
        CTRunGetStringIndices(run, CFRangeMake(0, glyphCount), &stringIndices)

        let attributes = CTRunGetAttributes(run) as NSDictionary
        guard let font = attributes[kCTFontAttributeName] as! CTFont? else {
            continue
        }

        var boundingRects = [CGRect](repeating: CGRect.zero, count: glyphCount)
        CTFontGetBoundingRectsForGlyphs(font, .default, &glyphs, &boundingRects, glyphCount)

        for i in 0 ..< glyphCount {
            let charIndex = stringIndices[i] - lineRange.location
            if charIndex >= 0 && charIndex < lineRange.length {
                let pos = positions[i]
                let bbox = boundingRects[i]
                result[charIndex] = CGRect(
                    x: pos.x + bbox.origin.x,
                    y: pos.y + bbox.origin.y,
                    width: bbox.width,
                    height: bbox.height
                )
            }
        }
    }

    return result
}
```

- [ ] **Step 2: Commit**

```bash
git add submodules/TelegramUI/Components/InteractiveTextComponent/Sources/InteractiveTextComponent.swift
git commit -m "feat: add computeCharacterRectsForLine helper"
```

---

### Task 4: Thread `computeCharacterRects` through `calculateLayout` and `calculateLayoutV2`

**Files:**
- Modify: `submodules/TelegramUI/Components/InteractiveTextComponent/Sources/InteractiveTextComponent.swift:1433-1452,2045-2051`

- [ ] **Step 1: Add parameter to `calculateLayoutV2`**

At line 1433, the signature is `private static func calculateLayoutV2(...)`. After the last parameter `expandedBlocks: Set<Int>` (line 1451), add:

```swift
        computeCharacterRects: Bool
```

- [ ] **Step 2: Add parameter to `calculateLayout`**

At line 2045, the signature is `static func calculateLayout(...)`. After `expandedBlocks: Set<Int>`, add:

```swift
        computeCharacterRects: Bool
```

- [ ] **Step 3: Pass through in `calculateLayout` body**

In the `calculateLayout` body, there are two calls to `calculateLayoutV2` (line 2050). Add `computeCharacterRects: computeCharacterRects` to both the early-return `InteractiveTextNodeLayout(...)` call (line 2047) — actually that one constructs a layout directly, not a call to V2, so skip it — and the `calculateLayoutV2(...)` call (line 2050). Add `computeCharacterRects: computeCharacterRects` as the last argument.

- [ ] **Step 4: Update the two `asyncLayout` call sites**

In `asyncLayout` (lines 2223 and 2226), there are two calls to `InteractiveTextNode.calculateLayout(...)`. Add `computeCharacterRects: arguments.computeCharacterRects` as the last argument to both.

- [ ] **Step 5: Commit**

```bash
git add submodules/TelegramUI/Components/InteractiveTextComponent/Sources/InteractiveTextComponent.swift
git commit -m "feat: thread computeCharacterRects through calculateLayout and calculateLayoutV2"
```

---

### Task 5: Update all 4 `InteractiveTextNodeLine` construction sites

**Files:**
- Modify: `submodules/TelegramUI/Components/InteractiveTextComponent/Sources/InteractiveTextComponent.swift:1619-1636,1661-1678,1720-1737,1775-1792`

- [ ] **Step 1: Title line construction (~line 1619)**

After `additionalTrailingLine: nil` (line 1635), add:

```swift
                        characterRects: nil
```

Title lines don't need character rects (they have `range: nil`).

- [ ] **Step 2: Main line construction (~line 1661)**

After `additionalTrailingLine: nil` (line 1677), add:

```swift
                        characterRects: computeCharacterRects ? computeCharacterRectsForLine(line: line, lineRange: NSRange(location: currentLineStartIndex, length: lineCharacterCount)) : nil
```

Note: `computeCharacterRects` here refers to the parameter passed into `calculateLayoutV2`. The `line` variable is the `CTLine` created on line 1646.

- [ ] **Step 3: Collapsed truncation construction (~line 1720)**

After `additionalTrailingLine: (truncationToken, 0.0)` (line 1736), add:

```swift
                            characterRects: computeCharacterRects ? computeCharacterRectsForLine(line: updatedLine, lineRange: lastLine.range ?? NSRange()) : nil
```

- [ ] **Step 4: Final truncation construction (~line 1775)**

After `additionalTrailingLine: (truncationToken, truncationTokenWidth)` (line 1791), add:

```swift
                        characterRects: computeCharacterRects ? computeCharacterRectsForLine(line: updatedLine, lineRange: lastLine.range ?? NSRange()) : nil
```

- [ ] **Step 5: Commit**

```bash
git add submodules/TelegramUI/Components/InteractiveTextComponent/Sources/InteractiveTextComponent.swift
git commit -m "feat: pass characterRects at all InteractiveTextNodeLine construction sites"
```

---

### Task 6: Implement `computeRevealedLines`

**Files:**
- Modify: `submodules/TelegramUI/Components/InteractiveTextComponent/Sources/InteractiveTextComponent.swift:2798-2852`

- [ ] **Step 1: Replace the stub with working implementation**

The function at line 2798 currently has a commented-out body and returns `[]`. Replace the body (keep the commented-out code above, don't delete it) so the full function reads:

```swift
    private func computeRevealedLines(lines: [InteractiveTextNodeLine], layerSize: CGSize, offset: CGPoint, characterLimit: Int) -> [RevealLineInfo] {
        /*var result: [RevealLineInfo] = []
        ...existing commented code stays...
        return result*/
        //TODO
        var result: [RevealLineInfo] = []
        var remainingCharacters = characterLimit

        for i in 0 ..< lines.count {
            let line = lines[i]

            var lineFrame = line.frame
            lineFrame.origin.y += offset.y

            if line.isRTL {
                lineFrame.origin.x = offset.x + floor(layerSize.width - lineFrame.width)
                lineFrame = displayLineFrame(frame: lineFrame, isRTL: true, boundingRect: CGRect(origin: CGPoint(), size: layerSize), cutout: nil)
            } else {
                lineFrame.origin.x += offset.x
            }

            let lineHeight = line.ascent + line.descent

            guard let characterRects = line.characterRects else {
                result.append(RevealLineInfo(lineFrame: lineFrame, lineHeight: lineHeight, revealedWidth: remainingCharacters > 0 ? lineFrame.width : 0.0, isFull: remainingCharacters > 0, isRTL: line.isRTL))
                continue
            }

            if remainingCharacters <= 0 {
                result.append(RevealLineInfo(lineFrame: lineFrame, lineHeight: lineHeight, revealedWidth: 0.0, isFull: false, isRTL: line.isRTL))
                continue
            }

            let revealCount = min(characterRects.count, remainingCharacters)
            var revealedWidth: CGFloat = 0.0
            for j in 0 ..< revealCount {
                let rect = characterRects[j]
                if !rect.isEmpty {
                    revealedWidth = max(revealedWidth, rect.maxX)
                }
            }
            revealedWidth = ceil(revealedWidth)

            remainingCharacters -= characterRects.count
            let isFull = remainingCharacters >= 0

            result.append(RevealLineInfo(lineFrame: lineFrame, lineHeight: lineHeight, revealedWidth: revealedWidth, isFull: isFull, isRTL: line.isRTL))
        }

        return result
    }
```

- [ ] **Step 2: Commit**

```bash
git add submodules/TelegramUI/Components/InteractiveTextComponent/Sources/InteractiveTextComponent.swift
git commit -m "feat: implement computeRevealedLines using characterRects"
```

---

### Task 7: Update `getCharacterToGlyphMapping`

**Files:**
- Modify: `submodules/TelegramUI/Components/InteractiveTextComponent/Sources/InteractiveTextComponent.swift:2263-2270`

- [ ] **Step 1: Implement the method**

Replace the stub body of `getCharacterToGlyphMapping()` (lines 2263-2270) with:

```swift
    public func getCharacterToGlyphMapping() -> [Int] {
        /*guard let cachedLayout = self.cachedLayout else {
            return []
        }
        return cachedLayout.getCharacterToGlyphMapping()*/
        guard let cachedLayout = self.cachedLayout else {
            return []
        }

        var result: [Int] = []
        var cumulativeGlyphCount = 0

        for segment in cachedLayout.segments {
            for line in segment.lines {
                if let characterRects = line.characterRects {
                    for rect in characterRects {
                        if !rect.isEmpty {
                            cumulativeGlyphCount += 1
                        }
                        result.append(cumulativeGlyphCount)
                    }
                } else {
                    let glyphRuns = CTLineGetGlyphRuns(line.line) as NSArray
                    for run in glyphRuns {
                        let run = run as! CTRun
                        let glyphCount = CTRunGetGlyphCount(run)
                        for _ in 0 ..< glyphCount {
                            cumulativeGlyphCount += 1
                            result.append(cumulativeGlyphCount)
                        }
                    }
                }
            }
        }

        return result
    }
```

This preserves the API contract: returns an array where each entry is the cumulative glyph count up to that character. When `characterRects` is available, characters with `.zero` rects (ligature components) don't increment the glyph count. When `characterRects` is `nil` (flag was off), it falls back to walking CTRuns directly (1:1 glyph-to-entry mapping).

- [ ] **Step 2: Commit**

```bash
git add submodules/TelegramUI/Components/InteractiveTextComponent/Sources/InteractiveTextComponent.swift
git commit -m "feat: implement getCharacterToGlyphMapping using characterRects"
```

---

### Task 8: Build verification

- [ ] **Step 1: Run the full build**

```bash
PATH=/opt/homebrew/opt/ruby/bin:`gem environment gemdir`/bin:$PATH python3 build-system/Make/Make.py --overrideXcodeVersion --cacheDir ~/telegram-bazel-cache build --configurationPath build-system/appstore-configuration.json --gitCodesigningRepository git@gitlab.com:peter-iakovlev/fastlanematch.git --gitCodesigningType development --gitCodesigningUseCurrent --buildNumber 1 --configuration debug_sim_arm64
```

Expected: Build succeeds with no errors related to `InteractiveTextComponent.swift`.

- [ ] **Step 2: Fix any compilation errors and re-run build if needed**

- [ ] **Step 3: Final commit if any fixes were needed**

```bash
git add submodules/TelegramUI/Components/InteractiveTextComponent/Sources/InteractiveTextComponent.swift
git commit -m "fix: address build errors in character rects implementation"
```
