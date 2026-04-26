# Wave 105 — DeviceContactInfoSubject enum payload Peer? → EnginePeer?

**Date:** 2026-04-26
**Pattern:** Multi-module enum-payload migration with completion-callback signature change (wave-91 shape — `ItemListWebsiteItem.peer + RecentSessionsController.website case payload + openWebSession callback`).
**Modules:** `AccountContext` (enum + computed property), `PeerInfoUI` (`DeviceContactInfoController.swift` primary consumer), `TelegramUI` (4 construction sites across 4 files).

## Goal

Migrate `DeviceContactInfoSubject` enum's 3 case payloads from `Peer?` to `EnginePeer?`, plus 2 callback signatures (`.filter`'s `(Peer?, DeviceContactExtendedData) -> Void` and `.create`'s `(Peer?, DeviceContactStableId, DeviceContactExtendedData) -> Void`) and the public `peer: Peer?` computed property. Net effect: −10 wraps dropped, +2 wraps added (Chat-side construction barriers), +1 `as? TelegramUser` → `case let .user(...)` rewrite. **Net wrap delta: −8.**

## Wave-71-shadow risk inventory (per `feedback_wave71_shadow_risk.md`)

| Layer | Result | Notes |
|---|---|---|
| 1. Downcasts (`as?` / `is`) on the migrated value | **1 site** | `DeviceContactInfoController.swift:849` — `if let peer = peer as? TelegramUser` becomes `if case let .user(peer) = peer`. Inner body accesses `peer.firstName`, `peer.lastName`, `peer.phone` — all `TelegramUser` fields, work after rebinding via case-let. |
| 2. Peer-protocol extension method calls | **0 blockers** | Inventory pass found ALL consumer-side access on the migrated bindings is `.id` only. No `Peer`-protocol-only methods (no `canSetupAutoremoveTimeout`, `displayTitle`, `addressName`, etc. on the migrated bindings). |
| 3. Field flow into `Peer`-typed function parameters | **2 ADD bridges** | `ChatControllerOpenAttachmentMenu.swift:683` and `:1850` — both pass `peerAndContactData.0` directly to `.filter(peer:)` constructor. The upstream signal type is explicitly `(Peer?, DeviceContactExtendedData?)` (see L634, L1822). After migration, the construction must wrap: `peerAndContactData.0.flatMap(EnginePeer.init)`. **Accepted barrier — net-negative wave delta still wins.** |
| 4. `Message`-builder / `SimpleDictionary<PeerId, Peer>` barriers | **0** | No `Message(...)` constructor calls or dict-store patterns on the migrated bindings. |

The 2 ADD bridges in Layer 3 are the only wave cost; net delta after accounting for them is still −8.

## Type changes

### AccountContext.swift (lines 703-718)

| Line | Before | After |
|---|---|---|
| 704 | `case vcard(Peer?, DeviceContactStableId?, DeviceContactExtendedData)` | `case vcard(EnginePeer?, DeviceContactStableId?, DeviceContactExtendedData)` |
| 705 | `case filter(peer: Peer?, contactId: DeviceContactStableId?, contactData: DeviceContactExtendedData, completion: (Peer?, DeviceContactExtendedData) -> Void)` | `case filter(peer: EnginePeer?, contactId: DeviceContactStableId?, contactData: DeviceContactExtendedData, completion: (EnginePeer?, DeviceContactExtendedData) -> Void)` |
| 706 | `case create(peer: Peer?, contactData: DeviceContactExtendedData, isSharing: Bool, shareViaException: Bool, completion: (Peer?, DeviceContactStableId, DeviceContactExtendedData) -> Void)` | `case create(peer: EnginePeer?, contactData: DeviceContactExtendedData, isSharing: Bool, shareViaException: Bool, completion: (EnginePeer?, DeviceContactStableId, DeviceContactExtendedData) -> Void)` |
| 708 | `public var peer: Peer? {` | `public var peer: EnginePeer? {` |

The `contactData: DeviceContactExtendedData` computed property at L719 is unchanged.

## Edit patterns

### Pattern A — `_asPeer()` drops at construction sites (5 sites)

| File:Line | Before | After |
|---|---|---|
| DeviceContactInfoController.swift:1289 | `subject: .vcard(peer?._asPeer(), contactId, contactData)` | `subject: .vcard(peer, contactId, contactData)` |
| DeviceContactInfoController.swift:1443 | `subject: .create(peer: peer?._asPeer(), contactData: contactData, isSharing: false, shareViaException: false, completion: { peer, stableId, contactData in` | `subject: .create(peer: peer, contactData: contactData, isSharing: false, shareViaException: false, completion: { peer, stableId, contactData in` |
| DeviceContactInfoController.swift:1489 | `subject: .create(peer: peer?._asPeer(), contactData: contactData, isSharing: peer != nil, shareViaException: false, completion: { _, _, _ in` | `subject: .create(peer: peer, contactData: contactData, isSharing: peer != nil, shareViaException: false, completion: { _, _, _ in` |
| StoryItemSetContainerViewSendMessage.swift:2132 | `subject: .filter(peer: peerAndContactData.0?._asPeer(), contactId: nil, contactData: contactData, completion: { [weak self, weak view] peer, contactData in` | `subject: .filter(peer: peerAndContactData.0, contactId: nil, contactData: contactData, completion: { [weak self, weak view] peer, contactData in` |
| OpenChatMessage.swift:443 | `subject: .vcard(peer?._asPeer(), nil, contactData)` | `subject: .vcard(peer, nil, contactData)` |

Each source `peer` is already `EnginePeer?` (verified per-site: line 1289 in `addContactToExisting` callback already typed `(EnginePeer?, ...)` at L1409; line 1443 in `dataSignal` callback that returns `(EnginePeer?, ...)`; line 1489 in `addContactOptionsController(peer: EnginePeer?, ...)`; line 2132 in `(EnginePeer?, ...)` signal; line 443 in `peer: EnginePeer?` source).

### Pattern B — `_asPeer()` drops at completion-call sites (2 sites)

| File:Line | Before | After |
|---|---|---|
| DeviceContactInfoController.swift:1105 | `completion(peerAndContactData.0?._asPeer(), filteredData)` | `completion(peerAndContactData.0, filteredData)` |
| DeviceContactInfoController.swift:1224 | `completion(contactIdAndData.2?._asPeer(), contactIdAndData.0, contactIdAndData.1)` | `completion(contactIdAndData.2, contactIdAndData.0, contactIdAndData.1)` |

The completion's first parameter type changes from `Peer?` to `EnginePeer?` per the enum migration. Source values (`peerAndContactData.0` and `contactIdAndData.2`) are already `EnginePeer?` (typed signal pipelines), so dropping `_asPeer()` is a clean simplification.

### Pattern C — `.flatMap(EnginePeer.init)` simplifications (3 sites)

DeviceContactInfoController.swift:941-946 region:

| File:Line | Before | After |
|---|---|---|
| 941-942 | `case let .vcard(peer, id, data):\n    contactData = .single((peer.flatMap(EnginePeer.init), id, data))` | `case let .vcard(peer, id, data):\n    contactData = .single((peer, id, data))` |
| 943-944 | `case let .filter(peer, id, data, _):\n    contactData = .single((peer.flatMap(EnginePeer.init), id, data))` | `case let .filter(peer, id, data, _):\n    contactData = .single((peer, id, data))` |
| 945-946 | `case let .create(peer, data, share, shareViaExceptionValue, _):\n    contactData = .single((peer.flatMap(EnginePeer.init), nil, data))` | `case let .create(peer, data, share, shareViaExceptionValue, _):\n    contactData = .single((peer, nil, data))` |

After migration, the destructured `peer: EnginePeer?` is already the target type — the `.flatMap(EnginePeer.init)` round-trip becomes redundant.

### Pattern D — Downcast → case-let (1 site)

| File:Line | Before | After |
|---|---|---|
| DeviceContactInfoController.swift:849 | `if let peer = peer as? TelegramUser {` | `if case let .user(peer) = peer {` |

The outer `peer` is bound from `case let .create(peer, contactData, _, _, _) = subject` at L845, which becomes `EnginePeer?` post-migration. `case let .user(peer) = peer` rebinds the inner `peer` to `TelegramUser` (the `.user` case associated value). Inner body accesses `peer.firstName`, `peer.lastName`, `peer.phone` — all `TelegramUser` instance methods/properties, work transparently after rebinding.

### Pattern E — ADD wraps at Chat-side construction (2 sites)

| File:Line | Before | After |
|---|---|---|
| ChatControllerOpenAttachmentMenu.swift:683 | `subject: .filter(peer: peerAndContactData.0, contactId: nil, contactData: contactData, completion: { peer, contactData in` | `subject: .filter(peer: peerAndContactData.0.flatMap(EnginePeer.init), contactId: nil, contactData: contactData, completion: { peer, contactData in` |
| ChatControllerOpenAttachmentMenu.swift:1850 | `subject: .filter(peer: peerAndContactData.0, contactId: nil, contactData: contactData, completion: { peer, contactData in` | `subject: .filter(peer: peerAndContactData.0.flatMap(EnginePeer.init), contactId: nil, contactData: contactData, completion: { peer, contactData in` |

Both sites have identical text — `Edit replace_all=true` bundles them. The upstream signal type is explicitly `(Peer?, DeviceContactExtendedData?)` (verified at L634 and L1822). The `.flatMap(EnginePeer.init)` wraps the optional `Peer?` to optional `EnginePeer?`.

### Pattern F — Pass-through (no edit needed)

These flow transparently through the type change:
- DeviceContactInfoController.swift:897, 1041, 1047 — `subject.peer` access (returns `EnginePeer?` post-migration, consumers use `.id` or `if let peer = subject.peer`)
- DeviceContactInfoController.swift:1041 — `.create(peer: subject.peer, ...)` — both sides EnginePeer? after migration
- DeviceContactInfoController.swift:1149-1163, 1183-1189 — destructured `peer` from `.create` becomes `EnginePeer?`, body accesses `peer.id` and passes to `completion(peer, ...)` (now `EnginePeer?`-accepting)
- ContactsController.swift:312, 785; OpenAddContact.swift:32; ComposeController.swift:220; ShareExtensionContext.swift:532 — `peer: nil` or `.vcard(nil, ...)` constructions, `nil` works for both optional types
- All callback consumer bodies that use `peer?.id` (StoryItemSetContainerViewSendMessage:2141, ChatControllerOpenAttachmentMenu:689, :1856) — `EnginePeer?.id` is `EnginePeer.Id` typealiased to `PeerId`, identical at usage sites

**Total edits: 17 across 5 files.** AccountContext.swift (4) + DeviceContactInfoController.swift (9) + ChatControllerOpenAttachmentMenu.swift (1 with replace_all) + StoryItemSetContainerViewSendMessage.swift (1) + OpenChatMessage.swift (1) = ~16 Edit calls.

## Risk register

| Risk | Mitigation |
|---|---|
| `_asPeer()` source not actually `EnginePeer?` at one of the drop sites | Per-site source typing verified during inventory: 1289 (addContactToExisting callback typed `(EnginePeer?, ...)` at L1409), 1443 (dataSignal returns `(EnginePeer?, ...)`), 1489 (function param `peer: EnginePeer?` at L1481), 2132 (signal callback typed `(EnginePeer?, ...)`), 443 (local `peer: EnginePeer?`). All confirmed. |
| `subject.peer` consumers break | 3 access sites, all pattern `if let peer = subject.peer { ... peer.id ... }`. Body uses `.id` (transparent). |
| Closure capture aliases of destructured `peer` flow into untyped contexts | Inventory found 8 destructure sites; all body uses are `.id` access or pass-through to completion calls (whose signature also migrates). |
| Build cascade through AccountContext consumers | AccountContext is foundational. The enum + computed property changes cascade ALL consumers. Build cost projection: 60-180s. |
| `case let .user(peer)` rebinding shadow at L849 | The outer `peer` (EnginePeer?) is shadowed by the inner `peer` (TelegramUser). Inner body uses `peer.firstName`, `peer.lastName`, `peer.phone` — all TelegramUser fields. No reference to the outer EnginePeer? inside the if-body. Safe. |
| `.flatMap(EnginePeer.init)` simplification leaves wrong type | After migration, destructured `peer: EnginePeer?`. `.flatMap(EnginePeer.init)` would re-wrap to `EnginePeer?` (a no-op). Dropping is safe. |
| Pre-existing `import Postbox` removable from any of the 5 touched files | `import Postbox` should NOT be dropped speculatively — these files use Postbox for unrelated symbols (most consumers retain `Peer` references for non-DeviceContactInfoSubject paths). Defer Postbox-import drops to dedicated cleanup waves. |

## Wave shape

**Classification:** wave-91-pattern multi-module enum-payload + callback-signature migration.
**Iteration budget:** 1-3 (target 1; wave 91 took 2; this wave is similar size, slightly more complex).
**Subagent dispatch:** not needed — 17 edits in 5 files is single-implementer scope, but coordinator should review the diff carefully before commit given multi-module footprint.

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

`--continueOnError` flag enabled given multi-module scope — surface all errors at once if iter-1 fails.

### Post-edit residue grep (expect specific patterns)

```sh
# Construction-site _asPeer drops complete:
grep -nE "subject:\s*\.(vcard|filter|create)\(.*_asPeer\(\)" \
  submodules/PeerInfoUI/Sources/DeviceContactInfoController.swift \
  submodules/TelegramUI/Components/Stories/StoryContainerScreen/Sources/StoryItemSetContainerViewSendMessage.swift \
  submodules/TelegramUI/Sources/OpenChatMessage.swift
# Expected: empty.

# Completion _asPeer drops complete:
grep -nE "completion\(.*_asPeer\(\)" submodules/PeerInfoUI/Sources/DeviceContactInfoController.swift
# Expected: empty.

# .flatMap(EnginePeer.init) simplifications complete in DeviceContactInfoController:
grep -nE "peer\.flatMap\(EnginePeer\.init\)" submodules/PeerInfoUI/Sources/DeviceContactInfoController.swift
# Expected: empty.

# Downcast rewrite complete:
grep -nE "peer as\? TelegramUser" submodules/PeerInfoUI/Sources/DeviceContactInfoController.swift
# Expected: empty.

# ADD wraps present at the 2 Chat sites:
grep -nE "peerAndContactData\.0\.flatMap\(EnginePeer\.init\)" submodules/TelegramUI/Sources/ChatControllerOpenAttachmentMenu.swift
# Expected: 2 lines (683 and 1850, line numbers may shift slightly).
```

## Net delta projection

| Category | Count | Sites |
|---|---|---|
| `_asPeer()` drops at construction | −5 | DeviceContactInfoController:1289, 1443, 1489 + StoryItemSetContainerViewSendMessage:2132 + OpenChatMessage:443 |
| `_asPeer()` drops at completion calls | −2 | DeviceContactInfoController:1105, 1224 |
| `.flatMap(EnginePeer.init)` simplifications | −3 | DeviceContactInfoController:942, 944, 946 |
| `EnginePeer.init` wraps added (Pattern E) | +2 | ChatControllerOpenAttachmentMenu:683, 1850 |
| Downcast → case-let conversions | +1 | DeviceContactInfoController:849 |
| Type annotations migrated | 4 | AccountContext: 3 enum cases + 1 computed property |

**Net wrap delta:** **−8** (10 drops minus 2 adds).

## Out of scope

- `import Postbox` drops in any of the 5 touched files — they use Postbox for unrelated symbols. Defer to dedicated cleanup waves.
- Migrating the `peerAndContactData` upstream signal type from `(Peer?, DeviceContactExtendedData?)` to `(EnginePeer?, ...)` — would drop the 2 ADD bridges at Chat sites but cascades into multiple closures. Separate wave.
- `addContactToExisting`'s internal completion call sites — already typed `(EnginePeer?, ...)` per L1409, no migration needed in this wave.

## Memory file update

After landing, update `project_postbox_refactor_next_wave.md`:
- Add wave 105 outcome line into the recent-waves section.
- Mark `DeviceContactInfoSubject` candidate as drained.
- Note the wave-91-shape success — multi-module enum-payload migrations remain viable when pre-flight inventory clears layers 1-4.
