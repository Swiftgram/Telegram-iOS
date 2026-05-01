# Rich-bubble text selection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire drag-handle text selection inside `ChatMessageRichDataBubbleContentNode`, available only in context-preview mode, with cross-paragraph selection across all visible `InstantPageTextItem`s.

**Architecture:** Extend `InstantPageTextItem` with a small public surface (`attributedString` + `attributesAtPoint(_:orNearest:)` + `textRangeRects(in:)`). Add a new `InstantPageMultiTextAdapter` that implements `TextNodeProtocol` by aggregating multiple items into one character-indexed view. In the rich-bubble, gate selection on `updateIsExtractedToContextPreview`, mirroring `ChatMessageTextBubbleContentNode`.

**Tech Stack:** Swift, AsyncDisplayKit, Bazel (`build-system/Make/Make.py`); modules `Display` (TextNodeProtocol, TextRangeRectEdge), `InstantPageUI` (text item + new adapter), `TextSelectionNode`, `ChatControllerInteraction`.

**Reference spec:** `docs/superpowers/specs/2026-05-01-rich-bubble-text-selection-design.md`

**Project context:** No automated tests (per `CLAUDE.md`). Per-task verification is "Bazel build green" using:

```sh
source ~/.zshrc 2>/dev/null; python3 build-system/Make/Make.py --overrideXcodeVersion \
  --cacheDir ~/telegram-bazel-cache \
  build \
  --configurationPath build-system/appstore-configuration.json \
  --gitCodesigningRepository git@gitlab.com:peter-iakovlev/fastlanematch.git \
  --gitCodesigningType development --gitCodesigningUseCurrent --buildNumber=1 --configuration=debug_sim_arm64 \
  --continueOnError
```

The final task is a manual smoke test in the simulator.

**Working-tree note:** The user has unrelated WIP modifications in the tree (notably `submodules/InstantPageUI/Sources/InstantPageLayout.swift`, `InstantPageControllerNode.swift`, `InstantPageTheme.swift`, plus a `lineSpacingFactor: 0.9` addition in the rich-bubble). DO NOT touch those files except for the specific edits this plan calls out. Use `git add <specific-path>` — never `git add -A` / `git add .`.

---

## File map

- **Modify:** `submodules/InstantPageUI/Sources/InstantPageTextItem.swift` — promote `attributedString` to public; add a new public `attributesAtPoint(_:orNearest:)` extending the existing internal one; add a new public `textRangeRects(in:)` returning `Display.TextRangeRectEdge`.
- **Create:** `submodules/InstantPageUI/Sources/InstantPageMultiTextAdapter.swift` — new file containing `InstantPageMultiTextAdapter: ASDisplayNode, TextNodeProtocol`. No BUILD changes needed; the file is picked up by `glob(["Sources/**/*.swift"])` and `Display` is already a dep of `InstantPageUI`.
- **Modify:** `submodules/TelegramUI/Components/Chat/ChatMessageRichDataBubbleContentNode/BUILD` — add `//submodules/TextSelectionNode` to `deps`.
- **Modify:** `submodules/TelegramUI/Components/Chat/ChatMessageRichDataBubbleContentNode/Sources/ChatMessageRichDataBubbleContentNode.swift` — add `import TextSelectionNode`, two new ivars, and the lifecycle hooks.

No other files change.

---

### Task 1: Public surface on `InstantPageTextItem`

Three accessors become public so the adapter (defined in Task 2, in the same module) and external consumers can compose with the item.

**Files:**
- Modify: `submodules/InstantPageUI/Sources/InstantPageTextItem.swift`

- [ ] **Step 1: Promote `attributedString` to public**

Locate (around line 170):
```swift
public final class InstantPageTextItem: InstantPageItem {
    let attributedString: NSAttributedString
    public let lines: [InstantPageTextLine]
```

Replace with:
```swift
public final class InstantPageTextItem: InstantPageItem {
    public let attributedString: NSAttributedString
    public let lines: [InstantPageTextLine]
```

- [ ] **Step 2: Add public `attributesAtPoint(_:orNearest:)`**

The existing internal method is at line 272 of `InstantPageTextItem.swift`:

```swift
    func attributesAtPoint(_ point: CGPoint) -> (Int, [NSAttributedString.Key: Any])? {
        let transformedPoint = CGPoint(x: point.x, y: point.y)
        let boundsWidth = self.frame.width
        for i in 0 ..< self.lines.count {
            let line = self.lines[i]
            
            let lineFrame = expandedFrameForLine(line, boundingWidth: boundsWidth, alignment: self.alignment)
            if lineFrame.insetBy(dx: -5.0, dy: -5.0).contains(transformedPoint) {
                var index = CTLineGetStringIndexForPosition(line.line, CGPoint(x: transformedPoint.x - lineFrame.minX, y: transformedPoint.y - lineFrame.minY))
                if index == self.attributedString.length {
                    index -= 1
                } else if index != 0 {
                    var glyphStart: CGFloat = 0.0
                    CTLineGetOffsetForStringIndex(line.line, index, &glyphStart)
                    if transformedPoint.x < glyphStart {
                        index -= 1
                    }
                }
                if index >= 0 && index < self.attributedString.length {
                    return (index, self.attributedString.attributes(at: index, effectiveRange: nil))
                }
                break
            }
        }
        return nil
    }
```

Leave that method untouched (it's still used by `urlAttribute(at:)` and `linkSelectionRects(at:)`). Immediately after it, add the new public method:

```swift
    public func attributesAtPoint(_ point: CGPoint, orNearest: Bool) -> (Int, [NSAttributedString.Key: Any])? {
        if let direct = self.attributesAtPoint(point) {
            return direct
        }
        guard orNearest, !self.lines.isEmpty else {
            return nil
        }
        
        let boundsWidth = self.frame.width
        var nearestLineIndex = 0
        var nearestDistance = CGFloat.greatestFiniteMagnitude
        for i in 0 ..< self.lines.count {
            let lineFrame = expandedFrameForLine(self.lines[i], boundingWidth: boundsWidth, alignment: self.alignment)
            let distance: CGFloat
            if point.y < lineFrame.minY {
                distance = lineFrame.minY - point.y
            } else if point.y > lineFrame.maxY {
                distance = point.y - lineFrame.maxY
            } else {
                distance = 0.0
            }
            if distance < nearestDistance {
                nearestDistance = distance
                nearestLineIndex = i
            }
        }
        
        let line = self.lines[nearestLineIndex]
        let lineFrame = expandedFrameForLine(line, boundingWidth: boundsWidth, alignment: self.alignment)
        let clampedX = max(lineFrame.minX, min(lineFrame.maxX, point.x))
        var index = CTLineGetStringIndexForPosition(line.line, CGPoint(x: clampedX - lineFrame.minX, y: 0.0))
        if index == self.attributedString.length {
            index -= 1
        } else if index != 0 {
            var glyphStart: CGFloat = 0.0
            CTLineGetOffsetForStringIndex(line.line, index, &glyphStart)
            if clampedX - lineFrame.minX < glyphStart {
                index -= 1
            }
        }
        guard index >= 0, index < self.attributedString.length else {
            return nil
        }
        return (index, self.attributedString.attributes(at: index, effectiveRange: nil))
    }
```

- [ ] **Step 3: Add public `textRangeRects(in:)`**

The existing internal `rangeRects(in:)` is at line 369 of the file. Leave it untouched. Add a new public method that wraps it and converts the edge type. Place it directly after the existing `rangeRects(in:)` (so the implementations live together).

```swift
    public func textRangeRects(in range: NSRange) -> (rects: [CGRect], start: TextRangeRectEdge, end: TextRangeRectEdge)? {
        guard let result = self.rangeRects(in: range), let start = result.start, let end = result.end, !result.rects.isEmpty else {
            return nil
        }
        let startEdge = TextRangeRectEdge(x: start.x, y: start.y, height: start.height)
        let endEdge = TextRangeRectEdge(x: end.x, y: end.y, height: end.height)
        return (result.rects, startEdge, endEdge)
    }
```

`TextRangeRectEdge` is in `Display`, which is already imported by `InstantPageTextItem.swift` (verify the imports near the top of the file include `import Display` — it should).

- [ ] **Step 4: Build to verify**

```sh
source ~/.zshrc 2>/dev/null; python3 build-system/Make/Make.py --overrideXcodeVersion --cacheDir ~/telegram-bazel-cache build --configurationPath build-system/appstore-configuration.json --gitCodesigningRepository git@gitlab.com:peter-iakovlev/fastlanematch.git --gitCodesigningType development --gitCodesigningUseCurrent --buildNumber=1 --configuration=debug_sim_arm64 --continueOnError
```

Expected: build succeeds.

Note: the user has unrelated WIP that may be breaking the build (a `sideInset` migration in `InstantPageLayout.swift` / `InstantPageControllerNode.swift` / `InstantPageTheme.swift`). If the build fails, check whether the failures mention `sideInset` and are inside those three files. If so, the failure is pre-existing and not from this task — flag it in your report and proceed. If failures are inside `InstantPageTextItem.swift`, those ARE from this task and need fixing.

- [ ] **Step 5: Commit**

```sh
git add submodules/InstantPageUI/Sources/InstantPageTextItem.swift
git commit -m "InstantPage: expose text-item attributedString and selection helpers"
```

---

### Task 2: `InstantPageMultiTextAdapter`

A `TextNodeProtocol`-conforming `ASDisplayNode` that aggregates multiple `InstantPageTextItem`s into a single character-indexed view, suitable for `TextSelectionNode`.

**Files:**
- Create: `submodules/InstantPageUI/Sources/InstantPageMultiTextAdapter.swift`

- [ ] **Step 1: Create the new file with the full adapter**

Write `submodules/InstantPageUI/Sources/InstantPageMultiTextAdapter.swift` containing exactly:

```swift
import Foundation
import UIKit
import AsyncDisplayKit
import Display
import TelegramCore

public final class InstantPageMultiTextAdapter: ASDisplayNode, TextNodeProtocol {
    private struct Entry {
        let item: InstantPageTextItem
        let charOffset: Int
        let frameOrigin: CGPoint
    }
    
    private let entries: [Entry]
    private let combinedString: NSAttributedString
    
    public init(items: [InstantPageTextItem]) {
        let separator = NSAttributedString(string: "\n\n")
        let combined = NSMutableAttributedString()
        var entries: [Entry] = []
        for (index, item) in items.enumerated() {
            let charOffset = combined.length
            entries.append(Entry(item: item, charOffset: charOffset, frameOrigin: item.frame.origin))
            combined.append(item.attributedString)
            if index != items.count - 1 {
                combined.append(separator)
            }
        }
        self.entries = entries
        self.combinedString = combined
        super.init()
        self.isUserInteractionEnabled = false
    }
    
    public var currentText: NSAttributedString? {
        return self.combinedString
    }
    
    public func attributesAtPoint(_ point: CGPoint, orNearest: Bool) -> (Int, [NSAttributedString.Key: Any])? {
        for entry in self.entries {
            let localPoint = CGPoint(x: point.x - entry.frameOrigin.x, y: point.y - entry.frameOrigin.y)
            if let (localIndex, attrs) = entry.item.attributesAtPoint(localPoint, orNearest: false) {
                return (entry.charOffset + localIndex, attrs)
            }
        }
        guard orNearest, !self.entries.isEmpty else {
            return nil
        }
        var nearestEntry = self.entries[0]
        var nearestDistance = CGFloat.greatestFiniteMagnitude
        for entry in self.entries {
            let frame = CGRect(origin: entry.frameOrigin, size: entry.item.frame.size)
            let distance: CGFloat
            if point.y < frame.minY {
                distance = frame.minY - point.y
            } else if point.y > frame.maxY {
                distance = point.y - frame.maxY
            } else {
                distance = 0.0
            }
            if distance < nearestDistance {
                nearestDistance = distance
                nearestEntry = entry
            }
        }
        let localPoint = CGPoint(x: point.x - nearestEntry.frameOrigin.x, y: point.y - nearestEntry.frameOrigin.y)
        if let (localIndex, attrs) = nearestEntry.item.attributesAtPoint(localPoint, orNearest: true) {
            return (nearestEntry.charOffset + localIndex, attrs)
        }
        return nil
    }
    
    public func textRangeRects(in range: NSRange) -> (rects: [CGRect], start: TextRangeRectEdge, end: TextRangeRectEdge)? {
        var allRects: [CGRect] = []
        var startEdge: TextRangeRectEdge?
        var endEdge: TextRangeRectEdge?
        for entry in self.entries {
            let itemLength = entry.item.attributedString.length
            let entryRange = NSRange(location: entry.charOffset, length: itemLength)
            let intersection = NSIntersectionRange(range, entryRange)
            if intersection.length == 0 {
                continue
            }
            let localRange = NSRange(location: intersection.location - entry.charOffset, length: intersection.length)
            guard let result = entry.item.textRangeRects(in: localRange) else {
                continue
            }
            for rect in result.rects {
                allRects.append(rect.offsetBy(dx: entry.frameOrigin.x, dy: entry.frameOrigin.y))
            }
            let translatedStart = TextRangeRectEdge(x: result.start.x + entry.frameOrigin.x, y: result.start.y + entry.frameOrigin.y, height: result.start.height)
            let translatedEnd = TextRangeRectEdge(x: result.end.x + entry.frameOrigin.x, y: result.end.y + entry.frameOrigin.y, height: result.end.height)
            if startEdge == nil {
                startEdge = translatedStart
            }
            endEdge = translatedEnd
        }
        guard !allRects.isEmpty, let start = startEdge, let end = endEdge else {
            return nil
        }
        return (allRects, start, end)
    }
}
```

- [ ] **Step 2: Build to verify**

```sh
source ~/.zshrc 2>/dev/null; python3 build-system/Make/Make.py --overrideXcodeVersion --cacheDir ~/telegram-bazel-cache build --configurationPath build-system/appstore-configuration.json --gitCodesigningRepository git@gitlab.com:peter-iakovlev/fastlanematch.git --gitCodesigningType development --gitCodesigningUseCurrent --buildNumber=1 --configuration=debug_sim_arm64 --continueOnError
```

Expected: build succeeds. The new file is picked up automatically by `glob(["Sources/**/*.swift"])` in `submodules/InstantPageUI/BUILD` (already verified). `Display` is already a dep so `TextNodeProtocol` and `TextRangeRectEdge` are reachable.

If the build fails inside the adapter file, fix and re-build. Pre-existing `sideInset` failures elsewhere are not from this task — see Task 1's note.

- [ ] **Step 3: Commit**

```sh
git add submodules/InstantPageUI/Sources/InstantPageMultiTextAdapter.swift
git commit -m "InstantPage: add multi-text adapter aggregating items as a TextNodeProtocol"
```

---

### Task 3: BUILD dep, import, and ivars

Bring `TextSelectionNode` into the rich-bubble's BUILD graph and add the two new ivars. The lifecycle methods land in Task 4.

**Files:**
- Modify: `submodules/TelegramUI/Components/Chat/ChatMessageRichDataBubbleContentNode/BUILD`
- Modify: `submodules/TelegramUI/Components/Chat/ChatMessageRichDataBubbleContentNode/Sources/ChatMessageRichDataBubbleContentNode.swift`

- [ ] **Step 1: Add `TextSelectionNode` to BUILD deps**

Locate the deps list. Currently it ends with these entries (order approximate; you'll see `GalleryUI` and `TextLoadingEffect` already present from prior work):

```
        "//submodules/TelegramUI/Components/Chat/ChatMessageBubbleContentNode",
        "//submodules/TelegramUI/Components/Chat/ChatMessageItemCommon",
        "//submodules/TelegramUI/Components/ChatControllerInteraction",
        "//submodules/TelegramUI/Components/TextLoadingEffect",
        "//submodules/TelegramUIPreferences",
        "//submodules/GalleryUI",
    ],
```

Append `"//submodules/TextSelectionNode",` immediately before the closing `],`:

```
        "//submodules/TelegramUI/Components/Chat/ChatMessageBubbleContentNode",
        "//submodules/TelegramUI/Components/Chat/ChatMessageItemCommon",
        "//submodules/TelegramUI/Components/ChatControllerInteraction",
        "//submodules/TelegramUI/Components/TextLoadingEffect",
        "//submodules/TelegramUIPreferences",
        "//submodules/GalleryUI",
        "//submodules/TextSelectionNode",
    ],
```

- [ ] **Step 2: Add the import**

In `submodules/TelegramUI/Components/Chat/ChatMessageRichDataBubbleContentNode/Sources/ChatMessageRichDataBubbleContentNode.swift`, the imports currently look like:

```swift
import Foundation
import UIKit
import AsyncDisplayKit
import Display
import TelegramCore
import Postbox
import SwiftSignalKit
import AccountContext
import ChatMessageBubbleContentNode
import ChatMessageItemCommon
import ChatControllerInteraction
import InstantPageUI
import TelegramUIPreferences
import TextLoadingEffect
```

Append `import TextSelectionNode` immediately after `import TextLoadingEffect`:

```swift
import Foundation
import UIKit
import AsyncDisplayKit
import Display
import TelegramCore
import Postbox
import SwiftSignalKit
import AccountContext
import ChatMessageBubbleContentNode
import ChatMessageItemCommon
import ChatControllerInteraction
import InstantPageUI
import TelegramUIPreferences
import TextLoadingEffect
import TextSelectionNode
```

(There may be additional imports below `TextLoadingEffect` from prior work, e.g. `GalleryUI`. If so, place `import TextSelectionNode` after them — order within the import block doesn't matter as long as you don't break alphabetization that already exists.)

- [ ] **Step 3: Add the two new ivars**

Locate the existing block of stored properties (currently around lines 27-32 — the `linkProgress*` and `linkHighlightingNode` group):

```swift
    private var linkProgressDisposable: Disposable?
    private var linkProgressRects: [CGRect]?
    private var linkHighlightingNode: LinkHighlightingNode?
    private var linkProgressView: TextLoadingEffectView?
```

Append the two new ivars immediately after `linkProgressView`:

```swift
    private var linkProgressDisposable: Disposable?
    private var linkProgressRects: [CGRect]?
    private var linkHighlightingNode: LinkHighlightingNode?
    private var linkProgressView: TextLoadingEffectView?
    private var textSelectionAdapter: InstantPageMultiTextAdapter?
    private var textSelectionNode: TextSelectionNode?
```

- [ ] **Step 4: Build to verify**

```sh
source ~/.zshrc 2>/dev/null; python3 build-system/Make/Make.py --overrideXcodeVersion --cacheDir ~/telegram-bazel-cache build --configurationPath build-system/appstore-configuration.json --gitCodesigningRepository git@gitlab.com:peter-iakovlev/fastlanematch.git --gitCodesigningType development --gitCodesigningUseCurrent --buildNumber=1 --configuration=debug_sim_arm64 --continueOnError
```

Expected: build succeeds. Unused `import TextSelectionNode` and unused private ivars don't trigger Swift warnings, so `-warnings-as-errors` stays clean.

- [ ] **Step 5: Commit**

```sh
git add submodules/TelegramUI/Components/Chat/ChatMessageRichDataBubbleContentNode/BUILD submodules/TelegramUI/Components/Chat/ChatMessageRichDataBubbleContentNode/Sources/ChatMessageRichDataBubbleContentNode.swift
git commit -m "Rich bubble: add TextSelectionNode dep and selection ivars"
```

---

### Task 4: Lifecycle hooks for entering / leaving context preview

Override `updateIsExtractedToContextPreview(_:)` to set up the adapter + `TextSelectionNode` when the bubble is lifted into the context-menu preview, and `willUpdateIsExtractedToContextPreview(_:)` to tear them down when it leaves.

**Files:**
- Modify: `submodules/TelegramUI/Components/Chat/ChatMessageRichDataBubbleContentNode/Sources/ChatMessageRichDataBubbleContentNode.swift`

- [ ] **Step 1: Replace the empty preview-lifecycle stubs**

The file currently contains two empty overrides (around the area near `updateSearchTextHighlightState`):

```swift
    override public func willUpdateIsExtractedToContextPreview(_ value: Bool) {
    }
    
    override public func updateIsExtractedToContextPreview(_ value: Bool) {
    }
```

Replace BOTH with:

```swift
    override public func willUpdateIsExtractedToContextPreview(_ value: Bool) {
        if !value, let textSelectionNode = self.textSelectionNode {
            self.textSelectionNode = nil
            self.textSelectionAdapter = nil
            textSelectionNode.highlightAreaNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false)
            textSelectionNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false, completion: { [weak textSelectionNode] _ in
                textSelectionNode?.highlightAreaNode.removeFromSupernode()
                textSelectionNode?.removeFromSupernode()
            })
        }
    }
    
    override public func updateIsExtractedToContextPreview(_ value: Bool) {
        guard value, self.textSelectionNode == nil, let messageItem = self.item, let layout = self.currentPageLayout?.layout, let rootNode = messageItem.controllerInteraction.chatControllerNode() else {
            return
        }
        
        let items = layout.items.compactMap { $0 as? InstantPageTextItem }.filter { $0.selectable && !$0.attributedString.string.isEmpty }
        guard !items.isEmpty else {
            return
        }
        
        let adapter = InstantPageMultiTextAdapter(items: items)
        adapter.frame = self.containerNode.bounds
        self.textSelectionAdapter = adapter
        self.containerNode.addSubnode(adapter)
        
        let incoming = messageItem.message.effectivelyIncoming(messageItem.context.account.peerId)
        let theme = messageItem.presentationData.theme.theme
        let selectionColor = incoming ? theme.chat.message.incoming.textSelectionColor : theme.chat.message.outgoing.textSelectionColor
        let knobColor = incoming ? theme.chat.message.incoming.textSelectionKnobColor : theme.chat.message.outgoing.textSelectionKnobColor
        
        let textSelectionNode = TextSelectionNode(
            theme: TextSelectionTheme(selection: selectionColor, knob: knobColor, isDark: theme.overallDarkAppearance),
            strings: messageItem.presentationData.strings,
            textNodeOrView: .node(adapter),
            updateIsActive: { _ in },
            present: { [weak self] c, a in
                guard let self, let item = self.item else {
                    return
                }
                if let subject = item.associatedData.subject, case let .messageOptions(_, _, info) = subject, case .reply = info {
                    item.controllerInteraction.presentControllerInCurrent(c, a)
                } else {
                    item.controllerInteraction.presentGlobalOverlayController(c, a)
                }
            },
            rootView: { [weak rootNode] in
                return rootNode?.view
            },
            performAction: { [weak self] text, action in
                guard let self, let item = self.item else {
                    return
                }
                item.controllerInteraction.performTextSelectionAction(item.message, true, text, nil, action)
            }
        )
        
        let enableCopy = (!messageItem.associatedData.isCopyProtectionEnabled && !messageItem.message.isCopyProtected()) || messageItem.message.id.peerId.isVerificationCodes
        textSelectionNode.enableCopy = enableCopy
        textSelectionNode.enableQuote = false
        textSelectionNode.enableTranslate = true
        textSelectionNode.enableShare = true
        textSelectionNode.enableLookup = true
        
        textSelectionNode.frame = self.containerNode.bounds
        textSelectionNode.highlightAreaNode.frame = self.containerNode.bounds
        self.containerNode.addSubnode(textSelectionNode.highlightAreaNode)
        self.containerNode.addSubnode(textSelectionNode)
        self.textSelectionNode = textSelectionNode
    }
```

Notes on this block:
- `chatControllerNode()` returns `ASDisplayNode?` from `ChatControllerInteraction`. The `rootView` closure weakly captures it.
- `TextSelectionTheme(selection:knob:isDark:)` — verified against `submodules/TextSelectionNode/Sources/TextSelectionNode.swift:66`.
- `TextSelectionNode(theme:strings:textNodeOrView:updateIsActive:present:rootView:externalKnobSurface:performAction:)` — verified against the same file at line 296. We omit `externalKnobSurface` (defaulted to `nil`).
- `controllerInteraction.performTextSelectionAction(_:_:_:_:_:)` signature `(Message?, Bool, NSAttributedString, [MessageTextEntity]?, TextSelectionAction)` — verified against `ChatControllerInteraction.swift:263`.
- The `subject` pattern `case let .messageOptions(_, _, info) = subject, case .reply = info` mirrors `ChatMessageTextBubbleContentNode.swift:1651-1654`.
- `enableLookup` defaults to `true` on `TextSelectionNode`; we set it explicitly for clarity.
- The capture `[weak self]` in `present` and `performAction` is enough; we don't need to retain `self` from inside those closures because the bubble node stays alive while the selection node does.

- [ ] **Step 2: Build to verify**

```sh
source ~/.zshrc 2>/dev/null; python3 build-system/Make/Make.py --overrideXcodeVersion --cacheDir ~/telegram-bazel-cache build --configurationPath build-system/appstore-configuration.json --gitCodesigningRepository git@gitlab.com:peter-iakovlev/fastlanematch.git --gitCodesigningType development --gitCodesigningUseCurrent --buildNumber=1 --configuration=debug_sim_arm64 --continueOnError
```

Expected: build succeeds.

Common likely errors and fixes:
- "value of type 'ChatMessageItemAssociatedData' has no member 'isCopyProtectionEnabled'" → property name has changed; grep `submodules/TelegramUI/Components/Chat/ChatMessageItemCommon/Sources/` for the canonical name and substitute.
- "value of type 'PeerId' has no member 'isVerificationCodes'" → grep `submodules/TelegramCore/Sources/` for `isVerificationCodes` and import the right module if missing.
- "instance method 'presentControllerInCurrent' requires…" / similar — both `presentControllerInCurrent` and `presentGlobalOverlayController` exist on `ChatControllerInteraction` (lines 219 and 222 of `ChatControllerInteraction.swift`); their signatures take `(ViewController, Any?)`.
- Missing pre-existing failures from the user's `sideInset` migration are NOT from this task — see Task 1 Step 4's note.

- [ ] **Step 3: Commit**

```sh
git add submodules/TelegramUI/Components/Chat/ChatMessageRichDataBubbleContentNode/Sources/ChatMessageRichDataBubbleContentNode.swift
git commit -m "Rich bubble: drag-handle text selection in context-preview mode"
```

---

### Task 5: Manual smoke verification

There are no automated tests for chat UI. Final task is a hands-on smoke test in the simulator.

**Files:** none modified. Verification only.

- [ ] **Step 1: Launch the app in the simulator**

The build command run in earlier tasks produces the app binary; launch via Xcode (open `Telegram-iOS.xcworkspace` if the workspace exists locally) or run the Bazel-produced target. Sign in to a real test account.

- [ ] **Step 2: Find or send a message with a rich-data IV preview**

Send a Telegraph or t.me URL that produces an instant-view preview. The `debugRichText` experimental setting must be enabled for the preview to render via `ChatMessageRichDataBubbleContentNode` instead of the standard webpage card. (`ChatMessageBubbleItemNode.swift:386-387` is the gate.)

- [ ] **Step 3: Long-press the bubble**

Long-press the rich-data bubble. The framework lifts it into the context-preview popover, the message context menu appears alongside.

- [ ] **Step 4: Drag-select text**

Tap and drag inside the lifted preview. Drag-handles (knobs) should appear; the selection should extend across paragraphs as you drag. The selection background uses the incoming/outgoing `textSelectionColor` from the current theme.

- [ ] **Step 5: Verify the action menu**

The action menu (Copy / Translate / Share / Speak / Look Up) should appear anchored on the selection. Verify:
- Copy: places the selected text on the pasteboard. Multi-paragraph selections include `\n\n` between paragraphs.
- Quote menu item is **not** present (we explicitly disabled it).
- Translate / Share / Speak / Look Up route through the standard chat flow and behave normally.

- [ ] **Step 6: Dismiss the context preview**

Tap outside the preview or scroll away. The selection overlay and knobs fade out cleanly (alpha 1→0 over 0.2s), and the bubble returns to its normal state. Re-opening the context preview should re-create the selection nodes from scratch.

- [ ] **Step 7: Sign-off**

If steps 4–6 behave as described, the change is complete. If any step fails, capture: which step, observed vs. expected, any console output. Common deviations:
- Knobs never appear → confirm `textSelectionNode.frame` and `textSelectionNode.highlightAreaNode.frame` are both `containerNode.bounds`. If `containerNode.bounds.size` is zero at the moment of preview entry, the selection node has nothing to draw on.
- Selection rects don't line up with text → confirm `adapter.frame.origin` is `.zero` and item frames in the layout are in `containerNode`-local coords (the layout origin is `(0, 0)` inside `containerNode`; the `(1, 1)` outer offset doesn't apply here because the selection nodes live INSIDE `containerNode`).
- Cross-paragraph drag stops at paragraph boundaries → confirm `attributesAtPoint` falls through to the nearest-entry branch when `orNearest == true`.
- Copy includes wrong text → confirm `combinedString` interleaves `"\n\n"` separators between items.

---

## Self-review

**Spec coverage:**
- Spec §"API exposure on `InstantPageTextItem`" → Task 1 (all three accessors).
- Spec §"`InstantPageMultiTextAdapter`" → Task 2 (full adapter).
- Spec §"Rich-bubble lifecycle wiring" — ivars/import/BUILD dep → Task 3; `updateIsExtractedToContextPreview` / `willUpdateIsExtractedToContextPreview` → Task 4.
- Spec §"Verification" → Task 5 (manual smoke).
- Spec §"Out of scope" stays out of scope; no tasks added.

All spec sections covered.

**Placeholder scan:** None of the "TBD" / "TODO" / "implement later" / "similar to Task N" patterns are present. Each step shows the actual code or command.

**Type consistency:**
- `InstantPageMultiTextAdapter` is named the same in Task 2 (definition) and Tasks 3–4 (consumers).
- `Entry` struct is internal to the adapter and not referenced externally.
- `InstantPageTextItem.attributesAtPoint(_:orNearest:)` and `textRangeRects(in:)` are defined in Task 1 with the same signatures the adapter calls in Task 2.
- `TextSelectionNode` initializer parameters in Task 4 match the verified signature from `submodules/TextSelectionNode/Sources/TextSelectionNode.swift:296` (`theme`, `strings`, `textNodeOrView`, `updateIsActive`, `present`, `rootView`, `performAction` — no `externalKnobSurface`).
- `TextSelectionTheme(selection:knob:isDark:)` matches the verified init at line 66 of the same file.
- `controllerInteraction.performTextSelectionAction` invocation matches `(Message?, Bool, NSAttributedString, [MessageTextEntity]?, TextSelectionAction)` from line 263 of `ChatControllerInteraction.swift`.
- `subject` pattern `.messageOptions(_, _, info)` with `case .reply = info` mirrors text-bubble exactly.
