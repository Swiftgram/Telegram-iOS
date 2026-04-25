---
title: "Postbox → TelegramEngine wave 37: peerTokenTitle peer parameter Peer → EnginePeer"
date: 2026-04-24
status: draft
---

# Wave 37 design — `peerTokenTitle` peer parameter Peer → EnginePeer

## Context

Wave 36 (commit `069a060de1`, squashed into `8408e0ae19`) migrated `ContactListPeer.peer` from `Peer` to `EnginePeer` and added two new `peer._asPeer()` bridges at `ContactMultiselectionController.swift:386` and `:403`, feeding the private free function `peerTokenTitle(accountPeerId: PeerId, peer: Peer, ...)` at `:21`.

Wave 37 migrates `peerTokenTitle`'s `peer` parameter so those two new bridges — plus three older bridges at `:171`, `:201`, and `:748` — can all drop to zero in one atomic commit. This is a ring-2 cleanup: it consumes bridges that prior waves installed.

## Scope

All changes are confined to `submodules/TelegramUI/Sources/ContactMultiselectionController.swift`.

### Changes

| Location | Before | After |
|---|---|---|
| L21 | `peer: Peer` | `peer: EnginePeer` |
| L27 | `EnginePeer(peer).displayTitle(strings: strings, displayOrder: nameDisplayOrder)` | `peer.displayTitle(strings: strings, displayOrder: nameDisplayOrder)` |
| L171 | `peer: peer._asPeer()` | `peer: peer` |
| L201 | `peer: peer._asPeer()` | `peer: peer` |
| L386 | `peer: peer._asPeer()` | `peer: peer` |
| L403 | `peer: peer._asPeer()` | `peer: peer` |
| L748 | `peer: peer._asPeer()` | `peer: peer` |

All 5 call-site bindings `peer` are already `EnginePeer` at the call site — verified by the existing `._asPeer()` bridge.

The function body at L22–L28 stays semantically identical: `peer.id`, `peer.id.isReplies`, and `EnginePeer.displayTitle(strings:displayOrder:)` are all available on `EnginePeer`.

### Intentionally out of scope

- **`accountPeerId: PeerId`** — `PeerId` is already typealiased to `EnginePeer.Id`; not a Postbox-type leak.
- **`import Postbox` at L5** — other parts of the file still use Postbox-typed APIs (e.g., `.peer(peer: Peer, ...)` at L459 feeding the `SelectedPeer` enum). File-level Postbox-free is a later wave.
- **L459's `peer._asPeer()`** — feeds a different, not-yet-migrated Peer-typed API (`SelectedPeer.peer(peer: Peer, ...)`), outside this wave.
- **Other callers** — `peerTokenTitle` is `private` to this file; a full-codebase grep confirmed zero external call sites.

## Verification

1. **Pre-build grep** — confirm zero remaining `peerTokenTitle(.*_asPeer())` matches in the file and the broader codebase.
2. **Single full project build** via `Make.py` with `--continueOnError`. Expected first-pass-clean.
3. **Post-build grep** — same `peerTokenTitle(.*_asPeer())` pattern should remain empty.

## Risk

**Very low.** Private free function, single file, fully self-contained, all call sites mechanical bridge drops. No public-API change, no BUILD-file touch, no other modules affected.

Expected outcome: first-pass-clean build. Good reset after wave 36's 6-iteration convergence.

## Commit message

```
Postbox → TelegramEngine wave 37

peerTokenTitle: peer parameter Peer → EnginePeer.

Drops 5 _asPeer() bridges in ContactMultiselectionController.swift
(L171, L201, L386, L403, L748) — bridges installed by prior waves.

Private free function, single-file change.
```

## References

- CLAUDE.md — "Postbox → TelegramEngine refactor (in progress)"
- `docs/superpowers/postbox-refactor-log.md` — wave history
- Memory `project_postbox_refactor_next_wave.md` — wave-37 candidate list
