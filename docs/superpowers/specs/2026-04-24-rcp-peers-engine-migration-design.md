# Wave 44 — `RenderedChannelParticipant.peers: [PeerId: Peer] → [EnginePeer.Id: EnginePeer]`

**Date:** 2026-04-24
**Status:** Approved, pending plan
**Predecessor:** Wave 41 (commit `32573c9808`) migrated `RenderedChannelParticipant.peer` from `Peer` to `EnginePeer` and installed ADD-WRAP markers at consumer-side read sites that this wave drops.
**Goal:** Close out the wave-41 ratchet by migrating the sibling `peers: [PeerId: Peer]` field to `[EnginePeer.Id: EnginePeer]`. After this wave, `RenderedChannelParticipant` has no raw `Peer` types in its public surface.

## Context

`RenderedChannelParticipant` is declared in `submodules/TelegramCore/Sources/TelegramEngine/Peers/ChannelParticipants.swift`:

```swift
public struct RenderedChannelParticipant: Equatable {
    public let participant: ChannelParticipant
    public let peer: EnginePeer                        // migrated in wave 41
    public let peers: [PeerId: Peer]                   // target of this wave
    public let presences: [PeerId: PeerPresence]       // out of scope (PeerPresence is Postbox protocol)

    public init(participant: ChannelParticipant, peer: EnginePeer, peers: [PeerId: Peer] = [:], presences: [PeerId: PeerPresence] = [:]) { ... }
}
```

`peers` is a supplementary dict of "referenced peers" (e.g. the admin who promoted this member, the admin who banned them). Consumers use it to render relationships — never with `as?`/`is` casts, only `.id` and `.displayTitle(...)` on extracted values.

## Migration target

- `peers: [PeerId: Peer]` → `peers: [EnginePeer.Id: EnginePeer]`
- init default: `[:]` on both sides (type changes transparently)
- `presences` field stays unchanged.

## Scope

### Declaration (1 file, 2 edits)

**`submodules/TelegramCore/Sources/TelegramEngine/Peers/ChannelParticipants.swift`**

- Line 11: `public let peers: [PeerId: Peer]` → `public let peers: [EnginePeer.Id: EnginePeer]`
- Line 14: `peers: [PeerId: Peer] = [:]` → `peers: [EnginePeer.Id: EnginePeer] = [:]`

### TelegramCore producer sites (8 files, 8 construction sites, ~16 edits)

All 8 producers follow the identical pattern of building a local `peers: [PeerId: Peer] = [:]` dict inside a `postbox.transaction` and passing it to an `RCP(peers: peers, ...)` constructor. Per-site edits: change local dict type, wrap each insertion value with `EnginePeer(...)`.

| File | `var peers:` decl | `peers[X.id] = X` insertions | RCP construction |
|---|---|---|---|
| `TelegramEngine/Messages/RequestStartBot.swift` | line 61 | line 64 | line 65 |
| `TelegramEngine/Peers/ChannelOwnershipTransfer.swift` | line 170 | lines 172, 176 | line 180 (2 RCP constructions share `peers`) |
| `TelegramEngine/Peers/JoinChannel.swift` | line 59 | lines 64, 77 | line 82 |
| `TelegramEngine/Peers/AddPeerMember.swift` | line 242 | lines 244, 251 | line 255 |
| `TelegramEngine/Peers/PeerAdmins.swift` | line 251 | lines 253, 259 | line 262 |
| `TelegramEngine/Peers/ChannelBlacklist.swift` | line 128 | lines 130, 136 | line 140 |
| `TelegramEngine/Peers/Ranks.swift` | line 60 | lines 62, 68 | line 95 |
| `TelegramEngine/Peers/ChannelMembers.swift` | line 102 | line 105 | line 115 |

**Per-site rewrite:**
```swift
// before
var peers: [PeerId: Peer] = [:]
peers[peer.id] = peer

// after
var peers: [EnginePeer.Id: EnginePeer] = [:]
peers[peer.id] = EnginePeer(peer)
```

### Consumer-side DROPs: `.mapValues({ $0._asPeer() })` transforms (5 sites)

These consumer-side constructors start from a `[PeerId: EnginePeer]` source dict and currently unwrap to `[PeerId: Peer]` to feed into the RCP constructor. After migration, the unwrap transform is a no-op and can be dropped.

| File | Line | Before → after |
|---|---|---|
| `PeerInfoUI/Sources/ChannelAdminsController.swift` | 926 | `peers: peers.mapValues({ $0._asPeer() })` → `peers: peers` |
| `PeerInfoUI/Sources/ChannelMembersSearchContainerNode.swift` | 994 | same |
| `PeerInfoUI/Sources/ChannelMembersSearchContainerNode.swift` | 998 | same |
| `PeerInfoUI/Sources/ChannelMembersSearchControllerNode.swift` | 409 | same |
| `PeerInfoUI/Sources/ChannelMembersSearchControllerNode.swift` | 413 | same |

**Verification required at plan time:** for each of these 5 sites, grep back up in the enclosing function to confirm the local `peers` variable is declared `[PeerId: EnginePeer]` (the source of the mapValues transform). If any of the sources turn out to be `[PeerId: Peer]` rather than `[PeerId: EnginePeer]`, that site's transform is NOT a no-op and instead becomes a wrap (`.mapValues(EnginePeer.init)`) — still a net-zero or gain depending on where the source originates.

### Consumer-side DROPs: `EnginePeer(peer).displayTitle(...)` wraps (6 sites)

These are the wave-41 ADD-WRAP markers. Pattern: extract `peer` from `participant.peers[X]`, wrap with `EnginePeer(peer)` to call `.displayTitle(...)`. After migration, `peer` is already `EnginePeer` — drop the wrap.

| File | Line | Pattern |
|---|---|---|
| `PeerInfoUI/Sources/ChannelAdminsController.swift` | 297 | `EnginePeer(peer).displayTitle(strings: strings, ...)` → `peer.displayTitle(strings: strings, ...)` |
| `PeerInfoUI/Sources/ChannelMembersSearchContainerNode.swift` | 839 | same |
| `PeerInfoUI/Sources/ChannelMembersSearchContainerNode.swift` | 870 | same |
| `PeerInfoUI/Sources/ChannelMembersSearchContainerNode.swift` | 1091 | same |
| `PeerInfoUI/Sources/ChannelMembersSearchContainerNode.swift` | 1122 | same |
| `PeerInfoUI/Sources/ChannelBlacklistController.swift` | 165 | same |

The adjacent `peer.id == participant.peer.id` comparisons are unchanged: both sides are `EnginePeer.Id` (already a typealias of `PeerId`).

### Consumer-side ADD-UNWRAP (1 site)

**`submodules/TelegramUI/Components/Chat/ChatRecentActionsController/Sources/ChatRecentActionsHistoryTransition.swift`**, lines 672–674:

```swift
for (_, peer) in participant.peers {
    peers[peer.id] = peer   // `peers` is SimpleDictionary<PeerId, Peer>
}
```

After migration `peer` is `EnginePeer`; the outer `peers` SimpleDictionary is still `[PeerId: Peer]`. Rewrite:

```swift
for (_, peer) in participant.peers {
    peers[peer.id] = peer._asPeer()
}
```

### Constructor sites with no `peers:` arg — no change (12 sites)

Default value's *type* changes (`[PeerId: Peer] = [:]` → `[EnginePeer.Id: EnginePeer] = [:]`) but the literal `[:]` works for either. These sites compile unchanged:

- TelegramCore: `ChannelAdminEventLogs.swift:271, 279` (x2), `:287` (x2), `:483` (x2) — 7 constructions
- `PeerInfoUI/.../ChannelAdminsController.swift:921`
- `PeerInfoUI/.../ChannelMembersSearchContainerNode.swift:987`
- `PeerInfoUI/.../ChannelMembersSearchControllerNode.swift:404`
- `TelegramUI/.../ChatRecentActionsController/.../ChatRecentActionsFilterController.swift:445`
- `TelegramUI/.../ChatControllerAdminBanUsers.swift:224, :370, :755` (3 constructions)
- `TelegramUI/.../StoryContainerScreen/.../StoryContentLiveChatComponent.swift:361`

## Net impact

**Consumer-surface bridges:** −6 wraps + −5 unwrap transforms + +1 unwrap = **−10 bridges**.

**TelegramCore-internal bridges:** +~12 wraps (`EnginePeer(peer)` at producer insertion points, inside `import Postbox` modules). These do not regress Postbox-hygiene since every producer file already imports Postbox.

**Structural:** `RenderedChannelParticipant` public surface contains no raw `Peer` types after this wave (only `ChannelParticipant`, `EnginePeer`, `[EnginePeer.Id: EnginePeer]`, `[PeerId: PeerPresence]`). `presences` still leaks `PeerPresence` — separate future migration.

## Iteration budget

**2–3 iterations** (wave-41 foundational-type lesson: field migrations on passed-around structs budget 2–4 iterations, not first-pass-clean).

Verified absence of hidden grep surface:
- No `as?` / `is TelegramX` casts on `participant.peers[X]` extractions (grepped).
- No Peer-only properties accessed on extractions (uses `.id` and `.displayTitle(...)` only — both EnginePeer-forwarded).
- All 8 TelegramCore producers build locally (verified) — no chain-migration.

## Risks

1. **Producer local-dict migration under `continueOnError`.** If a producer builds the dict with more than two insertions and misses one, the build flags mismatched dict-value types. Low blast radius (per-file local).
2. **Hidden consumer site.** If a grep miss surfaces a `participant.peers` site not enumerated here, the wrap/unwrap balance changes. Mitigation: plan document must re-run the narrow grep (`participant\.peers|rcp\.peers|renderedParticipant\.peers`) at plan-write time and iteration-0 time.
3. **mapValues source-dict check.** If any of the 5 consumer-side `.mapValues({ $0._asPeer() })` sites has a source `[PeerId: Peer]` (not `[PeerId: EnginePeer]`), the migration at that site inverts (becomes a wrap instead of a drop). Plan-time per-site verification required.
4. **SimpleDictionary import.** The one ADD-UNWRAP site in `ChatRecentActionsHistoryTransition.swift` already uses `SimpleDictionary<PeerId, Peer>` — no new Postbox exposure.

## Out of scope

- `RenderedChannelParticipant.presences: [PeerId: PeerPresence]` — `PeerPresence` is a Postbox protocol; separate migration with different shape.
- `RenderedPeer → EngineRenderedPeer` foundational-type migration (listed in wave-44 memo as candidate 6; save for a dedicated session).
- `PeerInfoHeader*` bundle (wave-44 memo candidate 1) — considered but not selected for wave 44; candidate for wave 45.

## Success criteria

1. `submodules/TelegramCore/Sources/TelegramEngine/Peers/ChannelParticipants.swift` has `peers: [EnginePeer.Id: EnginePeer]` declaration.
2. All 8 TelegramCore producers compile with wrapped inserts.
3. All 5 consumer `.mapValues({ $0._asPeer() })` transforms are removed.
4. All 6 consumer `EnginePeer(peer).displayTitle(...)` wraps on extracted dict values are removed (`peer.displayTitle(...)`).
5. `ChatRecentActionsHistoryTransition.swift:673` uses `peer._asPeer()` for the SimpleDictionary insertion value.
6. Full `Telegram/Telegram` build (`configuration=debug_sim_arm64`) is clean — **one** atomic commit.
7. Grep post-migration: `participant\.peers\[` returns only engine-typed call sites; no residual `EnginePeer(peer)` on `.peers[...]` extractions.

## Commit message template

```
Postbox -> TelegramEngine wave 44

Migrate RenderedChannelParticipant.peers from [PeerId: Peer] to
[EnginePeer.Id: EnginePeer]. Closes the wave-41 ratchet — the public
struct no longer leaks raw Peer types in any field (presences stays
Postbox-typed; separate migration).

Consumer-surface: -10 bridges (6 EnginePeer(peer) wraps dropped at
read sites, 5 .mapValues({ $0._asPeer() }) transforms dropped at
constructor sites, 1 ._asPeer() added at
ChatRecentActionsHistoryTransition.swift:673 where the value is
inserted into a raw-Peer SimpleDictionary).

TelegramCore producers: 8 files, each builds a local
[EnginePeer.Id: EnginePeer] dict from transaction.getPeer() wrapping
at the insertion point.

No unit tests in this project; full Telegram/Telegram build verified
under configuration=debug_sim_arm64.
```
