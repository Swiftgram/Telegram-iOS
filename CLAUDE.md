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

**How it's wired:** `//Telegram:TelegramWatchApp` (rule in `Telegram/prebuilt_watchos.bzl`, worker `Telegram/prebuilt_watchos_build.sh`) runs xcodebuild on the snapshot in a writable temp copy, codesigns the `.app` + nested `TDLibFramework.framework` (identity + `ph.telegra.Telegraph.watchkitapp` profile from `--define`s), and feeds it to the `Telegram` `ios_application`'s `watch_application` slot (gated by the `//Telegram:embedWatchApp` flag). The snapshot is a tracked Bazel input, so the watch build re-runs only when it changes.

**Non-obvious invariants** (also in the `.bzl` comments): `AppleBundleInfo`'s public init is banned — use the internal `new_applebundleinfo`; `watch_application` requires BOTH `AppleBundleInfo` (with a non-None `infoplist` File) AND `WatchosApplicationBundleInfo`; the embedded watch app's `CFBundleShortVersionString`/`CFBundleVersion` must exactly equal the host's (sourced from `versions.json['app']` + `--define=buildNumber`); the host does NOT re-sign the embedded watch app, so the worker must sign it; the watch bundle id `ph.telegra.Telegraph.watchkitapp` must track the host `telegram_bundle_id`.

**Status:** verified with **development** signing on `debug_arm64` only. Open follow-ups before App Store shipping: secure timestamp (drop `codesign --timestamp=none`), distribution profile (`get-task-allow=false`), `release_arm64` + `altool --validate-app`, and committing a `Package.resolved` for hermetic remote-SwiftPM resolution.

## View frame ownership

A view does not control its own `frame`. The parent (or a layout system) sets the frame; the view positions its own subviews against `self.bounds` in response.

This matters in two places specifically:

- **Reusable components (`UIView`/`ASDisplayNode` subclasses).** Public methods like `update(...)` / `apply(...)` rebuild internal state, mutate child frames, and read `self.bounds` to lay them out — but they do not write `self.frame`. The caller has already chosen the frame; mutating it from inside the component overrides that choice and fights the parent's next layout pass.
- **`asyncLayout`-style content nodes.** The measure pass runs off-main and returns a size; the apply step runs on main and the chat layout system positions the node. A child view that writes `self.frame` from `update()` corrupts the size the parent just measured.

Rare exceptions: top-level view-controller views integrating with the system's first-responder/inset model. If you find yourself wanting `self.frame = …` from inside a child view, refactor so the parent positions it instead.

## AI streaming animation (rich-text bubbles)

`ChatMessageRichDataBubbleContentNode` shows a "Thinking…" shimmer header and progressively reveals InstantPage V2 content while `TypingDraftMessageAttribute` is on the message. Mirrors the older animation in `ChatMessageTextBubbleContentNode`, adapted to the heterogeneous V2 layout.

Spec: [`docs/superpowers/specs/2026-05-19-richdata-streaming-animation-design.md`](docs/superpowers/specs/2026-05-19-richdata-streaming-animation-design.md). Plan: [`docs/superpowers/plans/2026-05-19-richdata-streaming-animation.md`](docs/superpowers/plans/2026-05-19-richdata-streaming-animation.md).

### Where things live

| File | Responsibility |
|---|---|
| `submodules/TelegramUI/Components/StreamingTextReveal/Sources/TextRevealController.swift` | Pacing controller, shared by both bubbles. EWMA inter-arrival → velocity-smoothed cursor. |
| `submodules/InstantPageUI/Sources/InstantPageRenderer.swift` (`InstantPageV2TextView`) | Drawing split: private `TextRenderView` does `draw(_)` inside a `renderContainer` whose layer carries a `revealMaskLayer`; new chars spawn cropped `SnippetLayer` siblings of the render container that animate in (blur + alpha + scale + position) and are absorbed into the mask on completion. Ported from `InteractiveTextComponent`. |
| `submodules/InstantPageUI/Sources/InstantPageV2RevealCost.swift` | `InstantPageV2RevealCostMap` + `InstantPageV2View.applyReveal(revealedCount:costMap:animated:)`. Bridges the global width-based cursor to per-text-view char counts (via `charCountForWidthBudget`) and per-item visibility / table-row pop-in. |
| `submodules/InstantPageUI/Sources/InstantPageV2Layout.swift` | `InstantPageTextLine.characterRects` (line-local CT coords, baseline-relative positive-up) populated when `computeRevealCharacterRects: true` is passed to `layoutInstantPageV2(...)`. Uses `CTFontGetBoundingRectsForGlyphs` for actual glyph ink, not advance widths. |
| `submodules/TelegramUI/Components/Chat/ChatMessageRichDataBubbleContentNode/...` | Streaming detection (`TypingDraftMessageAttribute`), "Thinking…" header layout, display-link wiring, container sizing. |

### Non-obvious invariants

- **Cost unit is points of width, not characters.** Each item's cost = its width in points along the reading direction. Text contributes sum of glyph ink widths; non-text items contribute `frame.width`. Table cells are floored at `cell.frame.width` so narrow- or empty-cell tables don't race through the cursor. Reveal pace becomes "points per second" — uniform across content types.
- **Mask uses per-glyph ink bounds, unioned per line.** Each revealed glyph's mask rect comes from `CTFontGetBoundingRectsForGlyphs` (not advance widths) so italics, accents, descenders are covered exactly. Per line, glyphs are unioned into one mask rect; consecutive fully-revealed lines union further — fully-revealed prefix is always one `CALayer`.
- **`containerNode` does ALL the clipping.** During streaming, containerNode is sized to `streamingHeaderOffset + revealedItemsMaxY` (no closing pad). The bubble itself is taller (`revealedContentSize.height + 2`) — the strip below containerNode is empty bubble background. pageView keeps its full `pageLayout.contentSize`; anything past containerNode's bottom is clipped at containerNode (`clipsToBounds = true` set in init). Do NOT shorten the pageView or set `pageView.clipsToBounds`.
- **The pageView is rebuilt on every `stableVersion` bump.** V2View's render context is constructor-fixed, so each AI chunk creates a brand-new `InstantPageV2View`. The reveal cursor survives on `TextRevealController` (owned by the bubble). The seed call `applyReveal(revealedCount: previousAnimateGlyphCount, …, animated: false)` after `ensurePageView` re-applies state to the fresh V2View so there's no flash of full-text-then-mask.
- **Layout cache key includes `message.stableVersion`.** Each AI chunk bumps stableVersion; without this the cached layout would shadow newly-arrived content.
- **`TypingDraftMessageAttribute` is the streaming gate.** Same trigger TextBubble uses. The InstantPage's `isComplete` flag is informational only.
- **Width-based cost → char count bridge.** Mask APIs (`updateRevealCharacterCount`) still take character counts. `applyRevealEntry` calls `charCountForWidthBudget(textItem:widthBudget:)` to translate the width-based local cursor into the per-text-view character count.
- **`Thinking…` header positioning matches TextBubble.** `streamingTextFrame.origin = (bubbleInsets.left - textInsets.left, topInset - textInsets.top)`. `streamingHeaderOffset` = visible bottom + 1pt spacing = where pageView's `frame.origin.y` and statusFrame y-shift attach. Bubble minimum width includes `visible_thinking_width + bubbleInsets.left + bubbleInsets.right + 2`.
- **Display-link tick re-layouts on extent change.** Tick reads `revealedContentSize` at the new cursor; if the height differs from the previous cursor, calls `requestFullUpdate`. So the bubble grows in flight when the cursor crosses a line/item boundary, not just between chunks. Tick passes `animated: true` to `applyReveal` to fire the snippet pop-in.

### Status node (date/time/checks) positioning

The `ChatMessageDateAndStatusNode` mirrors TextBubble's placement, adapted to the heterogeneous V2 layout. The node is a child of `self` (the content node), **not** of the clipping `containerNode`, so it is never clipped — the bubble height must be grown to contain it.

- **X is a fixed left edge, not the last line's `minX`.** Anchor x = `pageHorizontalInset` (10pt, the page layout's text inset; pageView sits at self-x 0). The status layout is measured with `boundingWidth - 2·pageHorizontalInset` (mirrors TextBubble's `boundingWidth - sideInsets`) so the right-aligned date lands at the right inset instead of off the bubble. Using `lastTextLineFrame.minX` (which is large for nested/indented last lines) shoved the date off to the right.
- **Trail the last line only when the bottom-most item is text.** `lastTextLineFrameIfLastItemIsText(in:)` (in `InstantPageV2Layout.swift`) returns the last line frame *only* when the bottom-most top-level item (max `maxY`) is a `.text`; otherwise nil, so the date wraps below all content (anchored at `contentSize.height`). For tables/images/etc. the date must not trail text buried above the final item.
- **InstantPage draws the baseline at the line frame's `maxY`** (`InstantPageRenderer` draws each line at `lineOrigin.y + lineFrame.height`), so the visible text of a plain line sits ~5pt below `maxY`. A date that **trails** on the line (`statusHeight == 0`) adds `trailingBottomPadding` (5pt) to align with the text; a date that **wraps** onto its own line below (`statusHeight > 0`) sits at the bare `maxY`. The pad is 0 for lines taller than their font line height (an inline animated emoji, ~`pointSize·24/17`, already pushes `maxY` down). `lastTextLineFrameIfLastItemIsText` returns `(frame, trailingBottomPadding)`; the bubble applies the pad only in the trailing case.
- **Bubble height leaves ~6pt below the date.** One unified formula for all cases: `boundingSize.height = max(boundingSize.height, statusBottomEdge + 6.0)`, where `statusBottomEdge = statusAnchorY + max(1, statusHeight)`. The `statusAnchorY` in the measure (`continue`) closure must mirror the `statusFrameY (+ streamingHeaderOffset)` in the apply closure exactly, or the date will be clipped/misplaced. 6pt matches TextBubble's bottom bubble inset.

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
- **Layers are owned by `InstantPageV2View`, not the text view.** Keyed by `InlineStickerItemLayer.Key(id: fileId, index: occurrence)`. The pageView is rebuilt per `stableVersion` bump (see streaming section), so the dict starts fresh each chunk — no orphan/leak across rebuilds; within one view, stale keys are pruned.
- **`visibilityRect` gates looping; `nil` means "not visible".** The bubble's `visibility` override pushes a full-width sub-rect to the root `pageView.visibilityRect`, re-pushed in the apply closure after `pageView.frame` is set (because `streamingHeaderOffset` shifts across chunks without a `visibility` change). `propagateVisibilityRect` converts the rect into each nested V2View's coordinate space (`self.convert(_:to:)`) for details bodies / table cells+title, fanning out via each child's `didSet`.
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

## Formulas trigger rich messages (strict math detection)

`$…$`/`$$…$$` (and `\(…\)`/`\[…\]`) math triggers a rich message, gated by a
strict boundary rule so casual `$` stays plain. Inverse companion of the
markdown-send gate above.

### Non-obvious invariants

- **Inline `$…$`/`$$…$$` detection requires a 4-way boundary** (in `markdownReplacingInlineFormulas`, `BrowserMarkdown.swift`): outer side of each delimiter = line edge OR non-alphanumeric; inner side = non-whitespace; opener/closer `$`-counts must match (1 or 2). This is what rejects `$5-$10`/`$FOO=$BAR`/`cost$5$total` (alphanumeric outer) while keeping `$x$`, `($x$)`, `the answer is $x$.`. The outer check is the addition over a plain "no-space-inside" rule.
- **Block `$$` detection** (`markdownBlockFormulaReplacement`): single-line `$$…$$` requires an exact `$$` opener (not `$$$`) and trailing whitespace only; multi-line requires a **bare** `$$` opener line. `$$x$$ trailing text` falls through to the inline rule. The `\[…\]` opener path is unchanged and exempt from these `$$`-only guards.
- **Detection is shared with the document path; the gate is chat-only.** `markdownPreparedSource` (detection) runs for both chat and document attachments. The triggers (`richTextIsEntityExpressible`/`blockIsEntityExpressible` → `.formula` is non-expressible; `$`/`\(`/`\[` in `markdownMightNeedRichLayout`) are read only by the chat classifier `richMarkdownAttributeIfNeeded`.

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
