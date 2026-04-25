# Wave 41 — `RenderedChannelParticipant.peer: Peer → EnginePeer` migration — Design

**Date:** 2026-04-24
**Wave:** 41
**Status:** spec

## Goal

Migrate the `peer` field of `TelegramCore.RenderedChannelParticipant` from the Postbox protocol `Peer` to the TelegramCore enum `EnginePeer`. All construction sites and consumer accesses are updated in one atomic commit.

## Motivation

- Drops 2 Shape-C `EnginePeer(participant.peer)` wraps installed by wave 39 (`ChannelMembersController.swift:707`, `ChannelBlacklistController.swift:381`).
- Drops ~37 additional `EnginePeer(...)` / `._asPeer()` bridges across the consumer surface (total ~39 bridge drops after counting `EnginePeer(peer.peer).compactDisplayTitle` sites in `AdminUserActionsSheet.swift`).
- Aligns `RenderedChannelParticipant.peer` with the pattern established for `FoundPeer.peer` (wave 34), `SendAsPeer.peer` (wave 35), `ContactListPeer.peer` (wave 36), and all `AccountContext.makeX(peer: ...)` facades (waves 37–40).
- Ratchet candidate for future waves: once `.peer` is `EnginePeer`, the `peers: [PeerId: Peer]` dict field becomes the only Postbox-typed field on the struct — a follow-up wave can migrate `peers: [EnginePeer.Id: EnginePeer]` in isolation.

## Scope

### In scope

**TelegramCore:**
- `submodules/TelegramCore/Sources/TelegramEngine/Peers/ChannelParticipants.swift` — change struct field + init param + Equatable impl
- 9 TelegramCore files containing 16 construction sites where `RenderedChannelParticipant(... peer: peer, ...)` is called with a raw `Peer` from `transaction.getPeer()` — wrap with `EnginePeer(peer)`:
  - `Messages/RequestStartBot.swift:65`
  - `Peers/AddPeerMember.swift:255`
  - `Peers/ChannelAdminEventLogs.swift:271, 279, 287, 483` (7 constructor calls total)
  - `Peers/ChannelBlacklist.swift:140`
  - `Peers/ChannelMembers.swift:115`
  - `Peers/ChannelOwnershipTransfer.swift:180` (2 constructor calls)
  - `Peers/JoinChannel.swift:82`
  - `Peers/PeerAdmins.swift:262`
  - `Peers/Ranks.swift:95`

**Consumer (17 files):** all sites accessing `participant.peer` or constructing `RenderedChannelParticipant`:
- `submodules/PeerInfoUI/Sources/ChannelAdminsController.swift`
- `submodules/PeerInfoUI/Sources/ChannelBlacklistController.swift`
- `submodules/PeerInfoUI/Sources/ChannelMembersController.swift`
- `submodules/PeerInfoUI/Sources/ChannelMembersSearchContainerNode.swift`
- `submodules/PeerInfoUI/Sources/ChannelMembersSearchControllerNode.swift`
- `submodules/PeerInfoUI/Sources/ChannelPermissionsController.swift`
- `submodules/SearchPeerMembers/Sources/SearchPeerMembers.swift`
- `submodules/TelegramUI/Components/AdminUserActionsSheet/Sources/AdminUserActionsSheet.swift`
- `submodules/TelegramUI/Components/Chat/ChatRecentActionsController/Sources/ChatRecentActionsController.swift`
- `submodules/TelegramUI/Components/Chat/ChatRecentActionsController/Sources/ChatRecentActionsFilterController.swift`
- `submodules/TelegramUI/Components/Chat/ChatRecentActionsController/Sources/ChatRecentActionsHistoryTransition.swift`
- `submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoMembers.swift`
- `submodules/TelegramUI/Components/ShareWithPeersScreen/Sources/ShareWithPeersScreenState.swift`
- `submodules/TelegramUI/Components/Stories/StoryContainerScreen/Sources/StoryContentLiveChatComponent.swift`
- `submodules/TelegramUI/Sources/ChatControllerAdminBanUsers.swift`
- `submodules/TemporaryCachedPeerDataManager/Sources/ChannelMemberCategoryListContext.swift`
- `submodules/TemporaryCachedPeerDataManager/Sources/PeerChannelMemberCategoriesContextsManager.swift`

### Out of scope (deferred)

- `RenderedChannelParticipant.peers: [PeerId: Peer]` — still `[PeerId: Peer]` dict. Not migrated this wave.
- `RenderedChannelParticipant.presences: [PeerId: PeerPresence]` — still `[PeerId: PeerPresence]` dict. Not migrated this wave.
- `PeerInfoScreenData.peer → EnginePeer` — future wave 42 candidate (drops 2 wave-40 wraps).
- `RenderedPeer → EngineRenderedPeer` — future major wave; saved for a dedicated session.
- `PeerInfoMember.peer: Peer` enum accessor in `PeerInfoMembers.swift:30-39` — retained as `Peer` for this wave (contained by a single `._asPeer()` inside the `.channelMember` branch). Migration of this accessor is a separate follow-up.

## Design

### Struct change

```swift
// submodules/TelegramCore/Sources/TelegramEngine/Peers/ChannelParticipants.swift

public struct RenderedChannelParticipant: Equatable {
    public let participant: ChannelParticipant
    public let peer: EnginePeer                              // ← was: Peer
    public let peers: [PeerId: Peer]                         // unchanged
    public let presences: [PeerId: PeerPresence]             // unchanged

    public init(participant: ChannelParticipant, peer: EnginePeer, peers: [PeerId: Peer] = [:], presences: [PeerId: PeerPresence] = [:]) {
        self.participant = participant
        self.peer = peer
        self.peers = peers
        self.presences = presences
    }

    public static func ==(lhs: RenderedChannelParticipant, rhs: RenderedChannelParticipant) -> Bool {
        return lhs.participant == rhs.participant && lhs.peer == rhs.peer   // ← was: lhs.peer.isEqual(rhs.peer)
    }
}
```

`EnginePeer` is `Equatable` by enum synthesis (verified — each associated value type is Equatable: `TelegramUser`, `TelegramGroup`, `TelegramChannel`, `TelegramSecretChat`). `==` becomes cleaner.

### Consumer-site shapes

Per the pre-flight classification, sites fall into these shapes:

- **ZERO** (transparent) — `.id`, `.isDeleted`, `.indexName`, `.addressName`, `.compactDisplayTitle`, `.displayTitle(strings:displayOrder:)`, `.displayLetters`, `.debugDisplayTitle`, etc. All exposed on `EnginePeer`. ~160 sites. **No edit.**

- **DROP** — `EnginePeer(participant.peer)` → `participant.peer`. ~32 consumer sites + 2 `.peer._asPeer()` downgrades that also drop. The biggest class of edits. Key sites:
  - `ChannelAdminsController.swift:326, 921, 926` (921, 926 drop `._asPeer()` from constructor)
  - `ChannelBlacklistController.swift:170, 381`
  - `ChannelMembersController.swift:334, 707`
  - `ChannelMembersSearchContainerNode.swift:212 (×2), 223`
  - `ChannelMembersSearchControllerNode.swift:148`
  - `ChannelPermissionsController.swift:480, 483`
  - `SearchPeerMembers.swift:30, 36, 61, 76`
  - `ChatRecentActionsController.swift:359`
  - `ChatRecentActionsFilterController.swift:217`
  - `ChatRecentActionsHistoryTransition.swift:719, 730, 740, 828, 842, 870, 943, 955, 973, 990, 1026` (one `EnginePeer(new.peer)` drop per site)
  - `ShareWithPeersScreenState.swift:558, 576`
  - `AdminUserActionsSheet.swift:284, 404, 416, 417, 522, 523` (EnginePeer(peer.peer) wraps)
  - `StoryContentLiveChatComponent.swift:370` (drops `._asPeer()`)
  - `ChatControllerAdminBanUsers.swift:372, 757` (drops `._asPeer()`)

- **CAST** — `if let user = participant.peer as? TelegramUser, user.botInfo != nil` → `if case let .user(user) = participant.peer, user.botInfo != nil`. 9 sites across 4 files:
  - `ChannelMembersController.swift:305`
  - `ChannelMembersSearchContainerNode.swift:752, 884, 1052, 1136`
  - `ChannelMembersSearchControllerNode.swift:516, 558`
  - `ShareWithPeersScreenState.swift:566`

  All 9 follow the identical 2-clause pattern (`as? TelegramUser`, `user.botInfo != nil`). Pattern-match rewrite is mechanically safe.

- **ADD-ASPEER** — site needs raw `Peer`. 3 sites:
  - `ChatRecentActionsHistoryTransition.swift:675` — `peers[participant.peer.id] = participant.peer` → `peers[participant.peer.id] = participant.peer._asPeer()` (assigning into `SimpleDictionary<PeerId, Peer>`).
  - `ChatRecentActionsHistoryTransition.swift:2275` — same pattern.
  - `PeerInfoMembers.swift:33` — `return participant.peer` → `return participant.peer._asPeer()` (outer enum accessor returns `Peer`; deliberately contained — migration of `PeerInfoMember.peer` deferred).

- **ADD-WRAP** — consumer construction site where the local is raw `Peer` but the field is now `EnginePeer`. 7 sites across 3 files:
  - `ChannelMembersSearchContainerNode.swift:987, 994, 998` — `peer: peer` where `peer = peerView.peers[participant.peerId]` is raw `Peer`. → `peer: EnginePeer(peer)`.
  - `ChannelMembersSearchControllerNode.swift:404, 409, 413` — same pattern.
  - `ChatRecentActionsFilterController.swift:445` — `peer: user` where `user: TelegramUser` (from `case let .user(user) = peer`). → `peer: .user(user)` or `peer: EnginePeer(user)`. Use `peer: .user(user)` (direct enum case) for clarity.
  - `ChatControllerAdminBanUsers.swift:226` — `peer: peer` where `peer = author: Peer`. → `peer: EnginePeer(peer)`.

### TelegramCore-internal constructor sites

All 16 sites receive a raw `Peer` (from `transaction.getPeer()` / `peers[id]`) and pass it as `peer:`. All become `peer: EnginePeer(peer)`:

```swift
// Before:
RenderedChannelParticipant(participant: participant, peer: peer, peers: peers, presences: presences)
// After:
RenderedChannelParticipant(participant: participant, peer: EnginePeer(peer), peers: peers, presences: presences)
```

No shape-selection judgment required — all 16 sites follow this exact template. The `peers` and `presences` dictionaries are unchanged.

## Risks

- **R1: CAST semantic preservation.** The 9 `as? TelegramUser` sites all gate on `user.botInfo != nil`. Pattern-match rewrite is `if case let .user(user) = participant.peer, user.botInfo != nil`. Verified: `EnginePeer.user(TelegramUser)` gives access to the same `TelegramUser` instance; `.botInfo` is a `TelegramUser` property. Semantically equivalent.

- **R2: `==` implementation change.** The struct's `==` goes from `lhs.peer.isEqual(rhs.peer)` (protocol dispatch) to `lhs.peer == rhs.peer` (synthesized). `EnginePeer.==` uses Swift-synthesized enum equality: each case compares associated values. Each associated-value type (`TelegramUser`, `TelegramGroup`, `TelegramChannel`, `TelegramSecretChat`) is `Equatable` via its own `==` implementation. Semantically equivalent to the protocol `isEqual`.

- **R3: PeerInfoMembers.swift:33 cascade.** `PeerInfoMember.peer: Peer` enum accessor at line 30-39 returns `participant.peer` on the `.channelMember` branch. Fix is a single `._asPeer()`. The outer enum's API stays unchanged — no cascade beyond this file. Future wave can migrate `PeerInfoMember.peer` to `EnginePeer`.

- **R4: Consumer-side constructor sites in ChannelMembersSearch*Node.** 3 sites each in the `Container` and `Controller` node files construct `RenderedChannelParticipant` for the legacy-group search path. The `peer` local is raw `Peer` from `peerView.peers`. Mechanical wrap with `EnginePeer(peer)` at the `peer:` argument.

- **R5: `participant.peers` dict staying `[PeerId: Peer]`.** Current code uses `peers.mapValues({ $0._asPeer() })` at construction sites where the local dict is `[EnginePeer.Id: EnginePeer]`. This pattern is unchanged by the wave — the `peers` field is not being migrated.

- **R6: Hidden consumer sites.** Pre-flight searched: `RenderedChannelParticipant(` constructors across `submodules/`, `participant.peer` access (subagent classification), all files that import TelegramCore/Postbox and reference `RenderedChannelParticipant`. 17 consumer files + 10 TelegramCore files confirmed. Risk of overlooked third-party or sparse consumer: low.

- **R7: Pre-existing WIP contamination.** `git status` shows unrelated WIP: `submodules/TelegramUI/Sources/ChatMessageTransitionNode.swift`, `build-system/bazel-rules/sourcekit-bazel-bsp` submodule marker, several untracked dirs. Wave-39 lesson: enumerate files explicitly in `git add`; run `git status --short` after staging.

## Verification

- Single full Bazel build with `--continueOnError` after all edits (extends wave-39 / wave-40 pattern).
- Expected outcome: **first-pass-clean build** based on wave-39 precedent — 52 files / 73 sites / non-propagating signature migration → first-pass-clean. This wave is comparable scale (27 files / ~200+ sites including ZEROs) with even cleaner mechanics: ZERO sites are literally no edit; DROP/CAST/ADD-WRAP/ADD-ASPEER patterns are all mechanical; no inference-dependent return types.
- Budget: 3–5 iterations if classification is wrong; first-pass-clean if classification is exact.

## Net ratchet economics

- Bridges dropped: ~37–39 (32 consumer DROPs + 2 `._asPeer()` drops in ChannelAdminsController + ~6 `EnginePeer(peer.peer).X` drops in AdminUserActionsSheet, possibly double-counted; final net post-commit grep will settle the number).
- Bridges added: ~23 (16 TelegramCore `EnginePeer(peer)` wraps at constructor call sites + 4 ADD-WRAP consumer constructors + 3 ADD-ASPEER).
- **Net:** ~−14 to −16 bridges. Positive economics even counting TelegramCore-internal adds.
- Ratchet marker: the 4 consumer ADD-WRAP constructor sites (`ChannelMembersSearch*Node` + `ChatControllerAdminBanUsers:226`) are candidates for drop in a future wave that migrates the `peerView.peers[id]` / `authors: [Peer]` upstream flows to EnginePeer.

## Out-of-scope inventory (for the next wave)

If a follow-up wave migrates **`RenderedChannelParticipant.peers: [PeerId: Peer] → [EnginePeer.Id: EnginePeer]`**, the ADD-WRAP sites in this wave (all `peers: peers.mapValues({ $0._asPeer() })`) simplify to `peers: peers`. That's a high-ratchet candidate wave that becomes mechanical once this wave lands.
