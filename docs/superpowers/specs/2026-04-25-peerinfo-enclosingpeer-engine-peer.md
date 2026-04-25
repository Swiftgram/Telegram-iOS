# Wave 50 — `enclosingPeer` Peer? → EnginePeer?

**Date:** 2026-04-25
**Pattern:** struct-field + stored-form `Peer?` → `EnginePeer?` (wave-47/48 shape).
**Module:** `submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/` only — no public-API leaks.

## Goal

Migrate the PeerInfo members chain's `enclosingPeer` field from raw Postbox `Peer?` to `EnginePeer?`. Drops 2 `_asPeer()` demotions, 1 `EnginePeer(...)` wrap, 1 `flatMap(EnginePeer.init)` simplification, and 1 PSPB boundary `_asPeer()` lift. Closes the wave-48-pattern internal-demotion-and-external-re-promotion ratchet at PIMP:354–363 (engine.data subscription returns `EnginePeer?`, currently demoted to `Peer?` at the storage boundary).

## Type changes

| File | Site | Before | After |
|---|---|---|---|
| `PeerInfoScreenMemberItem.swift:23` | stored `let enclosingPeer` | `Peer?` | `EnginePeer?` |
| `PeerInfoScreenMemberItem.swift:34` | init param | `Peer?` | `EnginePeer?` |
| `PeerInfoMembersPane.swift:92` | `func item(... enclosingPeer:)` | `Peer` | `EnginePeer` |
| `PeerInfoMembersPane.swift:271` | `func preparedTransition(... enclosingPeer:)` | `Peer` | `EnginePeer` |
| `PeerInfoMembersPane.swift:293` | `private var enclosingPeer` | `Peer?` | `EnginePeer?` |
| `PeerInfoMembersPane.swift:442` | `func updateState(enclosingPeer:)` | `Peer` | `EnginePeer` |

`PeerInfoScreenMemberItem` and `PeerInfoMembersPaneNode` are local to the module — no cross-module signature ripple.

## Edit patterns

### A. Conditional cast → case-let (wave-41/45 idiom)

| File:Line | Before | After |
|---|---|---|
| PSMI:152 | `if let channel = item.enclosingPeer as? TelegramChannel, channel.hasPermission(.editRank)` | `if case let .channel(channel) = item.enclosingPeer, channel.hasPermission(.editRank)` |
| PSMI:154 | `else if let group = item.enclosingPeer as? TelegramGroup, !group.hasBannedPermission(.banEditRank)` | `else if case let .legacyGroup(group) = item.enclosingPeer, !group.hasBannedPermission(.banEditRank)` |
| PIMP:113 | `if let channel = enclosingPeer as? TelegramChannel, channel.hasPermission(.editRank)` | `if case let .channel(channel) = enclosingPeer, channel.hasPermission(.editRank)` |
| PIMP:115 | `else if let group = enclosingPeer as? TelegramGroup, !group.hasBannedPermission(.banEditRank)` | `else if case let .legacyGroup(group) = enclosingPeer, !group.hasBannedPermission(.banEditRank)` |

The `case let` pattern binds `channel: TelegramChannel` / `group: TelegramGroup` directly — `.hasPermission(.editRank)` and `.hasBannedPermission(.banEditRank)` are class methods on the bound concrete types. No `_asPeer()` bridge needed.

### B. `is`-check → `case` (wave-41 always-false-warning fix)

| File:Line | Before | After |
|---|---|---|
| PSMI:181 | `if actions.contains(.promote) && item.enclosingPeer is TelegramChannel` | `if actions.contains(.promote), case .channel = item.enclosingPeer` |
| PSMI:187 | `if item.enclosingPeer is TelegramChannel` | `if case .channel = item.enclosingPeer` |
| PIMP:142 | `if actions.contains(.promote) && enclosingPeer is TelegramChannel` | `if actions.contains(.promote), case .channel = enclosingPeer` |
| PIMP:148 | `if enclosingPeer is TelegramChannel` | `if case .channel = enclosingPeer` |

PIMP:113/115/142/148 are inside `func item(... enclosingPeer: EnginePeer ...)`, so `enclosingPeer` is non-optional inside that body; PSMI sites are against `item.enclosingPeer: EnginePeer?`. `case let .channel(channel)` and `case .channel` both compile cleanly against optional and non-optional EnginePeer.

### C. Drop wraps / unwraps

| File:Line | Before | After |
|---|---|---|
| PSMI:178 | `peer: item.enclosingPeer.flatMap(EnginePeer.init)` | `peer: item.enclosingPeer` |
| PIMP:139 | `peer: EnginePeer(enclosingPeer)` | `peer: enclosingPeer` |
| PIMP:361 | `strongSelf.enclosingPeer = enclosingPeer._asPeer()` | `strongSelf.enclosingPeer = enclosingPeer` |
| PIMP:363 | `updateState(enclosingPeer: enclosingPeer._asPeer(), state: state, presentationData: presentationData)` | `updateState(enclosingPeer: enclosingPeer, state: state, presentationData: presentationData)` |
| PSPB:852 | `enclosingPeer: peer._asPeer()` | `enclosingPeer: peer` |

### D. No-op call sites (type flows through transparently)

- `PeerInfoSettingsItems.swift:132` — `enclosingPeer: nil` (nil literal works for any optional)
- `PeerInfoMembersPane.swift:275/276` — pass-through `enclosingPeer: enclosingPeer`
- `PeerInfoMembersPane.swift:437/438` — `if let enclosingPeer = self.enclosingPeer ... self.updateState(enclosingPeer: enclosingPeer, ...)` (both stored-form and `updateState` param shift to EnginePeer; type carries through)
- `PeerInfoMembersPane.swift:451` — pass-through
- `PeerInfoMembersPane.swift:485` — `self.enclosingPeer = enclosingPeer` (param and stored-form both EnginePeer)
- `PeerInfoScreenOpenMember.swift` — uses `self.data?.peer` (already `EnginePeer?` post-wave-42), unrelated to this migration

**Total edits:** 19 across 3 files (PSMI, PIMP, PSPB) — 6 type-change edits in the table at the top of this spec + 4 (Pattern A) + 4 (Pattern B) + 5 (Pattern C).

## Risk register

| Risk | Mitigation |
|---|---|
| `case .channel = item.enclosingPeer` against `EnginePeer?` semantics | Wave-45 lesson confirms `case let .x(y) = peer` compiles cleanly against `EnginePeer?`. Matches `.some(.channel)`, rejects `nil` and other cases — equivalent to `is TelegramChannel` semantics. |
| `if actions.contains(.promote), case .channel = ...` mixed boolean + pattern condition | Standard Swift if-case syntax (introduced in wave 41 idiom for this codebase). |
| Hidden Peer-only property access on bare `enclosingPeer` | Pre-flight grep complete: only access patterns are `.id` (EnginePeer has it), and cast-bound `channel.hasPermission` / `group.hasBannedPermission`. No `_asPeer()` bridges expected. |
| Closure capture aliases (wave-47 lesson) | Pre-flight grep covered `strongSelf.enclosingPeer` (PIMP:361) and `self.enclosingPeer` (PIMP:437/485). |
| `enclosingPeer: nil` literal at PSI:132 | `nil` is valid for any optional — no edit. |
| `availableActionsForMemberOfPeer` signature compatibility | Confirmed `EnginePeer?` at `PeerInfoData.swift:2314`. Both PSMI:178 and PIMP:139 are pure simplifications. |
| Always-false `is` check warning under `-warnings-as-errors` | Wave-41 lesson — handled by Pattern B. |

## Wave shape

**Classification:** cross-file private struct-field migration with stored-form ratchet (wave-47 taxonomy: "cross-file private").
**Iteration budget:** 1–2 (target first-pass-clean per wave 48/49 streak).
**Subagent dispatch:** not needed — 17 edits / 3 files is single-implementer scope.

## Verification

### Build

```sh
source ~/.zshrc 2>/dev/null; python3 build-system/Make/Make.py --overrideXcodeVersion \
 --cacheDir ~/telegram-bazel-cache \
 build \
 --configurationPath build-system/appstore-configuration.json \
 --gitCodesigningRepository git@gitlab.com:peter-iakovlev/fastlanematch.git \
 --gitCodesigningType development --gitCodesigningUseCurrent \
 --buildNumber=1 --configuration=debug_sim_arm64 --continueOnError
```

### Post-edit residue grep (expect empty)

```sh
grep -rnE "enclosingPeer\._asPeer|EnginePeer\(enclosingPeer\)|enclosingPeer\.flatMap\(EnginePeer" \
  submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/

grep -rnE "enclosingPeer.*as\? TelegramChannel|enclosingPeer.*as\? TelegramGroup|enclosingPeer is TelegramChannel" \
  submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/
```

## Net delta projection

- **Internal bridges:** −5 (2× `_asPeer()` at PIMP:361/363, 1× `EnginePeer(...)` at PIMP:139, 1× `flatMap(EnginePeer.init)` at PSMI:178, 1× boundary `_asPeer()` at PSPB:852).
- **Boundary lifts:** 0 net new — the source pipeline (engine.data subscription at PIMP:354) already yields `EnginePeer?`. Migration just removes the demote-then-promote dance.
- **ADD wraps:** 0 expected (no Peer-only property accesses on bare `enclosingPeer`).

## Out of scope

- `PeerInfoScreenData.chatPeer: Peer?` — large cascade (PSPB `as? TelegramX` × 5, ClearPeerHistory cascade, openClearHistory wraps × 4, PSOC × 2). Memory's wave-50 candidate Option 3, deferred for a multi-iteration wave.
- `PeerInfoGroupsInCommonPaneNode.PeerEntry.peer: Peer` — separate single-file migration, not bundled (wave-49 source-of-truth-coherence rule: unrelated chains stay in their own waves). Candidate for wave 51.
- `RenderedPeer → EngineRenderedPeer` foundational refactor — dedicated session.

## Memory file update

After landing, update `project_postbox_refactor_next_wave.md`:
- Move wave 50 outcome into the recent-waves list.
- Promote wave 51 candidate (`PeerInfoGroupsInCommonPaneNode.PeerEntry.peer` likely; otherwise re-scan the module with the standard grep).
