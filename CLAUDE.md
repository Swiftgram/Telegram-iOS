# CLAUDE.md

This file provides guidance to AI assistants when working with code in this repository.

## Build

The app is built using Bazel via the `Make.py` wrapper. There is no selective per-module build — the only supported invocation builds the full `Telegram/Telegram` target.

**Command:**

```sh
python3 build-system/Make/Make.py --overrideXcodeVersion \
 --cacheDir ~/telegram-bazel-cache \
 build \
 --configurationPath build-system/appstore-configuration.json \
 --gitCodesigningRepository git@gitlab.com:peter-iakovlev/fastlanematch.git \
 --gitCodesigningType development --gitCodesigningUseCurrent --buildNumber=1 --configuration=debug_sim_arm64
```

Add `--continueOnError` after `build` (forwards to bazel's `--keep_going`) when verifying changes that may surface errors in many files at once — it lets the full set of errors land in one pass instead of stopping at the first failing target.

The build needs `TELEGRAM_CODESIGNING_GIT_PASSWORD` in the environment. It is set in `~/.zshrc` but Claude Code's bash tool does NOT source shell config by default. Prefix build commands with `source ~/.zshrc 2>/dev/null;` to pick it up.

## Code Style Guidelines
- **Naming**: PascalCase for types, camelCase for variables/methods
- **Imports**: Group and sort imports at the top of files
- **Error Handling**: Properly handle errors with appropriate redaction of sensitive data
- **Formatting**: Use standard Swift/Objective-C formatting and spacing
- **Types**: Prefer strong typing and explicit type annotations where needed
- **Documentation**: Document public APIs with comments

## Project Structure
- Core launch and application extensions code is in `Telegram/` directory
- Most code is organized into libraries in `submodules/`
- External code is located in `third-party/`
- No tests are used at the moment

## Embedded watch app (`Telegram/WatchApp`)

A standalone watchOS Telegram client (developed in the separate `~/build/tgwatch` repo) is vendored into this repo at `Telegram/WatchApp/` and can be embedded into the **device** IPA under `Telegram.app/Watch/`. It is built by `xcodebuild` (not Bazel) and codesigned by the Bazel build.

**Build it:** add `--embedWatchApp` to a Make.py **device** build (`--configuration=debug_arm64` or `release_arm64`) together with `--watchApiId`, `--watchApiHash`, `--watchSigningIdentity`, `--watchProvisioningProfile`. Off by default (it adds a ~4-min xcodebuild step); simulator builds never embed, and the default `debug_sim_arm64` build is unaffected.

**`Telegram/WatchApp/` is a synced snapshot — do not hand-edit it.** The source of truth and dev tooling live in the `tgwatch` repo. To change the watch app, edit it there, then re-sync with `tgwatch/tools/export-sources.sh /abs/path/to/telegram-ios/Telegram/WatchApp` and commit the result. The committed `tgwatch.xcodeproj` is generated (kept via a `!tgwatch.xcodeproj` negation in `Telegram/WatchApp/.gitignore`, since the root `.gitignore` ignores `*.xcodeproj`); `.build`/`.swiftpm`/`xcuserdata` are excluded.

**How it's wired:** `//Telegram:TelegramWatchApp` (rule in `Telegram/prebuilt_watchos.bzl`) runs in **two actions**: `PrebuiltWatchosCompile` (`Telegram/prebuilt_watchos_compile.sh`) runs xcodebuild on the snapshot in a writable temp copy with PLACEHOLDER version/api values (the bundle ids are baked from the snapshot's pbxproj/Info.plist — `ph.telegra.Telegraph.watchkitapp` / `ph.telegra.Telegraph`), emitting an unsigned `.app`; `PrebuiltWatchosPatchSign` (`Telegram/prebuilt_watchos_patch.sh`) then rewrites **six** per-build Info.plist keys (`CFBundleShortVersionString`, `CFBundleVersion`, `TG_API_ID`, `TG_API_HASH`, `CFBundleIdentifier`, `WKCompanionAppBundleIdentifier`) and codesigns the `.app` + nested `TDLibFramework.framework` (identity + the watchkitapp profile from `--define`s). The result feeds the `Telegram` `ios_application`'s `watch_application` slot (gated by the `//Telegram:embedWatchApp` flag). The rule takes `bundle_id` (set to `"{telegram_bundle_id}.watchkitapp"` in `Telegram/BUILD`) and derives the host bundle id by stripping the `.watchkitapp` suffix; both are passed to the patch worker as args (not action inputs), so the patch action re-runs when the host bundle id changes but the (expensive) compile stays cached. **The compile action's only inputs are the snapshot (+ its worker)** — so changing the version, build number, api id/hash, host bundle id, or signing identity re-runs only the cheap patch+sign action, not xcodebuild; xcodebuild re-runs only when the snapshot changes. This is correct because none of those values reach the compiled binary: each lands only in the Info.plist (via `$(...)` substitution and a runtime `Bundle.main.object(forInfoDictionaryKey:)` lookup in `Secrets.swift`, except for the bundle-id keys which only Info.plist consumers read).

**Non-obvious invariants** (also in the `.bzl` comments): `AppleBundleInfo`'s public init is banned — use the internal `new_applebundleinfo`; `watch_application` requires BOTH `AppleBundleInfo` (with a non-None `infoplist` File) AND `WatchosApplicationBundleInfo`; the embedded watch app's `CFBundleShortVersionString`/`CFBundleVersion` must exactly equal the host's (sourced from `versions.json['app']` + `--define=buildNumber`); the host does NOT re-sign the embedded watch app, so the worker must sign it; the watch bundle id `ph.telegra.Telegraph.watchkitapp` must track the host `telegram_bundle_id`.

**Status:** verified with **development** signing on `debug_arm64` only. Open follow-ups before App Store shipping: secure timestamp (drop `codesign --timestamp=none`), distribution profile (`get-task-allow=false`), `release_arm64` + `altool --validate-app`, and committing a `Package.resolved` for hermetic remote-SwiftPM resolution.

## View frame ownership

A view does not control its own `frame`. The parent (or a layout system) sets the frame; the view positions its own subviews against `self.bounds` in response.

This matters in two places specifically:

- **Reusable components (`UIView`/`ASDisplayNode` subclasses).** Public methods like `update(...)` / `apply(...)` rebuild internal state, mutate child frames, and read `self.bounds` to lay them out — but they do not write `self.frame`. The caller has already chosen the frame; mutating it from inside the component overrides that choice and fights the parent's next layout pass.
- **`asyncLayout`-style content nodes.** The measure pass runs off-main and returns a size; the apply step runs on main and the chat layout system positions the node. A child view that writes `self.frame` from `update()` corrupts the size the parent just measured.

Rare exceptions: top-level view-controller views integrating with the system's first-responder/inset model. If you find yourself wanting `self.frame = …` from inside a child view, refactor so the parent positions it instead.

## AI streaming animation (rich-text bubbles)

`ChatMessageRichDataBubbleContentNode` progressively reveals InstantPage V2 content while `TypingDraftMessageAttribute` is on the message. Mirrors the older animation in `ChatMessageTextBubbleContentNode`, adapted to the heterogeneous V2 layout. The "Thinking…" indicator is now server-sent as `InstantPageBlock.thinking` rendered inside the pageView (see "InstantPage thinking blocks" section).

### Where things live

| File | Responsibility |
|---|---|
| `submodules/TelegramUI/Components/StreamingTextReveal/Sources/TextRevealController.swift` | Pacing controller, shared by both bubbles. EWMA inter-arrival → velocity-smoothed cursor. |
| `submodules/InstantPageUI/Sources/InstantPageRenderer.swift` (`InstantPageV2TextView`) | Drawing split: private `TextRenderView` does `draw(_)` inside a `renderContainer` whose layer carries a `revealMaskLayer`; new chars spawn cropped `SnippetLayer` siblings of the render container that animate in (blur + alpha + scale + position) and are absorbed into the mask on completion. Ported from `InteractiveTextComponent`. |
| `submodules/InstantPageUI/Sources/InstantPageV2RevealCost.swift` | `InstantPageV2RevealCostMap` + `InstantPageV2View.applyReveal(revealedCount:costMap:animated:)`. Bridges the global width-based cursor to per-text-view char counts (via `charCountForWidthBudget`) and per-item visibility / table-row pop-in. |
| `submodules/InstantPageUI/Sources/InstantPageV2Layout.swift` | `InstantPageTextLine.characterRects` (line-local CT coords, baseline-relative positive-up) populated when `computeRevealCharacterRects: true` is passed to `layoutInstantPageV2(...)`. Uses `CTFontGetBoundingRectsForGlyphs` for actual glyph ink, not advance widths. |
| `submodules/TelegramUI/Components/Chat/ChatMessageRichDataBubbleContentNode/...` | Streaming detection (`TypingDraftMessageAttribute`), display-link wiring, container sizing. The hardcoded "Thinking…" header was removed; thinking is now rendered by the pageView via `InstantPageBlock.thinking`. |

### Non-obvious invariants

- **Cost unit is points of width, not characters.** Each item's cost = its width in points along the reading direction. Text contributes sum of glyph ink widths; non-text items contribute `frame.width`. Table cells are floored at `cell.frame.width` so narrow- or empty-cell tables don't race through the cursor. Reveal pace becomes "points per second" — uniform across content types.
- **Mask uses per-glyph ink bounds, unioned per line.** Each revealed glyph's mask rect comes from `CTFontGetBoundingRectsForGlyphs` (not advance widths) so italics, accents, descenders are covered exactly. Per line, glyphs are unioned into one mask rect; consecutive fully-revealed lines union further — fully-revealed prefix is always one `CALayer`.
- **`containerNode` does ALL the clipping.** During streaming, containerNode is sized to `revealedItemsMaxY` (no header offset, no closing pad; `streamingHeaderOffset` is `0.0`). The bubble itself is taller (`revealedContentSize.height + 2`) — the strip below containerNode is empty bubble background. pageView keeps its full `pageLayout.contentSize`; anything past containerNode's bottom is clipped at containerNode (`clipsToBounds = true` set in init). Do NOT shorten the pageView or set `pageView.clipsToBounds`.
- **The pageView is REUSED across `stableVersion` bumps for the same message id.** `ensurePageView` calls `existing.renderContext?.updateContent(webpage:)` (where `webpage` is now a `public private(set) var` with an `updateContent` mutator) and returns the existing view; `update(layout:)` then diffs item views by stable id, tearing down only views whose block was removed. The pageView is rebuilt only when the bubble is recycled with a different message or webpage. The reveal cursor on `TextRevealController` persists across chunks; the seed re-apply (`applyReveal(revealedCount: previousAnimateGlyphCount, …, animated: false)`) is now a continuation from the reused views' state, eliminating the per-chunk flash-of-full-text-then-mask that required the earlier from-scratch re-seed.
- **Layout cache key includes `message.stableVersion`.** Each AI chunk bumps stableVersion; without this the cached layout would shadow newly-arrived content.
- **`TypingDraftMessageAttribute` is the streaming gate.** Same trigger TextBubble uses. The InstantPage's `isComplete` flag is informational only.
- **Width-based cost → char count bridge.** Mask APIs (`updateRevealCharacterCount`) still take character counts. `applyRevealEntry` calls `charCountForWidthBudget(textItem:widthBudget:)` to translate the width-based local cursor into the per-text-view character count.
- **The hardcoded "Thinking…" header was removed.** `streamingStatusTextNode`, `streamingStatusShimmerView`, and the header-layout machinery no longer exist. `streamingHeaderOffset` is now a constant `0.0` — the pageView starts at the top of the bubble. The "Thinking…" indicator is now server-sent as `InstantPageBlock.thinking` and rendered inside the pageView (see "InstantPage thinking blocks" section below).
- **Display-link tick re-layouts on extent change.** Tick reads `revealedContentSize` at the new cursor; if the height differs from the previous cursor, calls `requestFullUpdate`. So the bubble grows in flight when the cursor crosses a line/item boundary, not just between chunks. Tick passes `animated: true` to `applyReveal` to fire the snippet pop-in.

### Status node (date/time/checks) positioning

The `ChatMessageDateAndStatusNode` mirrors TextBubble's placement, adapted to the heterogeneous V2 layout. The node is a child of `self` (the content node), **not** of the clipping `containerNode`, so it is never clipped — the bubble height must be grown to contain it.

- **X is a fixed left edge, not the last line's `minX`.** Anchor x = `pageHorizontalInset` (10pt, the page layout's text inset; pageView sits at self-x 0). The status layout is measured with `boundingWidth - 2·pageHorizontalInset` (mirrors TextBubble's `boundingWidth - sideInsets`) so the right-aligned date lands at the right inset instead of off the bubble. Using `lastTextLineFrame.minX` (which is large for nested/indented last lines) shoved the date off to the right.
- **Trail the last line only when the bottom-most item is text.** `lastTextLineFrameIfLastItemIsText(in:)` (in `InstantPageV2Layout.swift`) returns the last line frame *only* when the bottom-most top-level item (max `maxY`) is a `.text`; otherwise nil, so the date wraps below all content (anchored at `contentSize.height`). For tables/images/etc. the date must not trail text buried above the final item.
- **InstantPage draws the baseline at the line frame's `maxY`** (`InstantPageRenderer` draws each line at `lineOrigin.y + lineFrame.height`), so the visible text of a plain line sits ~5pt below `maxY`. A date that **trails** on the line (`statusHeight == 0`) adds `trailingBottomPadding` (5pt) to align with the text; a date that **wraps** onto its own line below (`statusHeight > 0`) sits at the bare `maxY`. The pad is 0 for lines taller than their font line height (an inline animated emoji, ~`pointSize·24/17`, already pushes `maxY` down). `lastTextLineFrameIfLastItemIsText` returns `(frame, trailingBottomPadding)`; the bubble applies the pad only in the trailing case.
- **Bubble height leaves ~6pt below the date.** One unified formula for all cases: `boundingSize.height = max(boundingSize.height, statusBottomEdge + 6.0)`, where `statusBottomEdge = statusAnchorY + max(1, statusHeight)`. The `statusAnchorY` in the measure (`continue`) closure must mirror the `statusFrameY` in the apply closure exactly, or the date will be clipped/misplaced. (`streamingHeaderOffset` is `0.0` — there is no header offset to add.) 6pt matches TextBubble's bottom bubble inset.
- **`hasDraft` adds the same 6pt at the streaming site.** The status max() above is gated by `!hasDraft`, so during streaming (status hidden, alpha=0) it can't supply the bubble's bottom inset. A separate `boundingSize.height += 6.0` inside `if hasDraft` in the SizeBlock closure does it instead — same 6pt, so the streaming bubble's bottom breathing room matches its post-stream height and there's no 6pt grow-pop when the status node fades in at finalize. The `hadDraft && !hasDraft` finalize pass doesn't need it because `!hasDraft` re-enables the status max(). If you ever refactor the `+6.0` constant out of the status max() into a `bottomInset` (TextBubble's pattern), kill this separate term at the same time — they're two ends of the same invariant.

## InstantPage V2 table — flush frame, inset borders, rounded corners

A V2 `.table` block's item frame is **full-width / flush** with the bubble interior (so a horizontally-scrollable wide table's scroll container bleeds edge-to-edge), but the actual grid **borders start at the body-text side inset** — matching the V1 renderer. The grid card also has a **10pt rounded outer border**. Specs: [`…-table-inset-design.md`](docs/superpowers/specs/2026-05-30-instantpage-v2-table-inset-design.md), [`…-table-corner-radius-design.md`](docs/superpowers/specs/2026-05-30-instantpage-v2-table-corner-radius-design.md).

### Non-obvious invariants

- **`InstantPageV2TableItem.contentInset` (= page `horizontalInset`) is the linchpin.** `layoutTable` (`InstantPageV2Layout.swift`) sizes columns against `contentBoundingWidth = boundingWidth − horizontalInset·2` (so a fitting table aligns with body text on both sides) and stores `contentInset` on the item; the item `frame.width` is the flush `boundingWidth`, and `contentSize.width` stays the **bare grid width** (`totalWidth`, no inset).
- **The renderer (`InstantPageV2TableView`) realizes the inset as a view shift, not baked coordinates.** In `init` AND `update` it shifts the grid `contentView` to `x: contentInset`, sets `scrollView.contentSize.width = contentSize.width + contentInset * 2.0` (**margin on both sides**, mirroring V1's `InstantPageScrollableNode`), and `scrollView.clipsToBounds = true`. Cells, inner border lines, and the title stay x=0-relative inside `contentView`, so the single shift carries them all; the rounded outer border is `contentView.layer`'s own border (see below), which wraps the shifted layer automatically.
- **Scrollable tables clip to the full width with no inset on the clip.** The inset lives inside the scroll content as a symmetric margin on both sides (`contentInset * 2.0`): a fitting table (`grid + 2·inset ≤ boundingWidth`) doesn't scroll and shows both-side inset; an overflowing table rests with its left border at the inset and scrolls until its right border reaches a matching trailing inset (it does **not** jam flush against the screen edge — matches V1). The scroll-indicator threshold and `contentSize.width` use the same `+ contentInset * 2.0`, so "does it scroll" is exactly `grid > boundingWidth − 2·inset`.
- **Manual cell-coordinate helpers MUST add `contentInset`.** Because the shift is a real `contentView` frame change, UIKit `hitTest` and `self.convert(_:to:)` paths (`propagateVisibilityRect`, the row-reveal mask) handle it automatically — but the *manual* coordinate helpers `findTextItem` / `collectSelectableTextItems` (the live tap / URL / text-selection path) compute cell/title positions arithmetically and must add `table.contentInset` to the x-offset, or in-cell hit-testing is off by the inset. (These helpers still do **not** account for the table's live horizontal `scrollView.contentOffset` — a pre-existing limitation, so in-cell hit-testing is only correct at scroll offset 0.) The dead-but-symmetric `lastTextLineFrame(in:)` table branch has the same omission but has no callers.
- **The 10pt rounded outer border is `contentView.layer`'s own border, NOT sublayers.** `v2TableCornerRadius = 10.0` (`InstantPageV2Layout.swift`). The renderer sets `contentView.layer.cornerRadius`/`borderColor`/`borderWidth = bordered ? v2TableBorderWidth : 0.0` in BOTH `init` and `update` (the four straight outer-edge rect layers were removed; `lineLayers` now holds only inner grid lines). **Border-only — deliberately no `masksToBounds`:** `cornerRadius` rounds the layer's border without clipping contents (filled corner cells round their own fills separately — see next bullet), and there is **zero interaction with the streaming reveal mask** (`contentView.layer.mask`, set only during AI streaming) — the border reveals row-by-row with the rows and is part of the masked layer. The rounded card belongs to the grid (scrolls with it). For a non-empty-title table (never produced by markdown/AI), the border wraps title+grid since `contentView` includes the title region — an accepted, approved nuance.
- **Filled corner cells round their own fills to match the border.** A header/striped cell's background is a stripe `CALayer`; `tableStripeCornerMask(cellFrame:gridWidth:gridHeight:effectiveBorderWidth:)` detects which grid corners the cell's (grid-local) frame touches — `firstCol/firstRow` via `frame.min{X,Y} <= effectiveBorderWidth/2 + 0.5`, `lastCol/lastRow` via `frame.max{X,Y} >= grid{Width,Height} - …` (gridWidth = `item.contentSize.width`, gridHeight = `item.contentSize.height - gridOffsetY`) — and rounds only those corners: `stripe.cornerRadius = max(0, v2TableCornerRadius - effectiveBorderWidth)` (the `-borderWidth` leaves an even border ring; borderless → full radius) + `stripe.maskedCorners`, in BOTH `init` and `update`. A `CALayer`'s `backgroundColor` honors `cornerRadius`+`maskedCorners` with no `masksToBounds`. A full-width (colspan) header rounds both top corners; a one-row filled table rounds all four; bottom corners round only when the last row is filled. The empty-mask branch resets `cornerRadius = 0` **and** `maskedCorners = []` so reused stripes (persist across streaming chunks) don't keep stale rounding. Detection is grid-local, so it's independent of the `contentInset` shift / horizontal scroll.

## Inline custom emoji (RichText.textCustomEmoji)

`RichText.textCustomEmoji(fileId:alt:)` renders an inline **animated** custom emoji inside rich-data bubbles. Covers API parsing, Postbox + FlatBuffers serialization, and display in the InstantPage V2 renderer; the emoji participates in the streaming reveal above.

### Where things live

| File | Responsibility |
|---|---|
| `submodules/TelegramCore/Sources/SyncCore/SyncCore_RichText.swift` | Enum case `textCustomEmoji(fileId: Int64, alt: String)` + Postbox coding (discriminator 17, keys `ce.f`/`ce.a`), `==`, `plainText` (returns `alt`), and FlatBuffers codec. |
| `submodules/TelegramCore/FlatSerialization/Models/RichText.fbs` | FlatBuffers schema — `RichText_CustomEmoji` union member + table. **Source of truth**; the Bazel `flatc` genrule regenerates `*_generated.swift` at build time (the checked-in `Sources/*_generated.swift` is stale). |
| `submodules/TelegramCore/Sources/ApiUtils/RichText.swift` | `Api.RichText.textCustomEmoji` ⇄ Swift, lossless both ways. |
| `submodules/InstantPageUI/Sources/InstantPageTextItem.swift` (`attributedStringForRichText`) | Emits a single placeholder char carrying `ChatTextInputAttributes.customEmoji` (a `ChatTextInputTextCustomEmojiAttribute`) + a `CTRunDelegate` sized `font.pointSize · 24/17`. |
| `submodules/InstantPageUI/Sources/InstantPageV2Layout.swift` (line-breaker) | Collects per-line `InstantPageTextLine.emojiItems`; overwrites each placeholder char's `characterRect` with a full cell (`width = itemSize`) so it feeds the reveal cost map. |
| `submodules/InstantPageUI/Sources/InstantPageRenderer.swift` (`InstantPageV2View`) | Owns the `InlineStickerItemLayer`s: `updateInlineEmoji` (create/reuse/remove/position), `updateEmojiReveal` (reveal-driven pop-in), `updateEmojiVisibility` + `propagateVisibilityRect`. Layers attach to each text view's `emojiContainerView`. |

### Non-obvious invariants

- **flatc casing/`required` gotchas.** Edit `RichText.fbs`, not the generated Swift. Scalars (`long`) cannot be `(required)` — only strings/tables can. A union member `RichText_CustomEmoji` generates the Swift enum case `.richtextCustomemoji` (everything after the suffix's first letter is lowercased); the table type stays `TelegramCore_RichText_CustomEmoji` and field accessors keep `.fbs` casing (`value.fileId`). See the `flatbuffers-codegen` memory.
- **`ChatTextInputTextCustomEmojiAttribute` is reused end-to-end** (display layer ⇄ layout model). The attribute is written to the placeholder in `attributedStringForRichText` and read back by the V2 line-breaker under the SAME key (`ChatTextInputAttributes.customEmoji`); `InlineStickerItemLayer.init` consumes it directly and resolves the file lazily from `fileId`.
- **Emoji participates in the streaming reveal.** Its placeholder char's `characterRect` is overwritten to a full cell (width = `itemSize`, baseline-relative bottom at `y=0`), so the width-based cost map charges it like other content. `updateEmojiReveal` pops the layer in (alpha 0→1 + scale) when `charIndexInItem < currentRevealCharacterCount`; unrevealed → opacity 0.
- **Layers sit ABOVE the reveal mask.** They attach to `InstantPageV2TextView.emojiContainerView` (a sibling above `renderContainer`), NOT inside it — so the reveal mask wipes glyphs while emoji pop in independently. Adding a CTRunDelegate-glyph to the mask would clip-wipe them instead.
- **Layers are owned by `InstantPageV2View`, not the text view.** Keyed by `InlineStickerItemLayer.Key(id: fileId, index: occurrence)`. The pageView is now REUSED across `stableVersion` bumps (see streaming section), so the inline-emoji dict PERSISTS across chunks; `updateInlineEmoji` prunes stale keys (emoji whose blocks have been removed) and creates/repositions layers for new or unchanged emoji each update pass.
- **`visibilityRect` gates looping; `nil` means "not visible".** The bubble's `visibility` override pushes a full-width sub-rect to the root `pageView.visibilityRect`, re-pushed in the apply closure after `pageView.frame` is set. `propagateVisibilityRect` converts the rect into each nested V2View's coordinate space (`self.convert(_:to:)`) for details bodies / table cells+title, fanning out via each child's `didSet`.
- **CTRunDelegate extent buffers must be freed.** Every inline-attachment arm (`.image`/`.formula`/`.textCustomEmoji`) in `attributedStringForRichText` allocates an `extentBuffer`; the `dealloc` callback must `deallocate()` it (it re-runs per layout pass).

## RichText entity cases (mention / hashtag / bot command / bank card / auto link)

`RichText.textMention`, `.textMentionName(text:peerId:)`, `.textHashtag`, `.textCashtag`, `.textBotCommand`, `.textBankCard`, `.textAutoUrl`, `.textAutoEmail`, `.textAutoPhone` render the message-entity flavors of rich text inside rich-data bubbles with full tap interaction mirroring `ChatMessageTextBubbleContentNode`. Covers API parsing, Postbox + FlatBuffers serialization, display, and tap routing. (`textDate`/`textSpoiler` remain unimplemented — `.plain("")`.)

### Where things live

| File | Responsibility |
|---|---|
| `submodules/TelegramCore/Sources/SyncCore/SyncCore_RichText.swift` | The 9 enum cases (each wraps `text: RichText`; `textMentionName` adds raw `peerId: Int64`) + Postbox coding (discriminators 18–26, wrapped text under key `"t"`, mention-name peerId under `"mn.p"`), `==`, `plainText`, FlatBuffers codec. |
| `submodules/TelegramCore/FlatSerialization/Models/RichText.fbs` | Union members + tables (`RichText_MentionName` adds `peerId:long`). Source of truth — same flatc gotchas as the custom-emoji section above. |
| `submodules/TelegramCore/Sources/ApiUtils/RichText.swift` | `Api.RichText` ⇄ Swift, lossless. `textMentionName` carries `userId` ⇄ `peerId`. |
| `submodules/InstantPageUI/Sources/InstantPageTextItem.swift` (`attributedStringForRichText`) | Display: auto url/email/phone reuse the `InstantPageUrlItem` (`url:`) path; the six entity cases push `.link(false)`, recurse, then attach the matching `TelegramTextAttributes.*` key over the produced range. |
| `submodules/TelegramUI/Components/Chat/ChatMessageRichDataBubbleContentNode/...` | Tap routing: `entityForTapLocation` reads the attribute dict at the tapped point; `entityTapContent` maps keys → `ChatMessageBubbleContentTapAction.Content`. |

### Non-obvious invariants

- **Display attaches the same `TelegramTextAttributes.*` keys the chat text bubble uses; the bubble reads them back.** Contract: `textMention`→`PeerTextMention` (String); `textMentionName`→`PeerMention` (`TelegramPeerMention`, peerId built as `EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, …)` — `InstantPageTextItem` imports TelegramCore but NOT Postbox, so bare `PeerId` is out of scope); `textHashtag` AND `textCashtag`→`Hashtag` (`TelegramHashtag`; no dedicated cashtag key/tap-action — the leading `$` distinguishes them); `textBotCommand`→`BotCommand`; `textBankCard`→`BankCard`. Auto url/email/phone go through the URL path (`mailto:`/`tel:`/raw), NOT an entity key.
- **`linkSelectionRects` and the bubble tap path check all six interactive keys** (URL + the five entity keys), not just URL, so press-highlight and the link-loading shimmer cover entities too.
- **Rich-data text selection must reach a line's trailing edge.** This is general to rich-data selection, not just entities: `InstantPageTextItem.attributesAtPoint(_:orNearest:)`'s `orNearest: true` (selection-drag) path returns `line.range.upperBound` (via `CTLineGetStringRange`) when the point is at/past `lineFrame.maxX`. `TextSelectionNode` uses that index as the **exclusive** upper bound, so clamping to the last character's index — as the `orNearest: false` hit-testing path correctly does — would leave the last character/item of every line unselectable. Mirrors `Display.TextNode`. Do not collapse the two `orNearest` paths back together.

## Markdown send: entity vs. rich detection

On message send, the app auto-decides: if the typed markdown maps onto the regular message-entity set (bold/italic/code/strikethrough/spoiler/links/blockquote/fenced-code) it sends a **normal message** via the existing entity path; if it contains structure the entity set can't represent it sends a **rich message** (`RichTextMessageAttribute` carrying an `InstantPage`, rendered by `ChatMessageRichDataBubbleContentNode`). Always-on (no flag). **Effective rich triggers are headings, lists, and tables only.**

### Where things live

| File | Responsibility |
|---|---|
| `submodules/BrowserUI/Sources/BrowserMarkdown.swift` | The classifier `richMarkdownAttributeIfNeeded(context:text:)` (pre-filter `markdownMightNeedRichLayout` → parse via existing `inputRichTextAttributeFromText` → block inspection `instantPageNeedsRichLayout`/`blockIsEntityExpressible`/`richTextIsEntityExpressible`), plus the markdown→InstantPage conversion (`markdownWebpage`, `markdownBlocks(from:)`, `markdownBlocksWithGeneratedAnchors`). |
| `submodules/TelegramUI/Sources/ChatControllerNode.swift` (`sendCurrentMessage`, ~line 4860) | The gate: `if !isSpecialChatContents, let attribute = richMarkdownAttributeIfNeeded(context:, text: effectiveInputText.string)` routes to the rich branch; the unchanged `else` is the entity path. |

### Non-obvious invariants

- **Boundary rule:** send rich iff the parse yields an `InstantPageBlock` with no entity equivalent. Entity-expressible whitelist (→ normal): `.paragraph`, `.preformatted`, `.blockQuote` (empty caption), `.anchor`, `.unsupported`, **and `.divider`** (`---` is too common in casual text to trigger rich). **`.formula` (block and inline) DOES trigger rich**, gated by strict math detection (see "Formulas trigger rich messages" below) so casual `$` usage (`$5-$10`, `$FOO=$BAR`) stays plain. So effective triggers = headings, lists, tables, formulas.
- **Approach A (parse-then-inspect):** the classifier reuses the real parser, so "what triggers rich" can't drift from "what the rich renderer shows." `markdownMightNeedRichLayout` is a cheap necessary-condition over-approximation — it may over-trigger a parse but must **never** false-negative. It detects `#`, list markers, dash-lines (`-{1,}`, which also catches setext-H2 underlines → heading blocks), `\n=` (setext H1), `|`, `![`, and math delimiters `$`/`\(`/`\[` (formulas now trigger rich; the strict detection step decides whether a `$` run is actually math).
- **Chat vs. document path = `file == nil` / `context.documentURL == nil`.** `inputRichTextAttributeFromText` passes `file: nil`; the document-attachment path passes a real file. Two chat-only behaviors key off this: (a) generated heading anchors are **skipped** (`markdownBlocksWithGeneratedAnchors` runs only for documents — anchors exist for intra-document `#slug` links and otherwise prepend a spurious invisible `.anchor` block per heading); (b) a level-1 `#` heading maps to `.heading(text:, level: 1)`, not `.title` (the document/article-title treatment). H2–H6 → `.heading(level: 2…6)` for both paths. This converter only ever emits `.title` (H1-doc) or `.heading` — never `.header`/`.subheader`.
- **The classifier is fed the RAW `effectiveInputText.string`**, not the post-`convertMarkdownToAttributes` `inputText`, so inline `**bold**` survives into the rich render. The entity branch still uses the converted `inputText`.
- **Bypassed for `.customChatContents`** (business links / quick replies) via `isSpecialChatContents`. The compose/send gate lives here; **editing has its own symmetric re-classification** — see "Editing rich messages" below.
- **Transmission:** `RichTextMessageAttribute` → `Api.InputRichMessage` via `messages.sendMessage(richMessage:)` (flag bit 23, `StandaloneSendMessage.swift`); recipients reconstruct it from the incoming `richMessage` field (`StoreMessage_Telegram.swift`). The rich branch sends `text: ""` + the attribute, nils `mediaReference` (no separate webpage preview), and bypasses 4096-char chunking. iOS < 15 / oversize markdown → `inputRichTextAttributeFromText` returns nil → entity path (which chunks). 
- **`debugRichText` experimental flag is now orphaned** — it previously gated this path and is no longer read anywhere, though `DebugController`/`ExperimentalUISettings` still define/persist it. Optional cleanup.

## Editing rich messages (InstantPage → markdown)

Rich messages (`RichTextMessageAttribute`, `text == ""`) are made editable by reconstructing markdown source from the stored `InstantPage`, populating the editor with it, and re-classifying on save — the inverse of the send path above. Always-on (no flag). Images/videos are out of scope (skipped by the converter).

### Where things live

| File | Responsibility |
|---|---|
| `submodules/BrowserUI/Sources/InstantPageToMarkdown.swift` | `markdownStringFromInstantPage(_:)` — the inverse converter (block + inline + list + table + escaping). Pure, best-effort, never fails. |
| `submodules/TelegramUI/Sources/Chat/ChatControllerLoadDisplayNode.swift` | `setupEditMessage`: rich message → reconstruct markdown into the edit field. `editMessage` (save): re-classify the raw input, route rich-or-plain. |
| `submodules/TelegramStringFormatting/Sources/InstantPagePreviewText.swift` | `previewText()` extensions (`RichText`/`InstantPage*`) — one-line plaintext previews. |
| `submodules/TelegramStringFormatting/Sources/MessageContentKind.swift` | `messageContentKind` returns `.text(instantPage.previewText())` for rich, cascading to all preview surfaces. |

### Non-obvious invariants

- **The converter emits CommonMark inline, NOT the entity-regex dialect.** `**bold**`, `*italic*`, `` `code` ``, `~~strike~~`, `[text](url)` — because re-send re-parses the text through the *rich* path (`richMarkdownAttributeIfNeeded` → `NSAttributedString(markdown:)`, Apple CommonMark), not `convertMarkdownToAttributes` (whose dialect is `__italic__`/`||spoiler||`). The two parsers disagree on `__`/`*`; the rich round-trip is the contract.
- **Re-classify every edit (edit ≡ send).** `editMessage` runs the same `richMarkdownAttributeIfNeeded` on the RAW input string. Rich → `pendingUpdateMessageManager.add(text: "", entities: nil, richText: attr, …)`; else the unchanged plain path. So normal→rich (add a table) and rich→plain (drop all triggers) both work. Bypassed for `.customChatContents`.
- **Change-detection compares the rich attribute.** The save guard adds `currentRichText != richTextAttribute` (rich branch — skips no-op rich edits) and `currentRichText != nil` (plain branch — so rich→plain still saves even when `text.string` looks unchanged). `RichTextMessageAttribute` is `Equatable` on `instantPage`.
- **The `text.length == 0` early-return guard is safe for rich.** `convertMarkdownToAttributes` only rewrites inline tokens, never strips `#`/`-`/`|`, so a rich message's markdown source stays non-empty and passes; the rich branch then sends `text: ""`.
- **Known limitation:** a rich→plain edit that leaves only inline-formatted text loses `*italic*` (the entity path recognizes only `__…__`). Rare edge; the rich round-trip contract holds.
- **`previewText()` lives in TelegramStringFormatting, not TextFormat/TelegramCore.** It will gain a `strings: PresentationStrings` param (to localize the `"Photo"`/`"Video"`/`"Table"` placeholders), so it must sit in a UI-string module — `messageContentKind`/`descriptionStringForMessage` (same module) already take `strings:`. Teaching `messageContentKind` about rich cascades the preview to the edit accessory panel, reply/pinned panels, and forward preview in one place (those surfaces need no individual change).

## Copying rich messages as markdown (whole message + partial selection)

Rich messages (`RichTextMessageAttribute`, `text == ""`) are copyable as markdown two ways: the context-menu **Copy** action copies the whole message; a **text selection** inside the rich-data bubble copies just the selected range. Both reconstruct markdown that mirrors the edit round-trip (`markdownStringFromInstantPage`). Always-on.

### Where things live

| File | Responsibility |
|---|---|
| `submodules/TelegramUI/Sources/ChatInterfaceStateContextMenus.swift` | Whole-message Copy. Computes `richMessageMarkdown` from the message's `RichTextMessageAttribute.instantPage` (after `let message = messages[0]`), opens the Copy gate with `richMessageMarkdown != nil`, and short-circuits `copyTextWithEntities` to `storeMessageTextInPasteboard(markdown, entities: nil)`. |
| `submodules/BrowserUI/Sources/InstantPageToMarkdown.swift` | `markdownStringFromInstantPage` — the block-tree → markdown converter (also used by the edit round-trip). Blocks joined by `\n\n`; nested blockquotes via recursive `> ` wrapping. |
| `submodules/InstantPageUI/Sources/InstantPageTextItem.swift` | `InstantPageMarkdownBlockContext` (`kind` + `quoteDepth`) and the `markdownContext: InstantPageMarkdownBlockContext?` field on `InstantPageTextItem`. |
| `submodules/InstantPageUI/Sources/InstantPageV2Layout.swift` | `stampMarkdownContext`/`bumpQuoteDepth`; stamps `markdownContext` during layout (heading/title/code/list/blockQuote/`layoutQuoteText`/table-cell). |
| `submodules/InstantPageUI/Sources/InstantPageMultiTextAdapter.swift` | `markdownForRange(_ range: NSRange)` + the private attributed-substring→inline-markdown converter `inlineMarkdown(from:)`. |
| `submodules/TelegramUI/Components/Chat/ChatMessageRichDataBubbleContentNode/.../ChatMessageRichDataBubbleContentNode.swift` | Intercepts `.copy` in the `TextSelectionNode` `performAction` closure: `textSelectionNode.getSelection()` → `adapter.markdownForRange(range)` → stores as plain `NSAttributedString(string:)`. |

### Non-obvious invariants

- **The V2 layout discards block role.** A `.text` layout item from an `H2` heading is byte-identical to a body paragraph — heading level and the title category are dropped with no back-reference to the source `InstantPageBlock`. Precise structural markdown for a *selection* therefore requires stamping `markdownContext` at layout time (lists/code/tables/details are structurally recoverable; **heading level and `.title` are not**, so they MUST be stamped). Plain paragraphs stay `nil` (≡ plain).
- **`quoteDepth` is orthogonal to `kind`** so a heading/list/code line inside a blockquote round-trips (e.g. `> ## Title`). `bumpQuoteDepth` lifts a quote's children by 1; nested quotes accumulate. `layoutQuoteText` (single-paragraph blockquote fast path AND `.pullQuote`) bumps once — it is never reached by the multi-block recursion, so no double-count.
- **A blockquote is exploded into one text item per line.** `markdownForRange` must re-coalesce a run of consecutive `quoteDepth > 0` segments into ONE `\n`-joined block (each line prefixed at its own depth); otherwise every quote line becomes its own block separated by a blank line. Code/table/list runs are likewise coalesced (one fence; one pipe table; one tight list).
- **Both converters emit compact nested-quote markers (`>>`, not `> >`).** Selection: `String(repeating: ">", count: depth) + " "`. Whole-message: when wrapping a line that already starts with `>`, prepend a bare `>`. Keep the two in sync.
- **Inline markdown is read from display attributes, not the RichText tree.** `inlineMarkdown` inspects the slice's `UIFont` (bold/italic/mono — font-based, no symbolic-trait flag for named fonts), `.strikethroughStyle`, and `TelegramTextAttributes.URL` (→ `InstantPageUrlItem.url`, angle-bracketed if it contains `(`/`)`/space). Custom-emoji placeholders are dropped (no `alt` on the display attribute).
- **`.copy` stores plain text.** Passing `NSAttributedString(string: markdown)` through the existing `performTextSelectionAction(.copy)` path (`storeAttributedTextInPasteboard`) generates no entities, so the literal `**`/`#`/`>`/`|` survive. The whole-message Copy uses `storeMessageTextInPasteboard(_, entities: nil)` directly.
- **Fidelity caveats (intentional):** custom emoji omitted; ordered list + checkbox loses the ordinal (`-` wins); a partial table selection emits touched cells as rows (no forced header `---` separator); block prefixes apply to the whole touched line on a mid-line selection (correct markdown).

## Formulas trigger rich messages (strict math detection)

`$…$`/`$$…$$` (and `\(…\)`/`\[…\]`) math triggers a rich message, gated by a
strict boundary rule so casual `$` stays plain. Inverse companion of the
markdown-send gate above.

### Non-obvious invariants

- **Inline `$…$`/`$$…$$` detection requires a 4-way boundary** (in `markdownReplacingInlineFormulas`, `BrowserMarkdown.swift`): outer side of each delimiter = line edge OR non-alphanumeric; inner side = non-whitespace; opener/closer `$`-counts must match (1 or 2). This is what rejects `$5-$10`/`$FOO=$BAR`/`cost$5$total` (alphanumeric outer) while keeping `$x$`, `($x$)`, `the answer is $x$.`. The outer check is the addition over a plain "no-space-inside" rule.
- **Block `$$` detection** (`markdownBlockFormulaReplacement`): single-line `$$…$$` requires an exact `$$` opener (not `$$$`) and trailing whitespace only; multi-line requires a **bare** `$$` opener line. `$$x$$ trailing text` falls through to the inline rule. The `\[…\]` opener path is unchanged and exempt from these `$$`-only guards.
- **Detection is shared with the document path; the gate is chat-only.** `markdownPreparedSource` (detection) runs for both chat and document attachments. The triggers (`richTextIsEntityExpressible`/`blockIsEntityExpressible` → `.formula` is non-expressible; `$`/`\(`/`\[` in `markdownMightNeedRichLayout`) are read only by the chat classifier `richMarkdownAttributeIfNeeded`.

## InstantPageListItem task-list checkboxes (`- [ ]` / `- [x]`)

`InstantPageListItem` carries a first-class `checked: Bool?` — the **third** associated value of `.text(RichText, String?, Bool?)` / `.blocks([InstantPageBlock], String?, Bool?)`, orthogonal to the ordered-list `num` — representing a GitHub-style task-list checkbox. `nil` = not a checkbox item, `false` = unchecked, `true` = checked. Covers markdown parse, Postbox + FlatBuffers serialization, Telegram API transmission, display (V1 + V2), the edit round-trip, and previews.

Spec: [`docs/superpowers/specs/2026-05-27-instantpage-list-checkbox-design.md`](docs/superpowers/specs/2026-05-27-instantpage-list-checkbox-design.md). Plan: [`docs/superpowers/plans/2026-05-27-instantpage-list-checkbox.md`](docs/superpowers/plans/2026-05-27-instantpage-list-checkbox.md).

### Where things live

| File | Responsibility |
|---|---|
| `submodules/TelegramCore/Sources/SyncCore/SyncCore_InstantPage.swift` | The `checked: Bool?` enum payload; Postbox coding (key `"ck"`, tri-state Int32); `==`; FlatBuffers codec. Internal tri-state helpers `checkedFromTriState`/`triState(fromChecked:)`. |
| `submodules/TelegramCore/FlatSerialization/Models/InstantPageBlock.fbs` | `checkState:int32 (id: 2)` on `InstantPageListItem_Text` + `_Blocks`. **Source of truth**; the Bazel `flatc` genrule regenerates the Swift (checked-in `*_generated.swift` is stale). |
| `submodules/TelegramCore/Sources/ApiUtils/InstantPage.swift` | `checked` / `num` accessors; reads & writes the API `checkbox`=flags.0 / `checked`=flags.1 bits via `checkedFromApiFlags` / `apiFlags(fromChecked:)` across all four list-item types. |
| `submodules/BrowserUI/Sources/BrowserMarkdown.swift` | Forward parse: `markdownTaskListMarker` detects `[ ]`/`[x]`/`[X]`; the result routes into `checked` (NOT `num`). |
| `submodules/BrowserUI/Sources/InstantPageToMarkdown.swift` | Reverse: emits `- [ ] ` / `- [x] ` from `item.checked` for the edit round-trip. |
| `submodules/InstantPageUI/Sources/InstantPageV2Layout.swift` | V2 detection via `item.checked`; `.checklist(checked:colors:)` marker carrying `InstantPageV2CheckboxColors`. |
| `submodules/InstantPageUI/Sources/InstantPageRenderer.swift` | V2 marker view (`InstantPageV2ListMarkerView`) hosts a real `CheckNode`. |
| `submodules/InstantPageUI/Sources/InstantPageLayout.swift` | V1 detection via `item.checked` (renders the existing `InstantPageChecklistMarkerItem`). |
| `submodules/TelegramStringFormatting/Sources/InstantPagePreviewText.swift` | `previewText()` renders a `☐`/`☑︎` glyph + body for checkbox items. |

### Non-obvious invariants

- **`checked` is orthogonal to `num`.** The API keeps `checkbox`/`checked` as flags **separate from the list number**, so an ordered item can be both numbered AND a checkbox. This is exactly why the first-class field replaced an earlier sentinel-string-in-`num` prototype (which could not represent both). No `\u{001f}tg-md-task:*` sentinel remains anywhere.
- **API bits are `checkbox`=flags.0, `checked`=flags.1 on ALL FOUR list-item constructors** (`pageListItemText`/`Blocks` and `pageListOrderedItemText`/`Blocks`, in and out — `pageListItemText#2f58683c`, `pageListOrderedItemText#cd3ea036`, etc.). The iOS `Api.*` layer exposes only `flags: Int32`; mask the bits (`apiFlags(fromChecked:)` / `checkedFromApiFlags`). Because state rides the flags (not the text), it survives the server round-trip for sender + recipients — **including the sender's own send-confirmation echo** (`applyUpdateMessage` replaces local attributes with the server's reconstruction, `ApplyUpdateMessage.swift`).
- **Tri-state persistence `0=nil, 1=unchecked, 2=checked`** in BOTH Postbox (key `"ck"`, decoded with `decodeInt32ForKey(orElse: 0)`) and FlatBuffers (`checkState:int32`, default 0). Absent/0 → `nil`, so pre-existing stored pages decode unchanged.
- **Detection reads `item.checked != nil`** in both layout engines (was `instantPageTaskListMarkerState(item.num)`); the V2 marker kind is `.checklist(checked: item.checked == true, colors:)`. The empty-blocks `.blocks → .text(.plain(" "), num, checked)` promotion must carry `checked` through, not drop it.
- **V2 `CheckNode` is hosted directly in a plain `UIView`**, not an ASDisplayNode tree, so `checkNode.displaysAsynchronously = false` is set to avoid a first-draw blank flash. (The V2 pageView is now REUSED across streaming chunks via stable-id diffing — see the AI streaming section; `CheckNode` views survive across chunks as long as their list item is present.) `InstantPageV2CheckboxColors` (background←`panelAccentColor`, stroke←`pageBackgroundColor`, border←`controlColor`) is carried on the `.checklist` payload and mirrors the V1 `instantPageChecklistMarkerTheme`.
- **Forward parser keeps `[ ]` detection but routes to `checked`.** `markdownApplyTaskListMarker`/`markdownStrippingTaskListMarker`/`markdownTaskListMarker` still strip the marker from the item text; the state flows into `checked` while ordered items keep their real `"\(ordinal)"` number. The reverse converter emits lowercase `[x]` / `[ ]`, which the forward `hasPrefix` guards re-parse — that is the round-trip contract.
- **The enum-arity change is compile-enforced.** Adding the third associated value broke every `.text`/`.blocks` construction/destructure; the full build is the completeness gate. Read-only consumers outside the core set exist (`BrowserInstantPageContent.swift`, `CachedFaqInstantPage.swift`) — grep `\.(text|blocks)\(` repo-wide when touching the enum again.

## InstantPageBlock.blockQuote nested blocks

`InstantPageBlock.blockQuote` carries `(blocks: [InstantPageBlock], caption: RichText)` — a sequence of nested page blocks (paragraphs, headings, lists, code, even nested quotes), not the legacy text-only payload. `.pullQuote` is unchanged (still `(text: RichText, caption: RichText)`; the TL API has no `pullQuoteBlocks` constructor).

Spec: [`docs/superpowers/specs/2026-05-29-instantpage-blockquote-blocks-design.md`](docs/superpowers/specs/2026-05-29-instantpage-blockquote-blocks-design.md).

### Where things live

| File | Responsibility |
|---|---|
| `submodules/TelegramCore/Sources/SyncCore/SyncCore_InstantPage.swift` | Enum case shape; Postbox coding (legacy `"t"` lift → new `"b"` object array); equality (array-aware, mirrors `.collage`); FlatBuffers codec. |
| `submodules/TelegramCore/FlatSerialization/Models/InstantPageBlock.fbs` | `InstantPageBlock_BlockQuote`: `text` (now optional, legacy fallback) + `caption (required)` + new `blocks:[InstantPageBlock] (id: 2)`. **Source of truth**; Bazel regenerates the `*_generated.swift`. |
| `submodules/TelegramCore/Sources/ApiUtils/InstantPage.swift` | Parse both `pageBlockBlockquote` (lift text→`[.paragraph]`) and `pageBlockBlockquoteBlocks`; encode legacy-when-possible. |
| `submodules/InstantPageUI/Sources/InstantPageV2Layout.swift` | `layoutBlockQuote(blocks:…)` recurses into children; legacy single-paragraph fast path delegates to `layoutQuoteText` (the renamed shared text core, also used by `.pullQuote`). |
| `submodules/InstantPageUI/Sources/InstantPageLayout.swift` | V1 `.blockQuote` arm recurses via `layoutInstantPageBlock(...)`; same single-paragraph fast path. |
| `submodules/BrowserUI/Sources/BrowserMarkdown.swift` | Forward: one quote carrying all child blocks. Entity-expressibility gate (below). |
| `submodules/BrowserUI/Sources/InstantPageToMarkdown.swift` | Reverse: `markdownBlockQuoteBlocks(_:)` recurses per child and prefixes `> ` per line. |
| `submodules/TelegramStringFormatting/Sources/InstantPagePreviewText.swift` | Concatenates child `previewText()`s + caption. |

### Non-obvious invariants

- **Legacy shapes lift to `[.paragraph(text)]` at every decode boundary.** API `pageBlockBlockquote`, the Postbox `"t"` key (old cached pages), and the FlatBuffers `text` field (now optional) each lift into a single-paragraph blocks array. New writes emit only `blocks` (`"b"` / the FB vector). So pre-existing stored pages and older senders decode unchanged.
- **Outbound stays on the legacy wire constructor when the shape allows.** `apiInputBlock()` emits `pageBlockBlockquote` for empty or single-`.paragraph` quotes (so older recipients understand the common chat case) and `pageBlockBlockquoteBlocks` only for genuinely nested quotes.
- **Both renderers share one text core for the single-paragraph fast path.** `layoutQuoteText` (V2; the function formerly named `layoutBlockQuote`, `isPull:` distinguishes pull vs block) and the V1 fast-path branch keep the legacy italicized-body styling; nested children render with their own normal category styling.
- **Nested children use a FIXED 10pt inter-child gap, not `spacingBetweenBlocks`.** The full page-flow spacing (~27pt around quotes) is too airy when nested, and 0 is too tight. `childSpacing = 10.0` lives in both layout files; the first child hugs the container's `verticalInset` (no leading gap). Combined with a nested quote's own 4pt top inset this gives ~14pt effective separation.
- **Entity-expressibility:** a quote is entity-expressible (→ regular message path) only if its caption is empty AND every child is an entity-expressible `.paragraph`. A nested-structure or multi-paragraph quote is not, so it sends via the rich path. **Behavior change:** markdown `> p1\n>\n> p2` is now ONE quote with two paragraphs (rich) rather than two consecutive entity quotes — correct semantics.
- **The enum-arity change is compile-enforced** across all modules; the full Bazel build is the completeness gate (no per-module build). `CachedFaqInstantPage.swift` matches `case .blockQuote:` payload-less and needs no edit. `BrowserReadability.swift` constructs `.blockQuote(blocks: [.paragraph(.italic(...))], …)` and is easy to miss in the spec's file list — grep `\.blockQuote(` repo-wide when touching the case again.

## InstantPage thinking blocks (InstantPageBlock.thinking)

`InstantPageBlock.thinking(RichText)` renders server-sent reasoning as dimmed, continuously-shimmering text inside rich-data bubbles. V2 renderer only; V1 ignores the block (returns `[]`). The shimmer and fade-in mechanics are deliberately separate from the char-reveal cursor so thinking blocks do not affect the reveal pacing of the answer content that follows them.

### Where things live

| File | Responsibility |
|---|---|
| `submodules/InstantPageUI/Sources/InstantPageV2Layout.swift` | `InstantPageV2ThinkingItem` layout item + `layoutThinking(...)` (paragraph color × 0.55 alpha for the dimmed style) + `layoutBlock` `.thinking` arm. |
| `submodules/InstantPageUI/Sources/InstantPageRenderer.swift` | `InstantPageV2ThinkingView` — a `ShimmeringMaskView` wrapping a private inner `InstantPageV2TextView`; `InstantPageV2StableItemId.thinking(Int)` stable-id namespace; `makeItemView`/`reuse`/`stableId` arms for the `.thinking` item kind; the two-counter (content + thinking) stable-id loop in `InstantPageV2View.update`. |
| `submodules/InstantPageUI/Sources/InstantPageV2RevealCost.swift` | `.thinking(start:)` cost entry: contributes **zero** cursor cost; triggers whole-block alpha fade-in when `revealedCount >= start`. |
| `submodules/InstantPageUI/Sources/InstantPageLayout.swift` | V1 has no explicit `.thinking` case — it falls through `layoutInstantPageBlock`'s `default:` to an empty layout (no-op). |

### Non-obvious invariants

- **Zero reveal cost is the linchpin.** Thinking blocks do not advance the width-based cursor, so the answer's reveal position is identical whether or not thinking blocks are present — and is unaffected as they appear and disappear across streaming chunks. The answer text always reveals at the same rate regardless of how much thinking precedes it.
- **Whole-block fade, not char reveal.** The inner text is drawn fully under the shimmer mask at all times; the reveal mechanism is a simple alpha visibility keyed to the block's `start` index. A top-of-page thinking block (`start == 0`) is visible from the very first frame.
- **Shimmer runs continuously while the view is displayed** via `ShimmeringMaskView`'s `HierarchyTrackingLayer` self-animation. It does not stop when streaming ends.
- **Top-level only; separate stable-id namespace.** Thinking blocks appear only at the top level of the page. They use the `InstantPageV2StableItemId.thinking(Int)` namespace, numbered by a counter independent of content blocks. This means adding or removing a thinking block never renumbers the stable ids of content blocks — which, combined with pageView reuse, ensures content views and reveal state persist as thinking blocks come and go across chunks.
- **V1 is a no-op.** `InstantPageLayout.swift` has no `.thinking` case; the block falls through `layoutInstantPageBlock`'s `default:` to an empty layout, so V1 rendering silently skips it.

## Postbox → TelegramEngine refactor (in progress)

A gradual migration is underway to eliminate direct `import Postbox` from consumer submodules in favor of `TelegramEngine`.

**Historical record:** Wave-by-wave outcomes, the running tally of Postbox-free modules, and full verbose forms of the guidance subsections below live in [`docs/superpowers/postbox-refactor-log.md`](docs/superpowers/postbox-refactor-log.md). Read that file when you need wave-specific context, a full worked example of a pattern, or the history of a particular module's migration.

Waves landed so far (as of 2026-05-04): 238 waves plus standalone cleanups. See the log file for per-wave detail; the list of still-open migration opportunities lives in the `project_postbox_refactor_next_wave.md` memory file.

### Rules that apply to every wave

1. `TelegramCore` does **not** `@_exported import Postbox`. Once a consumer drops `import Postbox`, every remaining Postbox-type reference must use an engine-typealiased equivalent.
2. **Never typealias `Postbox`, `Account`, or `MediaBox`.** These umbrella types rename without encapsulating. Narrow utility typealiases (`MemoryBuffer`, `PostboxDecoder`, `PostboxEncoder`, `AdaptedPostboxDecoder`, `MediaResource`, …) remain allowed and expected.
3. No new engine wrapper **structs** unless the wave's spec explicitly allows — only typealiases and thin forwarding methods.
4. **Discovery first:** before adding any new engine wrapper/typealias, grep `submodules/TelegramCore/Sources/TelegramEngine/` for existing equivalents. Record the search result in the commit message.
5. **Abandonment protocol:** if a module can only be refactored by violating rule 2 or by editing a module outside the current wave's list, mark the task Abandoned with a recorded reason. Do NOT substitute a new module mid-wave.
6. Full project build per module. No unit tests exist in this project.
7. **TelegramCore never imports UIKit/Display.** `TelegramCore` is shared with the Telegram-Mac codebase; its Bazel `deps` and source files must not reference UIKit, Display, or any Apple-UI framework. UIKit-needing helpers (image scaling, rendering, etc.) stay in consumer-side submodules.
8. **Never substitute Postbox protocols (`Media`, `Peer`, `Message`) with `Any` / `AnyObject`** in code that previously used them. Type erasure throws away the domain semantics that the next reader expects. Use the matching engine wrapper (`EngineMedia`, `EnginePeer`, `EngineMessage`) — extending it as needed (e.g. add a missing case-init or convenience). If neither typealias nor wrapper covers the use site, restore the original Postbox import + type for now and flag the case for a future facade. Existing `Any`/`AnyObject` parameters predating the refactor are not in scope for this rule.

### Engine typealias cheat sheet (existing aliases)

```
PeerId              → EnginePeer.Id
MessageId           → EngineMessage.Id
MessageIndex        → EngineMessage.Index
MessageTags         → EngineMessage.Tags
MessageAttribute    → EngineMessage.Attribute
MessageFlags        → EngineMessage.Flags
MessageForwardInfo  → EngineMessage.ForwardInfo
MediaId             → EngineMedia.Id
PreferencesEntry    → EnginePreferencesEntry
TempBox             → EngineTempBox
PinnedItemId        → EngineChatList.PinnedItem.Id
MemoryBuffer        → EngineMemoryBuffer           (added 2026-04)
PostboxDecoder      → EnginePostboxDecoder         (added 2026-04)
PostboxEncoder      → EnginePostboxEncoder         (added 2026-04)
AdaptedPostboxDecoder → EngineAdaptedPostboxDecoder (added 2026-04)
ItemCollectionId    → EngineItemCollectionId       (added 2026-04-20)
FetchResourceSourceType → EngineFetchResourceSourceType (added 2026-04-20)
FetchResourceError  → EngineFetchResourceError     (added 2026-04-20)
StoryId             → EngineStoryId                (added 2026-05-02)
ChatListIndex       → EngineChatListIndex          (added 2026-05-03)
TempBoxFile         → EngineTempBoxFile            (added 2026-05-03)
ItemCollectionItemIndex → EngineItemCollectionItemIndex (added 2026-05-03)
ItemCollectionViewEntryIndex → EngineItemCollectionViewEntryIndex (added 2026-05-03)
ValueBoxEncryptionParameters → EngineValueBoxEncryptionParameters (added 2026-05-03)
MessageAndThreadId  → EngineMessageAndThreadId      (added 2026-05-03)
PeerStoryStats      → EnginePeerStoryStats          (added 2026-05-03)
MessageHistoryAnchorIndex → EngineMessageHistoryAnchorIndex (added 2026-05-03)
ChatListTotalUnreadStateCategory → EngineChatListTotalUnreadStateCategory (added 2026-05-03)
ChatListTotalUnreadStateStats → EngineChatListTotalUnreadStateStats (added 2026-05-03)
PeerSummaryCounterTags → EnginePeerSummaryCounterTags (added 2026-05-03)
ChatListTotalUnreadState → EngineChatListTotalUnreadState (added 2026-05-04)
ItemCacheEntryId    → EngineItemCacheEntryId        (added 2026-05-04)
HashFunctions       → EngineHashFunctions           (added 2026-05-04 wave 251)
CachedMediaResourceRepresentationResult → EngineCachedMediaResourceRepresentationResult (added 2026-05-04 wave 265)
MediaResourceDataFetchResult → EngineMediaResourceDataFetchResult (added 2026-05-04 wave 266)
MediaResourceDataFetchError → EngineMediaResourceDataFetchError (added 2026-05-04 wave 266)
MediaResourceStatus → EngineMediaResourceStatus     (added 2026-05-04 wave 272)
```

**Free-function thin forwarders in TelegramCore** (rule 3 allows):
- `engineFileSize(_ path:, useTotalFileAllocatedSize: Bool = false)` — forwards to Postbox's `fileSize(...)` (added 2026-05-04 wave 268)

**TelegramEngineUnauthorized.resources facade**: `UnauthorizedResources.storeResourceData(id: EngineMediaResource.Id, data:, synchronous:)` — bridges to `account.postbox.mediaBox.storeResourceData` (added 2026-05-04 wave 271)

For the `MediaResource` Postbox protocol, prefer the TelegramCore subtype `TelegramMediaResource` when the consumer's usage allows (note: `EngineMediaResource` is a wrapper **class**, not a typealias, so it is not interchangeable with the protocol).

### MediaResource → EngineMediaResource consumer migration

`EngineMediaResource` is a `final class` in `TelegramCore` wrapping a `MediaResource` value. Unlike the typealiases above it is **not** interchangeable with the protocol, but it does provide wrap/unwrap helpers:

- `EngineMediaResource(rawResource)` — wrap a raw `MediaResource`.
- `engineResource._asResource()` — unwrap to the raw `MediaResource`.
- `EngineMediaResource.ResourceData(rawResourceData)` — wrap `MediaResourceData`.
- `EngineMediaResource.Id(rawMediaResourceId)` — wrap `MediaResourceId`.

**Pattern for facade functions:** when a `TelegramEngine.<Area>` method leaks raw `MediaResource` in its public signature, **change the facade signature in place** to `EngineMediaResource` (and change any closure parameter types the same way). Bridge inside the facade body by calling the existing `_internal_*` function with `engineResource._asResource()` / wrapping raw inputs from inner closures with `EngineMediaResource(rawResource)`. Update all call sites in the same commit. The `_internal_*` function stays on raw `MediaResource` — it is the Postbox-facing layer.

Do **not** add opt-in `EngineMediaResource` overloads alongside raw-`MediaResource` overloads. Duplicate signatures fragment the public API and leave the leak in place forever.

For consumer modules, prefer `EngineMediaResource` as the type in properties, locals, generic arguments and function parameters when the usage is a pure type reference. Do **not** try to use `EngineMediaResource` where a class must conform to `TelegramMediaResource` (Postbox protocol) or override `isEqual(to: MediaResource)` — those remain `import Postbox`.

### Wave-selection guidance

Distilled lessons from waves 1–26. Each bullet below has a full-form counterpart in `postbox-refactor-log.md` (same subsection heading) with backstory, example scripts, and per-wave numbers.

**Shape selection.** The "leaf module, drop Postbox in isolation" approach (wave 1) only works when the candidate's public API doesn't leak Postbox domain types. Most candidates DO leak (`postbox: Postbox` / `account: Account` in public inits, `Media`/`Message` as public parameter types). Grep each candidate for `:\s*Postbox\b`, `:\s*Account\b`, `:\s*MediaBox\b`, and `Media`/`Message` as public parameter types before committing to a wave; abandon candidates whose public API leaks.

**Inventory at execution time, not just planning time.** Planning-time grep often undercounts. Re-inventory at Task-1 time using the full token set `\b(postbox|mediaBox|transaction|PostboxView|combinedView|MediaResource|PostboxDecoder|PostboxEncoder|MemoryBuffer)\b|^import Postbox` over the module's sources. If the count exceeds the plan, abandon before editing code rather than substituting a different module.

**Two feasible wave shapes.** Shape 1 = "per-module Postbox drop" (fragile; wave 1 lost 6 of 10 candidates). Shape 2 = "per-engine-facade-API migrate in place, update all call sites in one commit" (validated from wave 2 onward). Prefer shape 2 when the target is an API surface that multiple consumer modules depend on.

**Enum-payload migrations need full case-site grep.** When changing the payload type of a public enum, grep `case \.` / `let \.` / `\.<caseName>\(` across the enum's defining module — not just call sites of the facade that returns it. Wave 4 undercounted by 6 sites (shortcut constructions and destructures inside the same file as the facade) because the inventory only grepped facade callers.

**Unused-import sweeps** (wave-shape applied in waves 6, 14). Speculatively drop `^import Postbox$` from every candidate file, build with `--continueOnError`, extract failing files and restore their imports, iterate. After a few iterations, do pattern-based preemptive restores for files naming Postbox-only symbols (`MediaBox`, `PostboxCoding`, `PostboxDecoder`, `PostboxEncoder`, `TempBoxFile`, `ValueBoxKey`, `Postbox\b`, `PeerId`, `MessageId`, `MediaId`, `MessageIndex`, `MessageAndThreadId`, `PeerNameIndex`). Scope never leaves the consumer-module candidate set — halt if errors surface in TelegramCore / Postbox / TelegramApi. Run a matching BUILD-dep sweep immediately after (near-zero execution risk). Full methodology, scripts, and iteration-count history in the log.

**Public-Postbox-type inventory** (wave-11-pattern planning). Grep candidate modules against the full Postbox public-types allowlist, not just the pattern's target tokens. Waves before 16 missed types like `EngineMessageHistoryThread.Info` (Postbox-defined despite its "Engine" prefix) and `PeerStoryStats`. "Engine"-prefixed types can still be Postbox-defined — grep for the defining module, don't trust naming. Build allowlist with `grep -rhE "^public\s+(class|struct|enum|protocol|typealias)\s+\w+" submodules/Postbox/Sources/ | awk '{print $3}' | sed 's/[(:<].*//' | sort -u`, then grep candidates against it. Full script in the log.

**Wave-shape G: facade addition + consumer sweep in one commit** (validated across waves 19–26). Recipe:
1. Target a `MediaBox` method whose Postbox signature uses clean leaf types (`MediaResourceId`, `Data`, `String`, `Bool`) and whose return type is either non-Postbox or has an existing `Engine*` wrapper.
2. Pre-flight inventory: classify each call site as Shape A (`context.account.postbox.mediaBox.X(...)`, migratable), Shape B (different overload via `AccountContext`, migratable), Shape C (raw `account: Account` local, skip — needs per-module rework), Shape D (`self.postbox` stored field, skip). Also check for `accountManager.mediaBox.X(...)` — a separate migration path.
3. Design facade with `EngineMediaResource.Id` or `EngineMediaResource` parameters and engine-or-clean return types; preserve default argument values.
4. WIP-interference check: `git status --short | grep -v "^??"` — if any Shape-A site is in a WIP file, either skip those sites or wait.
5. Name-collision check: if the facade signature names a Swift stdlib type with availability restrictions (`RangeSet`, iOS 18+), verify the third-party module import is present in `TelegramEngineResources.swift`.
6. Batch duplicate call expressions with `replace_all=true`.
7. Cheapness: 5–50 sites per wave, single atomic commit, expected first-pass-clean build. If post-migration grep for the migrated expression returns empty (excluding Shape C/D) and build is green, commit.

Full per-shape recipe and wave-specific examples in the log.

### TelegramEngine.Resources facade inventory (as of wave 32)

All mediaBox methods with clean signatures (no Postbox-protocol leaks, no complex return-type migrations) have been migrated to `TelegramEngine.Resources`. Quick reference for consumers — all of these live in `submodules/TelegramCore/Sources/TelegramEngine/Resources/TelegramEngineResources.swift`:

| Facade | Wave | Wraps |
|---|---|---|
| `fetch(reference:userLocation:userContentType:)` | 3 | `fetchedMediaResource` |
| `status(resource:)` | 3 | `MediaBox.resourceStatus` (resource-based) |
| `status(id:, resourceSize:)` | 32 | `MediaBox.resourceStatus(_ id:, resourceSize:)` |
| `data(resource:, pathExtension:, waitUntilFetchStatus:)` | 3 | `MediaBox.resourceData` (resource-based) |
| `data(id:, attemptSynchronously:)` | 3 | `MediaBox.resourceData` (id-based, defaults to `.complete(waitUntilFetchStatus: false)`) |
| `custom(id:, fetch:, cacheTimeout:, attemptSynchronously:)` | pre-wave-21 | `MediaBox.customResourceData` |
| `httpData(url:, preserveExactUrl:)` | pre-wave-21 | `fetchHttpResource` |
| `shortLivedResourceCachePathPrefix(id:)` | 19 | `MediaBox.shortLivedResourceCachePathPrefix` |
| `completedResourcePath(id:, pathExtension:)` | 21 | `MediaBox.completedResourcePath(id:, pathExtension:)` |
| `storeResourceData(id:, data:, synchronous:)` | 22 | `MediaBox.storeResourceData(_ id:, data:, synchronous:)` |
| `cancelInteractiveResourceFetch(id:)` | 23 | `MediaBox.cancelInteractiveResourceFetch(resourceId:)` |
| `moveResourceData(id:, toTempPath:)` | 24 | `MediaBox.moveResourceData(_ id:, toTempPath:)` |
| `moveResourceData(from:, to:, synchronous:)` | 24 | `MediaBox.moveResourceData(from:, to:, synchronous:)` |
| `copyResourceData(id:, fromTempPath:)` | 25 | `MediaBox.copyResourceData(_ id:, fromTempPath:)` |
| `copyResourceData(from:, to:, synchronous:)` | 25 | `MediaBox.copyResourceData(from:, to:, synchronous:)` |
| `resourceRangesStatus(resource:)` | 26 | `MediaBox.resourceRangesStatus(_ resource:)` |
| `removeCachedResources(ids:, force:, notify:)` | 26 | `MediaBox.removeCachedResources(_ ids:, force:, notify:)` |
| `clearCachedMediaResources(mediaResourceIds:)` | 223 | `_internal_clearCachedMediaResources` |

**Facade-shape convention:** all of these take `EngineMediaResource.Id` or `EngineMediaResource` (never raw `MediaResourceId`/`MediaResource`). Return types either don't leak Postbox (`Void`, `String`, `String?`, `Signal<RangeSet<Int64>, NoError>`, `Signal<Float, NoError>`) or wrap via TelegramCore type (`Signal<EngineMediaResource.ResourceData, NoError>`).

**Swift-stdlib-vs-third-party-module name collisions** (learned in wave 26): `RangeSet<Int64>` collides with Swift stdlib's `RangeSet` (iOS 18+ only). Fix: `import RangeSet` at the file top of any TelegramCore file that names `RangeSet` in a signature. `TelegramCore/BUILD` already depends on `//submodules/Utils/RangeSet:RangeSet`. Future facade additions in TelegramEngineResources.swift should re-check this if new signature types are introduced.

## tgcalls Testbench

This repo includes a tgcalls testbench (CLI tool, Go/Pion SFU, Docker build) layered on top of the iOS source. All testbench code, build instructions, and architecture docs live inside the tgcalls submodule:

- `submodules/TgVoipWebrtc/tgcalls/CLAUDE.md` — top-level testbench overview, build/run commands
- `submodules/TgVoipWebrtc/tgcalls/tools/cli/CLAUDE.md` — CLI test tool architecture
- `submodules/TgVoipWebrtc/tgcalls/tools/go_sfu/CLAUDE.md` — Go SFU internals
- `submodules/TgVoipWebrtc/CLAUDE.md` — tgcalls library internals + macOS/Linux build patches

Build the test binary from this directory with:

`./build-input/bazel-8.4.2 build //submodules/TgVoipWebrtc/tgcalls/tools/cli:tgcalls_cli`
