# InstantPage BlockQuote — nested blocks payload

## Context

Telegram's instant-view API has two parallel constructors for the block-quote
page block:

- `pageBlockBlockquote(text: RichText, caption: RichText)` — legacy
  text-only form.
- `pageBlockBlockquoteBlocks(blocks: [PageBlock], caption: RichText)` — new
  form whose body is a sequence of nested page blocks (paragraphs, lists,
  headings, code, even nested quotes).

The Swift model currently represents only the legacy form
(`InstantPageBlock.blockQuote(text: RichText, caption: RichText)`) and the API
parser has a `//TODO` placeholder for the new constructor
(`submodules/TelegramCore/Sources/ApiUtils/InstantPage.swift:251`). This spec
upgrades parsing, serialization (Postbox + FlatBuffers), encoding back to the
wire, and rendering (V1 + V2) to support nested blocks throughout.

## Decisions

- **Single enum case, blocks-only payload.** Replace
  `(text: RichText, caption: RichText)` with
  `(blocks: [InstantPageBlock], caption: RichText)`. The legacy text-only
  inbound shape is lifted into the new shape at parse time by wrapping the
  RichText in a synthetic `.paragraph(text)`. Downstream code branches on
  zero shapes.
- **Full block-level layout in both renderers.** V2
  (`InstantPageV2Layout.swift`) and V1 (`InstantPageLayout.swift`) recurse
  into the child blocks. No surface where nested-block quotes render
  degraded.
- **Outbound: legacy when shape allows.** `apiInputBlock()` emits the legacy
  `pageBlockBlockquote` constructor when blocks is `[.paragraph(text)]` (or
  empty), and the new `pageBlockBlockquoteBlocks` constructor otherwise.
  Keeps the common chat case on the wire constructor older client recipients
  already understand.
- **`.pullQuote` is unchanged.** The TL API has no `pullQuoteBlocks`
  constructor; the `.pullQuote(text: RichText, caption: RichText)` case keeps
  its existing shape, parser, serializer, and renderer.

## Architecture

### Enum shape

`SyncCore_InstantPage.swift:73`:

```swift
case blockQuote(blocks: [InstantPageBlock], caption: RichText)
```

The enum is already declared `indirect`, so a `[InstantPageBlock]` payload
needs no further annotation.

### API parsing (`InstantPage.swift:247–252`)

```swift
case let .pageBlockBlockquote(data):
    self = .blockQuote(
        blocks: [.paragraph(RichText(apiText: data.text))],
        caption: RichText(apiText: data.caption)
    )
case let .pageBlockBlockquoteBlocks(data):
    self = .blockQuote(
        blocks: data.blocks.map { InstantPageBlock(apiBlock: $0) },
        caption: RichText(apiText: data.caption)
    )
```

### API encoding (`InstantPage.swift:376`)

```swift
case let .blockQuote(blocks, caption):
    if blocks.count == 1, case let .paragraph(text) = blocks[0] {
        return .pageBlockBlockquote(.init(
            text: text.apiRichText(), caption: caption.apiRichText()
        ))
    }
    if blocks.isEmpty {
        return .pageBlockBlockquote(.init(
            text: RichText.empty.apiRichText(),
            caption: caption.apiRichText()
        ))
    }
    return .pageBlockBlockquoteBlocks(.init(
        blocks: blocks.compactMap { $0.apiInputBlock() },
        caption: caption.apiRichText()
    ))
```

### Postbox coding

`SyncCore_InstantPage.swift:228` (encoder): write `"b"` (object array of
blocks) and `"c"` (caption). Stop writing `"t"`.

`SyncCore_InstantPage.swift:123` (decoder): mirror the `decodeListItems`
pattern at line 39 — if the legacy `"t"` key is present, lift it into a
single-paragraph blocks array; otherwise decode the new `"b"` array.

```swift
case InstantPageBlockType.blockQuote.rawValue:
    let caption = decoder.decodeObjectForKey("c", decoder: {
        RichText(decoder: $0)
    }) as! RichText
    if let legacyText = decoder.decodeObjectForKey("t", decoder: {
        RichText(decoder: $0)
    }) as? RichText {
        self = .blockQuote(blocks: [.paragraph(legacyText)], caption: caption)
    } else {
        let blocks: [InstantPageBlock] =
            decoder.decodeObjectArrayWithDecoderForKey("b")
        self = .blockQuote(blocks: blocks, caption: caption)
    }
```

Old stored cached pages (with `"t"` set) decode unchanged; new writes only use
`"b"`.

### FlatBuffers

`InstantPageBlock.fbs:93`:

```fbs
table InstantPageBlock_BlockQuote {
    text:RichText (id: 0);                  // (required) dropped — legacy only
    caption:RichText (id: 1, required);
    blocks:[InstantPageBlock] (id: 2);      // new
}
```

Dropping `(required)` from an existing field and appending a new field at a
higher id are both schema-evolution-safe per FlatBuffers rules. Per the
`flatbuffers-codegen` memory the `.fbs` is the source of truth and Bazel
regenerates `*_generated.swift`; the checked-in copies in `Sources/` are
stale and should NOT be hand-edited.

Codec decoder (`SyncCore_InstantPage.swift:620`):

```swift
case .instantpageblockBlockquote:
    guard let value = flatBuffersObject.value(
        type: TelegramCore_InstantPageBlock_BlockQuote.self
    ) else {
        throw FlatBuffersError.missingRequiredField()
    }
    let caption = try RichText(flatBuffersObject: value.caption)
    if value.blocksCount > 0 {
        let blocks = try (0 ..< value.blocksCount).map {
            try InstantPageBlock(flatBuffersObject: value.blocks(at: $0)!)
        }
        self = .blockQuote(blocks: blocks, caption: caption)
    } else if let legacyText = value.text {
        self = .blockQuote(
            blocks: [.paragraph(try RichText(flatBuffersObject: legacyText))],
            caption: caption
        )
    } else {
        self = .blockQuote(blocks: [], caption: caption)
    }
```

Codec encoder (`SyncCore_InstantPage.swift:799`): write `blocks` + `caption`;
omit `text`.

### Equality (`SyncCore_InstantPage.swift:448`)

```swift
case let .blockQuote(lhsBlocks, lhsCaption):
    if case let .blockQuote(rhsBlocks, rhsCaption) = rhs,
       lhsBlocks == rhsBlocks, lhsCaption == rhsCaption {
        return true
    } else {
        return false
    }
```

Mirrors the `.collage`/`.slideshow` pattern (which already do
`[InstantPageBlock]` equality).

### V2 renderer

`InstantPageV2Layout.swift:597` keeps dispatching to `layoutBlockQuote` for
the blockquote arm. Split the existing function:

- `layoutBlockQuote(blocks:caption:...)` — new, for `.blockQuote` only.
- `layoutPullQuote(text:caption:...)` — for `.pullQuote` only; same behavior
  as today's `isPull = true` branch.

`layoutBlockQuote` strategy:

```swift
private func layoutBlockQuote(
    blocks: [InstantPageBlock],
    caption: RichText,
    boundingWidth: CGFloat,
    horizontalInset: CGFloat,
    context: inout LayoutContext
) -> [InstantPageV2LaidOutItem] {
    let verticalInset: CGFloat = 4.0
    let lineInset: CGFloat = 20.0
    let barWidth: CGFloat = 3.0

    var result: [InstantPageV2LaidOutItem] = []
    var contentHeight: CGFloat = verticalInset

    let innerBoundingWidth = boundingWidth - horizontalInset * 2.0 - lineInset
    let innerHorizontalInset = horizontalInset + lineInset

    if blocks.count == 1, case let .paragraph(text) = blocks[0] {
        // Fast path: preserve today's italicized body styling for the
        // legacy single-paragraph shape (unchanged from current code).
    } else {
        var previousItems: [InstantPageV2LaidOutItem] = []
        for (i, child) in blocks.enumerated() {
            var childItems = layoutBlock(
                child,
                boundingWidth: innerBoundingWidth,
                horizontalInset: innerHorizontalInset,
                isCover: false,
                previousItems: previousItems,
                isLast: i == blocks.count - 1,
                context: &context
            )
            // Stack vertically: offset Y by current contentHeight.
            // X is already correct (children laid out at innerHorizontalInset).
            for j in childItems.indices {
                childItems[j] = childItems[j].translatedY(by: contentHeight)
            }
            let childMaxY = childItems.map { $0.frame.maxY }.max() ?? contentHeight
            contentHeight = max(contentHeight, childMaxY)
            previousItems.append(contentsOf: childItems)
            result.append(contentsOf: childItems)
        }
    }

    // Caption (existing branch, unchanged).
    if case .empty = caption { /* nothing */ } else {
        contentHeight += 14.0
        // ...existing caption layout, using innerHorizontalInset...
    }
    contentHeight += verticalInset

    // Vertical bar on the leading edge (existing behavior).
    let bar = InstantPageV2BarItem(
        frame: CGRect(x: horizontalInset, y: 0.0,
                      width: barWidth, height: contentHeight),
        color: context.theme.textCategories.paragraph.color,
        cornerRadius: barWidth / 2.0
    )
    result.append(.blockQuoteBar(bar))

    return result
}
```

Notes:

- **Translation helper.** `InstantPageV2LaidOutItem` covers many variants
  (text/shape/list-marker/bar/checklist/media/...). Add a small extension
  method `translatedY(by:)` that returns a copy with the item's frame's
  `origin.y` offset. Implemented as a switch over the case set, mirroring
  any existing per-variant frame-edit helper in the file.
- **`previousItems` for spacing.** V2's per-block layout functions consume
  `previousItems` to compute inter-block gaps. Passing a fresh array per
  recursion gives correct in-quote spacing without affecting the outer
  page's `previousItems`.
- **Styling of nested children.** Direct children render with their normal
  category styling (heading stays a heading, list stays a list). Italics are
  applied only by the single-paragraph fast path — consistent with the
  visual fidelity goal for legacy quotes without complicating the recursive
  case.

### V1 renderer

`InstantPageLayout.swift:504` is the `.blockQuote` arm of the giant top-level
`switch self` inside the `extension InstantPageBlock { func layout(...) -> InstantPageLayout }`.
Because the enum is already `indirect`, the arm can simply call
`child.layout(...)` recursively for each block in `blocks` — no signature
refactor needed.

BlockQuote arm:

```swift
case let .blockQuote(blocks, caption):
    let lineInset: CGFloat = 20.0
    let verticalInset: CGFloat = 4.0
    var contentSize = CGSize(width: boundingWidth, height: verticalInset)
    var items: [InstantPageItem] = []

    let innerBoundingWidth = boundingWidth - horizontalInset * 2.0 - lineInset
    let innerHorizontalInset = horizontalInset + lineInset

    if blocks.count == 1, case let .paragraph(text) = blocks[0] {
        // Fast path: existing italicized body layout (unchanged).
    } else {
        var previousChildItems: [InstantPageItem] = []
        for child in blocks {
            let childLayout = child.layout(
                boundingWidth: innerBoundingWidth,
                horizontalInset: innerHorizontalInset,
                safeInset: safeInset,
                isCover: false,
                previousItems: previousChildItems,
                fillToSize: nil,
                media: media,
                mediaIndexCounter: &mediaIndexCounter,
                embedIndexCounter: &embedIndexCounter,
                detailsIndexCounter: &detailsIndexCounter,
                theme: theme,
                strings: strings,
                /* ... whichever other params the current signature takes ... */
                fitToWidth: fitToWidth,
                webpage: webpage
            )
            for var item in childLayout.items {
                item.frame = item.frame.offsetBy(dx: 0.0, dy: contentSize.height)
                items.append(item)
                previousChildItems.append(item)
            }
            contentSize.height += childLayout.contentSize.height
        }
    }

    // Caption (existing branch, using innerHorizontalInset).
    if case .empty = caption { /* nothing */ } else {
        contentSize.height += 14.0
        // ...existing caption layout, parameterized on innerHorizontalInset...
    }
    contentSize.height += verticalInset

    let shapeItem = InstantPageShapeItem(
        frame: CGRect(origin: CGPoint(x: horizontalInset, y: 0.0),
                      size: CGSize(width: 3.0, height: contentSize.height)),
        shapeFrame: CGRect(origin: .zero,
                           size: CGSize(width: 3.0, height: contentSize.height)),
        shape: .roundLine,
        color: theme.textCategories.paragraph.color
    )
    items.append(shapeItem)

    return InstantPageLayout(origin: CGPoint(),
                             contentSize: contentSize, items: items)
```

The exact parameter list of the recursive `child.layout(...)` call mirrors
the current method's parameter list as it exists in the codebase; the planning
step will reconcile against the actual method signature (which may differ
from the snippet above in nominal arity).

### Markdown forward parser

`BrowserMarkdown.swift:1394`. Replace the current per-child-paragraph
fragmentation with a single quote that carries all child blocks:

```swift
case .blockQuote:
    var childBlocks: [InstantPageBlock] = []
    for child in node.children {
        guard let parsed = markdownBlocks(
            from: child, context: context, depth: depth + 1
        ) else {
            return nil
        }
        childBlocks.append(contentsOf: parsed)
    }
    guard !childBlocks.isEmpty else {
        return []
    }
    return [.blockQuote(blocks: childBlocks, caption: .empty)]
```

**Behavior change worth noting.** Today a markdown
`> p1\n>\n> p2` produces TWO separate top-level quotes because the current
code emits one quote per child paragraph (a workaround for the text-only
model). Under the new model that becomes one quote with two paragraphs —
which is the correct semantics. Both forms continue to trigger the rich-send
gate (under the new entity-expressibility rule below, a multi-paragraph
quote is no longer entity-expressible — see "Risks" below).

### Entity-expressibility (`BrowserMarkdown.swift:1119`)

Telegram message-entity blockquotes are flat (single span of inline text).
The new gate:

```swift
case .blockQuote(let blocks, let caption):
    guard isEmptyRichText(caption) else { return false }
    return blocks.allSatisfy { child in
        if case let .paragraph(text) = child {
            return richTextIsEntityExpressible(text)
        }
        return false
    }
```

- A single `> quote` stays entity-expressible (`[.paragraph(t)]`, entity-
  expressible text) → sends via the regular entity path.
- A nested-structure quote (`> # heading`, `> - list`) is not entity-
  expressible → sends via the rich path.
- See "Risks" for the multi-paragraph case.

### Markdown reverse converter

`InstantPageToMarkdown.swift:42`. Recurse into each child block, dispatching
through the file's existing `markdownString(from:)` (which already knows
how to emit headings, lists, code, etc.), and prepend `> ` to every line:

```swift
case let .blockQuote(blocks, _):
    return markdownBlockQuote(blocks: blocks)

private func markdownBlockQuote(blocks: [InstantPageBlock]) -> String {
    var lines: [String] = []
    for block in blocks {
        guard let body = markdownString(from: block, /* args */) else {
            continue
        }
        for line in body.split(separator: "\n",
                               omittingEmptySubsequences: false) {
            lines.append("> \(String(line))")
        }
    }
    return lines.joined(separator: "\n")
}
```

`.pullQuote(text, _)` continues to call the existing
`markdownBlockQuote(_:RichText)`.

### Preview text (`InstantPagePreviewText.swift:126`)

```swift
case let .blockQuote(blocks, caption):
    let body = blocks.map { $0.previewText() }.joined(separator: " ")
    return body + caption.previewText()
```

Uses the existing per-block `previewText()` extension at the top of the
file so nested previews work transparently.

### FAQ matcher (`CachedFaqInstantPage.swift:23`)

The match is `case .blockQuote:` with no payload destructure — no change
needed.

## Risks

- **Behavior change for multi-paragraph quotes in chat send.** Under today's
  text-only model, `> p1\n>\n> p2` fragments into two top-level
  `.blockQuote(text: p_i, caption: .empty)` blocks, each of which is
  individually entity-expressible — so the message sends via the regular
  entity path (two consecutive blockquote entities). Under the new model
  the markdown parser emits one `.blockQuote(blocks: [.paragraph(p1),
  .paragraph(p2)], caption: .empty)`, which is no longer entity-expressible
  under the proposed gate (multi-paragraph blockquote can't be a single
  flat entity). So the same message starts going via the rich path.

  This is correct semantically — the structure IS preserved end to end —
  but it changes the wire format for an existing user-visible flow. A
  minor compromise is available: in `blockIsEntityExpressible`, treat a
  multi-paragraph quote as entity-expressible by serializing each
  paragraph through a separate entity at the message-build step; this is
  more involved and out of scope for the first cut. The risk is small —
  recipients of the rich message render it correctly; the only user-
  visible difference is that the message lands as a rich block on
  recipients who would otherwise have seen the consecutive-entities
  flattening.

- **Old recipients receiving `pageBlockBlockquoteBlocks` over the wire.**
  Older clients that haven't been updated to parse the new constructor
  will route it to `.unsupported` and skip it. The outbound choice
  ("legacy when shape allows") keeps the common single-paragraph case
  on the legacy constructor, minimizing this risk to actual nested-block
  quotes where there's no legacy equivalent anyway.

- **FlatBuffers schema evolution.** Dropping `(required)` and appending a
  new field at a higher id are documented as safe under FBS rules. The
  same iOS app and a Telegram-Mac peer share the schema definition (per
  the project's TelegramCore conventions), so both ends must move together
  or accept that one side will see `text` populated while the other writes
  only `blocks` — which the decoder handles correctly (legacy path).

- **V1 recursive layout call signature drift.** The exact parameter list of
  `child.layout(...)` is reconciled in the implementation plan, not in the
  spec — the V1 layout method's signature is long and any plumbing detail
  is best captured at edit time rather than guessed here.

## Out of scope

- `.pullQuote` enum shape, parsing, encoding, and renderer.
- Streaming/reveal animation in `ChatMessageRichDataBubbleContentNode`.
  Nested-block quotes emit ordinary `InstantPageV2LaidOutItem`s consumed by
  the existing width-based reveal cost map; no special handling.
- Inline animated emoji owned by `InstantPageV2View`. Quotes carrying
  paragraphs with custom emoji "just work" because each child paragraph's
  text items route through `updateInlineEmoji` normally.

## Files affected

| File | Change |
|---|---|
| `submodules/TelegramCore/Sources/SyncCore/SyncCore_InstantPage.swift` | Enum case shape; Postbox encoder/decoder; equality; FlatBuffers encoder/decoder. |
| `submodules/TelegramCore/FlatSerialization/Models/InstantPageBlock.fbs` | Drop `(required)` from `text`; add `blocks:[InstantPageBlock] (id: 2)`. |
| `submodules/TelegramCore/Sources/ApiUtils/InstantPage.swift` | API parse for both inbound constructors; API encode with legacy-when-possible. |
| `submodules/InstantPageUI/Sources/InstantPageV2Layout.swift` | Split `layoutBlockQuote` into block- and pull- variants; recurse into child blocks. Add `translatedY(by:)` helper on `InstantPageV2LaidOutItem`. |
| `submodules/InstantPageUI/Sources/InstantPageLayout.swift` | Recurse into child blocks in the `.blockQuote` arm. |
| `submodules/BrowserUI/Sources/BrowserMarkdown.swift` | Single quote with all child blocks (forward); entity-expressibility gate. |
| `submodules/BrowserUI/Sources/InstantPageToMarkdown.swift` | Recursive `markdownBlockQuote(blocks:)`. |
| `submodules/TelegramStringFormatting/Sources/InstantPagePreviewText.swift` | Concatenate child previews. |

`submodules/SettingsUI/Sources/CachedFaqInstantPage.swift` (line 23) is a
payload-less match and needs no edit, but should be re-verified during the
implementation build (full build is the completeness gate per the
project's "no per-module build" rule).
