# InstantPage list checkboxes (task-list style) — design

**Date:** 2026-05-27
**Status:** Approved for planning

## Summary

`InstantPageListItem` gains first-class **task-list checkbox** support — the `- [ ]` / `- [x]`
markdown construct — covering parsing, local serialization (Postbox + FlatBuffers),
API transmission, display, and the edit round-trip in rich-data message bubbles.

A prior prototype already wired most of this through a **sentinel string stuffed into the
ordered-list `num` field** (`"\u{001f}tg-md-task:checked"` / `:unchecked`). This design
**replaces that sentinel with a first-class `checked: Bool?`** on the list item, orthogonal
to `num`, because:

1. The Telegram API represents the checkbox as **flags independent of the list number** on
   all four list-item types (see "API facts" below). The sentinel-in-`num` cannot represent
   an item that is *both* numbered *and* a checkbox, which the API allows.
2. The sentinel never survived the server round-trip — `apiInputBlock` hardcoded `flags: 0`
   and dropped it — so checkboxes silently reverted to bullets the moment a message was
   confirmed, even for the sender.

The first-class field fixes transmission (real API flags), makes the local model faithful to
the API, and removes the sentinel hack from three files.

## API facts (verified against generated `Api.*` source, not inferred)

All four list-item constructors carry `checkbox` and `checked` as conditional-`true` flags;
`checkbox` = bit 0, `checked` = bit 1. They are **independent** of the ordered-list number.

```
pageListItemText#2f58683c        flags:# checkbox:flags.0?true checked:flags.1?true text:RichText
pageListItemBlocks#63ca67aa      flags:# checkbox:flags.0?true checked:flags.1?true blocks:Vector<PageBlock>
pageListOrderedItemText#cd3ea036 flags:# checkbox:flags.0?true checked:flags.1?true num:string text:RichText
pageListOrderedItemBlocks#422931d4 flags:# checkbox:flags.0?true checked:flags.1?true num:string blocks:Vector<PageBlock>
```

| iOS `Api.` type | Used for | checkbox | checked | other bits |
|---|---|---|---|---|
| `Api.PageListItem` (`.pageListItemText` / `.Blocks`) | send + receive (unordered) | flags.0 | flags.1 | — |
| `Api.PageListOrderedItem` | receive (ordered) | flags.0 | flags.1 | `num` (unconditional string) |
| `Api.InputPageListOrderedItem` | send (ordered) | flags.0 | flags.1 | value=flags.2, type=flags.3 |

The generated structs expose only `flags: Int32`; checkbox/checked are read/written by
masking bits 0 and 1. The current conversion code ignores them.

## Data model

`InstantPageListItem` (`SyncCore_InstantPage.swift`) gains a third associated value:

```swift
public indirect enum InstantPageListItem: PostboxCoding, Equatable {
    case unknown
    case text(RichText, String?, Bool?)            // (text, num, checked)
    case blocks([InstantPageBlock], String?, Bool?) // (blocks, num, checked)
}
```

`checked` semantics (orthogonal to `num`):

- `nil`  — not a checkbox item (ordinary bullet / numbered item)
- `false` — checkbox, unchecked
- `true`  — checkbox, checked

A new accessor mirrors the existing `var num`:

```swift
public extension InstantPageListItem {
    var checked: Bool? { … }   // returns the third value for .text/.blocks, nil for .unknown
}
```

The `var num` accessor is unchanged.

### Why an associated value (not a new enum case)

A checkbox item is still a text/blocks item; the only new dimension is the checkbox state.
An associated value keeps every existing `switch` at three cases (one extra bound variable
each) rather than forcing a fourth case into every exhaustive switch. The change is
source-breaking by design — the compiler enumerates every construction/destructure site, so
a full build with `--continueOnError` is the completeness check.

## Components

### 1. Enum + local serialization — `SyncCore_InstantPage.swift`

- Add the `Bool?` associated value to `.text` / `.blocks`; add the `checked` accessor.
- **Postbox**: encode the checked tri-state under a new key (`"ck"`) using the **same
  `0=nil, 1=unchecked, 2=checked`** mapping as FlatBuffers (below); encode only when
  `checked != nil`, and decode with `decodeInt32ForKey("ck", orElse: 0)` → `0→nil, 1→false,
  2→true`. Old stored data lacks the key → `orElse: 0` → `nil` (backward compatible).
- **FlatBuffers**: add `checkState:int32 (id: 2)` to both `InstantPageListItem_Text` and
  `InstantPageListItem_Blocks` in `InstantPageBlock.fbs` (tri-state: `0=nil, 1=unchecked,
  2=checked`). int32 defaults to 0, so absent → `nil` (backward compatible) — this mirrors
  the existing `alignment:int32` / `level:int32` pattern and sidesteps optional-scalar-bool
  ambiguity. Edit the `.fbs` (source of truth; the Bazel `flatc` genrule regenerates the
  Swift); update the hand-written codec in `SyncCore_InstantPage.swift` to read/write
  `checkState`. Encode only when non-nil (keeps the wire compact).
- **Equatable**: compare the new value in the `.text` / `.blocks` arms.

### 2. API transmission — `ApiUtils/InstantPage.swift`

- **Receive** `init(apiListItem:)` (unordered) and `init(apiListOrderedItem:)` (ordered):
  read `flags & (1<<0)` (checkbox present) and `flags & (1<<1)` (checked). Set
  `checked = (flags & 1<<0) != 0 ? ((flags & 1<<1) != 0) : nil`. Keep `num` as today
  (nil for unordered, the API `num` string for ordered).
- **Send** `apiInputPageListItem()` (→ `Api.PageListItem`) and `apiInputPageOrderedListItem()`
  (→ `Api.InputPageListOrderedItem`): when `checked != nil`, set `flags |= (1<<0)` and add
  `(1<<1)` when `checked == true`. Preserve the existing `value`/`type` bit handling on the
  ordered input.
- The `var num` accessor is unaffected; add `checked` reads where the items are built.
- **Bonus:** incoming Telegra.ph / cross-client task lists now render as checkboxes.

### 3. Real V2 checkbox artwork — `InstantPageRenderer.swift` + `InstantPageV2Layout.swift`

The V2 renderer (the live path for rich-message bubbles) currently draws a **placeholder**
square. Replace it with the real artwork:

- In `InstantPageV2ListMarkerView.rebuildContents()`'s `.checklist` case, host a
  `CheckNode(theme:, content: .check(isRectangle: true))` (add its `.view` as a subview),
  themed exactly like the V1 `InstantPageChecklistMarkerNode` (`CheckNodeTheme` from
  `panelAccentColor` / `pageBackgroundColor` / `controlColor`), and call
  `setSelected(checked, animated: false)`. `import CheckNode` (the module is already a
  `BUILD` dep of InstantPageUI).
- The marker view's `init` does not receive the theme, only `update(item:theme:)` does. Carry
  the three required colors on the `.checklist` marker payload (the layout has
  `context.theme`) so the view stays theme-agnostic and the colors are present at init time.
- Layout detection switches from `instantPageTaskListMarkerState(item.num)` to `item.checked`;
  the marker kind becomes `.checklist(checked: item.checked == true)` whenever
  `item.checked != nil`. Remove the V1/V2 sentinel constants and `instantPageTaskListMarkerState`.

### 4. Reverse markdown (edit path) — `InstantPageToMarkdown.swift`

`markdownList` currently ignores the marker, so editing a rich message downgrades checkboxes
to bullets. Read `item.checked` and emit `- [ ] ` / `- [x] ` (task markers are an unordered
construct). Re-classification on save re-parses it back to a checkbox → API flags.

### 5. preview-text — `InstantPagePreviewText.swift`

`previewText()` currently prepends `num` blindly, which under the old sentinel leaked
`"\u{001f}tg-md-task:checked. text"` into notifications/reply panels. With the first-class
field, `num` is once again only a real number, so the leak is gone; additionally render a
checkbox glyph (`"☑︎ "` / `"☐ "`) before the text when `checked != nil`.

### 6. Markdown forward parser — `BrowserMarkdown.swift`

`markdownListItems` keeps the existing `[ ]`/`[x]`/`[X]` detection
(`markdownTaskListMarker` / `markdownStrippingTaskListMarker` / `markdownApplyTaskListMarker`)
but routes the result into the new `checked` field instead of the `num` sentinel:

- Unordered task item → `.text(text, nil, state)` (number stays nil).
- Ordered task item (`1. [ ] x`) → `.text(text, "\(ordinal)", state)` — number **and** checkbox
  now coexist (previously the sentinel destroyed the number).

Remove the markdown sentinel constants (`markdownTaskListUncheckedNumber` /
`CheckedNumber`) and `markdownTaskListNumber`. Update the `.blocks(...)` / `.text(...)`
construction arms and the `validate(listItem:)` destructure to the 3-value shape.

### 7. Other construction/destructure sites (mechanical, compiler-enforced)

The enum change touches these files' `.text(...)` / `.blocks(...)` sites; all are in
list-handling modules (no external consumer constructs `InstantPageListItem`):

- `SyncCore_InstantPage.swift` — decodeListItems, Postbox decode/encode, `==`, FlatBuffers codec
- `ApiUtils/InstantPage.swift` — `num`/`checked` accessors, `init(apiListItem:)`,
  `init(apiListOrderedItem:)`, `apiInputPageListItem()`, `apiInputPageOrderedListItem()`
- `BrowserReadability.swift` — `.blocks(blocks, nil)` / `.text(...)` builders → add `nil`
- `InstantPageV2Layout.swift` / `InstantPageLayout.swift` — `layoutList` empty-blocks
  substitution (`.text(.plain(" "), num)` must carry `checked` through) and the
  `.text`/`.blocks` destructures
- `InstantPagePreviewText.swift`, `InstantPageToMarkdown.swift` — destructures (see 4 / 5)

## Round-trip contract

```
compose "- [ ] x"
  → markdown parse → .text("x", nil, false)
  → render checkbox (V2 CheckNode)
  → send: Api.PageListItem.pageListItemText(flags: 1<<0, text:"x")
  → server echo → receive: flags bit0 set, bit1 clear → .text("x", nil, false)
  → render checkbox on SENDER and RECIPIENT (and native checkbox on other clients)
edit
  → reverse markdown reads checked=false → "- [ ] x"
  → re-classify → .text("x", nil, false)  (identical)
```

Postbox/FlatBuffers carry `checked` locally across app restarts; the API flags carry it
across the server.

## Out of scope

- Interactivity (tapping a rendered checkbox to toggle it). These are display-only, matching
  the rest of InstantPage rendering.
- Inline images/videos inside list items (unchanged; pre-existing behavior).

## Testing / verification

No unit tests exist in this project. Verify manually after a full build:

1. **Build** the full `Telegram/Telegram` target (`--continueOnError`) — the compile-breaking
   enum change surfaces any missed `.text`/`.blocks` site.
2. **Send round-trip:** send a rich message `- [ ] a` / `- [x] b` to Saved Messages; confirm
   the checkboxes persist **after the send confirms** (not just in the pre-send preview), and
   that checked/unchecked states are correct.
3. **Edit round-trip:** edit that message; confirm the editor repopulates `- [ ] a` / `- [x] b`
   and saving preserves the states.
4. **Preview surfaces:** confirm the chat list / notification / reply panel previews show a
   checkbox glyph, never the raw sentinel or `num`.
5. **Regression:** ordinary ordered (`1.`) and unordered (`-`) lists still render with correct
   numbers/bullets.

## Risks

- **FlatBuffers regen:** the checked-in `*_generated.swift` is stale; the build regenerates
  from the `.fbs`. Follow the flatc casing rules already documented (edit `.fbs`, not the
  generated Swift).
- **Source-breaking enum change:** mitigated by the compiler — every site must be updated to
  build. The full-build step is the completeness gate.
- **Tri-state encoding:** both Postbox (`"ck"` int) and FlatBuffers (`checkState:int32`) treat
  absent/0 as `nil`, so pre-existing stored pages decode unchanged.
