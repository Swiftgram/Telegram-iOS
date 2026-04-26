# Wave 103 — `ChatRecentActionsControllerNode.peer: Peer → EnginePeer`

**Date:** 2026-04-26
**Pattern:** close-the-shadow boundary unwrap drop (wave-71-shadow). Single-file private stored-field migration with caller-side `_asPeer()` removal at the module boundary.
**Module:** `submodules/TelegramUI/Components/Chat/ChatRecentActionsController/` only — no public-API leak.

## Goal

Migrate `ChatRecentActionsControllerNode`'s stored `peer: Peer` to `EnginePeer`, dropping the `_asPeer()` boundary call inside `ChatRecentActionsController`. Net effect: −1 `_asPeer()` boundary wrap, −1 `import Postbox`, −1 module from the Postbox-importing list.

The caller (`ChatRecentActionsController`) already holds `peer: EnginePeer` and demotes it once at line 277 before passing into the ControllerNode init. This is the wave-71-shadow shape: the public API is already `EnginePeer`, but a private internal storage form was left as `Peer` at wave-71 time. Closing it now is a clean, contained migration.

## Type changes

| File | Site | Before | After |
|---|---|---|---|
| `ChatRecentActionsControllerNode.swift:46` | stored `private let peer` | `Peer` | `EnginePeer` |
| `ChatRecentActionsControllerNode.swift:111` | init param `peer:` | `Peer` | `EnginePeer` |
| `ChatRecentActionsControllerNode.swift:5` | `import Postbox` | present | removed |
| `ChatRecentActionsController.swift:277` | call `peer: self.peer._asPeer()` | demoted | `peer: self.peer` |

`ChatRecentActionsControllerNode` has no public-API consumers outside `ChatRecentActionsController` (single caller site verified by grep `ChatRecentActionsControllerNode\(`).

## Edit patterns

### A. Conditional cast → case-let (wave-41/45 idiom)

| File:Line | Before | After |
|---|---|---|
| ChatRecentActionsControllerNode.swift:899 | `if let peer = strongSelf.peer as? TelegramChannel { ... }` | `if case let .channel(peer) = strongSelf.peer { ... }` |
| ChatRecentActionsControllerNode.swift:948 | `if let channel = self.peer as? TelegramChannel, case .broadcast = channel.info { ... }` | `if case let .channel(channel) = self.peer, case .broadcast = channel.info { ... }` |
| ChatRecentActionsControllerNode.swift:1088 | `if let channel = self.peer as? TelegramChannel { ... }` | `if case let .channel(channel) = self.peer { ... }` |

The `case let .channel(channel)` pattern binds `channel: TelegramChannel` directly. Inner code (`channel.info`, etc.) ports verbatim because `EnginePeer.channel`'s associated value is the concrete `TelegramChannel` class.

`self.peer` is non-optional `EnginePeer` post-migration, so all three case-let conditions compile cleanly without optional-chaining.

### B. Pass-through (no edit, type flows transparently)

- `self.peer.id` — 4 sites (lines 145, 161, 1138, 1490). `EnginePeer.id` is an `EnginePeer.Id` typealias of `PeerId`, identical at the call sites that consume it (`channelAdminEventLog(peerId:)`, `admins(peerId:)`, `updateChannelMemberBannedRights(peerId:)`, et al. all accept the typealiased form).

### C. Caller boundary drop

| File:Line | Before | After |
|---|---|---|
| ChatRecentActionsController.swift:277 | `ChatRecentActionsControllerNode(... peer: self.peer._asPeer(), ...)` | `ChatRecentActionsControllerNode(... peer: self.peer, ...)` |

`ChatRecentActionsController.peer` is already declared `EnginePeer` (init signature at line 42 confirmed).

**Total edits:** 7 across 2 files. 4 type-change edits (3 in node + 1 caller) + 3 case-let rewrites.

## Risk register

| Risk | Mitigation |
|---|---|
| Other unrelated `_asPeer()` and `EnginePeer(peer)` sites in the same file (lines 357, 368, 1005 / 263, 1009, 1011, 1208, 1222) | Pre-flight grep verified these all operate on DIFFERENT `peer` locals (callback-bound search results, not `self.peer`). They are unaffected by this migration. |
| Hidden `Peer`-only property access on `self.peer` | Pre-flight grep complete: only attribute access is `.id` (EnginePeer-compatible). 3 `as? TelegramChannel` downcasts are the only conversion sites, all handled by Pattern A. |
| `as? TelegramGroup` or `as? TelegramUser` downcasts on `self.peer` | None present (verified by grep `self\.peer as\?` returning only the 3 TelegramChannel sites). |
| `is TelegramChannel`-style always-false warning under `-warnings-as-errors` | None present (no `is`-checks on `self.peer` — verified by grep). |
| Closure capture alias migration (wave-47 lesson) | Only `strongSelf.peer` and `self.peer` aliases — both ride the type change. No locally-bound `let peer = self.peer` aliases that would need separate type-flow tracking (verified by grep). |
| Caller side-effects from `_asPeer()` removal | `ChatRecentActionsController.swift:277` is the only call site (verified). The `_asPeer()` is pure conversion with no side effects. |
| Build cascade beyond the two files | Consumer-only — both files are inside `submodules/TelegramUI/Components/Chat/ChatRecentActionsController/`. No TelegramCore touch, no cross-module ripple. Build cost ~25s. |

## Wave shape

**Classification:** wave-71-shadow close (single-file private stored-form migration with single-caller boundary drop).
**Iteration budget:** 1 (target first-pass-clean given the contained scope and validated pre-flight grep).
**Subagent dispatch:** not needed — 7 edits across 2 files is single-implementer scope.

## Verification

### Build

```sh
source ~/.zshrc 2>/dev/null; python3 build-system/Make/Make.py --overrideXcodeVersion \
 --cacheDir ~/telegram-bazel-cache \
 build \
 --configurationPath build-system/appstore-configuration.json \
 --gitCodesigningRepository git@gitlab.com:peter-iakovlev/fastlanematch.git \
 --gitCodesigningType development --gitCodesigningUseCurrent \
 --buildNumber=1 --configuration=debug_sim_arm64
```

(No `--continueOnError` — single-iter target with small scope.)

### Post-edit residue grep (expect empty)

```sh
# No remaining as? TelegramChannel on self.peer / strongSelf.peer
grep -nE "(self|strongSelf)\.peer as\? Telegram(Channel|Group|User)" \
  submodules/TelegramUI/Components/Chat/ChatRecentActionsController/Sources/

# No remaining _asPeer() on self.peer
grep -nE "self\.peer\._asPeer\(\)" \
  submodules/TelegramUI/Components/Chat/ChatRecentActionsController/Sources/

# No remaining import Postbox in the module
grep -rn "^import Postbox$" \
  submodules/TelegramUI/Components/Chat/ChatRecentActionsController/Sources/
```

## Net delta projection

- **Internal bridges:** −1 (the `_asPeer()` at `ChatRecentActionsController.swift:277`).
- **`import Postbox` drops:** −1 (`ChatRecentActionsControllerNode.swift:5`).
- **ADD wraps:** 0 (no Peer-only property accesses on bare `self.peer`).
- **Module Postbox-free count:** +1.

## Out of scope

- Other `Peer`-typed locals in the same file (search-callback-bound `peer` at lines 357, 368, 1005, etc.) — these belong to separate signatures (`Signal<Peer?, NoError>`, search result destructures from APIs that still return raw `Peer`). Migrating them is gated on those upstream APIs migrating first.
- `context.account.postbox.network` and similar Shape-D Postbox accesses — unrelated to this wave's `peer` field migration.
- `EnginePeer(peer)` boundary wraps inside callbacks (lines 263, 1009, 1011, 1208, 1222) — these wrap callback-bound search results, not `self.peer`. Out of scope for the same reason as above.

## Memory file update

After landing, update `project_postbox_refactor_next_wave.md`:
- Move wave 103 outcome into the recent-waves list (commit hash + 7-edit single-iter summary).
- Update the "Wave 103+ Shape-C/D candidates" line in `MEMORY.md` since this is technically a wave-71-shadow close, not a Shape-C/D refactor — the candidates listed there (NativeVideoContent, DirectMediaImageCache, SecureIdDocumentFormControllerNode) carry forward to wave 104+.
- The `ChatRecentActionsControllerNode.peer: Peer -> EnginePeer` candidate line in the next-wave file (currently bullet 5) gets removed.
