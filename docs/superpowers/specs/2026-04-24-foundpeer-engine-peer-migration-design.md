# Wave 34 Design: `FoundPeer.peer: Peer → EnginePeer`

**Date:** 2026-04-24
**Wave:** 34 (Postbox → TelegramEngine refactor)
**Predecessor:** Wave 33 (loadedPeerWithId consumer sweep, commit `16d017853a`)

## Goal

Migrate the public field `FoundPeer.peer` from the Postbox `Peer` protocol to the TelegramCore `EnginePeer` enum. Drops 4 of the 5 `._asPeer()` bridges introduced by wave 33 and eliminates one Postbox-protocol leak from a `TelegramEngine.Contacts` / `TelegramEngine.Calls` return type.

## Non-Goals

- Migrating other Peer-typed-API surfaces (`SendAsPeer`, `makePeerInfoController`, `makeChatRecentActionsController`, `makeChatQrCodeScreen`, `FoundPeer` is the smallest probe in this class — those are separate future waves).
- Dropping `import Postbox` from `SearchPeers.swift`. The `_internal_*` functions in that file still call `postbox.transaction`, `parseTelegramGroupOrChannel`, `AccumulatedPeers`, `updatePeers`. They remain the Postbox-facing layer per project rule.
- Dropping `import Postbox` from any consumer module. None of the touched files reach zero Postbox use through this change alone.
- Auto-synthesizing `Equatable` for `FoundPeer`. Manual `==` is preserved per user decision.

## Scope

One atomic commit. Approximately 46 semantic edits plus type-name continuations across:

- `submodules/TelegramCore/Sources/TelegramEngine/Peers/SearchPeers.swift` (definition + `_internal_searchPeers` body)
- 7 consumer files in `submodules/`:
  - `submodules/TelegramCallsUI/Sources/VideoChatScreen.swift`
  - `submodules/TelegramCallsUI/Sources/VideoChatScreenMoreMenu.swift`
  - `submodules/ContactListUI/Sources/ContactListNode.swift`
  - `submodules/ChatListUI/Sources/ChatListSearchListPaneNode.swift`
  - `submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreenCallActions.swift`
  - `submodules/TelegramBaseController/Sources/TelegramBaseController.swift`
  - `submodules/SettingsUI/Sources/Data and Storage/StorageUsageExceptionsScreen.swift`

The remaining ~10 files identified by `grep -rln "FoundPeer\b"` (StorageUsageExceptionsScreen field-only refs aside, the file IS in the touched list above) contain only C5 type-name mentions or unrelated `.peer.peer` accesses on other types and require no edit.

**Verification (performed 2026-04-24)** that nearby `EnginePeer(peer.peer)` patterns in other files are NOT FoundPeer access: those sites bind `peer` to `SelectivePrivacyPeer`, `SendAsPeer`, `InactiveChannel`, `RenderedChannelParticipant`, or `RenderedPeer` — all of which still expose `.peer: Peer`. They remain unchanged by this wave.

## Changes

### 1. `submodules/TelegramCore/Sources/TelegramEngine/Peers/SearchPeers.swift`

**Struct:**

```swift
public struct FoundPeer: Equatable {
    public let peer: EnginePeer            // was: Peer
    public let subscribers: Int32?

    public init(peer: EnginePeer, subscribers: Int32?) {   // was: peer: Peer
        self.peer = peer
        self.subscribers = subscribers
    }

    public static func ==(lhs: FoundPeer, rhs: FoundPeer) -> Bool {
        return lhs.peer == rhs.peer && lhs.subscribers == rhs.subscribers
        // was: lhs.peer.isEqual(rhs.peer) && lhs.subscribers == rhs.subscribers
    }
}
```

**`_internal_searchPeers` body changes:**

- All four `FoundPeer(peer: peer, subscribers: …)` constructions (lines 70, 72, 85, 87) wrap the raw `peer` value with `EnginePeer(peer)`.
- Six scope-filter expressions (2 per non-trivial scope × 3 scopes — `.channels` lines 96–109, `.groups` lines 110–128, `.privateChats` lines 129–143) rewrite to enum pattern matching:
  - `as? TelegramChannel, case .broadcast = channel.info` → `if case let .channel(channel) = item.peer, case .broadcast = channel.info`
  - `as? TelegramChannel, case .group = channel.info` plus `else if item.peer is TelegramGroup` → `if case let .channel(channel) = item.peer, case .group = channel.info` plus `else if case .legacyGroup = item.peer`
  - `if item.peer is TelegramUser` → `if case .user = item.peer`

Filter behavior is preserved exactly; only the destructuring form changes.

### 2. Consumer-side edits (by category)

Inventory was performed on 2026-04-24 via Explore agent against the 10 files identified by `grep -rln "FoundPeer\b" submodules/ Telegram/`. An additional 3 files surfaced (`ShareControllerNode.swift`, `SharePeersContainerNode.swift`, `PeerSelectionControllerNode.swift`, `ContactSelectionControllerNode.swift`, `ChatListNode.swift`) — most are C5 type-name mentions or false positives in field names that don't reference the type.

**C1 — peer-protocol method reads (~28 sites): no edit required.**
`peer.peer.id`, `peer.peer.displayTitle`, `peer.peer.namespace`, `peer.peer.debugDisplayTitle`, `peer.peer.smallProfileImage` — all available on `EnginePeer` with the same signatures.

**C5 — type-signature mentions (~60 sites): no edit required.**
`[FoundPeer]`, `Signal<([FoundPeer], [FoundPeer]), NoError>`, `Atomic<([FoundPeer], [FoundPeer])?>`, `case globalPeer(FoundPeer, …)`, etc. The type continues to compile under the new field.

**C2 — downcast rewrites (30 sites).**

EnginePeer is an enum, so `peer.peer as? TelegramX` / `peer.peer is TelegramX` patterns must rewrite to `if case .X = peer.peer` (or `if case let .X(x) = peer.peer` when the bound value is reused). Case mapping:

- `TelegramUser` → `.user`
- `TelegramSecretChat` → `.secretChat`
- `TelegramGroup` → `.legacyGroup`
- `TelegramChannel` → `.channel`

| File | Line | Current pattern | After (representative) |
|---|---|---|---|
| `TelegramCallsUI/VideoChatScreenMoreMenu.swift` | 628 | `peer.peer is TelegramGroup` | `if case .legacyGroup = peer.peer` |
| `TelegramCallsUI/VideoChatScreenMoreMenu.swift` | 631 | `as? TelegramChannel, case .group = peer.info` | `if case let .channel(channel) = peer.peer, case .group = channel.info` |
| `TelegramCallsUI/VideoChatScreenMoreMenu.swift` | 648 | `as? TelegramChannel, case .broadcast = peer.info` | `if case let .channel(channel) = peer.peer, case .broadcast = channel.info` |
| `ContactListUI/ContactListNode.swift` | 1501 | `if let _ = peer.peer as? TelegramChannel` | `if case .channel = peer.peer` |
| `ContactListUI/ContactListNode.swift` | 1563, 1569, 1574 | `if let user = peer.peer as? TelegramUser, user.flags.contains(.requirePremium)` | `if case let .user(user) = peer.peer, user.flags.contains(.requirePremium)` |
| `ContactListUI/ContactListNode.swift` | 1658, 1665, 1695, 1703, 1733 | `let user = peer.peer as? TelegramUser` (in if-let chains) | `if case let .user(user) = peer.peer, …` |
| `ContactListUI/ContactListNode.swift` | 1673, 1711 | `if peer.peer is TelegramGroup` (with possible `&& <bool>`) | `if case .legacyGroup = peer.peer` (with `, <bool>`) |
| `ContactListUI/ContactListNode.swift` | 1675, 1713 | `else if let channel = peer.peer as? TelegramChannel` | `else if case let .channel(channel) = peer.peer` |
| `ChatListUI/ChatListSearchListPaneNode.swift` | 1024 | `!(peer.peer is TelegramUser \|\| peer.peer is TelegramSecretChat)` | rewrite to combined enum-pattern (×2 within the line) |
| `ChatListUI/ChatListSearchListPaneNode.swift` | 1029, 1030 | `if let _ = peer.peer as? TelegramGroup` / `else if let peer = peer.peer as? TelegramChannel, case .group = peer.info` | `if case .legacyGroup = peer.peer` / `else if case let .channel(channel) = peer.peer, case .group = channel.info` |
| `ChatListUI/ChatListSearchListPaneNode.swift` | 1038, 1040 | `if peer.peer is TelegramUser` / `else if let channel = peer.peer as? TelegramChannel, case .broadcast = channel.info` | `if case .user = peer.peer` / `else if case let .channel(channel) = peer.peer, case .broadcast = channel.info` |
| `ChatListUI/ChatListSearchListPaneNode.swift` | 1500, 1507 | `if let channel = peer.peer as? TelegramChannel, case .broadcast = channel.info` | `if case let .channel(channel) = peer.peer, case .broadcast = channel.info` |
| `PeerInfoScreen/PeerInfoScreenCallActions.swift` | 175, 178, 193 | (see prior lines, same pattern set) | (same) |
| `TelegramBaseController/TelegramBaseController.swift` | 243, 246, 258 | `peer.peer is TelegramGroup` / `as? TelegramChannel, case .group = peer.info` / `as? TelegramChannel, case .broadcast = peer.info` | (same enum-pattern rewrites as above) |

Two name-shadowing notes:

- **Inner `peer` shadowing.** Several rewrites (e.g., `else if let peer = peer.peer as? TelegramChannel`) currently shadow the loop variable with a new `peer` of type `TelegramChannel`. After rewrite these become `else if case let .channel(channel) = peer.peer` — the binding name moves from `peer` to `channel` to avoid further shadowing of the EnginePeer loop variable. Adjust subsequent body references inside the if-let scope (they currently say `peer.info` referring to `TelegramChannel.info`; they become `channel.info`). Spot-check each rewrite within its block.
- **`channel.info` references.** When a downcast block uses the bound `peer` for `.info` access (e.g., line 178: `peer.info`), update those references to use the new binding name (`channel.info`). Block-internal-only — no cascade.

Plus 6 filter sites inside `SearchPeers.swift` `_internal_searchPeers` body (already counted under §1).

**C4 — constructor edits (6 sites):**

Bridge-drop sites — wave-33 added `._asPeer()` because the value was already `EnginePeer`; with this wave the field accepts EnginePeer directly:

| File | Line | Current | After |
|---|---|---|---|
| `TelegramCallsUI/VideoChatScreen.swift` | 1833 | `FoundPeer(peer: peer._asPeer(), subscribers: nil)` | `FoundPeer(peer: peer, subscribers: nil)` |
| `ContactListUI/ContactListNode.swift` | 1485 | `FoundPeer(peer: mainPeer._asPeer(), subscribers: nil)` | `FoundPeer(peer: mainPeer, subscribers: nil)` |
| `ContactListUI/ContactListNode.swift` | 1517 | `FoundPeer(peer: $0._asPeer(), subscribers: nil)` (inside `peers.map { … }`) | `FoundPeer(peer: $0, subscribers: nil)` |
| `TelegramBaseController/TelegramBaseController.swift` | 208 | `FoundPeer(peer: peer._asPeer(), subscribers: nil)` | `FoundPeer(peer: peer, subscribers: nil)` |
| `PeerInfoScreen/PeerInfoScreenCallActions.swift` | 156 | `FoundPeer(peer: peer._asPeer(), subscribers: nil)` | `FoundPeer(peer: peer, subscribers: nil)` |
| `PeerInfoScreen/PeerInfoScreenCallActions.swift` | 265 | `FoundPeer(peer: peer._asPeer(), subscribers: nil)` | `FoundPeer(peer: peer, subscribers: nil)` |

Wrap-needed sites — value at the call site is raw `Peer`, must be wrapped:

| File | Line | Current | After |
|---|---|---|---|
| `ContactListUI/ContactListNode.swift` | 1506 | `mappedPeers.append(FoundPeer(peer: peer.peer, subscribers: subscribers))` | already-EnginePeer (since `peer: FoundPeer` after migration) → `mappedPeers.append(FoundPeer(peer: peer.peer, subscribers: subscribers))` — **no edit** |
| `SettingsUI/StorageUsageExceptionsScreen.swift` | 288 | `FoundPeer(peer: peer, subscribers: subscriberCount)` | `FoundPeer(peer: EnginePeer(peer), subscribers: subscriberCount)` |

Note: ContactListNode:1506 is inside a `for peer in mappedPeers` over `[FoundPeer]`, so `peer.peer` is already `EnginePeer` after migration. No edit. Re-classified from C4-wrap-needed to no-op.

So: 4 bridge-drop edits + 1 actual wrap (StorageUsageExceptionsScreen:288) = 5 C4 edits, not 6.

**C3 — drop redundant `EnginePeer(peer.peer)` wrap (22 sites).**

After migration `peer.peer` is already `EnginePeer`, and `EnginePeer.init(_ peer: Peer)` does not accept an EnginePeer argument — so each `EnginePeer(peer.peer)` wrap MUST be dropped to just `peer.peer` or the build fails.

| File | Line | Wraps | Pattern (representative) |
|---|---|---|---|
| `SettingsUI/StorageUsageExceptionsScreen.swift` | 173 | 1 | `EnginePeer(peer.peer).displayTitle(…)` → `peer.peer.displayTitle(…)` |
| `SettingsUI/StorageUsageExceptionsScreen.swift` | 176 | 1 | `iconPeer: EnginePeer(peer.peer)` → `iconPeer: peer.peer` |
| `TelegramBaseController/TelegramBaseController.swift` | 265 | 2 | `peer: EnginePeer(peer.peer), title: EnginePeer(peer.peer).displayTitle(…)` → `peer: peer.peer, title: peer.peer.displayTitle(…)` |
| `PeerInfoScreen/PeerInfoScreenCallActions.swift` | 201 | 1 | `peerAvatarCompleteImage(… peer: EnginePeer(peer.peer), …)` → `peerAvatarCompleteImage(… peer: peer.peer, …)` |
| `PeerInfoScreen/PeerInfoScreenCallActions.swift` | 202 | 1 | `text: EnginePeer(peer.peer).displayTitle(…)` → `text: peer.peer.displayTitle(…)` |
| `PeerInfoScreen/PeerInfoScreenCallActions.swift` | 288 | 2 | `.secondLineWithValue(EnginePeer(peer.peer).displayTitle(…))` and `peerAvatarCompleteImage(… peer: EnginePeer(peer.peer), …)` |
| `ChatListUI/ChatListSearchListPaneNode.swift` | 1075 | 2 | `peer: .peer(peer: EnginePeer(peer.peer), chatPeer: EnginePeer(peer.peer))` |
| `ChatListUI/ChatListSearchListPaneNode.swift` | 1076 | 1 | `interaction.peerSelected(EnginePeer(peer.peer), nil, nil, nil, false)` |
| `ChatListUI/ChatListSearchListPaneNode.swift` | 1078 | 1 | `interaction.disabledPeerSelected(EnginePeer(peer.peer), nil, …)` |
| `ChatListUI/ChatListSearchListPaneNode.swift` | 1081 | 1 | `peerContextAction(EnginePeer(peer.peer), .search(nil), node, gesture, location)` |
| `ChatListUI/ChatListSearchListPaneNode.swift` | 3088 | 1 | `filteredPeer(EnginePeer(peer.peer), EnginePeer(accountPeer))` (only the FoundPeer wrap drops; the `EnginePeer(accountPeer)` wrap stays — `accountPeer` is a raw Peer) |
| `ChatListUI/ChatListSearchListPaneNode.swift` | 3096 | 1 | same pattern as 3088 |
| `ChatListUI/ChatListSearchListPaneNode.swift` | 3214 | 1 | same pattern as 3088 |
| `ChatListUI/ChatListSearchListPaneNode.swift` | 3216 | 1 | `entries.append(.localPeer(EnginePeer(peer.peer), …))` |
| `ChatListUI/ChatListSearchListPaneNode.swift` | 3241 | 1 | same pattern as 3088 |
| `TelegramCallsUI/VideoChatScreenMoreMenu.swift` | 171 | 2 | `.secondLineWithValue(EnginePeer(peer.peer).displayTitle(…))` and `peerAvatarCompleteImage(… peer: EnginePeer(peer.peer), …)` |
| `TelegramCallsUI/VideoChatScreenMoreMenu.swift` | 658 | 1 | `peerAvatarCompleteImage(… peer: EnginePeer(peer.peer), …)` |
| `TelegramCallsUI/VideoChatScreenMoreMenu.swift` | 679 | 1 | `text: EnginePeer(peer.peer).displayTitle(…)` |
| **Total** | | **22** | |

Note: only the inner `EnginePeer(peer.peer)` is dropped. Adjacent `EnginePeer(<other>)` wraps (e.g., `EnginePeer(accountPeer)` at lines 3088/3096/3214/3241) are unrelated to this wave and remain.

### Total semantic-edit count

- §1 (TelegramCore): struct (3 lines) + 6 filter rewrites + 4 constructor wraps = ~13 spot edits in one file
- §2 C2: 30 consumer-site downcast rewrites
- §2 C4: 5 consumer-site constructor edits (4 bridge-drops + 1 wrap)
- §2 C3: 22 consumer-site `EnginePeer(peer.peer)` wrap drops

**Total: ~70 semantic edits** across 1 TelegramCore file + 7 consumer files. Type-name mentions in signal/collection signatures need no edit; the type continues to compile.

## Verification

- **Build:** `source ~/.zshrc 2>/dev/null; python3 build-system/Make/Make.py --overrideXcodeVersion --cacheDir ~/telegram-bazel-cache build --configurationPath build-system/appstore-configuration.json --gitCodesigningRepository git@gitlab.com:peter-iakovlev/fastlanematch.git --gitCodesigningType development --gitCodesigningUseCurrent --buildNumber=1 --configuration=debug_sim_arm64 --continueOnError`
- **Expected outcome:** first-pass-clean build. Errors that surface most likely indicate (a) a missed C2 site, (b) a FoundPeer field-access I missed in the inventory, or (c) a downstream API receiving `peer.peer` that requires raw `Peer` (would need a `._asPeer()` bridge added).
- **Post-build grep validations:**
  - `grep -rn "FoundPeer(peer:.*\._asPeer()" submodules/` → expect zero hits in production code (the 4 bridge-drops succeeded).
  - `grep -nE "peer\.peer\s+(as\?|is)\s+Telegram" <touched-files>` → expect zero hits in the 7 touched consumer files (FoundPeer-relevant downcasts all rewritten). Other unrelated `something_else.peer.peer as?` patterns may remain on `RenderedPeer` etc.
  - `grep -rn "EnginePeer(peer\.peer)" submodules/ --include="*.swift" | grep -v "^submodules/TelegramCore/"` → expect zero hits in the 7 touched consumer files (other files keep their wraps because their `peer` is non-FoundPeer).

## Risks and mitigations

- **Misnamed enum case bindings (C2).** A wrong binding name (e.g. `if case let .channel(c) = peer.peer` then accessing `channel.info`) compiles but is a typo. *Mitigation:* the rewrites are mechanical and each table-row in §2 above shows the exact target form. Each binding is reused inside the same `if case let` clause.
- **Hidden field accesses missed by the inventory.** *Mitigation:* `--continueOnError` build catches everything in one pass. If 5+ unexpected error sites surface, abandon and re-inventory. If only 1–2 surface, fix in place.
- **Downstream APIs requiring raw `Peer`.** Some consumer code may pass `foundPeer.peer` to a function taking the `Peer` protocol. Inventory found 2 such sites already simplified (C3), but unknown sites may exist. *Mitigation:* if surfaced by build errors, bridge with `._asPeer()` at the call site (acceptable transitional pattern — these become next-wave candidates for downstream migration).
- **Equatable behavior change.** `Peer.isEqual(_:)` is the protocol's polymorphic identity test; `EnginePeer.==` is the synthesized-or-manual enum equality. *Mitigation:* `EnginePeer.==` is the canonical equality on the enum and is used throughout the engine codebase. The two should agree on identity-relevant fields (peer id, namespace), and FoundPeer equality is used in `Equatable` set/array dedup contexts where both forms produce the same answer for distinct peers. If tests existed, this would be the place to add one — they don't, so we accept the substitution.

## Out-of-scope cleanups (for future waves)

- The downstream `peerAvatarCompleteImage(account:peer:size:)` in `PeerInfoScreenCallActions.swift:202` accepts `EnginePeer` — no change needed there.
- Wave 33's 5th `._asPeer()` bridge (the one not at a `FoundPeer` constructor) remains. It is at a different downstream API — separate wave.
- `SendAsPeer`, `makePeerInfoController`, `makeChatRecentActionsController`, `makeChatQrCodeScreen` migrations — each is its own wave, larger blast radius.
