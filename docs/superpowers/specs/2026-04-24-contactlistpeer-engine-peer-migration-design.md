# Wave 36 — `ContactListPeer.peer` `Peer` → `EnginePeer`

Date: 2026-04-24
Status: approved design, awaiting plan
Wave shape: Peer-typed-API enum-case payload migration, single atomic commit (waves 34/35 pattern)

## Goal

Eliminate the Postbox-protocol `Peer` leak in the `ContactListPeer.peer(peer:isGlobal:participantCount:)` case payload by migrating the `peer` field from `Peer` to `EnginePeer`. Drop the outflow `._asPeer()` bridges that waves 33/34 installed at construction sites, and the inflow `EnginePeer(...)` wrappings at destructure sites. Apply wave 35's validated pre-flight pattern set (literal token + `.peer as?`/`is` + outflow-args + `EnginePeer(.peer)` + `._asPeer()`) to keep undercount below wave 35's 14%.

## Non-goals

- `ContactListPeerId.peer(PeerId)` (sibling enum, different payload) — unchanged; `PeerId == EnginePeer.Id` makes it already-clean.
- `canSendMessagesToPeer(_ peer: Peer, ignoreDefault: Bool) -> Bool` parameter migration — broader blast radius, deferred.
- `makePeerInfoController` / `makeChatQrCodeScreen` / `makeChatRecentActionsController` protocol-method migrations — broader blast radius, deferred.
- `openPeer(peer: Peer, ...)` / other Peer-typed APIs called from destructured bodies — if any destructured `peer` outflows into a raw-`Peer`-typed API after migration, add a `._asPeer()` bridge at that call site. Migrating those APIs is its own future wave.
- No new engine wrappers, typealiases, or facades introduced in this wave.
- No `import Postbox` drops in this wave — deferred to a follow-on unused-import sweep.

## Type change

```swift
// Before
public enum ContactListPeer: Equatable {
    case peer(peer: Peer, isGlobal: Bool, participantCount: Int32?)
    case deviceContact(DeviceContactStableId, DeviceContactBasicData)

    public var id: ContactListPeerId { … }
    public var indexName: PeerIndexNameRepresentation { … }

    public static func ==(lhs: ContactListPeer, rhs: ContactListPeer) -> Bool {
        switch lhs {
        case let .peer(lhsPeer, lhsIsGlobal, lhsParticipantCount):
            if case let .peer(rhsPeer, rhsIsGlobal, rhsParticipantCount) = rhs,
               lhsPeer.isEqual(rhsPeer),                                // Postbox protocol method
               lhsIsGlobal == rhsIsGlobal, lhsParticipantCount == rhsParticipantCount {
                return true
            } else { return false }
        case let .deviceContact(id, contact):
            if case .deviceContact(id, contact) = rhs { return true } else { return false }
        }
    }
}

// After
public enum ContactListPeer: Equatable {
    case peer(peer: EnginePeer, isGlobal: Bool, participantCount: Int32?)
    case deviceContact(DeviceContactStableId, DeviceContactBasicData)

    public var id: ContactListPeerId { … }                              // body unchanged; peer.id is EnginePeer.Id == PeerId
    public var indexName: EnginePeer.IndexName { … }                    // return type changed — body unchanged but type flows from EnginePeer.indexName

    public static func ==(lhs: ContactListPeer, rhs: ContactListPeer) -> Bool {
        switch lhs {
        case let .peer(lhsPeer, lhsIsGlobal, lhsParticipantCount):
            if case let .peer(rhsPeer, rhsIsGlobal, rhsParticipantCount) = rhs,
               lhsPeer == rhsPeer,                                       // EnginePeer is Equatable
               lhsIsGlobal == rhsIsGlobal, lhsParticipantCount == rhsParticipantCount {
                return true
            } else { return false }
        case let .deviceContact(id, contact):
            if case .deviceContact(id, contact) = rhs { return true } else { return false }
        }
    }
}
```

The custom `==` is retained (rather than relying on synthesis) because `DeviceContactStableId` / `DeviceContactBasicData` conformance to Equatable is not verified here; minimising unrelated change. Only the `lhsPeer.isEqual(rhsPeer)` clause is rewritten.

## In-scope files

Scope based on the pre-flight Explore inventory plus a manual deep-scan pass that caught additional inflow wraps and Postbox-concrete casts the Explore agent missed. One definition file plus nine consumer files; seven of the consumer files need edits. Two (ComposeController, ChatSendAudioMessageContextPreview) have only `.id`-level accesses and should need no body change — plan verifies each during implementation.

### Category α — Definition (`AccountContext`)

**`submodules/AccountContext/Sources/ContactSelectionController.swift`**
- Line 62: enum case signature change `peer: Peer` → `peer: EnginePeer`.
- Line 74: computed property return type change `PeerIndexNameRepresentation` → `EnginePeer.IndexName`. Rationale: after the payload migration, `peer.indexName` at line 77 returns `EnginePeer.IndexName` (from `EnginePeer.indexName`), not `PeerIndexNameRepresentation`. Changing the return type up rather than re-bridging via `peer._asPeer().indexName` eliminates a Postbox-typed API from AccountContext and incidentally lets two `EnginePeer.IndexName(...)` wraps at ContactListNode:517 drop. The two enum case shapes match exactly — `EnginePeer.IndexName.title(title:addressNames:)` and `EnginePeer.IndexName.personName(first:last:addressNames:phoneNumber:)` are defined at `submodules/TelegramCore/Sources/TelegramEngine/Peers/Peer.swift:145-147` with the same parameter labels and types as `PeerIndexNameRepresentation`'s cases.
- Line 77: `return peer.indexName` — body unchanged; type now flows `EnginePeer → EnginePeer.IndexName`.
- Line 79: `return .personName(first: contact.firstName, last: contact.lastName, addressNames: [], phoneNumber: "")` — body unchanged; case resolution retargets to `EnginePeer.IndexName.personName`.
- Line 86: `==` operator — rewrite `lhsPeer.isEqual(rhsPeer)` to `lhsPeer == rhsPeer`.
- Line 67: `peer.id` same-type access (EnginePeer.id returns EnginePeer.Id ≡ PeerId) — unchanged.

### Category β — Outflow-bridge drops (the dominant pattern)

Every site below is `.peer(peer: <expr>._asPeer(), isGlobal: …, participantCount: …)` → `.peer(peer: <expr>, …)`, because `<expr>` is already `EnginePeer` at the call site.

**`submodules/ContactListUI/Sources/ContactListNode.swift`** — 12 sites: 632, 690, 701, 747, 765, 1365, 1647, 1656, 1693, 1731, 1942, 1944.

**`submodules/ContactListUI/Sources/ContactsSearchContainerNode.swift`** — 3 sites: 494, 535, 569.

**`submodules/TelegramUI/Sources/ContactMultiselectionController.swift`** — 2 bridged sites: 451, 459.

**`submodules/TelegramUI/Sources/ContactMultiselectionControllerNode.swift`** — 1 site: 317.

**`submodules/TelegramUI/Sources/ContactSelectionControllerNode.swift`** — 2 sites: 160, 230.

Total: 20 outflow-bridge drops.

### Category γ — Removed

Earlier draft flagged `TelegramUI/ContactMultiselectionController.swift:379` as a raw-`Peer` construction needing `EnginePeer(peer)` promotion. Rechecked: line 379 is inside a destructure at line 347 (`case let .peer(peer, _, _) = peer`), so post-migration the inner `peer` is already `EnginePeer` and the existing `.peer(peer: peer, ...)` continues to compile without wrapping. No edit needed.

### Category δ — Inflow-wrapping drops at destructure sites

Every site is `EnginePeer(peer)` applied to a destructured peer that becomes `EnginePeer` directly post-migration → drop each wrap.

- **ContactListNode.swift**: 4 wraps total.
    - Line 204 wraps `peer` twice inside `.peer(peer: EnginePeer(peer), chatPeer: EnginePeer(peer))` (inside destructure at line 177).
    - Line 252 wraps once inside `interaction.openDisabledPeer(EnginePeer(peer), …)` (inside destructure at line 251).
    - Line 844 wraps once inside `isPeerEnabled(EnginePeer(peer))` (inside destructure at line 833).
- **ContactsController.swift**: 1 wrap — line 294 `chatLocation: .peer(EnginePeer(peer))` where `peer` is destructured at line 287.
- **ContactsSearchContainerNode.swift**: 4 wraps total.
    - Line 164 `peerItem = .peer(peer: EnginePeer(peer), chatPeer: EnginePeer(peer))` (2 wraps, inside destructure at line 163).
    - Line 165 `nativePeer = EnginePeer(peer)` (1 wrap, same destructure).
    - Line 181 `openDisabledPeer(EnginePeer(peer), …)` (1 wrap, inside destructure at line 180).
- **TelegramUI/Sources/ContactMultiselectionController.swift**: 4 wraps total.
    - Line 386 `subject: .peer(EnginePeer(peer))` (inside destructure at line 347).
    - Line 403 `subject: .peer(EnginePeer(peer))` (same destructure).
    - Line 481 `self.params.sendMessage?(EnginePeer(peer))` (inside destructure at line 468).
    - Line 491 `self.params.openProfile?(EnginePeer(peer))` (same destructure).
- **TelegramUI/Sources/ContactMultiselectionControllerNode.swift**: 1 wrap — line 492 `EnginePeer(peer).compactDisplayTitle` (inside destructure at line 491).
- **TelegramUI/Sources/ContactSelectionController.swift**: 2 wraps total.
    - Line 517 `self.sendMessage?(EnginePeer(peer))` (inside destructure at line 504).
    - Line 527 `self.openProfile?(EnginePeer(peer))` (same destructure).

Total: 16 inflow-wrap drops.

### Category φ — Postbox-concrete cast rewrites

Destructured `peer` post-migration is `EnginePeer`. Existing `peer as? TelegramUser`/`TelegramGroup`/`TelegramChannel` casts no longer compile; rewrite to `EnginePeer` case-pattern matches. Both sites are in `ContactListNode.swift`.

- **ContactListNode.swift:182-186** — inside destructure at line 177. Rewrite the `if let _ = peer as? TelegramUser { … } else if let group = peer as? TelegramGroup { … } else if let channel = peer as? TelegramChannel { … }` chain to `switch peer { case .user: … case let .legacyGroup(group): … case let .channel(channel): … default: break }`, or equivalently to the `if case .user = peer / if case let .legacyGroup(group) = peer / if case let .channel(channel) = peer` chain. Inner `group.participantCount`, `channel.info`, `case .group = channel.info` continue to compile unchanged because `EnginePeer.channel` / `.legacyGroup` wrap the exact same concrete types (`TelegramChannel`, `TelegramGroup`) and `.user` wraps `TelegramUser`. Note: the original `if let _ = peer as? TelegramUser` branch doesn't bind the user — rewrite keeps that (either `case .user = peer` or `if case .user = peer`).
- **ContactListNode.swift:1968** — inside destructure at line 1966. Rewrite `let user = peer as? TelegramUser` to `case let .user(user) = peer`. Inner `user.phone` continues to compile (`EnginePeer.user` wraps `TelegramUser`).

EnginePeer enum case mapping (reference):

| Postbox concrete | EnginePeer case |
|---|---|
| `TelegramUser` | `.user(TelegramUser)` |
| `TelegramGroup` | `.legacyGroup(TelegramGroup)` |
| `TelegramChannel` | `.channel(TelegramChannel)` |

Lines 1802, 1818, 1820 in ContactListNode.swift also contain `peer as? TelegramChannel`/`peer is TelegramGroup` casts but these are on `peer` values sourced from `entryData.renderedPeer.peer` (raw Postbox `Peer`), not from a ContactListPeer destructure. They stay unchanged — out of wave scope.

### Category ε′ — `ContactListPeer.indexName` return-type cascade

Because category α changes the return type of `ContactListPeer.indexName` to `EnginePeer.IndexName`, call sites that currently wrap that return in `EnginePeer.IndexName(...)` can drop the wrap:

- **ContactListNode.swift:517** — `let result = EnginePeer.IndexName(lhs.indexName).isLessThan(other: EnginePeer.IndexName(rhs.indexName), ordering: sortOrder)` → `let result = lhs.indexName.isLessThan(other: rhs.indexName, ordering: sortOrder)`. Two wraps drop. The `isLessThan(other:ordering:)` extension is defined on `EnginePeer.IndexName` only (see `submodules/LocalizedPeerData/Sources/PeerTitle.swift:64`), so the existing wrap idiom was required pre-migration.

- **ContactListNode.swift:539, 590** — `switch peer.indexName` / `switch orderedPeers[i].indexName` with `case let .title(…)` and `case let .personName(…)` — continues to compile unchanged. Same case names and shapes.

### Category ε — Same-type field access (no edit)

Destructured peer bindings whose only uses are `.id`, `.addressName`, value equality via `.id`, etc. All of these exist on `EnginePeer` with identical semantics.

Known sites from inventory (accept as same-type):
- **ContactSelectionController.swift**: 67, 76 — `.id`, `.indexName`.
- **ContactListNode.swift**: 121, 177, 209, 216, 251, 255, 491, 505, 519, 520, 782, 787, 827, 833, 1636, 1966 — `.id`/`.addressName`/value comparisons on `.id`. Sites 204 and 251 also appear in category δ because the same binding is used both ways in the same block.
- **ContactsSearchContainerNode.swift**: 151 — `.addressName`.
- **ContactMultiselectionController.swift**: 347, 468 — `.id`.
- **ContactMultiselectionControllerNode.swift**: 491 — `selectedPeers.first` destructure to access `.id`.
- **ContactSelectionController.swift (TelegramUI)**: 504 — context-action passthrough.
- **ComposeController.swift**: 120, 160 — `.id` for chat creation.
- **ChatSendAudioMessageContextPreview.swift**: 88 — `.contact`/name accessors.

These need no code edits; they are listed only to record coverage.

### Category ζ — Outflow-to-`Peer`-typed-API (bridge required)

Any destructured `peer` (now `EnginePeer`) passed to a function that takes raw `Peer` needs `._asPeer()` appended at the call site.

Known candidate from inventory:
- **ContactsSearchContainerNode.swift:180** — `isPeerEnabled(peer)`. Verify the parameter type at edit time. If it is `(EnginePeer) -> Bool`, no bridge needed; if `(ContactListPeer) -> Bool`, also no bridge (the destructured value is discarded for the overall `peer` value anyway). If `(Peer) -> Bool`, add `._asPeer()`.

Plan-time step 7 verifies each category-ε site against the API it feeds into; any surprise is resolved by adding `._asPeer()` inline.

## Out-of-scope — name collisions

Files listed in the 20-file grep but not touched in this wave:
- **PeerInfoUI/ChannelMembersController.swift**, **PeerInfoUI/ChannelVisibilityController.swift**, **SettingsUI/…/GlobalAutoremoveScreen.swift**, **IncomingMessagePrivacyScreen.swift**, **SelectivePrivacySettingsController.swift**, **SelectivePrivacySettingsPeersController.swift**, **PresentAddMembers.swift**, **ComposeController.swift (TelegramUI)**, **OpenResolvedUrl.swift**, **ChatSendAudioMessageContextPreview.swift** — the inventory found only `ContactListPeerId.peer(…)` destructures or pass-throughs of the entire `ContactListPeer` enum value, not `ContactListPeer.peer` payload access. The payload-type migration does not affect these.

Plan-time verification: re-grep these files for `case .peer(let peer`, `case let .peer(peer,`, and `.peer(peer:` before declaring "no edits needed". If a missed payload destructure surfaces, promote the file into scope.

## Execution plan outline (for writing-plans)

Single atomic commit ordering:

1. Edit `AccountContext/ContactSelectionController.swift` — change case payload type (L62); change `indexName` property return type to `EnginePeer.IndexName` (L74); rewrite `lhsPeer.isEqual(rhsPeer)` to `lhsPeer == rhsPeer` (L86).
2. Edit `ContactListNode.swift` — drop 12 `._asPeer()` bridges (outflow); drop 4 inflow `EnginePeer(peer)` wraps (2 on L204, 1 on L252, 1 on L844); rewrite cast chain at L182-186 to EnginePeer case patterns; rewrite cast at L1968; drop 2 `EnginePeer.IndexName(...)` wraps on L517.
3. Edit `ContactsController.swift` — drop 1 inflow `EnginePeer(peer)` wrap at L294.
4. Edit `ContactsSearchContainerNode.swift` — drop 3 `._asPeer()` bridges at L494/535/569; drop 4 inflow `EnginePeer(peer)` wraps (2 on L164, 1 on L165, 1 on L181). Do NOT drop `._asPeer()` at L488/528/562 (these feed `canSendMessagesToPeer(_: Peer)` — deferred wave).
5. Edit `TelegramUI/ContactMultiselectionController.swift` — drop 2 outflow bridges at L451/459; drop 4 inflow wraps at L386/403/481/491. Do NOT edit L171/201/748 (these feed `peerTokenTitle(peer: Peer)` — deferred).
6. Edit `TelegramUI/ContactMultiselectionControllerNode.swift` — drop 1 outflow bridge at L317; drop 1 inflow wrap at L492.
7. Edit `TelegramUI/ContactSelectionController.swift` — drop 2 inflow wraps at L517/527.
8. Edit `TelegramUI/ContactSelectionControllerNode.swift` — drop 2 outflow bridges at L160/230.
9. Verify `ComposeController.swift` and `ChatSendAudioMessageContextPreview.swift` need no body edits. If build surfaces a leak, fold the fix into an additional task step.
10. Build: `source ~/.zshrc 2>/dev/null; python3 build-system/Make/Make.py --overrideXcodeVersion --cacheDir ~/telegram-bazel-cache build --configurationPath build-system/appstore-configuration.json --gitCodesigningRepository git@gitlab.com:peter-iakovlev/fastlanematch.git --gitCodesigningType development --gitCodesigningUseCurrent --buildNumber=1 --configuration=debug_sim_arm64 --continueOnError`.
11. Address undercount misses (expected ≤3 — pre-flight was thorough but file count is large) and commit once build is green.

## Risk register

| Risk | Mitigation |
|------|------------|
| Inventory undercount (wave 35 had 14%; trend decreasing) | Pre-flight already uses validated pattern set. `--continueOnError` on the build surfaces all misses in one pass. Expected ≤2 missed sites. |
| Destructure sites that flow a peer into a raw-`Peer`-typed API (category ζ) not caught by inventory | Build will flag the type mismatch; fix inline with `._asPeer()` at the flagged call site. Plan step 8 is the explicit verification gate. |
| `ContactListPeer` Equatable semantic regression | Replacing `lhsPeer.isEqual(rhsPeer)` (Postbox dynamic dispatch) with `lhsPeer == rhsPeer` (EnginePeer synthesized `==`) compares the same underlying concrete types (`.user(TelegramUser)`, `.channel(TelegramChannel)`, etc.) via their own Equatable conformances. Truth table preserved. |
| `ContactListPeer.indexName` return-type change cascades beyond ContactListNode:517/539/590 | Consumers of `ContactListPeer.indexName` enumerated via `grep -rn "\.indexName" submodules/ --include="*.swift"` filtered for ContactListPeer-typed receivers: only ContactListNode has such uses. No other submodule destructures or pattern-matches on this property. Build will flag any miss immediately. |
| `peer.isEqual` used elsewhere in scope files but on non-ContactListPeer bindings | Inventory confirmed ContactListNode:306 uses `!=` on a `ContactListNodeEntry.peer` binding, not `ContactListPeer.peer`. Scope boundary respected. No other `isEqual` call on a ContactListPeer-destructured binding was found. |
| Files flagged "no ContactListPeer.peer payload access" turn out to have one | Plan step 8 re-greps these files; any hit gets promoted into scope without rerunning the wave. |
| Pre-existing WIP on `ChatListFilterPresetController.swift` / `ChatListFilterPresetListController.swift` | Out of wave scope — untouched. No ContactListPeer reference expected in those files. |

## Validation

- Full Bazel build (`--configuration=debug_sim_arm64 --continueOnError`).
- No TelegramCore/Postbox/TelegramApi errors (scope boundary check — halt if they surface).
- Grep post-commit: `rg "ContactListPeer\.peer\(peer: .*\._asPeer" submodules/` returns empty.
- Grep post-commit: `rg "case \.peer\(peer: .*\._asPeer" submodules/` returns empty (catch shortcut constructions).
- Grep post-commit: no surviving `EnginePeer\(peer\)` in the 10 touched files where `peer` was destructured from a `ContactListPeer.peer` case (manual spot-check — automated grep too noisy).

## Lessons to carry forward

- Wave 35's pre-flight pattern set (literal token + `.peer as?`/`is` + outflow-args + `EnginePeer(.peer)` + `._asPeer()`) applied to this wave; record the post-commit undercount percentage to continue the calibration trend (wave 34: ~33%, wave 35: ~14%).
- This wave is dominated by **bridge removal** — 20 outflow `._asPeer()` drops + 16 inflow `EnginePeer(peer)` drops + 2 `EnginePeer.IndexName(...)` drops + 1 `.isEqual` → `==` fix + 2 Postbox-cast chain rewrites. Zero bridge additions. Updated tallies supersede earlier draft counts in this spec. Confirms the ratchet effect: earlier waves added bridges at Peer/EnginePeer boundaries precisely so future waves like this one can drop them atomically. Record the ratio (bridge drops : bridge additions) as a health metric across Peer-typed-API waves.
- Custom enum `==` operators using `Peer.isEqual(_:)` are a predictable Category-F leak in every Peer-payload migration. Future Peer-typed-API waves should grep the enum's defining module for `\.isEqual\(` specifically.
- **Computed properties on the enum that return Postbox types (e.g., `PeerIndexNameRepresentation`) are a second predictable leak** — discovered mid-spec for `ContactListPeer.indexName`. Future Peer-typed-enum waves should grep the enum's definition file for `public var` / `public func` returning any Postbox-defined type (`PeerIndexNameRepresentation`, `PeerNameIndex`, `MessageId`, etc.) before committing to the inventory — changing the return type to the Engine equivalent frequently cascades into consumer-side wrap drops (here, 2 wraps at ContactListNode:517).
