# InstantPage list checkboxes (task-list style) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give `InstantPageListItem` a first-class `checked: Bool?` so task-list checkboxes (`- [ ]` / `- [x]`) parse, serialize (Postbox + FlatBuffers), transmit (native API flags), render (real V2 CheckNode artwork), and survive the edit round-trip in rich-data message bubbles.

**Architecture:** Add a third associated value `Bool?` to `InstantPageListItem.text` / `.blocks`, orthogonal to the existing `num` string, and delete the prior sentinel-in-`num` hack. Transmission reads/writes the `checkbox`=flags.0 / `checked`=flags.1 bits that already exist on all four API list-item constructors. Display reads `item.checked`; the V2 marker hosts a `CheckNode`.

**Tech Stack:** Swift, Bazel (`Make.py`), Postbox coding, FlatBuffers (`flatc` genrule), Telegram `Api.*` TL types, `CheckNode` (ASDisplayNode).

---

## Critical execution notes

- **No unit tests exist in this project.** Verification is a full Bazel build plus a manual app round-trip (Task 10 / Task 11). Do not invent a test harness.
- **The enum change is source-breaking across modules.** TelegramCore will not compile until every `.text(...)` / `.blocks(...)` site (Tasks 1–9) is updated. **Do not attempt a build until Task 10.** Per-task subagents make edits only; the controller runs the single build-to-green at Task 10 (the full Bazel build must be driven by the controller with `run_in_background`, not by a subagent — backgrounded subagent builds get torn down on yield).
- **Commit once, at the end** (Task 11), after the build is green and verification passes — intermediate states don't compile. This matches the repo's feature-level commit style.
- **Build command** (from repo root, Task 10):
  ```sh
  source ~/.zshrc 2>/dev/null; python3 build-system/Make/Make.py --overrideXcodeVersion \
    --cacheDir ~/telegram-bazel-cache build \
    --configurationPath build-system/appstore-configuration.json \
    --gitCodesigningRepository git@gitlab.com:peter-iakovlev/fastlanematch.git \
    --gitCodesigningType development --gitCodesigningUseCurrent --buildNumber=1 \
    --configuration=debug_sim_arm64 --continueOnError
  ```

## Tri-state convention (used everywhere)

`checked: Bool?` maps to a tri-state integer for both Postbox and FlatBuffers:

```
0 → nil   (not a checkbox item)
1 → false (checkbox, unchecked)
2 → true  (checkbox, checked)
```

Helper used in serialization tasks (define locally where needed):
- encode: `nil → 0, false → 1, true → 2`
- decode: `0 → nil, 1 → false, 2 → true`

---

## Task 1: Data model — enum, FlatBuffers schema, Postbox, Equatable

**Files:**
- Modify: `submodules/TelegramCore/Sources/SyncCore/SyncCore_InstantPage.swift` (enum ~1022, decodeListItems ~44, Postbox ~1027-1059, `==` ~1061-1082, FlatBuffers ~1084-1145)
- Modify: `submodules/TelegramCore/FlatSerialization/Models/InstantPageBlock.fbs:214-222`

- [ ] **Step 1: Add the `checkState` field to both FlatBuffers tables**

In `InstantPageBlock.fbs`, change:

```
table InstantPageListItem_Text {
    text:RichText (id: 0, required);
    number:string (id: 1);
}

table InstantPageListItem_Blocks {
    blocks:[InstantPageBlock] (id: 0, required);
    number:string (id: 1);
}
```

to:

```
table InstantPageListItem_Text {
    text:RichText (id: 0, required);
    number:string (id: 1);
    checkState:int32 (id: 2);
}

table InstantPageListItem_Blocks {
    blocks:[InstantPageBlock] (id: 0, required);
    number:string (id: 1);
    checkState:int32 (id: 2);
}
```

(int32 defaults to 0 → absent decodes as `nil`; the Bazel `flatc` genrule regenerates the Swift at build time. Do NOT edit the checked-in `*_generated.swift`.)

- [ ] **Step 2: Add the associated value to the enum**

In `SyncCore_InstantPage.swift`, change the enum (~line 1022):

```swift
public indirect enum InstantPageListItem: PostboxCoding, Equatable {
    case unknown
    case text(RichText, String?)
    case blocks([InstantPageBlock], String?)
```

to:

```swift
public indirect enum InstantPageListItem: PostboxCoding, Equatable {
    case unknown
    case text(RichText, String?, Bool?)
    case blocks([InstantPageBlock], String?, Bool?)
```

- [ ] **Step 3: Update `decodeListItems` construction (~line 44)**

```swift
        items.append(.text(item, nil))
```

to:

```swift
        items.append(.text(item, nil, nil))
```

- [ ] **Step 4: Update the Postbox `init(decoder:)` (~lines 1027-1036)**

Replace:

```swift
    public init(decoder: PostboxDecoder) {
        switch decoder.decodeInt32ForKey("r", orElse: 0) {
            case InstantPageListItemType.text.rawValue:
                self = .text(decoder.decodeObjectForKey("t", decoder: { RichText(decoder: $0) }) as! RichText, decoder.decodeOptionalStringForKey("n"))
            case InstantPageListItemType.blocks.rawValue:
                self = .blocks(decoder.decodeObjectArrayWithDecoderForKey("b"), decoder.decodeOptionalStringForKey("n"))
            default:
                self = .unknown
        }
    }
```

with:

```swift
    public init(decoder: PostboxDecoder) {
        switch decoder.decodeInt32ForKey("r", orElse: 0) {
            case InstantPageListItemType.text.rawValue:
                self = .text(decoder.decodeObjectForKey("t", decoder: { RichText(decoder: $0) }) as! RichText, decoder.decodeOptionalStringForKey("n"), InstantPageListItem.checkedFromTriState(decoder.decodeInt32ForKey("ck", orElse: 0)))
            case InstantPageListItemType.blocks.rawValue:
                self = .blocks(decoder.decodeObjectArrayWithDecoderForKey("b"), decoder.decodeOptionalStringForKey("n"), InstantPageListItem.checkedFromTriState(decoder.decodeInt32ForKey("ck", orElse: 0)))
            default:
                self = .unknown
        }
    }
```

- [ ] **Step 5: Update the Postbox `encode` (~lines 1038-1059)**

Replace:

```swift
    public func encode(_ encoder: PostboxEncoder) {
        switch self {
            case let .text(text, num):
                encoder.encodeInt32(InstantPageListItemType.text.rawValue, forKey: "r")
                encoder.encodeObject(text, forKey: "t")
                if let num = num {
                    encoder.encodeString(num, forKey: "n")
                } else {
                    encoder.encodeNil(forKey: "n")
                }
            case let .blocks(blocks, num):
                encoder.encodeInt32(InstantPageListItemType.blocks.rawValue, forKey: "r")
                encoder.encodeObjectArray(blocks, forKey: "b")
                if let num = num {
                    encoder.encodeString(num, forKey: "n")
                } else {
                    encoder.encodeNil(forKey: "n")
                }
            default:
                break
        }
    }
```

with:

```swift
    public func encode(_ encoder: PostboxEncoder) {
        switch self {
            case let .text(text, num, checked):
                encoder.encodeInt32(InstantPageListItemType.text.rawValue, forKey: "r")
                encoder.encodeObject(text, forKey: "t")
                if let num = num {
                    encoder.encodeString(num, forKey: "n")
                } else {
                    encoder.encodeNil(forKey: "n")
                }
                if let triState = InstantPageListItem.triState(fromChecked: checked) {
                    encoder.encodeInt32(triState, forKey: "ck")
                } else {
                    encoder.encodeNil(forKey: "ck")
                }
            case let .blocks(blocks, num, checked):
                encoder.encodeInt32(InstantPageListItemType.blocks.rawValue, forKey: "r")
                encoder.encodeObjectArray(blocks, forKey: "b")
                if let num = num {
                    encoder.encodeString(num, forKey: "n")
                } else {
                    encoder.encodeNil(forKey: "n")
                }
                if let triState = InstantPageListItem.triState(fromChecked: checked) {
                    encoder.encodeInt32(triState, forKey: "ck")
                } else {
                    encoder.encodeNil(forKey: "ck")
                }
            default:
                break
        }
    }
```

- [ ] **Step 6: Add the tri-state helpers as static methods on the enum**

Immediately after the `encode(_:)` method (still inside `InstantPageListItem`), add:

```swift
    static func checkedFromTriState(_ value: Int32) -> Bool? {
        switch value {
        case 1: return false
        case 2: return true
        default: return nil
        }
    }

    /// Returns the persisted tri-state (1 = unchecked, 2 = checked) or nil when not a checkbox item.
    static func triState(fromChecked checked: Bool?) -> Int32? {
        switch checked {
        case .some(false): return 1
        case .some(true): return 2
        case .none: return nil
        }
    }
```

- [ ] **Step 7: Update `==` (~lines 1061-1082)**

Replace the `.text` and `.blocks` arms:

```swift
            case let .text(lhsText, lhsNum):
                if case let .text(rhsText, rhsNum) = rhs, lhsText == rhsText, lhsNum == rhsNum {
                    return true
                } else {
                    return false
                }
            case let .blocks(lhsBlocks, lhsNum):
                if case let .blocks(rhsBlocks, rhsNum) = rhs, lhsBlocks == rhsBlocks, lhsNum == rhsNum {
                    return true
                } else {
                    return false
                }
```

with:

```swift
            case let .text(lhsText, lhsNum, lhsChecked):
                if case let .text(rhsText, rhsNum, rhsChecked) = rhs, lhsText == rhsText, lhsNum == rhsNum, lhsChecked == rhsChecked {
                    return true
                } else {
                    return false
                }
            case let .blocks(lhsBlocks, lhsNum, lhsChecked):
                if case let .blocks(rhsBlocks, rhsNum, rhsChecked) = rhs, lhsBlocks == rhsBlocks, lhsNum == rhsNum, lhsChecked == rhsChecked {
                    return true
                } else {
                    return false
                }
```

- [ ] **Step 8: Update the FlatBuffers `init(flatBuffersObject:)` (~lines 1084-1105)**

Replace the two value arms:

```swift
            self = .text(try RichText(flatBuffersObject: textValue.text), textValue.number)
```

with:

```swift
            self = .text(try RichText(flatBuffersObject: textValue.text), textValue.number, InstantPageListItem.checkedFromTriState(textValue.checkState))
```

and:

```swift
            self = .blocks(blocks, blocksValue.number)
```

with:

```swift
            self = .blocks(blocks, blocksValue.number, InstantPageListItem.checkedFromTriState(blocksValue.checkState))
```

- [ ] **Step 9: Update the FlatBuffers `encodeToFlatBuffers` (~lines 1107-1145)**

Change the destructure of the two arms from `case let .text(text, number):` to `case let .text(text, number, checked):` and from `case let .blocks(blocks, number):` to `case let .blocks(blocks, number, checked):`. Then, after each existing `if let _ = number { ... add(number:) }` block (and before computing `offset`), add the checkState write:

For the `.text` arm:

```swift
            if let triState = InstantPageListItem.triState(fromChecked: checked) {
                TelegramCore_InstantPageListItem_Text.add(checkState: triState, &builder)
            }
```

For the `.blocks` arm:

```swift
            if let triState = InstantPageListItem.triState(fromChecked: checked) {
                TelegramCore_InstantPageListItem_Blocks.add(checkState: triState, &builder)
            }
```

- [ ] **Step 10: Static self-check (no build yet)**

Run: `grep -nE '\.(text|blocks)\(' submodules/TelegramCore/Sources/SyncCore/SyncCore_InstantPage.swift | grep -iE 'listitem|\.plain|decodeObjectArray|RichText\(flat|item, nil'`
Expected: every `InstantPageListItem` `.text(...)`/`.blocks(...)` now has three components. (Confirmed at build in Task 10.)

---

## Task 2: API transmission — accessors + checkbox flag bits

**Files:**
- Modify: `submodules/TelegramCore/Sources/ApiUtils/InstantPage.swift` (`num` accessor ~16-27, `init(apiListItem:)` ~30-39, `init(apiListOrderedItem:)` ~41-50, `apiInputPageListItem()` ~52-61, `apiInputPageOrderedListItem()` ~63-88)

- [ ] **Step 1: Update the `num` accessor and add a `checked` accessor (~lines 16-27)**

Replace:

```swift
public extension InstantPageListItem {
    var num: String? {
        switch self {
            case let .text(_, num):
                return num
            case let .blocks(_, num):
                return num
            default:
                return nil
        }
    }
}
```

with:

```swift
public extension InstantPageListItem {
    var num: String? {
        switch self {
            case let .text(_, num, _):
                return num
            case let .blocks(_, num, _):
                return num
            default:
                return nil
        }
    }

    var checked: Bool? {
        switch self {
            case let .text(_, _, checked):
                return checked
            case let .blocks(_, _, checked):
                return checked
            default:
                return nil
        }
    }
}
```

- [ ] **Step 2: Read checkbox flags on receive — `init(apiListItem:)` (~lines 30-39)**

Replace:

```swift
    init(apiListItem: Api.PageListItem) {
        switch apiListItem {
            case let .pageListItemText(pageListItemTextData):
                let text = pageListItemTextData.text
                self = .text(RichText(apiText: text), nil)
            case let .pageListItemBlocks(pageListItemBlocksData):
                let blocks = pageListItemBlocksData.blocks
                self = .blocks(blocks.map({ InstantPageBlock(apiBlock: $0) }), nil)
        }
    }
```

with:

```swift
    init(apiListItem: Api.PageListItem) {
        switch apiListItem {
            case let .pageListItemText(pageListItemTextData):
                let text = pageListItemTextData.text
                self = .text(RichText(apiText: text), nil, InstantPageListItem.checkedFromApiFlags(pageListItemTextData.flags))
            case let .pageListItemBlocks(pageListItemBlocksData):
                let blocks = pageListItemBlocksData.blocks
                self = .blocks(blocks.map({ InstantPageBlock(apiBlock: $0) }), nil, InstantPageListItem.checkedFromApiFlags(pageListItemBlocksData.flags))
        }
    }
```

- [ ] **Step 3: Read checkbox flags on receive — `init(apiListOrderedItem:)` (~lines 41-50)**

Replace:

```swift
    init(apiListOrderedItem: Api.PageListOrderedItem) {
        switch apiListOrderedItem {
            case let .pageListOrderedItemText(pageListOrderedItemTextData):
                let (num, text) = (pageListOrderedItemTextData.num, pageListOrderedItemTextData.text)
                self = .text(RichText(apiText: text), num)
            case let .pageListOrderedItemBlocks(pageListOrderedItemBlocksData):
                let (num, blocks) = (pageListOrderedItemBlocksData.num, pageListOrderedItemBlocksData.blocks)
                self = .blocks(blocks.map({ InstantPageBlock(apiBlock: $0) }), num)
        }
    }
```

with:

```swift
    init(apiListOrderedItem: Api.PageListOrderedItem) {
        switch apiListOrderedItem {
            case let .pageListOrderedItemText(pageListOrderedItemTextData):
                let (num, text) = (pageListOrderedItemTextData.num, pageListOrderedItemTextData.text)
                self = .text(RichText(apiText: text), num, InstantPageListItem.checkedFromApiFlags(pageListOrderedItemTextData.flags))
            case let .pageListOrderedItemBlocks(pageListOrderedItemBlocksData):
                let (num, blocks) = (pageListOrderedItemBlocksData.num, pageListOrderedItemBlocksData.blocks)
                self = .blocks(blocks.map({ InstantPageBlock(apiBlock: $0) }), num, InstantPageListItem.checkedFromApiFlags(pageListOrderedItemBlocksData.flags))
        }
    }
```

- [ ] **Step 4: Write checkbox flags on send — `apiInputPageListItem()` (~lines 52-61)**

Replace:

```swift
    func apiInputPageListItem() -> Api.PageListItem {
        switch self {
        case let .text(value, _):
            return .pageListItemText(Api.PageListItem.Cons_pageListItemText(flags: 0, text: value.apiRichText()))
        case let .blocks(blocks, _):
            return .pageListItemBlocks(Api.PageListItem.Cons_pageListItemBlocks(flags: 0, blocks: blocks.compactMap { $0.apiInputBlock() }))
        case .unknown:
            return .pageListItemText(Api.PageListItem.Cons_pageListItemText(flags: 0, text: .textPlain(Api.RichText.Cons_textPlain(text: ""))))
        }
    }
```

with:

```swift
    func apiInputPageListItem() -> Api.PageListItem {
        switch self {
        case let .text(value, _, checked):
            return .pageListItemText(Api.PageListItem.Cons_pageListItemText(flags: InstantPageListItem.apiFlags(fromChecked: checked), text: value.apiRichText()))
        case let .blocks(blocks, _, checked):
            return .pageListItemBlocks(Api.PageListItem.Cons_pageListItemBlocks(flags: InstantPageListItem.apiFlags(fromChecked: checked), blocks: blocks.compactMap { $0.apiInputBlock() }))
        case .unknown:
            return .pageListItemText(Api.PageListItem.Cons_pageListItemText(flags: 0, text: .textPlain(Api.RichText.Cons_textPlain(text: ""))))
        }
    }
```

- [ ] **Step 5: Write checkbox flags on send — `apiInputPageOrderedListItem()` (~lines 63-88)**

Replace:

```swift
    func apiInputPageOrderedListItem() -> Api.InputPageListOrderedItem {
        switch self {
        case let .text(value, num):
            var flags: Int32 = 0
            
            var inputNum: Int32?
            if let num, let numValue = Int32(num) {
                inputNum = numValue
                flags |= (1 << 2)
            }
            
            return .inputPageListOrderedItemText(Api.InputPageListOrderedItem.Cons_inputPageListOrderedItemText(flags: flags, text: value.apiRichText(), value: inputNum, type: nil))
        case let .blocks(blocks, num):
            var flags: Int32 = 0
            
            var inputNum: Int32?
            if let num, let numValue = Int32(num) {
                inputNum = numValue
                flags |= (1 << 2)
            }
            
            return .inputPageListOrderedItemBlocks(Api.InputPageListOrderedItem.Cons_inputPageListOrderedItemBlocks(flags: flags, blocks: blocks.compactMap { $0.apiInputBlock() }, value: inputNum, type: nil))
        case .unknown:
            return .inputPageListOrderedItemText(Api.InputPageListOrderedItem.Cons_inputPageListOrderedItemText(flags: 0, text: .textPlain(Api.RichText.Cons_textPlain(text: "")), value: nil, type: nil))
        }
    }
```

with:

```swift
    func apiInputPageOrderedListItem() -> Api.InputPageListOrderedItem {
        switch self {
        case let .text(value, num, checked):
            var flags: Int32 = InstantPageListItem.apiFlags(fromChecked: checked)
            
            var inputNum: Int32?
            if let num, let numValue = Int32(num) {
                inputNum = numValue
                flags |= (1 << 2)
            }
            
            return .inputPageListOrderedItemText(Api.InputPageListOrderedItem.Cons_inputPageListOrderedItemText(flags: flags, text: value.apiRichText(), value: inputNum, type: nil))
        case let .blocks(blocks, num, checked):
            var flags: Int32 = InstantPageListItem.apiFlags(fromChecked: checked)
            
            var inputNum: Int32?
            if let num, let numValue = Int32(num) {
                inputNum = numValue
                flags |= (1 << 2)
            }
            
            return .inputPageListOrderedItemBlocks(Api.InputPageListOrderedItem.Cons_inputPageListOrderedItemBlocks(flags: flags, blocks: blocks.compactMap { $0.apiInputBlock() }, value: inputNum, type: nil))
        case .unknown:
            return .inputPageListOrderedItemText(Api.InputPageListOrderedItem.Cons_inputPageListOrderedItemText(flags: 0, text: .textPlain(Api.RichText.Cons_textPlain(text: "")), value: nil, type: nil))
        }
    }
```

- [ ] **Step 6: Add the API-flag helpers**

Add to the `public extension InstantPageListItem` block in this file (after the `checked` accessor from Step 1). `checkbox` = bit 0, `checked` = bit 1 (verified against the generated `Api.PageListItem` / `Api.PageListOrderedItem` / `Api.InputPageListOrderedItem`).

```swift
    static func checkedFromApiFlags(_ flags: Int32) -> Bool? {
        guard (flags & (1 << 0)) != 0 else {
            return nil
        }
        return (flags & (1 << 1)) != 0
    }

    static func apiFlags(fromChecked checked: Bool?) -> Int32 {
        guard let checked else {
            return 0
        }
        var flags: Int32 = 1 << 0
        if checked {
            flags |= (1 << 1)
        }
        return flags
    }
```

- [ ] **Step 7: Static self-check**

Run: `grep -nE 'flags: 0|apiFlags|checkedFromApiFlags' submodules/TelegramCore/Sources/ApiUtils/InstantPage.swift`
Expected: the two `.pageListItem*` send arms use `apiFlags(...)`; the two `.unknown` fallbacks keep `flags: 0`; both receive inits use `checkedFromApiFlags(...)`.

---

## Task 3: Markdown forward parser — route into `checked`, drop the sentinel

**Files:**
- Modify: `submodules/BrowserUI/Sources/BrowserMarkdown.swift` (sentinel consts ~23-24, `validate(listItem:)` ~203, `markdownListItems` ~1436-1475, `markdownTaskListNumber` ~1477-1484, `markdownFirstParagraphText` list arm ~2287-2292)

- [ ] **Step 1: Remove the markdown sentinel constants (~lines 23-24)**

Delete:

```swift
private let markdownTaskListUncheckedNumber = "\u{001f}tg-md-task:unchecked"
private let markdownTaskListCheckedNumber = "\u{001f}tg-md-task:checked"
```

- [ ] **Step 2: Update `validate(listItem:)` destructure (~line 203)**

```swift
        if case let .blocks(blocks, _) = listItem {
```

to:

```swift
        if case let .blocks(blocks, _, _) = listItem {
```

- [ ] **Step 3: Rewrite the item construction in `markdownListItems` (~lines 1449-1472)**

Replace:

```swift
        let taskListState = markdownApplyTaskListMarker(to: &blocks)
        let number: String?
        if let taskListState {
            number = markdownTaskListNumber(for: taskListState)
        } else if ordered {
            number = "\(ordinal)"
        } else {
            number = nil
        }
        if blocks.isEmpty {
            if let number {
                result.append(.text(.plain(" "), number))
            }
            continue
        }
        if blocks.count == 1, case let .paragraph(text) = blocks[0] {
            if number != nil && markdownIsWhitespaceOnly(text) {
                result.append(.text(.plain(" "), number))
            } else {
                result.append(.text(text, number))
            }
        } else {
            result.append(.blocks(blocks, number))
        }
```

with:

```swift
        let taskListState = markdownApplyTaskListMarker(to: &blocks)
        let checked: Bool?
        switch taskListState {
        case .unchecked:
            checked = false
        case .checked:
            checked = true
        case nil:
            checked = nil
        }
        let number: String? = ordered ? "\(ordinal)" : nil
        if blocks.isEmpty {
            if checked != nil || number != nil {
                result.append(.text(.plain(" "), number, checked))
            }
            continue
        }
        if blocks.count == 1, case let .paragraph(text) = blocks[0] {
            if markdownIsWhitespaceOnly(text) && (checked != nil || number != nil) {
                result.append(.text(.plain(" "), number, checked))
            } else {
                result.append(.text(text, number, checked))
            }
        } else {
            result.append(.blocks(blocks, number, checked))
        }
```

(Note: task lists are unordered, so a task item normally has `number == nil`; an ordered task item now keeps its number *and* its checkbox.)

- [ ] **Step 4: Delete the now-unused `markdownTaskListNumber` (~lines 1477-1484)**

Delete:

```swift
private func markdownTaskListNumber(for state: MarkdownTaskListState) -> String {
    switch state {
    case .unchecked:
        return markdownTaskListUncheckedNumber
    case .checked:
        return markdownTaskListCheckedNumber
    }
}
```

(Keep `markdownApplyTaskListMarker`, `markdownStrippingTaskListMarker`, `markdownTaskListMarker`, and the `MarkdownTaskListState` enum — they still detect the `[ ]`/`[x]` syntax.)

- [ ] **Step 5: Update `markdownFirstParagraphText` list-item destructures (~lines 2288, 2292)**

```swift
                case let .text(text, _):
```
to
```swift
                case let .text(text, _, _):
```
and
```swift
                case let .blocks(blocks, _):
```
to
```swift
                case let .blocks(blocks, _, _):
```

- [ ] **Step 6: Static self-check**

Run: `grep -n 'markdownTaskList\|tg-md-task' submodules/BrowserUI/Sources/BrowserMarkdown.swift`
Expected: no `markdownTaskListUncheckedNumber`/`CheckedNumber`/`markdownTaskListNumber`/`tg-md-task` references remain (only `markdownTaskListMarker` / `markdownApplyTaskListMarker` / `markdownStrippingTaskListMarker` / `MarkdownTaskListState`).

---

## Task 4: BrowserReadability construction sites

**Files:**
- Modify: `submodules/BrowserUI/Sources/BrowserReadability.swift` (~lines 613, 616, 623)

- [ ] **Step 1: Update the two construction sites (~lines 613, 616)**

```swift
                    items.append(.blocks(blocks, nil))
```
to
```swift
                    items.append(.blocks(blocks, nil, nil))
```
and
```swift
                items.append(.text(trim(parseRichText(item, &media)), nil))
```
to
```swift
                items.append(.text(trim(parseRichText(item, &media)), nil, nil))
```

- [ ] **Step 2: Update the destructure (~line 623)**

```swift
        if case let .text(text, _) = item {
```
to
```swift
        if case let .text(text, _, _) = item {
```

- [ ] **Step 3: Static self-check**

Run: `grep -nE '\.(text|blocks)\(' submodules/BrowserUI/Sources/BrowserReadability.swift | grep -iE 'items\.append|case let'`
Expected: all list-item `.text`/`.blocks` sites carry three components.

---

## Task 5: Reverse markdown — emit `- [ ]` / `- [x]` for the edit round-trip

**Files:**
- Modify: `submodules/BrowserUI/Sources/InstantPageToMarkdown.swift` (`markdownList` ~164-200)

- [ ] **Step 1: Emit the task marker from `checked` (~lines 168-196)**

Replace the body of the `for item in items` loop in `markdownList`:

```swift
    for item in items {
        // The stored per-item marker string (`InstantPageListItem`'s `String?`) is
        // intentionally ignored: ordered markers are regenerated from the running
        // index (CommonMark renumbers anyway) and the unordered marker is fixed.
        let marker = ordered ? "\(index). " : "- "
        switch item {
        case let .text(text, _):
            lines.append("\(indentString)\(marker)\(markdownInline(from: text))")
        case let .blocks(blocks, _):
            var remainder = blocks
            var markerLineText = ""
            if case let .paragraph(text)? = remainder.first {
                markerLineText = markdownInline(from: text)
                remainder = Array(remainder.dropFirst())
            }
            lines.append("\(indentString)\(marker)\(markerLineText)")
            let childIndentString = String(repeating: " ", count: (indent + 1) * 2)
            for block in remainder {
                if case let .list(nestedItems, nestedOrdered) = block {
                    lines.append(markdownList(items: nestedItems, ordered: nestedOrdered, indent: indent + 1))
                } else if let rendered = markdownString(from: block) {
                    for line in rendered.split(separator: "\n", omittingEmptySubsequences: false) {
                        lines.append("\(childIndentString)\(line)")
                    }
                }
            }
        case .unknown:
            break
        }
        index += 1
    }
```

with:

```swift
    for item in items {
        // Ordered markers are regenerated from the running index (CommonMark renumbers
        // anyway); the unordered marker is fixed. A task-list `checked` state is emitted
        // as a GitHub task marker so re-classification on save re-parses it as a checkbox.
        let listMarker = ordered ? "\(index). " : "- "
        let taskMarker: String
        switch item.checked {
        case .some(false):
            taskMarker = "[ ] "
        case .some(true):
            taskMarker = "[x] "
        case .none:
            taskMarker = ""
        }
        let marker = "\(listMarker)\(taskMarker)"
        switch item {
        case let .text(text, _, _):
            lines.append("\(indentString)\(marker)\(markdownInline(from: text))")
        case let .blocks(blocks, _, _):
            var remainder = blocks
            var markerLineText = ""
            if case let .paragraph(text)? = remainder.first {
                markerLineText = markdownInline(from: text)
                remainder = Array(remainder.dropFirst())
            }
            lines.append("\(indentString)\(marker)\(markerLineText)")
            let childIndentString = String(repeating: " ", count: (indent + 1) * 2)
            for block in remainder {
                if case let .list(nestedItems, nestedOrdered) = block {
                    lines.append(markdownList(items: nestedItems, ordered: nestedOrdered, indent: indent + 1))
                } else if let rendered = markdownString(from: block) {
                    for line in rendered.split(separator: "\n", omittingEmptySubsequences: false) {
                        lines.append("\(childIndentString)\(line)")
                    }
                }
            }
        case .unknown:
            break
        }
        index += 1
    }
```

(`item.checked` resolves via the accessor added in Task 2; both files are in modules that import TelegramCore.)

- [ ] **Step 2: Static self-check**

Run: `grep -n 'item.checked\|\[x\] \|\[ \] ' submodules/BrowserUI/Sources/InstantPageToMarkdown.swift`
Expected: the `[ ] ` / `[x] ` task markers are emitted from `item.checked`.

---

## Task 6: preview text — checkbox glyph, no sentinel leak

**Files:**
- Modify: `submodules/TelegramStringFormatting/Sources/InstantPagePreviewText.swift` (`previewText()` ~55-81)

- [ ] **Step 1: Render a glyph for checkbox items (~lines 60-78)**

Replace the `.text` and `.blocks` arms:

```swift
        case let .text(text, num):
            if let num, !num.isEmpty {
                return "\(num). \(text.previewText())"
            } else {
                return text.previewText()
            }
        case let .blocks(blocks, num):
            var blocksText = ""
            for block in blocks {
                if !blocksText.isEmpty {
                    blocksText.append("\n")
                }
                blocksText.append(block.previewText())
            }
            if let num {
                return "\(num). \(blocksText)"
            } else {
                return blocksText
            }
```

with:

```swift
        case let .text(text, num, checked):
            let body = text.previewText()
            if let checked {
                return "\(checked ? "☑︎" : "☐") \(body)"
            } else if let num, !num.isEmpty {
                return "\(num). \(body)"
            } else {
                return body
            }
        case let .blocks(blocks, num, checked):
            var blocksText = ""
            for block in blocks {
                if !blocksText.isEmpty {
                    blocksText.append("\n")
                }
                blocksText.append(block.previewText())
            }
            if let checked {
                return "\(checked ? "☑︎" : "☐") \(blocksText)"
            } else if let num {
                return "\(num). \(blocksText)"
            } else {
                return blocksText
            }
```

- [ ] **Step 2: Static self-check**

Run: `grep -nE '\.(text|blocks)\(' submodules/TelegramStringFormatting/Sources/InstantPagePreviewText.swift`
Expected: both arms destructure three components and branch on `checked`.

---

## Task 7: V1 layout — read `checked`, remove the sentinel

**Files:**
- Modify: `submodules/InstantPageUI/Sources/InstantPageLayout.swift` (sentinel ~134-147, list detection ~383, 392, empty-blocks ~435-436, destructures ~439, 469)

- [ ] **Step 1: Remove the V1 sentinel constants and helper (~lines 134-147)**

Delete:

```swift
private let instantPageTaskListUncheckedNumber = "\u{001f}tg-md-task:unchecked"
private let instantPageTaskListCheckedNumber = "\u{001f}tg-md-task:checked"
```

and the whole helper:

```swift
private func instantPageTaskListMarkerState(_ number: String?) -> Bool? {
    switch number {
    case instantPageTaskListUncheckedNumber:
        return false
    case instantPageTaskListCheckedNumber:
        return true
    default:
        return nil
    }
}
```

Keep `private let instantPageChecklistMarkerSize = CGSize(width: 18.0, height: 18.0)`.

- [ ] **Step 2: Replace the two `instantPageTaskListMarkerState(item.num)` reads (~lines 383, 392)**

```swift
                    if instantPageTaskListMarkerState(item.num) != nil {
```
to
```swift
                    if item.checked != nil {
```
and
```swift
                if let checked = instantPageTaskListMarkerState(item.num) {
```
to
```swift
                if let checked = item.checked {
```

- [ ] **Step 3: Update the empty-blocks substitution (~lines 435-436)**

```swift
                if case let .blocks(blocks, num) = effectiveItem, blocks.isEmpty {
                    effectiveItem = .text(.plain(" "), num)
                }
```
to
```swift
                if case let .blocks(blocks, num, checked) = effectiveItem, blocks.isEmpty {
                    effectiveItem = .text(.plain(" "), num, checked)
                }
```

- [ ] **Step 4: Update the two destructures (~lines 439, 469)**

```swift
                    case let .text(text, _):
```
to
```swift
                    case let .text(text, _, _):
```
and
```swift
                    case let .blocks(blocks, _):
```
to
```swift
                    case let .blocks(blocks, _, _):
```

- [ ] **Step 5: Static self-check**

Run: `grep -n 'instantPageTaskListMarkerState\|tg-md-task\|item.checked' submodules/InstantPageUI/Sources/InstantPageLayout.swift`
Expected: no sentinel/helper references; list detection now reads `item.checked`.

---

## Task 8: V2 layout — `checked` detection + carry checkbox colors to the marker

**Files:**
- Modify: `submodules/InstantPageUI/Sources/InstantPageV2Layout.swift` (marker kind/item ~139-149, sentinel ~1999-2011, `layoutList` detection ~2027-2057, empty-blocks ~2112-2113, destructures ~2117, 2166, `.checklist` construction ~2057)

- [ ] **Step 1: Add a checkbox-colors struct and extend the `.checklist` marker kind (~lines 139-149)**

Replace:

```swift
public enum InstantPageV2ListMarkerKind {
    case bullet
    case number(String)
    case checklist(checked: Bool)
}
```

with:

```swift
public struct InstantPageV2CheckboxColors {
    public let background: UIColor
    public let stroke: UIColor
    public let border: UIColor

    public init(background: UIColor, stroke: UIColor, border: UIColor) {
        self.background = background
        self.stroke = stroke
        self.border = border
    }
}

public enum InstantPageV2ListMarkerKind {
    case bullet
    case number(String)
    case checklist(checked: Bool, colors: InstantPageV2CheckboxColors)
}
```

(The existing no-bind `case .checklist:` matches in `markerFrameFor` and the `firstBlockLineMidY` switch keep working — only the construction site and the renderer's binding need updating.)

- [ ] **Step 2: Remove the V2 sentinel constants and helper (~lines 1999-2011)**

Delete:

```swift
private let instantPageTaskListUncheckedNumber = "\u{001f}tg-md-task:unchecked"
private let instantPageTaskListCheckedNumber = "\u{001f}tg-md-task:checked"

private func instantPageTaskListMarkerState(_ number: String?) -> Bool? {
    switch number {
    case instantPageTaskListUncheckedNumber:
        return false
    case instantPageTaskListCheckedNumber:
        return true
    default:
        return nil
    }
}
```

- [ ] **Step 3: Replace the `hasTaskMarkers` detection in `layoutList` (~lines 2027-2042)**

Replace:

```swift
    if ordered {
        for item in listItems {
            if instantPageTaskListMarkerState(item.num) != nil {
                hasTaskMarkers = true
            } else if let num = item.num, !num.isEmpty {
                hasNums = true
            }
        }
    } else {
        for item in listItems {
            if instantPageTaskListMarkerState(item.num) != nil {
                hasTaskMarkers = true
                break
            }
        }
    }
```

with:

```swift
    if ordered {
        for item in listItems {
            if item.checked != nil {
                hasTaskMarkers = true
            } else if let num = item.num, !num.isEmpty {
                hasNums = true
            }
        }
    } else {
        for item in listItems {
            if item.checked != nil {
                hasTaskMarkers = true
                break
            }
        }
    }
```

- [ ] **Step 4: Replace the per-item marker descriptor build (~lines 2052-2057)**

Replace:

```swift
    for (i, item) in listItems.enumerated() {
        if let checked = instantPageTaskListMarkerState(item.num) {
            if ordered {
                maxIndexWidth = max(maxIndexWidth, checklistMarkerSize.width)
            }
            markerInfos.append(MarkerInfo(kind: .checklist(checked: checked), naturalWidth: checklistMarkerSize.width))
        } else if ordered {
```

with:

```swift
    let checkboxColors = InstantPageV2CheckboxColors(
        background: context.theme.panelAccentColor,
        stroke: context.theme.pageBackgroundColor,
        border: context.theme.controlColor
    )
    for (i, item) in listItems.enumerated() {
        if let checked = item.checked {
            if ordered {
                maxIndexWidth = max(maxIndexWidth, checklistMarkerSize.width)
            }
            markerInfos.append(MarkerInfo(kind: .checklist(checked: checked, colors: checkboxColors), naturalWidth: checklistMarkerSize.width))
        } else if ordered {
```

- [ ] **Step 5: Update the empty-blocks substitution (~lines 2112-2113)**

```swift
        if case let .blocks(blocks, num) = effectiveItem, blocks.isEmpty {
            effectiveItem = .text(.plain(" "), num)
        }
```
to
```swift
        if case let .blocks(blocks, num, checked) = effectiveItem, blocks.isEmpty {
            effectiveItem = .text(.plain(" "), num, checked)
        }
```

- [ ] **Step 6: Update the two `layoutList` destructures (~lines 2117, 2166)**

```swift
        case let .text(text, _):
```
to
```swift
        case let .text(text, _, _):
```
and
```swift
        case let .blocks(blocks, _):
```
to
```swift
        case let .blocks(blocks, _, _):
```

(These are inside `layoutList`'s `switch effectiveItem`. Do NOT touch the unrelated `InstantPageV2LaidOutItem` `.text(...)` cases elsewhere in the file — those take a single `InstantPageV2TextItem` and are a different enum.)

- [ ] **Step 7: Verify the theme color names**

Run: `grep -nE 'var (panelAccentColor|pageBackgroundColor|controlColor)' submodules/InstantPageUI/Sources/InstantPageTheme.swift`
Expected: all three exist on `InstantPageTheme` (they back the V1 `instantPageChecklistMarkerTheme`). If a name differs, use the V1 names from `InstantPageChecklistMarkerItem.swift`'s `instantPageChecklistMarkerTheme`.

- [ ] **Step 8: Static self-check**

Run: `grep -n 'instantPageTaskListMarkerState\|tg-md-task\|item.checked\|\.checklist(' submodules/InstantPageUI/Sources/InstantPageV2Layout.swift`
Expected: no sentinel/helper references; detection reads `item.checked`; `.checklist(checked:colors:)` at the construction site.

---

## Task 9: V2 renderer — real CheckNode artwork

**Files:**
- Modify: `submodules/InstantPageUI/Sources/InstantPageRenderer.swift` (imports ~1-15, `.checklist` case ~1362-1377)

- [ ] **Step 1: Add the CheckNode import**

After `import Display` (line 3), add:

```swift
import CheckNode
```

(`//submodules/CheckNode:CheckNode` is already in `InstantPageUI/BUILD`.)

- [ ] **Step 2: Replace the placeholder `.checklist` drawing (~lines 1362-1377)**

Replace:

```swift
        case let .checklist(checked):
            // V0 placeholder: simple square outline (unchecked) or filled square (checked).
            // The existing V1 InstantPageChecklistMarkerItem artwork can be ported later if needed.
            let outer = CALayer()
            outer.borderColor = item.color.cgColor
            outer.borderWidth = 1.0
            outer.cornerRadius = 3.0
            outer.frame = CGRect(origin: .zero, size: item.frame.size)
            self.layer.addSublayer(outer)
            if checked {
                let fill = CALayer()
                fill.backgroundColor = item.color.cgColor
                fill.cornerRadius = 3.0
                fill.frame = CGRect(origin: .zero, size: item.frame.size).insetBy(dx: 2.0, dy: 2.0)
                self.layer.addSublayer(fill)
            }
```

with:

```swift
        case let .checklist(checked, colors):
            let checkNodeTheme = CheckNodeTheme(
                backgroundColor: colors.background,
                strokeColor: colors.stroke,
                borderColor: colors.border,
                overlayBorder: false,
                hasInset: false,
                hasShadow: false
            )
            let checkNode = CheckNode(theme: checkNodeTheme, content: .check(isRectangle: true))
            checkNode.isUserInteractionEnabled = false
            checkNode.frame = CGRect(origin: .zero, size: item.frame.size)
            checkNode.setSelected(checked, animated: false)
            self.addSubview(checkNode.view)
```

- [ ] **Step 3: Static self-check**

Run: `grep -n 'import CheckNode\|CheckNode(theme:\|\.checklist(checked' submodules/InstantPageUI/Sources/InstantPageRenderer.swift`
Expected: the import is present and the `.checklist(checked, colors)` case builds a `CheckNode`.

---

## Task 10: Full build to green (controller-driven)

**Files:** none (verification only)

- [ ] **Step 1: Run the full Bazel build**

The controller runs (background, real exit captured — not a subagent):

```sh
source ~/.zshrc 2>/dev/null; python3 build-system/Make.py --overrideXcodeVersion \
  --cacheDir ~/telegram-bazel-cache build \
  --configurationPath build-system/appstore-configuration.json \
  --gitCodesigningRepository git@gitlab.com:peter-iakovlev/fastlanematch.git \
  --gitCodesigningType development --gitCodesigningUseCurrent --buildNumber=1 \
  --configuration=debug_sim_arm64 --continueOnError
```

Expected: build succeeds. `--continueOnError` surfaces every remaining `.text`/`.blocks` arity error in one pass.

- [ ] **Step 2: Fix any compile errors**

For each error, it will be a missed `.text(...)`/`.blocks(...)` construction (add `, nil`) or destructure (add `, _`), or a flatc-regeneration mismatch (re-check `checkState` casing per the flatbuffers-codegen rules: field `checkState` → accessor `value.checkState`, add method `add(checkState:)`). Fix and re-run Step 1 until green.

- [ ] **Step 3: Confirm no sentinel survives anywhere**

Run: `grep -rn 'tg-md-task' submodules/ --include="*.swift" | grep -v '_generated'`
Expected: **no matches** — the sentinel is fully removed.

---

## Task 11: Manual verification + commit

**Files:** none (verification), then the feature commit

- [ ] **Step 1: Launch the simulator build and verify the round-trip**

Install/run the built app (XcodeBuildMCP `build_run_sim` or the produced `.app`). In Saved Messages:

1. **Send:** type `- [ ] buy milk` and `- [x] done` on separate lines, send. Confirm both render as checkboxes (empty + checked) and that **the checkboxes remain after the send confirms** (not just in the pre-send preview).
2. **Edit:** long-press → Edit. Confirm the editor repopulates `- [ ] buy milk` / `- [x] done`. Change `[ ]` → `[x]`, save; confirm the checkbox updates.
3. **Preview:** confirm the chat-list preview / reply panel shows a checkbox glyph (`☐`/`☑︎`), never raw brackets or a sentinel.
4. **Regression:** send `1. one` / `2. two` and `- a` / `- b`; confirm ordinary numbered and bulleted lists are unaffected.

- [ ] **Step 2: Commit the feature**

```bash
git add submodules/TelegramCore/Sources/SyncCore/SyncCore_InstantPage.swift \
        submodules/TelegramCore/FlatSerialization/Models/InstantPageBlock.fbs \
        submodules/TelegramCore/Sources/ApiUtils/InstantPage.swift \
        submodules/BrowserUI/Sources/BrowserMarkdown.swift \
        submodules/BrowserUI/Sources/BrowserReadability.swift \
        submodules/BrowserUI/Sources/InstantPageToMarkdown.swift \
        submodules/TelegramStringFormatting/Sources/InstantPagePreviewText.swift \
        submodules/InstantPageUI/Sources/InstantPageLayout.swift \
        submodules/InstantPageUI/Sources/InstantPageV2Layout.swift \
        submodules/InstantPageUI/Sources/InstantPageRenderer.swift
git commit -m "$(cat <<'EOF'
InstantPage list checkboxes: first-class checked state + API flags

Replace the sentinel-in-num task-list prototype with a first-class
`checked: Bool?` on InstantPageListItem (orthogonal to num). Transmit via
the native PageListItem/PageListOrderedItem checkbox/checked flag bits, so
state survives the server for sender and recipients. Render real CheckNode
artwork in the V2 bubble, restore the edit round-trip (reverse markdown),
and fix the preview-text sentinel leak.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Self-review notes (spec coverage)

- Parsing → Task 3 (markdown forward). Serialization → Task 1 (Postbox + FlatBuffers). Transmission → Task 2 (API flags, all four types). V2 artwork → Tasks 8–9. Edit round-trip → Task 5. Preview leak → Task 6. V1 parity → Task 7. Mechanical sites → Tasks 1,3,4,7,8. Build/verify → Tasks 10–11.
- The `checked`/`num`/`checkedFromTriState`/`triState`/`checkedFromApiFlags`/`apiFlags` symbol names are consistent across Tasks 1–8.
- No sentinel references remain after Tasks 3, 7, 8 (asserted in Task 10 Step 3).
