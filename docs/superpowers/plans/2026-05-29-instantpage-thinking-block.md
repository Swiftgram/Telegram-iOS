# InstantPage V2 thinking-block rendering + cross-update view reuse — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render top-level `InstantPageBlock.thinking(RichText)` as a dimmed, always-shimmering, reusable block in the InstantPage V2 renderer (zero reveal-cost, whole-block fade-in at its index); remove the hardcoded "Thinking…" header from the rich-data bubble; and make the streaming pageView reuse views across chunks instead of rebuilding wholesale.

**Architecture:** A new `InstantPageV2LaidOutItem.thinking` case carries a single dimmed `InstantPageTextItem`; a new `InstantPageV2ThinkingView` hosts that text inside a `ShimmeringMaskView`; a new zero-cost `.thinking` reveal-cost entry fades the whole view in when the cursor reaches its index. The pageView stops rebuilding per `stableVersion` by making `InstantPageV2RenderContext.webpage` mutable and switching `ensurePageView` to update-in-place, leaning on the renderer's existing stable-id diffing — with thinking blocks placed in their own stable-id namespace so their churn never renumbers content blocks.

**Tech Stack:** Swift, UIKit, AsyncDisplayKit, CoreText; Bazel via `build-system/Make/Make.py`. **This repo has NO unit tests and NO per-module build** (CLAUDE.md) — the only build is the full `Telegram/Telegram` target, which is also the enum-arity completeness gate. Verification is therefore: (a) the full Bazel build at the integration checkpoints below, and (b) manual streaming inspection in Task 11.

---

## Spec

`docs/superpowers/specs/2026-05-29-instantpage-thinking-block-design.md`

## Build command (the integration gate)

```sh
source ~/.zshrc 2>/dev/null; python3 build-system/Make/Make.py --overrideXcodeVersion \
 --cacheDir ~/telegram-bazel-cache \
 build \
 --configurationPath build-system/appstore-configuration.json \
 --gitCodesigningRepository git@gitlab.com:peter-iakovlev/fastlanematch.git \
 --gitCodesigningType development --gitCodesigningUseCurrent --buildNumber=1 --configuration=debug_sim_arm64 \
 --continueOnError
```

`--continueOnError` surfaces every error in one pass (the enum-arity change touches many switches). The controller must drive this build directly (run_in_background + capture real exit code), not a subagent — see the `feedback_subagent_build_execution` memory.

## Completeness-gate switch inventory (every exhaustive switch over `InstantPageV2LaidOutItem` / cost-map `Entry`)

Adding `InstantPageV2LaidOutItem.thinking` breaks these and they MUST each gain a `.thinking` arm (those with a `default:` need no edit — listed for completeness):

| File | Symbol | Line (approx) | Has `default:`? |
|---|---|---|---|
| `InstantPageV2Layout.swift` | `collectMedias` | 47 | **yes — no edit** |
| `InstantPageV2Layout.swift` | `frame` computed prop | 90 | no — **edit** |
| `InstantPageV2Layout.swift` | `offsetBy` | 113 | no — **edit** |
| `InstantPageV2Layout.swift` | `layoutBlock` (switches `InstantPageBlock`, not the laid-out item) | 892 (`case .thinking`) | n/a — **replace stub** |
| `InstantPageRenderer.swift` | `reuse` | 572 | no — **edit** |
| `InstantPageRenderer.swift` | `stableId(for:atPosition:)` | 636 | no — **edit** |
| `InstantPageRenderer.swift` | `makeItemView` | 700 | no — **edit** |
| `InstantPageV2RevealCost.swift` | `computeEntries` | 258 | no — **edit** |
| `InstantPageV2RevealCost.swift` | `revealedExtent` (switches cost `Entry`) | 159 | no — **edit (new Entry case)** |
| `InstantPageV2RevealCost.swift` | `applyRevealEntry` (switches cost `Entry`) | 380 | no — **edit (new Entry case)** |

---

## Task 1: Add the `.thinking` laid-out item model

**Files:**
- Modify: `submodules/InstantPageUI/Sources/InstantPageV2Layout.swift` (enum + 2 switches)

- [ ] **Step 1: Add the item struct.** After the `InstantPageV2CodeBlockItem` struct (ends at `submodules/InstantPageUI/Sources/InstantPageV2Layout.swift:144`), insert:

```swift
public struct InstantPageV2ThinkingItem {
    public var frame: CGRect
    /// The dimmed thinking text, laid out in block-local coordinates. Drawn fully (never
    /// char-reveal-masked); the shimmer + whole-block fade are the only animations.
    public let textItem: InstantPageTextItem
}
```

- [ ] **Step 2: Add the enum case.** In `InstantPageV2LaidOutItem` (the `case formula(...)` line is `submodules/InstantPageUI/Sources/InstantPageV2Layout.swift:87`), add after it:

```swift
    case thinking(InstantPageV2ThinkingItem)
```

- [ ] **Step 3: Handle it in the `frame` computed property.** In the switch starting at `InstantPageV2Layout.swift:90`, after `case let .formula(item):   return item.frame` add:

```swift
        case let .thinking(item):          return item.frame
```

- [ ] **Step 4: Handle it in `offsetBy`.** In the switch starting at `InstantPageV2Layout.swift:113`, after the `.formula` line add:

```swift
        case var .thinking(item):         item.frame = item.frame.offsetBy(dx: delta.x, dy: delta.y); return .thinking(item)
```

- [ ] **Step 5: Commit** (will not build standalone — no per-module build exists; full build runs at the Task 6 checkpoint).

```bash
git add submodules/InstantPageUI/Sources/InstantPageV2Layout.swift
git commit -m "InstantPage V2: add .thinking laid-out item model"
```

---

## Task 2: Lay out the thinking block

**Files:**
- Modify: `submodules/InstantPageUI/Sources/InstantPageV2Layout.swift` (new `layoutThinking` + `layoutBlock` arm)

- [ ] **Step 1: Add `layoutThinking`.** Insert immediately after `layoutCodeBlock` (which ends at `submodules/InstantPageUI/Sources/InstantPageV2Layout.swift:1945`):

```swift
private func layoutThinking(
    _ text: RichText,
    boundingWidth: CGFloat,
    horizontalInset: CGFloat,
    context: inout LayoutContext
) -> [InstantPageV2LaidOutItem] {
    // Dimmed/secondary base color: the paragraph body color at reduced alpha. RichText keeps
    // its own bold/italic/link/inline-emoji formatting on top of this base (mirrors the old
    // hardcoded "Thinking…" header, which used the message theme's dimmed description color).
    let base = context.theme.textCategories.paragraph
    let dimmedAttributes = InstantPageTextAttributes(
        font: base.font,
        color: base.color.withAlphaComponent(0.55),
        underline: false
    )
    let styleStack = InstantPageTextStyleStack()
    setupStyleStack(styleStack, theme: context.theme, attributes: dimmedAttributes)
    let attributedString = attributedStringForRichText(text, styleStack: styleStack)

    let (textItem, _, textSize) = layoutTextItem(
        attributedString,
        boundingWidth: boundingWidth - horizontalInset * 2.0,
        offset: CGPoint(x: horizontalInset, y: 0.0),
        fitToWidth: context.fitToWidth,
        computeRevealCharacterRects: context.computeRevealCharacterRects
    )
    guard let textItem = textItem else { return [] }

    let blockFrame = CGRect(x: 0.0, y: 0.0, width: boundingWidth, height: textSize.height)
    return [.thinking(InstantPageV2ThinkingItem(frame: blockFrame, textItem: textItem))]
}
```

- [ ] **Step 2: Replace the `layoutBlock` stub.** At `submodules/InstantPageUI/Sources/InstantPageV2Layout.swift:892`, replace:

```swift
    case .thinking:
        return []
```

with:

```swift
    case let .thinking(text):
        return layoutThinking(text, boundingWidth: boundingWidth,
                              horizontalInset: horizontalInset, context: &context)
```

- [ ] **Step 3: Commit.**

```bash
git add submodules/InstantPageUI/Sources/InstantPageV2Layout.swift
git commit -m "InstantPage V2: lay out .thinking block as dimmed text"
```

---

## Task 3: Add the `ShimmeringMask` dependency to InstantPageUI

**Files:**
- Modify: `submodules/InstantPageUI/BUILD`

- [ ] **Step 1: Inspect current deps.** Run:

```bash
grep -n "ComponentFlow\|HierarchyTracking\|ShimmeringMask\|deps = \[" submodules/InstantPageUI/BUILD
```

Expected: `//submodules/ComponentFlow:ComponentFlow` present; no `ShimmeringMask`.

- [ ] **Step 2: Add the dep.** In the `deps = [ ... ]` list of the `swift_library` in `submodules/InstantPageUI/BUILD`, add (next to the existing `ComponentFlow` line, keeping the list's existing ordering/indentation):

```python
        "//submodules/TelegramUI/Components/ShimmeringMask:ShimmeringMask",
```

`ShimmeringMask` itself depends on `ComponentFlow`, `Display`, and `HierarchyTrackingLayer`; those resolve transitively, so no other dep line is required.

- [ ] **Step 3: Commit.**

```bash
git add submodules/InstantPageUI/BUILD
git commit -m "InstantPageUI: depend on ShimmeringMask for thinking-block shimmer"
```

---

## Task 4: Add `InstantPageV2ThinkingView` + renderer wiring

**Files:**
- Modify: `submodules/InstantPageUI/Sources/InstantPageRenderer.swift` (import, stable-id enum, new view class, `makeItemView`, `reuse`, `stableId`)

- [ ] **Step 1: Import ShimmeringMask.** At the top of `submodules/InstantPageUI/Sources/InstantPageRenderer.swift`, with the other imports, add:

```swift
import ShimmeringMask
```

- [ ] **Step 2: Add the stable-id case.** In `InstantPageV2StableItemId` (`submodules/InstantPageUI/Sources/InstantPageRenderer.swift:29`), after `case details(Int)` add:

```swift
    case thinking(Int)                       // thinking-block sequence index (own namespace)
```

- [ ] **Step 3: Add the view class.** Immediately after `InstantPageV2CodeBlockView` (ends at `submodules/InstantPageUI/Sources/InstantPageRenderer.swift:1849`), insert:

```swift
// MARK: - Thinking view (dimmed shimmering reasoning block)

/// A top-level thinking block: dimmed text drawn fully, masked by a continuously-running
/// `ShimmeringMaskView`. Reveal is whole-block alpha (driven from the cost map), NOT char-by-char,
/// and the block contributes zero reveal cost. Structure mirrors `InstantPageV2CodeBlockView`
/// (container hosting an inner `InstantPageV2TextView`).
final class InstantPageV2ThinkingView: UIView, InstantPageItemView {
    private(set) var item: InstantPageV2ThinkingItem
    var itemFrame: CGRect { return self.item.frame }

    private let shimmerView: ShimmeringMaskView
    let textView: InstantPageV2TextView

    init(item: InstantPageV2ThinkingItem) {
        self.item = item
        self.shimmerView = ShimmeringMaskView(peakAlpha: 0.3, duration: 1.0)
        let innerV2TextItem = InstantPageV2TextItem(frame: item.textItem.frame, textItem: item.textItem)
        self.textView = InstantPageV2TextView(item: innerV2TextItem)

        super.init(frame: item.frame)
        self.backgroundColor = .clear
        self.addSubview(self.shimmerView)
        self.shimmerView.contentView.addSubview(self.textView)
        self.layoutContents()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Parent positions children (see CLAUDE.md "View frame ownership"): the shimmer covers the
    /// whole block; the inner text view sits at its block-local typographic frame (expanded by the
    /// text view's clipping inset, matching `InstantPageV2TextView.init`).
    private func layoutContents() {
        self.shimmerView.frame = CGRect(origin: .zero, size: self.item.frame.size)
        self.textView.frame = self.item.textItem.frame.insetBy(dx: -v2TextViewClippingInset, dy: -v2TextViewClippingInset)
        self.shimmerView.update(
            size: self.item.frame.size,
            containerWidth: self.item.frame.size.width,
            offsetX: 0.0,
            gradientWidth: 200.0,
            transition: .immediate
        )
    }

    func update(item: InstantPageV2ThinkingItem, theme: InstantPageTheme) {
        self.item = item
        let innerV2TextItem = InstantPageV2TextItem(frame: item.textItem.frame, textItem: item.textItem)
        self.textView.update(item: innerV2TextItem, theme: theme)
        self.layoutContents()
    }
}
```

- [ ] **Step 4: Wire `makeItemView`.** In the switch at `submodules/InstantPageUI/Sources/InstantPageRenderer.swift:700`, after the `case let .formula(formula):` arm (the last one), add:

```swift
        case let .thinking(thinking):
            return InstantPageV2ThinkingView(item: thinking)
```

- [ ] **Step 5: Wire `reuse`.** In the switch at `submodules/InstantPageUI/Sources/InstantPageRenderer.swift:572`, after the last media arm (before the closing `}` of the switch), add:

```swift
        case let .thinking(thinking):
            guard let v = existingView as? InstantPageV2ThinkingView else { return nil }
            v.update(item: thinking, theme: theme)
            return v
```

- [ ] **Step 6: Wire `stableId`.** In the switch at `submodules/InstantPageUI/Sources/InstantPageRenderer.swift:636`, after `case let .formula(...)` add:

```swift
        case .thinking:                return .thinking(position)
```

(The `update()` loop passes a thinking-specific index here — see Task 5.)

- [ ] **Step 7: Commit.**

```bash
git add submodules/InstantPageUI/Sources/InstantPageRenderer.swift
git commit -m "InstantPage V2: add InstantPageV2ThinkingView + renderer wiring"
```

---

## Task 5: Separate stable-id namespaces in the update loop

**Files:**
- Modify: `submodules/InstantPageUI/Sources/InstantPageRenderer.swift` (the `update()` loop at lines 215-242)

- [ ] **Step 1: Replace the enumerate loop header.** At `submodules/InstantPageUI/Sources/InstantPageRenderer.swift:215`, replace:

```swift
        for (position, item) in layout.items.enumerated() {
            let id = InstantPageV2View.stableId(for: item, atPosition: position)
```

with:

```swift
        // Two independent position counters so thinking-block churn never renumbers content
        // blocks' stable ids (requirement: adding/removing a thinking block must not affect other
        // blocks). Content items are numbered ignoring thinking items; thinking items get their
        // own .thinking(index) namespace.
        var contentPosition = 0
        var thinkingPosition = 0
        for item in layout.items {
            let id: InstantPageV2StableItemId
            if case .thinking = item {
                id = InstantPageV2View.stableId(for: item, atPosition: thinkingPosition)
                thinkingPosition += 1
            } else {
                id = InstantPageV2View.stableId(for: item, atPosition: contentPosition)
                contentPosition += 1
            }
```

(The rest of the loop body — the `if let existing … else …` block, lines 218-241 — is unchanged. Confirm the loop's closing brace still matches.)

- [ ] **Step 2: Verify no other use of the old `position` variable.** Run:

```bash
sed -n '215,243p' submodules/InstantPageUI/Sources/InstantPageRenderer.swift
```

Expected: the only references to a position value inside the loop are the two `stableId(... atPosition:)` calls just edited; `actualFrame(forItem:)` and the rest use `item`/`reusedView`, not `position`.

- [ ] **Step 3: Commit.**

```bash
git add submodules/InstantPageUI/Sources/InstantPageRenderer.swift
git commit -m "InstantPage V2: namespace thinking vs content stable ids"
```

---

## Task 6: Zero-cost reveal entry for thinking + first build checkpoint

**Files:**
- Modify: `submodules/InstantPageUI/Sources/InstantPageV2RevealCost.swift` (Entry enum + 3 switches + clear path)

- [ ] **Step 1: Add the Entry case.** In the `fileprivate enum Entry` (`submodules/InstantPageUI/Sources/InstantPageV2RevealCost.swift:14`), after `case nonText(start: Int, end: Int)` add:

```swift
        case thinking(start: Int)
```

- [ ] **Step 2: Emit a zero-cost entry in `computeEntries`.** In the switch at `submodules/InstantPageUI/Sources/InstantPageV2RevealCost.swift:258`, add a dedicated arm BEFORE the grouped `case .formula, .mediaImage, …` arm (line 326):

```swift
        case .thinking:
            // Zero cost: do NOT advance the cursor. This is the linchpin — answer-content cursor
            // positions are identical whether or not thinking blocks are present, so adding/
            // removing a thinking block never jumps the answer's reveal position.
            entries.append(.thinking(start: cursor))
```

- [ ] **Step 3: Contribute height when revealed in `revealedExtent`.** In the switch at `submodules/InstantPageUI/Sources/InstantPageV2RevealCost.swift:159`, after the `case let .nonText(start, end):` arm add:

```swift
    case let .thinking(start):
        // Revealed (and contributes its full height) once the cursor reaches its index position.
        // A top thinking block (start == 0) is revealed from the first frame.
        if revealedCount < start { return nil }
        return item.frame
```

- [ ] **Step 4: Fade the whole view in `applyRevealEntry`.** In the switch at `submodules/InstantPageUI/Sources/InstantPageV2RevealCost.swift:380`, after the `case let .nonText(start, end):` arm add:

```swift
    case let .thinking(start):
        // Whole-block 0.12s alpha fade-in at the index position; inner text is drawn fully
        // (never char-reveal-masked) — the shimmer is the only ongoing animation.
        let visible = revealedCount >= start
        applyVisibility(view: view, visible: visible, animated: animated)
```

- [ ] **Step 5: Handle the clear path.** In `clearRevealOn` (`submodules/InstantPageUI/Sources/InstantPageV2RevealCost.swift:533`), after the `InstantPageV2TableView` block (ends ~line 551, before the final `applyVisibility(view: view, visible: true, …)` line) add:

```swift
    if let thinkingView = view as? InstantPageV2ThinkingView {
        // Defensive: the inner text is never char-masked, but ensure it's full on clear.
        thinkingView.textView.updateRevealCharacterCount(value: nil, animated: animated)
    }
```

- [ ] **Step 6: Build checkpoint (full Bazel build).** This is the first point where all InstantPageUI enum-arity edits are complete. Run the build command from the top of this plan (controller-driven, run_in_background, capture exit).
  - Expected: **BUILD SUCCESSFUL**, or only errors in files this plan has not yet touched.
  - If errors: every error should name one of the inventory switches above or a typo in the new code — fix inline before committing.

- [ ] **Step 7: Commit.**

```bash
git add submodules/InstantPageUI/Sources/InstantPageV2RevealCost.swift
git commit -m "InstantPage V2: zero-cost reveal entry + whole-block fade for thinking"
```

---

## Task 7: Make the render context updatable

**Files:**
- Modify: `submodules/InstantPageUI/Sources/InstantPageRenderer.swift` (`InstantPageV2RenderContext`)

- [ ] **Step 1: Make `webpage` mutable + add an update method.** In `InstantPageV2RenderContext` (`submodules/InstantPageUI/Sources/InstantPageRenderer.swift:49`), change:

```swift
    public let webpage: TelegramMediaWebpage
```

to:

```swift
    public private(set) var webpage: TelegramMediaWebpage
```

Then, immediately after the `init(...)` closing brace (currently `submodules/InstantPageUI/Sources/InstantPageRenderer.swift:80`), add:

```swift
    /// Update the content-bearing fields for a later chunk of the SAME message. Enables the
    /// streaming bubble to reuse one V2View across `stableVersion` bumps instead of rebuilding.
    /// Only `webpage` changes across chunks; the `imageReference`/`fileReference` closures keep
    /// their construction-time `MessageReference` snapshot, which is acceptable because the message
    /// id is stable across chunks (media resolves by id) and streamed AI content carries no media.
    public func updateContent(webpage: TelegramMediaWebpage) {
        self.webpage = webpage
    }
```

- [ ] **Step 2: Commit.**

```bash
git add submodules/InstantPageUI/Sources/InstantPageRenderer.swift
git commit -m "InstantPage V2: make render context webpage updatable"
```

---

## Task 8: Reuse the pageView across chunks (`ensurePageView`)

**Files:**
- Modify: `submodules/TelegramUI/Components/Chat/ChatMessageRichDataBubbleContentNode/Sources/ChatMessageRichDataBubbleContentNode.swift` (`ensurePageView`, lines 104-145)

- [ ] **Step 1: Update-in-place on a stableVersion-only change.** In `ensurePageView` (`…/ChatMessageRichDataBubbleContentNode.swift:104`), replace the early-return + teardown block (lines 105-113):

```swift
        let key = (id: item.message.id, stableVersion: item.message.stableVersion)
        if let existing = self.pageView,
           let current = self.pageViewMessageKey,
           current.id == key.id,
           current.stableVersion == key.stableVersion {
            return existing
        }
        self.pageView?.removeFromSuperview()
        self.pageView = nil
```

with:

```swift
        let key = (id: item.message.id, stableVersion: item.message.stableVersion)
        if let existing = self.pageView, let current = self.pageViewMessageKey, current.id == key.id {
            if current.stableVersion == key.stableVersion {
                return existing
            }
            // Same message, new chunk: reuse the view. Update only the content-bearing webpage on
            // the existing render context; the subsequent pageView.update(layout:) call diffs item
            // views by stable id (content blocks keep their ids — see Task 5 — so their views and
            // in-flight reveal state persist; only added/removed blocks change). This replaces the
            // old wholesale rebuild and eliminates the per-chunk full-text-then-mask flash.
            existing.renderContext?.updateContent(webpage: webpage)
            self.pageViewMessageKey = key
            return existing
        }
        self.pageView?.removeFromSuperview()
        self.pageView = nil
```

- [ ] **Step 2: Commit.**

```bash
git add submodules/TelegramUI/Components/Chat/ChatMessageRichDataBubbleContentNode/Sources/ChatMessageRichDataBubbleContentNode.swift
git commit -m "RichData bubble: reuse pageView across streaming chunks"
```

---

## Task 9: Remove the hardcoded "Thinking…" header

**Files:**
- Modify: `submodules/TelegramUI/Components/Chat/ChatMessageRichDataBubbleContentNode/Sources/ChatMessageRichDataBubbleContentNode.swift`

This removes the built-in header and collapses `streamingHeaderOffset` to a constant `0`. Do the edits in order; several reference each other.

- [ ] **Step 1: Remove the stored properties.** Delete lines `…:52-53`:

```swift
    private var streamingStatusTextNode: InteractiveTextNodeWithEntities?
    private var streamingStatusShimmerView: ShimmeringMaskView?
```

- [ ] **Step 2: Remove the async-layout closure capture.** Delete line `…:177`:

```swift
        let streamingStatusTextLayout = InteractiveTextNodeWithEntities.asyncLayout(self.streamingStatusTextNode)
```

- [ ] **Step 3: Remove the header layout block.** Delete the whole `streamingTextLayoutAndApply` block (`…:409-425`):

```swift
                var streamingTextLayoutAndApply: (layout: InteractiveTextNodeLayout, apply: (InteractiveTextNodeWithEntities.Arguments) -> InteractiveTextNodeWithEntities)?
                if hasDraft || hadDraft {
                    //TODO:localize
                    streamingTextLayoutAndApply = streamingStatusTextLayout(InteractiveTextNodeLayoutArguments(
                        attributedString: NSAttributedString(string: "Thinking...", font: textFont, textColor: messageTheme.fileDescriptionColor),
                        backgroundColor: nil,
                        maximumNumberOfLines: 1,
                        truncationType: .end,
                        constrainedSize: textConstrainedSize,
                        alignment: .natural,
                        cutout: nil,
                        insets: textInsets,
                        lineColor: messageTheme.accentControlColor,
                        customTruncationToken: nil,
                        computeCharacterRects: true
                    ))
                }
```

- [ ] **Step 4: Replace the streaming-frame / offset block.** Replace `…:431-467` (the `var streamingTextFrame …` through the `boundingSize.height += streamingHeaderOffset` block) with a constant-zero offset:

```swift
                // The hardcoded "Thinking…" header was removed in favor of server-sent
                // InstantPageBlock.thinking blocks (rendered inside the pageView). There is no
                // header strip anymore, so the page content starts at the top of the bubble.
                let streamingHeaderOffset: CGFloat = 0.0
```

(This deletes `streamingTextFrame`, the `thinkingMinBubbleWidth` width bump, the `boundingSize.height += streamingHeaderOffset` line, and the `streamingTextSpacing` use. Keep `streamingHeaderOffset` as a `let 0.0` so the downstream references in Step 6 still compile; a follow-up could inline it, but leaving it avoids a wide diff.)

- [ ] **Step 5: Remove the now-unused `streamingTextSpacing`.** Delete line `…:406`:

```swift
                let streamingTextSpacing: CGFloat = 1.0
```

Then run `grep -n "streamingTextSpacing\|textConstrainedSize" submodules/TelegramUI/Components/Chat/ChatMessageRichDataBubbleContentNode/Sources/ChatMessageRichDataBubbleContentNode.swift` — if `textConstrainedSize` (line ~408) is now unused (it fed only the deleted header layout), delete its declaration too. The build is warnings-as-error (`project_swift_warnings_as_errors` memory), so unused `let`s fail.

- [ ] **Step 6: Remove the apply-time header wiring.** Delete the entire "2. Update the "Thinking…" header." block — `…:765-820` — from the comment `// 2. Update the "Thinking…" header.` through the closing `}` of the `else if let streamingStatusShimmerView` branch (the block that ends by removing `streamingStatusShimmerView` from its superview). After deletion, the surrounding numbered comments ("1. Compute / cache the cost map." above, "3. Drive the reveal controller." below) should be adjacent.

- [ ] **Step 7: Remove the import.** Delete line `…:18`:

```swift
import ShimmeringMask
```

- [ ] **Step 8: Grep for stragglers.** Run:

```bash
grep -n "streamingStatus\|streamingTextFrame\|streamingTextLayoutAndApply\|thinkingMinBubbleWidth\|ShimmeringMask\|Thinking" submodules/TelegramUI/Components/Chat/ChatMessageRichDataBubbleContentNode/Sources/ChatMessageRichDataBubbleContentNode.swift
```

Expected: **no matches** (the only remaining `streamingHeaderOffset` references are the `let = 0.0` and the status-node `statusAnchorY`/`statusFrameY (+ streamingHeaderOffset)` arithmetic, which now add 0 and are harmless). If any `streamingStatus*` / `streamingTextFrame` / `Thinking` match remains, remove it.

- [ ] **Step 9: Commit.**

```bash
git add submodules/TelegramUI/Components/Chat/ChatMessageRichDataBubbleContentNode/Sources/ChatMessageRichDataBubbleContentNode.swift
git commit -m "RichData bubble: remove hardcoded Thinking header (server-controlled now)"
```

---

## Task 10: Second build checkpoint (bubble changes)

**Files:** none (build + fix)

- [ ] **Step 1: Full Bazel build.** Run the build command from the top of this plan (controller-driven).
  - Expected: **BUILD SUCCESSFUL**.
  - Common failures to watch for: leftover reference to a deleted `streamingStatus*` symbol (Task 9), an unused-`let` warnings-as-error (`textConstrainedSize`/`streamingTextSpacing`), or `ShimmeringMask` import still present in the bubble. Fix inline.

- [ ] **Step 2: If fixes were needed, commit them.**

```bash
git add -A
git commit -m "Fix build after thinking-block integration"
```

---

## Task 11: Manual verification

**Files:** none

- [ ] **Step 1: Run the app on the simulator** (use the project's run tooling / XcodeBuildMCP, simulator `debug_sim_arm64`).

- [ ] **Step 2: Stream an AI rich message whose server payload includes one or more top-level `.thinking` blocks interleaved with answer content.** Confirm each, against the spec's Verification section:
  - thinking blocks render in dimmed/secondary color and **shimmer continuously** (streaming and after completion);
  - a top thinking block is visible from the start; a thinking block placed after content **fades in** (0.12s) as the reveal cursor passes its position;
  - the answer's reveal pace does **not** jump when a thinking block appears or disappears across chunks (zero-cost);
  - across chunks, answer-content blocks are **reused** — no per-chunk full-text flash, no reveal reset;
  - the bubble grows to contain revealed thinking blocks; the date/status node sits correctly with the header gone;
  - a finalized message that still carries a thinking block renders it (shimmering).

- [ ] **Step 3: Capture a screen recording / screenshots** for the PR and note any visual deltas from the spec.

---

## Task 12: Update CLAUDE.md invariants

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Rewrite the flipped invariants in the "AI streaming animation" section.** Update:
  - The bullet "**The pageView is rebuilt on every `stableVersion` bump.**" → describe the new behavior: the pageView is now **reused** across `stableVersion` bumps (same message id); `ensurePageView` updates the render context's webpage and lets `update(layout:)` diff by stable id. Views are torn down only when their block is removed.
  - The inline-emoji note "**the dict starts fresh each chunk — no orphan/leak across rebuilds**" → the dict now **persists** across chunks; stale keys are pruned within the view by `updateInlineEmoji`/`updateInlineImages`.
  - The "Status node positioning" / `streamingHeaderOffset` notes → the hardcoded "Thinking…" header is gone; `streamingHeaderOffset` is a constant `0`; thinking content is server-sent `InstantPageBlock.thinking` rendered inside the pageView.

- [ ] **Step 2: Add a new subsection documenting thinking blocks** (under the InstantPage sections), covering: top-level only; `InstantPageV2LaidOutItem.thinking` + `InstantPageV2ThinkingView` (shimmer over dimmed text); zero reveal-cost + whole-block fade at index; separate `.thinking(Int)` stable-id namespace; V1 no-op. Link the spec + this plan.

- [ ] **Step 3: Commit.**

```bash
git add CLAUDE.md
git commit -m "Docs: thinking blocks + pageView cross-chunk reuse invariants"
```

---

## Self-review notes (for the implementer)

- **Spec coverage:** Part B.2 → Task 2; B.3 → Tasks 3-4; B.4 → Task 6; A.1 → Task 7; A.2 → Task 8; A.3 → Task 5; A.4 → Task 9; CLAUDE.md risk → Task 12; V1 no-op → unchanged (the spec requires no V1 edit; `InstantPageLayout.swift` has no `InstantPageV2LaidOutItem` switch). Visual style / shimmer-always / dimmed color → Tasks 2 + 4.
- **Type consistency:** `InstantPageV2ThinkingItem` (frame + textItem) is constructed in Task 2 and consumed in Tasks 4 (view) and 6 (cost). `InstantPageV2ThinkingView.textView` (exposed `let`) is read by `clearRevealOn` in Task 6. `InstantPageV2StableItemId.thinking(Int)` defined in Task 4, produced in Tasks 4 (`stableId`) + 5 (loop). Cost `Entry.thinking(start:)` defined in Task 6 and handled in all three Entry switches in the same task.
- **No per-module build:** intermediate tasks are not independently buildable; the two full-build checkpoints (Tasks 6 and 10) are the real gates.
