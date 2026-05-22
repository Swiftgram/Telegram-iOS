# RichText.textCustomEmoji — parsing, serialization & display

**Date:** 2026-05-22
**Status:** Design approved, ready for implementation plan

## Goal

Add full support for inline custom emoji (`textCustomEmoji`) in `RichText`:

1. **API parsing** — decode `Api.RichText.textCustomEmoji(documentId, alt)` into a real Swift `RichText` case instead of dropping it to `.plain("")`.
2. **Serialization** — round-trip the case through the API, Postbox coding, and FlatBuffers.
3. **Display** — render the emoji as a **full animated** inline sticker inside the InstantPage V2 text renderer used by `ChatMessageRichDataBubbleContentNode`, including participation in the AI streaming reveal.

## Context

`RichText` is the InstantPage rich-text tree. AI "rich data" chat bubbles render a synthesized InstantPage V2 document via `ChatMessageRichDataBubbleContentNode` → `InstantPageV2View`.

Today `Api.RichText.textCustomEmoji` (which carries `documentId: Int64, alt: String`) is mapped to `.plain("")` in `submodules/TelegramCore/Sources/ApiUtils/RichText.swift:56-58` — the emoji is silently lost. The Swift `RichText` enum, Postbox coding, and FlatBuffers schema have no custom-emoji case.

The V2 text renderer (`InstantPageRenderer.swift`, `TextRenderView`) currently draws only glyphs + decorations; inline images render as grey placeholders. Inline emoji rendering is therefore greenfield, but the codebase has a mature reference: `InteractiveTextNodeWithEntities` drives `InlineStickerItemLayer`s for inline custom emoji in chat text.

### Key facts established during exploration

- The Swift `RichText` enum, Postbox `init(decoder:)`/`encode(_:)`, `==`, `plainText`, and the FlatBuffers extension all live in `submodules/TelegramCore/Sources/SyncCore/SyncCore_RichText.swift`. The enum has 17 cases today (`empty`…`formula`), Postbox discriminators 0–16.
- FlatBuffers `*_generated.swift` files are **regenerated at build time** by a Bazel `flatc` genrule (`submodules/TelegramCore/FlatSerialization/BUILD`, target `GenerateModels`) from the `.fbs` sources. The checked-in `RichText_generated.swift` is stale (it is already missing `formula`). **The `.fbs` is the source of truth.**
- `attributedStringForRichText` (`submodules/InstantPageUI/Sources/InstantPageTextItem.swift:669`) is **shared** by the V1 and V2 layout paths — single edit point for attribute insertion.
- `InstantPageTextLine` (`InstantPageTextItem.swift:79`) carries per-line `imageItems`/`formulaItems`; the V2 line-breaker (`InstantPageV2Layout.swift:~2553-2746`) collects them and computes per-character ink rects for the reveal mask.
- `InlineStickerItemLayer` lives in `submodules/TelegramUI/Components/EmojiTextAttachmentView`; it takes a `ChatTextInputTextCustomEmojiAttribute`, an `AnimationCache`, and a `MultiAnimationRenderer`, resolves the file lazily from `fileId` when `file == nil`, and is driven by `frame` + `isVisibleForAnimations` + `dynamicColor`. Reference usage: `InteractiveTextNodeWithEntities.updateInteractiveContents` (`submodules/TelegramUI/Components/InteractiveTextComponent/Sources/InteractiveTextNodeWithEntities.swift:279`).
- InstantPageUI already depends on `TextFormat` and `AccountContext` but **not** on `EmojiTextAttachmentView`/`AnimationCache`/`MultiAnimationRenderer`. Adding those is **cycle-free** (verified: none of them depend on InstantPageUI).
- No visibility plumbing exists in the bubble or `InstantPageV2View` today. `ChatMessageTextBubbleContentNode:129` is the reference for forwarding `visibility` → `visibilityRect`.

### Decisions

- **Display fidelity:** full animated `InlineStickerItemLayer` (lazy file resolution, animation, visibility-driven looping). Managed at the `InstantPageV2View` level.
- **Streaming reveal:** emoji **participates in the reveal** — contributes its width to the cost map and pops in (alpha + scale) when the reveal cursor crosses its glyph position.
- **Attribute representation (Approach A):** reuse `ChatTextInputAttributes.customEmoji` + `ChatTextInputTextCustomEmojiAttribute` end-to-end. The layout model carries the chat-input attribute directly (TextFormat is already a dependency), and `InlineStickerItemLayer.init` consumes it without translation.
- **Enum payload:** `case textCustomEmoji(fileId: Int64, alt: String)`. Raw `Int64` (not `MediaId`) — namespace is always `Namespaces.Media.CloudFile`, the API gives `documentId: Int64`, and the display layer speaks `fileId: Int64`.

## Section 1 — Data model, parsing & serialization

### `SyncCore_RichText.swift`

- Add `case textCustomEmoji(fileId: Int64, alt: String)` to the `RichText` enum.
- Add `case textCustomEmoji = 17` to the private `RichTextTypes` discriminator enum.
- `init(decoder:)`: decode `Int64` (key `"ce.f"`) + `String` (key `"ce.a"`).
- `encode(_:)`: encode discriminator 17 + the two fields.
- `==`: add the case comparison.
- `plainText`: return `alt` (so text extraction / accessibility / copy yields the fallback glyph).
- FlatBuffers extension: add the `.richtextCustomEmoji` case to `init(flatBuffersObject:)` and the `.textCustomEmoji` case to `encodeToFlatBuffers`.

### `submodules/TelegramCore/Sources/ApiUtils/RichText.swift`

- `init(apiText:)`: replace the stub at lines 56–58 with
  `self = .textCustomEmoji(fileId: data.documentId, alt: data.alt)`.
- `apiRichText()`: add
  `case let .textCustomEmoji(fileId, alt): return .textCustomEmoji(.Cons_textCustomEmoji(documentId: fileId, alt: alt))`.
  (Confirmed constructor: `Api.RichText.Cons_textCustomEmoji(documentId: Int64, alt: String)`.)

### `submodules/TelegramCore/FlatSerialization/Models/RichText.fbs`

- Append `RichText_CustomEmoji` to the `RichText_Value` union (after `RichText_Formula` — appending keeps existing discriminators stable).
- Add `table RichText_CustomEmoji { fileId:long (id: 0, required); alt:string (id: 1, required); }`.
- The Bazel build regenerates `RichText_generated.swift`; no manual edit of the generated file is required for the Bazel build.

## Section 2 — Layout & reveal participation

### Attribute insertion — `attributedStringForRichText` (`InstantPageTextItem.swift:669`)

New `.textCustomEmoji(fileId, alt)` case emits **one placeholder character** carrying:

- `ChatTextInputAttributes.customEmoji` = `ChatTextInputTextCustomEmojiAttribute(interactivelySelectedFromPackId: nil, fileId: fileId, file: nil, custom: nil)` — file resolves lazily in the layer; this attribute doubles as the line-breaker's marker.
- the current style-stack font + foreground color (correct baseline/line metrics).
- a `CTRunDelegate` sized `itemSize = font.pointSize · 24.0/17.0`, ascent/descent from the font, width = `itemSize` (identical to the `InteractiveTextNodeWithEntities` reference).

### Line model — `InstantPageTextItem.swift`

- New struct: `struct InstantPageTextEmojiItem { let frame: CGRect; let range: NSRange; let emoji: ChatTextInputTextCustomEmojiAttribute }`.
- `InstantPageTextLine` gains `let emojiItems: [InstantPageTextEmojiItem]`, added to its initializer with default `[]` so V1 and all other call sites compile unchanged.

### V2 collection — `InstantPageV2Layout.swift` line-breaker (~2553–2746)

Mirror the existing `pendingImages` flow:

- In the run-attribute walk (~2566) add an `else if` reading `ChatTextInputAttributes.customEmoji` → append to a `pendingEmoji` list with `xOffset` (`CTLineGetOffsetForStringIndex`), `range`, `itemSize`, and the attribute.
- Add an emoji ascent loop alongside the image/formula loops so a tall emoji grows `lineAscent`.
- Build `InstantPageTextEmojiItem` frames from `baselineY`, vertically centered on the line, and pass `emojiItems: lineEmojiItems` into the `InstantPageTextLine(...)` constructor.

### Reveal participation

After `lineCharacterRects` is built (~2700–2742), overwrite each emoji placeholder char's slot with its full cell rect (`x = CTLineGetOffsetForStringIndex(...)`, width/height = `itemSize`, baseline-relative to match the glyph-rect convention). The glyph-ink path would otherwise leave the slot ~empty (the run-delegate run has no real glyph). With a real rect:

- the emoji automatically contributes `itemSize` points of width to `InstantPageV2RevealCostMap` (cost unit = points of width), and
- the reveal cursor/mask gets a position to cross.

Expected: **no change** to `InstantPageV2RevealCost.swift` beyond verifying the cost sum picks the new rect up.

## Section 3 — Display lifecycle & bubble wiring

### Layer management in `InstantPageV2View` (`InstantPageRenderer.swift`)

Mirrors `InteractiveTextNodeWithEntities.updateInteractiveContents`:

- New state: `inlineStickerItemLayers: [InlineStickerItemLayer.Key: EmojiLayerData]`, where `EmojiLayerData` holds the layer, a weak ref to its owning `InstantPageV2TextView`, the emoji's local frame, and its global char index (for reveal gating).
- New `updateInlineEmoji()`, called at the end of `update(layout:theme:animation:)`. No-op when `renderContext == nil` (consistent with the grey-placeholder fallback). It walks `currentLayout` text items → lines → `emojiItems`, allocates `InlineStickerItemLayer.Key(id: fileId, index:)` by occurrence order (`nextIndexById`), and creates/reuses/removes layers:
  ```swift
  InlineStickerItemLayer(
    context: rc.context, userLocation: .other, attemptSynchronousLoad: false,
    emoji: item.emoji, file: item.emoji.file,
    cache: rc.context.animationCache, renderer: rc.context.animationRenderer,
    placeholderColor: <theme secondary/link color>,
    pointSize: CGSize(width: floor(itemSize · 1.3), height: floor(itemSize · 1.3)),
    dynamicColor: <text color>)
  ```
- Layers attach to a new `emojiContainerView` on `InstantPageV2TextView`, layered **above** `renderContainer` so the reveal mask wipes glyphs while emoji pop in independently.

### Visibility + reveal pop-in

- `InstantPageV2View.visibilityRect: CGRect?` (new) — `didSet` updates every layer's `isVisibleForAnimations = enableLooping && rect.intersects(visibilityRect) && isRevealed`, matching the reference. `enableLooping = rc.context.sharedContext.energyUsageSettings.loopEmoji`.
- `applyReveal(revealedCount:costMap:animated:)` (`InstantPageV2RevealCost.swift`) — after it computes each text view's revealed char count, it sets each emoji's revealed state. Crossing into the revealed range with `animated` → alpha 0→1 + small scale pop (matches the snippet pop-in aesthetic); unrevealed → alpha 0 and not animating.

### Bubble wiring — `ChatMessageRichDataBubbleContentNode.swift`

- Override `visibility` (none today), following `ChatMessageTextBubbleContentNode:129`: compute the full-width `subRect` and forward to `pageView.visibilityRect`.
- No render-context change: the bubble already builds `InstantPageV2RenderContext` with an `AccountContext`; the V2View reads `animationCache`/`animationRenderer` from it.

### BUILD

`submodules/InstantPageUI/BUILD` gains deps: `EmojiTextAttachmentView`, `AnimationCache`, `MultiAnimationRenderer` (cycle-free, verified).

## Out of scope / noted

- The legacy V1 InstantPage line-breaker (`InstantPageTextItem.swift` layout) is **not** taught to collect emoji items, so a `textCustomEmoji` inside a classic Instant View would render as a blank placeholder. Acceptable — this task targets the rich-data bubble. The shared `attributedStringForRichText` change is harmless there (the placeholder simply isn't picked up).

## Verification

- Build the full `Telegram/Telegram` target via `Make.py` (no per-module build; no unit tests in this project).
- In the simulator: confirm a `textCustomEmoji` node decodes from the wire (not blank), animates inline at the correct baseline/size, pops in as the AI stream reveals across it, and loops only while on-screen.
- Confirm Postbox + FlatBuffers round-trip (a re-decoded message preserves `fileId`/`alt`).
