# Postbox → TelegramEngine refactor — log

This file is the historical record of the Postbox → TelegramEngine refactor. It is **not loaded by default** into AI sessions (only `CLAUDE.md` is). Read this file when you need wave-specific context, a full worked example of a pattern, or the running tally of module Postbox-freeness.

The short, actively-maintained rules and references live in `CLAUDE.md` under the "Postbox → TelegramEngine refactor" section. This file holds the narrative backstory, verbose example scripts, and per-wave outcomes that would otherwise bloat every AI session's context.

---

## Wave-selection guidance — full versions

The following subsections are trimmed to terse bullets in `CLAUDE.md`. Full versions (rule + backstory + scripts + per-wave examples) live here.

### Shape-selection backstory

The "leaf module, drop Postbox in isolation" approach only works for modules whose **public API doesn't leak Postbox domain types**. Most candidate leaf modules DO leak such types (`postbox: Postbox` / `account: Account` in public inits, `Media`/`Message` in public function parameters). Those modules need paired caller-migration waves, not isolated refactors.

Before selecting a wave's module list, grep each candidate for:
- `:\s*Postbox\b`, `:\s*Account\b`, `:\s*MediaBox\b` in public signatures → abandon candidate
- `Media`/`Message` as public parameter types → likely needs paired wave with callers

### Inventory at execution time, not just planning time

**Inventory at execution time, not just planning time.** Wave 2's `SaveToCameraRoll` task was planned from a narrow grep that only matched `MediaResource`/`TelegramMediaResource` and missed three `postbox: Postbox` public-function leaks plus multiple `postbox.mediaBox.*` bodies. Planning-time inventory should grep the full set `\b(postbox|mediaBox|transaction|PostboxView|combinedView|MediaResource|PostboxDecoder|PostboxEncoder|MemoryBuffer)\b|^import Postbox` over the module's Sources, not just the tokens specific to that wave's goal. If the planning inventory under-counts, the executor should re-inventory at Task-1 time and abandon early before editing code.

### Two feasible wave shapes

**Two feasible wave shapes.** Wave 1 tried "per-module Postbox drop". Wave 2 tried "per-engine-facade-API migrate MediaResource to EngineMediaResource (modify in place, update all call sites in one commit)". The second shape worked well: narrow, clean commits, no abandonment cascade. Prefer it when the refactor target is an API surface that multiple consumer modules depend on.

### Enum-payload migrations need a full case-site grep

**Enum-payload migrations need a full case-site grep, not just a facade call-site grep.** If a wave changes the payload type of a public enum (wave 4 changed `UploadStickerStatus.complete`'s payload from `CloudDocumentMediaResource` to `EngineMediaResource`), inventory ALL construction and destructure sites of the enum across TelegramCore, not just call sites of the facade that returns it. Wave 4's plan undercounted by 6 consumer sites inside `ImportStickers.swift` itself (3 shortcut `.complete(...)` constructions in guard branches, 3 destructure+field-access sites using `CloudDocumentMediaResource`-specific members). For enum-payload waves, grep `case \.|let \.|\.<caseName>\(` over the enum's defining module before execution and add those sites to the plan.

### Unused-import sweeps are a valid wave shape

**Unused-import sweeps are a valid wave shape.** After a round of facade migrations, consumer files accumulate `import Postbox` lines whose last semantic use was removed. Periodically sweep these:

1. `grep -rl "^import Postbox$" submodules --include="*.swift" | grep -vE "/(TelegramCore|Postbox|TelegramApi)/"` generates the candidate list.
2. `sed -i '' '/^import Postbox$/d' <file>` (BSD `sed`) speculatively drops the import from every candidate.
3. Run the full build **with `--continueOnError`** — without `--keep_going`, bazel stops at the first failing target and surfaces only a few errors per iteration. `Make.py` forwards `--continueOnError` to `--keep_going`; always use it.
4. Each iteration: extract failing files via `grep -E "^submodules/.*\.swift:[0-9]+:[0-9]+: error:" <build-out> | awk -F: '{print $1}' | sort -u`, restore via `git checkout -- <file>`, rebuild.
5. The dependency graph has many layers (wave 6 needed ~18 rebuilds to reach a clean build). Per-iteration failures shrink roughly: 18 → 4 → 5 → 3 → 12 → 4 → 13 → 9 → 11 → ... Accelerate by doing **pattern-based preemptive restores** after the first few iterations: scan still-dropped files for tokens that are definitively Postbox-only (`MediaBox`, `PostboxCoding`, `PostboxDecoder`, `PostboxEncoder`, `TempBoxFile`, `ValueBoxKey`, `Postbox\b`, `PeerId`, `MessageId`, `MediaId`, `MessageIndex`, `MessageAndThreadId`, `PeerNameIndex`, etc. — note that CLAUDE.md's "engine typealias cheat sheet" arrows are migration targets, **not** typealiases in TelegramCore — `PeerId` etc. are still raw Postbox types and files using them need `import Postbox`) and restore those files in bulk.
6. Only restore files from the candidate set. If errors surface in `TelegramCore`, `Postbox`, or `TelegramApi`, halt — the sweep has cascaded beyond its scope.
7. Commit the surviving drops as one atomic commit.

Tally impact from a sweep: dozens of consumer modules can become Postbox-free in a single commit. First run (wave 6): 782 candidates, 18 iterations, 183 survivors, **189 modules** newly Postbox-free. Re-run after every 2-3 facade-migration waves.

### Public-Postbox-type inventory (wave-11-pattern planning)

**Public-Postbox-type inventory (wave-11-pattern planning).** For wave-11-shape candidates (modules whose public init takes `postbox: Postbox, network: Network` purely for avatar/setPeer forwarding), grepping only for `Postbox`/`Network` tokens **undercounts** — public-surface types defined in Postbox can leak without ever naming "Postbox" literally. Wave 16 hit this: the plan missed `EngineMessageHistoryThread.Info?` and `PeerStoryStats?`, both Postbox-defined types whose names don't include "Postbox". Mitigation: build a Postbox-defined-public-types allowlist once, then grep the candidate module against it.

```bash
# Build allowlist once (or re-run if Postbox sources change):
grep -rhE "^public\s+(class|struct|enum|protocol|typealias)\s+\w+" submodules/Postbox/Sources/ \
  | awk '{print $3}' | sed 's/[(:<].*//' | sort -u > /tmp/postbox-public-types.txt

# Then, for each candidate module, grep its sources for any of those names:
grep -rhoE "\b($(cat /tmp/postbox-public-types.txt | tr '\n' '|' | sed 's/|$//'))\b" \
  submodules/<CandidateModule>/Sources/ | sort -u
```

Any hit in a public-surface position (field type, init param type, enum payload type, generic arg) that isn't already a documented typealias is a blocker. "Engine"-prefixed types can still be Postbox-defined — don't trust naming conventions, grep for the defining module. If the module hits only `Postbox` itself (i.e., literal `Postbox`/`Network` pair), it's a clean wave-11 candidate. Otherwise, decide per leak: (a) move the type to TelegramCore if it's a namespace-only class (wave 16a pattern — prototype: `EngineMessageHistoryThread`), (b) accept that the module can't become Postbox-free and ship a partial `engine:`/`stateManager:` collapse that keeps `import Postbox` (wave 16b pattern — `PeerStoryStats` is too baked into Postbox views to move cleanly), (c) abandon the candidate.

### Wave-shape G: facade addition + consumer sweep in one commit

**Wave-shape G: facade addition + consumer sweep in one commit.** Validated at scale across waves 19-26. Six consecutive sessions migrated ~95 consumer sites and added ~15 mediaBox facades, all with clean first-pass builds (exception: wave 26 needed a second pass to add `import RangeSet`). Shape recipe:

1. **Target:** a `MediaBox` (or similar Postbox type) method where Postbox's signature uses clean leaf types (`MediaResourceId`, `Data`, `String`, `Bool`) and the return type is either non-Postbox or has an existing `Engine*` wrapper.
2. **Pre-flight inventory:** grep `context\.account\.postbox\.mediaBox\.<methodName>` over `submodules/` (excluding TelegramCore/Postbox/TelegramApi). Classify each hit:
   - **Shape A**: `context.account.postbox.mediaBox.X(...)` → migratable.
   - **Shape B**: `context.account.postbox.mediaBox.X(id: ...)` (different overload) → migratable with identical pattern.
   - **Shape C**: `account.postbox.mediaBox.X(...)` where `account: Account` is a local (not `AccountContext`) → skip this wave (needs per-module rework).
   - **Shape D**: `self.postbox.mediaBox.X(...)` where `postbox: Postbox` is a stored field → skip this wave.
   - Plus: check for `accountManager.mediaBox.X(...)` which is Account-manager-scoped, a different migration path entirely. Never migrate via `TelegramEngine.Resources.*`.
3. **Facade design rules:**
   - Signatures take `EngineMediaResource.Id` (`MediaResourceId` aliased at call site via `EngineMediaResource.Id(x.id)`) or `EngineMediaResource` (wraps `resource` when the Postbox overload takes a resource with members accessed via `.id`).
   - Parameters with `Bool` defaults (`synchronous: Bool = false`) preserve defaults on the facade.
   - Return types: prefer `Void`, `String`, `String?`, `Signal<T, NoError>` where `T` is a non-Postbox type or an `Engine*` wrapper. Where Postbox return types are wrapped (e.g., `Signal<MediaResourceData, NoError>` → `Signal<EngineMediaResource.ResourceData, NoError>`), confirm the `Engine*` wrapper exists and decide whether consumer-side field-access rewrites are acceptable for the wave.
4. **WIP interference check:** before starting, `git status --short | grep -v "^??"` to list modified files. If any Shape-A site is in a WIP file, either skip those sites (document the skip in the outcome) or wait for the WIP to commit. Wave 23 hit this in `ChatMessageInteractiveMediaNode.swift`.
5. **Name collision check:** if a facade return type names a Swift stdlib type that has availability restrictions (e.g., `RangeSet` — iOS 18+), verify the third-party module import is present in `TelegramEngineResources.swift`. Wave 26 needed `import RangeSet`.
6. **Replace_all usage:** for files with duplicate identical call text, `replace_all=true` on the exact call expression (without leading whitespace) batches the migration. When leading whitespace varies across identical-call sites within a file, the tool still matches if the unchanged prefix (`context.account.postbox.mediaBox.X(...)`) is unique enough — but verify via post-edit grep.
7. **Cheapness:** ~5-50 sites per wave, single atomic commit, expected first-pass-clean build. If post-migration grep for `context\.account\.postbox\.mediaBox\.<methodName>` returns empty (exclude Shape-C/D) and build is green, commit.

---

## Wave 1 outcome (2026-04-16)

4 modules done: `ChatInterfaceState`, `ChatSendMessageActionUI`, `ContactListUI`, `DrawingUI`.
6 modules abandoned with recorded reasons in the wave-1 plan: `ActionSheetPeerItem`, `ChatListSearchRecentPeersNode`, `DirectMediaImageCache`, `FetchManagerImpl`, `GalleryData`, `ICloudResources`.

## Wave 2 outcome (2026-04-17)

5 `TelegramEngine` facades migrated to `EngineMediaResource` (signatures changed in place; `_internal_*` Postbox layer unchanged):
- `TelegramEngine.Peers.uploadedPeerPhoto`, `uploadedPeerVideo`, `updatePeerPhoto`
- `TelegramEngine.AccountData.updateAccountPhoto`, `updateFallbackPhoto`
- `TelegramEngine.Contacts.updateContactPhoto`
- `TelegramEngine.Auth.uploadedPeerVideo`

1 consumer submodule fully de-Postboxed: `MapResourceToAvatarSizes` (signature changed from `(postbox: Postbox, resource: MediaResource, …)` to `(engine: TelegramEngine, resource: EngineMediaResource, …)`; 27 call sites migrated).

1 consumer signal type swapped: `AuthorizationUI/AuthorizationSequenceController.swift` (`Signal<TelegramMediaResource?>` → `Signal<EngineMediaResource?>`).

1 task abandoned with recorded reason in the wave-2 plan: `SaveToCameraRoll` (full-module Postbox coupling, needs its own wave).

## Wave 3 outcome (2026-04-18)

3 thin forwarders added on `TelegramEngine.Resources` over `MediaBox`:
- `fetch(reference:userLocation:userContentType:)` → `Signal<FetchResourceSourceType, FetchResourceError>` (Postbox return types remain a documented accepted leak)
- `status(resource: EngineMediaResource)` → `Signal<EngineMediaResource.FetchStatus, NoError>`
- `data(resource: EngineMediaResource, pathExtension:, waitUntilFetchStatus:)` → `Signal<EngineMediaResource.ResourceData, NoError>` (takes a `Bool` rather than exposing `ResourceDataRequestOption`, per YAGNI)

1 consumer submodule fully de-Postboxed: `SaveToCameraRoll`. Public signatures changed from `(context:, postbox: Postbox, userLocation:, …)` to `(context:, userLocation:, …)`; `FetchMediaDataState.data` payload changed from `MediaResourceData` to `EngineMediaResource.ResourceData`; internals rewired through `context.engine.resources.*`. 23 call sites across 14 files migrated atomically with the module.

Pre-flight verified that `ShareController.swift:2406`'s `self.currentContext.stateManager.postbox` is equivalent to `context.account.postbox` in the `ShareControllerAppAccountContext` path (because `AccountStateManager` is constructed with the account's own `postbox`), so the `postbox:` argument could be dropped without behavior change.

No tasks abandoned. Shape validated: "per-engine-facade-API migration + full consumer module rewrite" (the wave-2 shape, scaled up to a full module drop).

Plan: `docs/superpowers/plans/2026-04-18-postbox-to-telegramengine-wave-3.md`

## Wave 4 outcome (2026-04-18)

1 `TelegramEngine` facade migrated in place to `EnginePeer` + `EngineMediaResource` (signature changed; `_internal_uploadSticker` keeps its raw `Peer`/`MediaResource` parameter list):

- `TelegramEngine.Stickers.uploadSticker(peer: Peer → EnginePeer, resource: MediaResource → EngineMediaResource, thumbnail: MediaResource? → EngineMediaResource?, …)`

1 public enum payload migrated: `UploadStickerStatus.complete(CloudDocumentMediaResource, String)` → `.complete(EngineMediaResource, String)`. `_internal_uploadSticker` wraps `EngineMediaResource(uploadedResource)` at its one `.complete(...)` result-construction site — a narrow, spec-allowed one-line deviation from "internal Postbox-facing stays raw", taken to keep `UploadStickerStatus` as a single public enum.

**Plan-time inventory undercount** — worth recording as a lesson. The spec and plan enumerated 2 external call sites and 1 internal construction site. Execution uncovered 6 additional consumer sites inside `ImportStickers.swift` itself that also needed adapting: 3 shortcut `.complete(...)` construction sites (lines 204, 371, 492, each emitting `.complete(CloudDocumentMediaResource, String)` directly from `as? CloudDocumentMediaResource` guards) and 3 destructure sites (lines 216, 384, 505) that accessed `CloudDocumentMediaResource`-specific fields. Each construction site now wraps via `EngineMediaResource(resource)`; each destructure site unwraps with `let rawResource = resource._asResource() as? CloudDocumentMediaResource`. MediaEditorScreen's two `stickerFile(resource:)` calls also needed `as! TelegramMediaResource` casts because `_asResource()` returns the Postbox `MediaResource` protocol while `stickerFile` takes the TelegramCore `TelegramMediaResource` sub-protocol. **Future planning-time inventory for enum-payload migrations should grep not only call-sites of the facade but every `case .complete` / `case let .complete` of the migrated enum across the whole TelegramCore source tree.**

2 external call sites migrated atomically with the facade:
- `submodules/ImportStickerPackUI/Sources/ImportStickerPackController.swift:91` (plus a `peer: Peer → EnginePeer(peer)` wrap, since the local `peer` comes from `postbox.loadedPeerWithId(...)` which returns raw `Peer`)
- `submodules/TelegramUI/Components/MediaEditorScreen/Sources/MediaEditorScreen.swift:8099` (plus 6 cascading sites inside the enclosing block for the new `UploadStickerStatus.complete` payload)

No module becomes Postbox-free in this wave (both caller files import Postbox for unrelated reasons).

Plan: `docs/superpowers/plans/2026-04-18-postbox-to-telegramengine-wave-4.md`

## Wave 5 outcome (2026-04-18)

Completes the last explicitly-named future-wave candidate from the wave-2 final review.

`uploadSecureIdFile(context: SecureIdAccessContext, postbox: Postbox, network: Network, resource: MediaResource)` migrated in place to `(context:, engine: TelegramEngine, resource: EngineMediaResource)`. Function body accesses raw Postbox types via `engine.account.postbox` / `engine.account.network` (internal Postbox-facing layer stays raw per the standing rule).

1 consumer submodule fully de-Postboxed: `SecureIdVerificationDocumentsContext` (PassportUI/Sources). Signature changed from `(postbox: Postbox, network: Network, context: SecureIdAccessContext, update: ...)` to `(engine: TelegramEngine, context: SecureIdAccessContext, update: ...)`; stored props collapsed into a single `engine: TelegramEngine` field. One instantiation site updated in the same commit.

After this wave, the "Known future-wave candidates" list contains only the 4 permanently-blocked classes conforming to `TelegramMediaResource`.

Plan: `docs/superpowers/plans/2026-04-18-postbox-to-telegramengine-wave-5.md`

## Wave 6 outcome (2026-04-19)

First build-verified unused-import sweep. Ran the speculative-drop + build-verify methodology (see "Unused-import sweeps" under Wave-selection guidance above): dropped `import Postbox` from all 782 consumer files where a plain `^import Postbox$` line appeared, iterated 18 full builds with `--continueOnError`, restoring imports on files that failed to compile.

**183 drops survived** (single atomic commit `7b2b74e79b`, 0 insertions / 183 deletions). **189 modules** transitioned to Postbox-free status — full list is inferable by running the methodology's module-scan against HEAD. Representative additions spanning alphabetically: `AccountUtils`, `ActivityIndicator`, `AdUI`, `AlertUI`, `AnimatedStickerNode`, `AppLock`, `AttachmentTextInputPanelNode`, `BotPaymentsUI`, `CalendarMessageScreen`, `CallListUI`, `Camera`, `ChatImportUI`, etc. The running tally below preserves the per-module enumeration only for the ~10 individually-documented waves 1–5 modules. Wave 6's 189 additions are not re-enumerated here because the size would overwhelm the doc; see `git show 7b2b74e79b --stat` for the per-file breakdown and `grep -rL "^(@_exported )?import Postbox" submodules/*/Sources --include="*.swift"` for the current per-module status.

Deviation from plan: the plan capped at 3 iterations; execution needed 18 because the dependency graph is deep and each bazel build surfaces only the currently-compilable layer. Pattern-based preemptive restores (using the symbol list in the "Unused-import sweeps" guidance) were used from iteration 9 onward to accelerate convergence from iteration-by-iteration single-file restores to bulk restores. No unexpected path cascades; no abandoned state.

Plan: `docs/superpowers/plans/2026-04-19-postbox-to-telegramengine-wave-6.md`

## Wave 7 outcome (2026-04-20)

Closed out the seven remaining raw-Postbox leaks in `TelegramEngine.*` public facades surfaced by a post-wave-6 scouting pass. Single atomic commit, one full build, zero abandonment.

Seven `TelegramEngine` facades migrated in place (all `_internal_*` implementations kept raw per the standing rule):

**Messages (3):**
- `downloadMessage(messageId:)` — return `Signal<Message?, NoError>` → `Signal<EngineMessage?, NoError>`. Return-side wrap via `|> map { $0.flatMap(EngineMessage.init) }`.
- `topPeerActiveLiveLocationMessages(peerId:)` — return `Signal<(Peer?, [Message]), NoError>` → `Signal<(EnginePeer?, [EngineMessage]), NoError>`. Return-side tuple wrap.
- `getSynchronizeAutosaveItemOperations()` — **deleted**. Dead facade: sole caller (`StoreDownloadedMedia.swift`) already bypassed it by calling `_internal_getSynchronizeAutosaveItemOperations` directly inside its own transaction block.

**Peers (1):**
- `updatedRemotePeer(peer:)` — return `Signal<Peer, UpdatedRemotePeerError>` → `Signal<EnginePeer, UpdatedRemotePeerError>`. `PeerReference` param kept as-is (no `EnginePeer.Reference` alias today). The sole call site in `ChannelAdminsController.swift` uses `ignoreValues`, so no caller change was needed.

**Resources (4):**
- `renderStorageUsageStatsMessages(…existingMessages:)` — `[EngineMessage.Id: Message]` → `[EngineMessage.Id: EngineMessage]` on both sides. Facade unwraps input via `.mapValues { $0._asMessage() }`, wraps output via `.mapValues(EngineMessage.init)`.
- `clearStorage(peerId:categories:includeMessages:excludeMessages:)` — `[Message]` → `[EngineMessage]`. Facade unwraps via `.map { $0._asMessage() }`.
- `clearStorage(peerIds:includeMessages:excludeMessages:)` — same shape.
- `clearStorage(messages:)` — same shape. No external callers; migrated for overload-set consistency.

**Consumer call-site updates** (5 files):
- `ChatListUI/Sources/ChatListSearchListPaneNode.swift`: dropped now-redundant `.flatMap(EngineMessage.init)` wrap at the `downloadMessage` call site.
- `LocationUI/Sources/LocationViewControllerNode.swift`: dropped now-redundant `.map(EngineMessage.init)` at the `topPeerActiveLiveLocationMessages` call site.
- `LiveLocationManager/Sources/LiveLocationSummaryManager.swift`: dropped redundant `EnginePeer(author)` / `EngineMessage(message)` construction (`author`, `message` are now already `EnginePeer` / `EngineMessage`).
- `TelegramUI/Components/StorageUsageScreen/Sources/StorageUsageScreen.swift`: bridged at 4 facade-call points (1 `renderStorageUsageStatsMessages`, 2 `clearStorage` overloads with message arrays; the `includeMessages: [], excludeMessages: []` site at line 3038 needed no change as empty arrays infer to `[EngineMessage]` just as well).

**Minimal-scope bridging.** `StorageUsageScreen.swift` still has 43 raw `Message`/`MessageId` references inside its `AggregatedData` helper class and surrounding logic — not touched in this wave. A future "StorageUsageScreen full de-Postbox" wave would drop those (migrate `AggregatedData.messages: [MessageId: Message]` → `[EngineMessage.Id: EngineMessage]`, `clearIncludeMessages: [Message]` → `[EngineMessage]`, etc.) and potentially drop `import Postbox`. Out of scope here.

**No modules became Postbox-free in this wave** — all five touched consumer files still import Postbox for reasons unrelated to the migrated facades.

Plan / record: `docs/superpowers/plans/2026-04-20-postbox-to-telegramengine-wave-7.md`.

After this wave, the "Known future-wave candidates" list contains only the 4 permanently-blocked classes conforming to `TelegramMediaResource`. The full public `TelegramEngine.*` facade surface is now engine-typed (modulo those four types).

## Wave 8 outcome (2026-04-20)

`StorageUsageScreen` consumer-module migration of raw `Message` domain types to `EngineMessage`. Scope explicitly narrower than a full de-Postbox: two files touched, module remains `import Postbox` due to two out-of-scope site clusters.

**Types migrated:**
- `StorageFileListPanelComponent.Item.message: Message` → `EngineMessage` (item type co-located with the panel component).
- `StorageUsageScreen.Component.AggregatedData.messages: [MessageId: Message]` → `[EngineMessage.Id: EngineMessage]`; `.clearIncludeMessages` / `.clearExcludeMessages: [Message]` → `[EngineMessage]`. Init param updated to match.
- `StorageUsageScreen.Component.SelectionState.togglePeer(availableMessages:)` param: `[EngineMessage.Id: Message]` → `[EngineMessage.Id: EngineMessage]`.
- `StorageUsageScreen.Component.RenderResult.messages: [MessageId: Message]` → `[EngineMessage.Id: EngineMessage]`.
- `openMessage(message: Message)` → `openMessage(message: EngineMessage)` (external `OpenChatMessageParams.message` / `chatMediaListPreviewControllerData(message:)` calls unwrap via `message._asMessage()` at the two call sites — those APIs still take raw `Message`).

**Wave-7 facade-boundary bridging dropped:** the `renderStorageUsageStatsMessages` call-site's `(…).mapValues(EngineMessage.init)` / `.mapValues { $0._asMessage() }` bridges and the two `clearStorage` call sites' `.map(EngineMessage.init)` wraps all vanish — `AggregatedData.messages` / `.clearIncludeMessages` / `.clearExcludeMessages` are now engine-typed and pass through the facade unchanged. Inside the `AggregatedData.updateSelected...` selected-messages accumulation loop, four `item.message._asMessage()` calls (for imageItems, which hold EngineMessage) drop back to plain `item.message` since the target array is now `[EngineMessage]`. And `StorageMediaGridPanelComponent.Item(message: EngineMessage(message), …)` drops the `EngineMessage(…)` wrap since `message` is already `EngineMessage`.

**Out of scope — future-wave candidates (module still imports Postbox):**
- `StorageUsageScreen.swift:1047-1062` and `3131-3185`: preferences-view observation of `AccountSpecificCacheStorageSettings` via `postbox.combinedView` + `PreferencesView`, and a `postbox.transaction { transaction in transaction.getPeer / transaction.getPeerCachedData as? CachedGroupData / CachedChannelData }` block classifying peer-storage-timeout exceptions. Substantial: requires `EngineData`-subscription rewrite for the preferences observation, plus engine-API equivalents for peer-category classification + cached-data subscriber counts.
- `StorageFileListPanelComponent.swift:105`: `Icon.media(Media, TelegramMediaImageRepresentation)` enum case, constructed only as `.media(TelegramMediaFile, …)` or `.media(TelegramMediaImage, …)` (both TelegramCore types). Trivial future wave: split into `.mediaFile(TelegramMediaFile, …)` / `.mediaImage(TelegramMediaImage, …)`, drop `import Postbox`.

Single atomic commit. Build verified green (59s incremental build, 27 actions). Net −11 lines in `StorageUsageScreen.swift` (simplification).

Plan / record: `docs/superpowers/plans/2026-04-20-postbox-to-telegramengine-wave-8.md`.

## Wave 9 outcome (2026-04-20)

Closes the first of the two "future-wave candidates" left open by wave 8: rewrites both `AccountSpecificCacheStorageSettings` preferences-view observation sites in `StorageUsageScreen.swift` using engine APIs, and drops `import Postbox` from that file.

**Site 1 — `cacheSettingsExceptionCount` signal** (former lines 1047–1087):
- `postbox.combinedView(keys: [.preferences(keys: Set([PreferencesKeys.accountSpecificCacheStorageSettings]))])` + `PreferencesView` extraction →
  `context.engine.data.subscribe(TelegramEngine.EngineData.Item.Configuration.ApplicationSpecificPreference(key: PreferencesKeys.accountSpecificCacheStorageSettings))` + `preferencesEntry?.get(AccountSpecificCacheStorageSettings.self) ?? .defaultSettings`.
- Downstream `EngineDataMap` + `EnginePeer` per-category counting logic unchanged (already engine-only).

**Site 2 — `peerExceptions` signal in `openKeepMediaCategory`** (former lines 3131–3196):
- Same preferences observation replacement as Site 1.
- `postbox.transaction { transaction.getPeer / transaction.getPeerCachedData as? CachedGroupData / CachedChannelData; FoundPeer(peer:subscribers:) }` → `context.engine.data.get(EngineDataMap(...TelegramEngine.EngineData.Item.Peer.Peer.init(id:)))` + pattern match on `EnginePeer.user / .secretChat / .legacyGroup / .channel`.
- Signal element type `[(peer: FoundPeer, value: Int32)]` → `[(peer: EnginePeer, value: Int32)]`. `FoundPeer` wrapper and its `subscribers` field dropped entirely — they were computed by the transaction block but never read by downstream consumers (the only consumer sites read `.isEmpty`, `.count`, and `.prefix(3).map { EnginePeer($0.peer.peer) }`).
- One downstream consumer updated: `peerExceptions.prefix(3).map { EnginePeer($0.peer.peer) }` → `.prefix(3).map { $0.peer }` at the `MultiplePeerAvatarsContextItem` construction (redundant wrap removed since `$0.peer` is already `EnginePeer`).

**Typealias fixup.** With `import Postbox` removed, `var mergedMedia: [MessageId: Int64]` at former line 2397 needed renaming to `[EngineMessage.Id: Int64]`. `MessageId` is the raw Postbox type name — CLAUDE.md's engine-typealias cheat sheet lists these as migration targets, not pre-existing aliases in TelegramCore. Caught by first-pass build failure (`cannot find type 'MessageId' in scope`).

**Reusable pattern.** `TelegramEngine.EngineData.Item.Configuration.ApplicationSpecificPreference(key: ValueBoxKey)` (at `TelegramCore/Sources/TelegramEngine/Data/ConfigurationData.swift:356`) is the general-purpose engine replacement for any `postbox.combinedView(keys: [.preferences(keys: Set([key]))]) + PreferencesView` idiom — takes any `ValueBoxKey`, returns `PreferencesEntry?`, decodes via `.get(T.self)`. Crucially, callers need not `import Postbox` even though `ValueBoxKey` is a Postbox type: passing `PreferencesKeys.<name>` through makes `ValueBoxKey` an inferred-only type that never gets named in the consumer module. Use this pattern when de-Postboxing any future module that observes preferences.

`StorageUsageScreen.swift` is now Postbox-free. The wave 8 outcome's other candidate (`StorageFileListPanelComponent.swift`'s `Icon.media(Media, ...)` enum case) remains — trivial future wave to split into `.mediaFile(TelegramMediaFile, ...)` / `.mediaImage(TelegramMediaImage, ...)` cases, at which point the `StorageUsageScreen` consumer module as a whole becomes Postbox-free.

Net: 1 file changed, +30 / -54. Build verified green (27 actions, cached).

Plan / record: `docs/superpowers/plans/2026-04-20-postbox-to-telegramengine-wave-9.md`.

## Wave 10 outcome (2026-04-20)

Closes the second (and last) future-wave candidate from wave 8: eliminates `StorageFileListPanelComponent.swift`'s `Icon.media(Media, TelegramMediaImageRepresentation)` enum case. **`StorageUsageScreen` (the module as a whole) is now fully Postbox-free** — the other in-module file (`StorageUsageScreen.swift`) landed in wave 9.

**Split the enum case.** `Icon.media(Media, TelegramMediaImageRepresentation)` → two concrete cases `case mediaFile(TelegramMediaFile, TelegramMediaImageRepresentation)` + `case mediaImage(TelegramMediaImage, TelegramMediaImageRepresentation)`. Lossless split: the two construction sites already knew the concrete subtype (`imageIconValue = .media(file, representation)` from a `as? TelegramMediaFile` branch, `.media(image, representation)` from a `as? TelegramMediaImage` branch), and the consumer binding site immediately downcast via `as?` to pick which `setSignal(...)` flavor to call. New split removes the downcast; exhaustiveness-checked switch is both safer and terser.

**Equatable rewritten.** Old: manual outer-`switch` + inner `if case` dispatch, comparing media by `media.id` only. New: switch-over-tuple `(lhs, rhs)` with id-based equality per concrete type (`lFile.fileId == rFile.fileId`, `lImage.imageId == rImage.imageId`). Same id-based equality semantics as before.

**Binding-site rewrite.** Old: `if case let .media(media, representation) = component.icon { ... if let file = media as? TelegramMediaFile { ... } else if let image = media as? TelegramMediaImage { ... } }`. New: a compound case-binding pattern `case let .mediaFile(_, representation), let .mediaImage(_, representation):` lifts the shared `representation` variable, then an inner switch dispatches to the right `setSignal` branch. Works because both cases carry the same `TelegramMediaImageRepresentation` payload type; Swift allows compound case patterns when the bindings have identical types.

**Placeholder `PeerId(...)` construction fixup.** Second-pass build failure after dropping `import Postbox` surfaced a placeholder `PeerId(namespace: PeerId.Namespace._internalFromInt32Value(0), id: PeerId.Id._internalFromInt64Value(0))` in the `measureItem` layout-measurement instance at former line 1062. Naming `PeerId`, `PeerId.Namespace`, and `PeerId.Id` all require `import Postbox` (these are raw Postbox types, not TelegramCore typealiases — consistent with wave 9's `MessageId` → `EngineMessage.Id` fixup). Replaced with `component.context.account.peerId` (a real `EnginePeer.Id` already in scope). Semantically equivalent since the measurement instance's `messageId` is only used for `.peerId` extraction inside image-fetch `userLocation` and for Equatable comparison (the measurement instance isn't compared to anything).

**Lesson.** Placeholder `PeerId(...)` / `MessageId(peerId:...)` constructions in layout-measurement code are a recurring trap for de-Postbox work. Common pattern in this codebase: construct a dummy component instance purely to call `.update(...)` and read back the returned size. The dummy values are not used meaningfully but naming the types pins `import Postbox`. When de-Postboxing, grep for `PeerId(namespace:`/`MessageId(peerId:` with all-zero args and replace with any convenient real value in scope (`context.account.peerId` is almost always available).

Net: 1 file changed, +22 / -29 lines (−7 simplification — new switch-over-tuple Equatable is both terser and more idiomatic).

Plan / record: `docs/superpowers/plans/2026-04-20-postbox-to-telegramengine-wave-10.md`.

## Wave 11 outcome (2026-04-20)

Revisits `ActionSheetPeerItem` — one of the six wave-1 abandonments. The wave-1 blocker was that the public init took `postbox: Postbox` + `network: Network` explicitly, forcing the module to `import Postbox`, and the sole external caller (ShareController, out-of-wave at the time) couldn't be edited. This wave resolves the blocker without any rule-2 violation by routing the pair through `AccountStateManager`.

**Init-surface collapse.** `ActionSheetPeerItem.init(accountPeerId:postbox:network:contentSettings:peer:…)` → `.init(accountPeerId:stateManager:contentSettings:peer:…)`. `AccountStateManager` is a TelegramCore public class whose public API surface includes `postbox: Postbox` and `network: Network` fields; passing the manager as a single handle lets the module hold on to the two values without ever naming `Postbox` in its own source. The setItem call site becomes `self.avatarNode.setPeer(…, postbox: item.stateManager.postbox, network: item.stateManager.network, …)` — Swift's type inference resolves `Postbox` through transitive module visibility (TelegramCore → AvatarNode), no `import Postbox` needed in the consumer.

**Convenience init unchanged in shape.** The `(context: AccountContext, …)` convenience delegates to `(accountPeerId:stateManager:contentSettings:…)`; the two callable forms stay aligned.

**Caller (`ShareController.swift:1146`).** Dropped `postbox: info.account.stateManager.postbox, network: info.account.stateManager.network` → single `stateManager: info.account.stateManager`. `ShareControllerAccountContext` (the per-switchable-account protocol) already exposes `stateManager: AccountStateManager`, so this is a collapse, not a signature divergence. ShareController continues to import Postbox for its own unrelated reasons; no change to its dependency profile.

**Reusable pattern.** For any wave-1-style module that was abandoned because a public init takes `postbox: Postbox, network: Network` with avatar-rendering downstream: collapse to `stateManager: AccountStateManager` (TelegramCore type) and unpack inside the setItem/setPeer body. The pattern applies broadly — most wave-1 abandonments used this param-pair for avatar setup. Candidates to try next: `ChatListSearchRecentPeersNode`, `HorizontalPeerItem`, `SelectablePeerNode`, `ItemListPeerItem`, `ItemListAvatarAndNameInfoItem`, `ItemListStickerPackItem` (verify each by grep first — some may use `postbox` for non-avatar reasons).

Net: 3 files changed, +8 / -15 lines. Build green (5854 actions, ~6min).

Plan / record: (no plan doc this wave — single-module, low-complexity).

## Wave 12 outcome (2026-04-20)

Applies the wave-11 `stateManager: AccountStateManager` collapse pattern to `HorizontalPeerItem` — another wave-1-era candidate whose public init leaked `postbox: Postbox, network: Network`. Additionally ripples the collapse one layer up into `ChatListSearchRecentPeersNode`'s public init so the `HorizontalPeerItem` call site has `stateManager:` in scope.

**`HorizontalPeerItem` fully Postbox-free.** `init(postbox: Postbox, network: Network, …)` + matching stored fields → `init(stateManager: AccountStateManager, …)` + `let stateManager`. SelectablePeerNode.setup call site routes via `item.stateManager.postbox` / `.network`. Module drops `import Postbox` and `//submodules/Postbox:Postbox` dep.

**`ChatListSearchRecentPeersNode` public surface migrated, module still imports Postbox.** Public `init(accountPeerId:postbox:network:…)` → `init(accountPeerId:stateManager:…)`. Two private helpers (`item(…)` on `ChatListSearchRecentPeersEntry` and `preparedRecentPeersTransition(…)`) get the same collapse for forwarding. Internal uses of raw postbox (`_internal_recentPeers`, `postbox.peerView`, `postbox.combinedView`, `_internal_managedUpdatedRecentPeers`) rewritten to `stateManager.postbox` / `stateManager.network` — the module stays on `import Postbox` because of `PostboxViewKey` / `UnreadMessageCountsItem` / `UnreadMessageCountsView` usage inside the peerViews-to-unread-counts pipeline. That pipeline could be rewritten against `EngineDataMap` + `TelegramEngine.EngineData.Item.Peer.Notifications.*` in a future wave, but the public surface simplification is valuable standalone.

**Two external caller sites migrated:**
- `ShareController/Sources/ShareControllerRecentPeersGridItem.swift:66-67` — `postbox: context.stateManager.postbox, network: context.stateManager.network` → `stateManager: context.stateManager` (ShareControllerAccountContext protocol already exposes `stateManager`).
- `ChatListUI/Sources/ChatListRecentPeersListItem.swift:125-126` — `postbox: item.context.account.postbox, network: item.context.account.network` → `stateManager: item.context.account.stateManager`.
- `SettingsUI/Sources/DeleteAccountPeersItem.swift:51-52` (call site for `HorizontalPeerItem`) — `postbox: context.account.postbox, network: context.account.network` → `stateManager: context.account.stateManager`.

**Lesson reinforcement.** The wave-11 collapse pattern is very cheap to ripple through intermediate owners. Whenever a consumer module takes `(postbox:Postbox, network:Network)` purely to forward them to another call downstream, collapse to `stateManager: AccountStateManager` — no propagation fan-out required for the raw pair because the stateManager is a single handle. Even when the intermediate owner itself uses raw `postbox.peerView` internally (like this wave's `ChatListSearchRecentPeersNode`), the public surface still gets the collapse at zero cost.

Net: 6 files changed, +26 / -36 lines. Build verified green (incremental, 136 actions).

Plan / record: (no plan doc this wave — pattern-application, low-complexity).

## Wave 13 outcome (2026-04-20)

Targeted `AttachmentTextInputPanelNode` at the user's request. On inspection, the module was already Postbox-free at the source level (swept in wave 6) — its two `.swift` files compile fine without `import Postbox`. Two leftover items were fixed:

1. **Dead `//submodules/Postbox:Postbox` BUILD dep** — wave 6 swept `^import Postbox$` lines from source but never touched BUILD files. `AttachmentTextInputPanelNode/BUILD` (and, it turns out, 97 other modules' BUILDs — see wave 14) still listed the dep despite no source file needing it. Removed.
2. **Two raw `peerId?.namespace == Namespaces.Peer.SecretChat` checks** (lines 436, 2102) migrated to use the existing `PeerId.isSecretChat` extension at `submodules/TelegramCore/Sources/Utils/PeerUtils.swift:615`. (First-pass attempt introduced a duplicate `isSecretChat` extension and failed with "invalid redeclaration" — note for future waves: always grep TelegramCore for an existing helper before adding.)

**No new TelegramEngine methods/types introduced.** The refactor was smaller than anticipated; the module's migration debt had already been paid down by wave 6's source-level sweep. The BUILD-dep leftover and the namespace-equality sites were the only remaining items. Both are quality-of-life cleanups rather than structural migration.

**Observation that drove wave 14.** Wave 6's methodology-note in the "Unused-import sweeps" guidance only measured Postbox-freeness by `^import Postbox$` lines in sources. After touching `AttachmentTextInputPanelNode/BUILD` in this wave, I noticed many other wave-6-swept modules still carry dead BUILD deps, ~= the wave-6 survivor count. That's the whole of wave 14.

Net: 2 files changed, +2 / -3 lines.

Plan / record: (no plan doc this wave — discovery pass).

## Wave 14 outcome (2026-04-20)

Build-dep sweep analogous to wave 6's source-import sweep: drop `//submodules/Postbox:Postbox` (and `//submodules/Postbox`) from every BUILD whose source files no longer `import Postbox`.

**Methodology.**
1. For each `submodules/*/BUILD` referencing `submodules/Postbox`, check whether any `.swift` file in the module's `Sources/` tree has `^import Postbox$`.
2. If none do, speculatively drop the Postbox dep line from the BUILD via `sed -i '' -e '/^[[:space:]]*"\/\/submodules\/Postbox\(:Postbox\)\{0,1\}",[[:space:]]*$/d'`.
3. Full `Make.py build --continueOnError`.
4. Restore any BUILD that now fails to compile (none did).
5. Commit surviving drops.

**Result.** 98 candidate BUILDs identified. **Zero iterations needed** — first-pass build came up green (80 incremental actions, no restores). Net: 98 BUILD files, −98 lines (each lost exactly its `//submodules/Postbox` dep line).

**Why zero iterations.** Bazel Swift rules require source-level `import` for symbol resolution. If a module compiled after wave 6's `import Postbox` sweep, then none of its source files are physically referencing Postbox symbols. The BUILD-level dep was always redundant — it was carried for historical reasons (code likely once imported Postbox but was migrated off) but had no effect on either compilation or the actual dependency graph (Postbox is still transitively pulled in by TelegramCore, which every module depends on). Dropping it is a metadata cleanup with no semantic effect.

**Lesson / reusable pattern.**
- After every source-level `import Postbox` sweep (wave-6 shape), run a matching BUILD-dep sweep immediately. Same candidate set, near-zero execution risk, same commit.
- Script for identifying candidates:
  ```bash
  find submodules -name "BUILD" -type f | while read build; do
    dir=$(dirname "$build")
    if grep -q "submodules/Postbox" "$build" 2>/dev/null && [ -d "$dir/Sources" ]; then
      if ! grep -rq "^import Postbox$" "$dir/Sources" 2>/dev/null; then
        echo "$dir"
      fi
    fi
  done
  ```
- After waves 13+14, 194 modules still list `//submodules/Postbox` in BUILD — all of them have source files still importing Postbox.

Net (wave 14 alone): 98 files changed, 0 insertions / 98 deletions.

Plan / record: (no plan doc this wave — mechanical sweep).

## Wave 15 outcome (2026-04-20)

Applies the wave-11/12 `stateManager: AccountStateManager` collapse pattern to `SelectablePeerNode` — another wave-1-era candidate listed in the post-wave-14 shortlist. Module becomes fully Postbox-free (source + BUILD).

**`SelectablePeerNode` fully Postbox-free.** Two public setup methods migrated:
- `setup(accountPeerId: EnginePeer.Id, postbox: Postbox, network: Network, …)` → `setup(accountPeerId:, stateManager: AccountStateManager, …)`.
- `setupStoryRepost(accountPeerId: EnginePeer.Id, postbox: Postbox, network: Network, …)` → `setupStoryRepost(accountPeerId:, stateManager: AccountStateManager, …)`.

Internal forwards rewired: `AvatarNode.setPeer(…, postbox: stateManager.postbox, network: stateManager.network, …)` and `EmojiStatusComponent(postbox: stateManager.postbox, …)`. Neither site names `Postbox` in the consumer — Swift infers through transitive module visibility.

**Namespaces.Peer.SecretChat fixup (×3).** Replaced `peer.peerId.namespace == Namespaces.Peer.SecretChat` checks with `peer.peerId.isSecretChat` at three sites, matching the wave-13 pattern (`PeerId.isSecretChat` at `TelegramCore/Sources/Utils/PeerUtils.swift:611`). The third site (`updateSelection` in the not-selected branch) additionally needed an `?? false` fallback — previous expression was `self.peer?.peerId.namespace == Namespaces.Peer.SecretChat` (optional-equals-non-optional produces `Bool`), new expression is `(self.peer?.peerId.isSecretChat ?? false)`.

**Share-Extension boundary — `stateManager:` over `engine:`.** `SelectablePeerNode` is used by `ShareControllerPeerGridItem`, whose context is `ShareControllerAccountContext`. That protocol exposes `stateManager: AccountStateManager` and `engineData: TelegramEngine.EngineData`, but **no `engine: TelegramEngine`** — and the Share Extension's `ShareControllerAccountContextExtension` concrete impl has no `Account`, so constructing a full `TelegramEngine` (`init(account: Account)`) is physically unreachable there. This is the documented "rare but genuine" fallback to `stateManager:` from the user-preference memory (`feedback_postbox_refactor_handle.md`) — prefer `engine:` except when crossing the Share-Extension boundary.

**Three external call sites migrated:**
- `HorizontalPeerItem/Sources/HorizontalPeerItem.swift:227` (wave 12's `stateManager:` field now forwards directly): `postbox: item.stateManager.postbox, network: item.stateManager.network` → `stateManager: item.stateManager`.
- `ShareController/Sources/ShareControllerPeerGridItem.swift:237` (setup): `postbox: context.stateManager.postbox, network: context.stateManager.network` → `stateManager: context.stateManager`.
- `ShareController/Sources/ShareControllerPeerGridItem.swift:273` (setupStoryRepost): same.

**Convenience init unchanged.** `setup(context: AccountContext, …)` now delegates with `stateManager: context.account.stateManager`; signature unchanged — `JoinLinkPreviewPeerContentNode.swift:147` (the one caller using the convenience init) needed no edit.

Net: 4 files changed, +12 / -17 lines. Build verified green (193 actions, 131s — Telegram.ipa target built successfully).

Plan / record: (no plan doc this wave — pattern-application, low-complexity).

## Wave 16 outcome (2026-04-20)

Two-commit wave targeting `ItemListPeerItem`. Planning-time inventory (`project_postbox_wave16_plan.md`) only grepped for `Postbox`/`Network` tokens and missed two Postbox-defined public-surface types: `EngineMessageHistoryThread.Info?` (on `threadInfo`) and `PeerStoryStats?` (on `storyStats`). The first-pass "drop `import Postbox`" attempt failed at build time. Rather than abandon, the wave split into 16a (move `EngineMessageHistoryThread` to TelegramCore — clean, independently valuable) and 16b (partial `engine:` collapse on `ItemListPeerItem`, keeping `import Postbox` because `PeerStoryStats` remains Postbox-defined).

**Wave 16a — move `EngineMessageHistoryThread` to TelegramCore.** Before: Postbox declared an empty `public final class EngineMessageHistoryThread` namespace with a nested `public final class Item`; TelegramCore's `ForumChannels.swift` added the `.Info` nested type via `public extension EngineMessageHistoryThread { final class Info … }`. The outer name's Postbox residency forced every consumer of `.Info` to `import Postbox` too. After: promote Postbox's internal `MutableMessageHistoryThreadIndexView.Item` to a top-level public type `MessageHistoryThreadIndexItem`; delete the empty `EngineMessageHistoryThread` class from Postbox; move the class shell into `ForumChannels.swift`, collapsing the existing extension into a proper class definition (`public final class EngineMessageHistoryThread { class Info … }`).

`MessageHistoryThreadIndexView.items` type changes from `[EngineMessageHistoryThread.Item]` to `[MessageHistoryThreadIndexItem]`; its init simplifies (no more wrap/unwrap conversion — the old init re-built items element-by-element just to swap the outer wrapper name). The second public extension on `EngineMessageHistoryThread` (`.NotificationException`, at `ForumChannels.swift:1318`) works unchanged — same-module extension after the class moves.

Zero consumer-site changes: the two Postbox-consumer iteration sites (`ChatListUI/Sources/Node/ChatListNodeLocation.swift:229`, `ShareController/Sources/ShareControllerNode.swift:2086`) iterate with `for item in view.items` (no type annotation) and access only fields that exist identically on both types (`id`, `info`, `index`, `pinnedIndex`, `tagSummaryInfo`, `topMessage`, `embeddedInterfaceState`).

Commit `3bb22d503c`. Net: 2 files, +67 / −111 (Postbox file nets −174 lines, TelegramCore file +4).

**Wave 16b — `ItemListPeerItem.Context` `engine:` collapse.** Wave-11 pattern applied to `ItemListPeerItem.Context.Custom`. Before: `Context.Custom.init(accountPeerId:, postbox: Postbox, network: Network, animationCache:, animationRenderer:, isPremiumDisabled:, resolveInlineStickers:)` + matching stored fields; `Context` had computed `postbox: Postbox` and `network: Network` that switched over the `.account` / `.custom` cases. After: `Context.Custom.init(accountPeerId:, engine: TelegramEngine, animationCache:, animationRenderer:, isPremiumDisabled:, resolveInlineStickers:)`; `Context` has one computed `engine: TelegramEngine` that returns `context.engine` for the `.account` case and `custom.engine` for the `.custom` case. Six internal forwards rewire from `item.context.postbox` / `item.context.network` to `item.context.engine.account.postbox` / `item.context.engine.account.network` (three `EmojiStatusComponent(postbox:…)` sites and three `AvatarNode.setPeer(…, postbox:…, network:…, …)` sites).

Handle choice: `engine:` (not `stateManager:`). The sole external `.custom(Custom(...))` construction site codebase-wide is `PeerInfoSettingsItems.swift:121` — main-app-only, doesn't cross the Share-Extension boundary. `peerAccountContext` in that loop is typed `AccountContext` (from the `accountsAndPeers: [(AccountContext, EnginePeer, Int32)]` field), so `.engine: TelegramEngine` is directly available. Per the standing guidance from `feedback_postbox_refactor_handle.md`, prefer `engine:` except when physically forced to `stateManager:` by a Share-Extension boundary.

All 37 other `ItemListPeerItem(…)` construction sites use the `.account(context: AccountContext)` convenience overload (at L485) and need no change. `PeerInfoScreenMemberItem.swift:223` forwards its own `context: ItemListPeerItem.Context` field straight through (pass-through) — no change.

Module does **not** become Postbox-free: `PeerStoryStats?` remains on the `storyStats` public-surface field. `PeerStoryStats` is defined in `Postbox/Sources/ChatListView.swift:281` and is deeply baked into Postbox view APIs (`PeerView.storyStats`, `PeerStoryStatsView.storyStats`, `ChatListEntry.storyStats`, `MessageHistoryView.peerStoryStats`, `Postbox.getPeerStoryStats(peerId:)`). Moving it would require a cross-module wrapper rewrite across Postbox, TelegramCore, and every view consumer — out of scope for wave 16.

Commit `a5432e44a8`. Net: 2 files, +17 / −30.

**Lessons.**
- **Public-surface inventory must go beyond the collapse-target tokens.** Waves 11/12/15's `stateManager`/`engine` collapses were clean because their target modules had no other Postbox-defined public types. Wave 16's planning inventory only grepped for `Postbox`/`Network` and missed `EngineMessageHistoryThread` + `PeerStoryStats` — both symbols whose names happen to not include `Postbox`. For future wave-11-pattern candidates, planning-time grep should include the full alphabet of Postbox-defined public types: `^public\s+(class|struct|enum|protocol|typealias)\s+\w+` over `submodules/Postbox/Sources/` to build an exhaustive type-name allowlist, then grep for any of those names in the candidate module's public surface.
- **"Engine"-prefixed types can still be Postbox-defined.** `EngineMessageHistoryThread` has an "Engine" prefix but was declared in Postbox all along; the `.Info` nested type living in TelegramCore was a code-organization half-measure that still forced `import Postbox` on consumers. Don't trust naming conventions; grep for the defining module.
- **Splitting a failing wave into a cleanup + a partial collapse is often the right move.** Wave 16 could have been abandoned entirely when the build failed — instead, the `EngineMessageHistoryThread` move (which had been a latent cleanup opportunity for the entire history of the `.Info` extension) was promoted to a standalone commit (16a), and the partial `engine:` collapse shipped as a second commit (16b). Both are independently valuable; the wave's "module becomes Postbox-free" goal didn't land but other goals did.
- **The "promote internal Postbox `Item` to top-level, drop Postbox wrapper class, move wrapper class to TelegramCore" pattern generalizes.** Any Postbox-defined class whose only role is to namespace a TelegramCore extension is a candidate for this move. Future audit target: `grep -l "public extension <ClassName>" submodules/TelegramCore/Sources/` where `<ClassName>` is a Postbox-defined outer type with no semantic content of its own.

Plan / record: `project_postbox_wave16_plan.md` (updated with outcome).

## Wave 17 outcome (2026-04-20)

Applies the wave-11/12/15 `stateManager: AccountStateManager` collapse pattern to `ItemListAvatarAndNameInfoItem` — another wave-1-era candidate. Module becomes fully Postbox-free (source + BUILD). Clean one-shot execution (no abandonment, no replan).

**`ItemListAvatarAndNameInfoItem.ItemContext` enum case collapsed.** Before: `case other(accountPeerId: EnginePeer.Id, postbox: Postbox, network: Network)` + matching destructure at L761 + `AvatarNode.setPeer(…, postbox: postbox, network: network, …)` internal forward. After: `case other(accountPeerId: EnginePeer.Id, stateManager: AccountStateManager)` + `case let .other(accountPeerId, stateManager):` destructure + `AvatarNode.setPeer(…, postbox: stateManager.postbox, network: stateManager.network, …)` forward. The `.accountContext(AccountContext)` sister case is unchanged.

**Share-Extension-boundary handle choice: `stateManager:`.** The sole external `.other(...)` construction site codebase-wide is `DeviceContactInfoController.swift:413`, inside a ternary that fires only when `arguments.context` is not a `ShareControllerAppAccountContext` — i.e., when running inside the Share Extension. `ShareControllerAccountContext` (protocol at `AccountContext/Sources/ShareController.swift:16`) exposes `stateManager: AccountStateManager` but not `engine: TelegramEngine`, and constructing a full `TelegramEngine` is physically unreachable in the Share Extension's `ShareControllerAccountContextExtension` impl (no `Account`). Per `feedback_postbox_refactor_handle.md` and the wave-15 precedent, use `stateManager:` at Share-Extension boundaries.

**Pre-flight inventory was correct.** Running the public-Postbox-type inventory grep returned only `Postbox` itself (the one enum-case payload leak) — no `EngineMessageHistoryThread`-style surprises. Wave 17 validates the post-wave-16 lesson: when planning-time inventory uses the full Postbox public-types allowlist (not just `Postbox`/`Network` tokens), wave-11-shape candidates execute cleanly.

**Single external caller migrated:**
- `PeerInfoUI/Sources/DeviceContactInfoController.swift:413` — `postbox: arguments.context.stateManager.postbox, network: arguments.context.stateManager.network` → `stateManager: arguments.context.stateManager`. The enclosing `PeerInfoUI` module still imports Postbox for its own unrelated reasons; that stays.

The 5 other `ItemListAvatarAndNameInfoItem(itemContext:…)` construction sites codebase-wide all use `.accountContext(arguments.context)` and need no change (`ChannelBannedMemberController.swift:321`, `DeviceContactInfoController.swift:415`, `ChannelAdminController.swift:370`, `CreateChannelController.swift:197`, `CreateGroupController.swift:324`).

**Pattern-consistency note (reinforced).** `accountPeerId: EnginePeer.Id` is kept as a separate enum-case payload even though `AccountStateManager` also exposes `accountPeerId`. This matches waves 11/12/15 (`ActionSheetPeerItem`, `ChatListSearchRecentPeersNode`, `SelectablePeerNode` all kept `accountPeerId` explicit alongside `stateManager`). Future wave-11-pattern executions should default to this shape unless a specific reason exists to collapse further.

Net: 3 files changed, +4 / -5 lines (ItemListAvatarAndNameItem.swift: +2 / -3, DeviceContactInfoController.swift: +1 / -1, BUILD: −1). Build verified green for target modules (`ItemListAvatarAndNameInfoItem`, `PeerInfoUI` both compiled and linked successfully); the one unrelated failing target in the full build (`ChatMessageInteractiveMediaNode.swift`) is user-uncommitted work-in-progress that predates this wave.

Plan / record: (plan doc `project_postbox_wave17_plan.md` deleted post-commit per the plan's own post-commit housekeeping instructions).

## Wave 18 outcome (2026-04-20)

Mixed-shape wave targeting `ItemListStickerPackItem`. Originally shortlisted (post-wave-17) as "likely wave-11 shape", but plan-writing-time inspection invalidated that hypothesis — the module's public API doesn't take `postbox:`/`network:`. Actual shape combined three existing wave patterns plus a narrow typealias addition. Module becomes fully Postbox-free (source + BUILD).

**Three narrow typealiases added to TelegramCore.** `submodules/TelegramCore/Sources/TelegramEngine/Utils/EnginePostboxCoding.swift` grew by 3 lines:

- `EngineItemCollectionId = ItemCollectionId` — needed at public closure-param positions.
- `EngineFetchResourceSourceType = FetchResourceSourceType` — needed at `var updatedFetchSignal` type annotation.
- `EngineFetchResourceError = FetchResourceError` — same.

Per CLAUDE.md rule 1 these narrow-utility typealiases are explicitly allowed (same shape as the existing `EngineMemoryBuffer`/`EnginePostboxDecoder`/… batch). Cheat sheet updated.

**Wave-4 enum-payload migration on `StickerPackThumbnailItem`.** Public enum case `animated(MediaResource, PixelDimensions, Bool, Bool)` → `animated(EngineMediaResource, PixelDimensions, Bool, Bool)`. Equatable `==` simplified: `lhsResource.isEqual(to: rhsResource)` → `lhsResource == rhsResource` (uses `EngineMediaResource.==` which has identical semantics). Two construction sites wrapped via `EngineMediaResource(thumbnail.resource)` / `EngineMediaResource(itemFile.resource)`. Two destructure-and-forward sites unwrap via `resource._asResource()` when handing off to `chatMessageStickerPackThumbnail(resource: MediaResource)` and `AnimatedStickerResourceSource(account:, resource: MediaResource, …)`. One `resource.id` site (for `shortLivedResourceCachePathPrefix`) needs the raw `MediaResourceId`, handled by a local `let rawResource = resource._asResource()` that serves both the `.id` read and the `AnimatedStickerResourceSource` init in the same block.

**Wave-3 facade swap.** `fetchedMediaResource(mediaBox: item.context.account.postbox.mediaBox, userLocation: .other, userContentType: .sticker, reference: resourceReference)` → `item.context.engine.resources.fetch(reference: resourceReference, userLocation: .other, userContentType: .sticker)`. Engine facade (`TelegramEngine.Resources.fetch`) already exists from wave 3; no new TelegramEngine API needed.

**External-caller check confirmed zero source edits needed.** `StickerPackThumbnailItem` has no external consumers (UndoUI declares its own nested-private same-named enum). The 6 external `ItemListStickerPackItem(setPackIdWithRevealedOptions:)` caller sites all pass closures with inferred param types; `EngineItemCollectionId` being a typealias to `ItemCollectionId` makes the types interchangeable. The 3 module-field declarations outside the target module that name `(ItemCollectionId?, ItemCollectionId?) -> Void` explicitly (`SettingsUI/Stickers/ArchivedStickerPacksController.swift:27`, `SettingsUI/Stickers/InstalledStickerPacksController.swift:27`, and the init at L32/L42 of those same files) compile unchanged — those modules still import Postbox for their own reasons, and `EngineItemCollectionId == ItemCollectionId` so no rename is required.

**BUILD dep dropped.** `//submodules/Postbox:Postbox` removed from `submodules/ItemListStickerPackItem/BUILD`.

**Pre-existing `ChatMessageInteractiveMediaNode.swift` WIP still present at build time — no longer failing.** The uncommitted change introduces an `allowSticker` validation around secret-chat sticker playback (~30 lines added in the `currentReplaceAnimatedStickerNode` block). Per wave-17's note it had failed to compile; on this wave's full build (`bazel build Telegram/Telegram`, 565 actions, 258s, 0 errors) it compiled and linked without issue. Either the user fixed it between waves 17 and 18, or the bazel dependency graph simply needed a full rebuild. Either way, wave 18's build was clean end-to-end — `Telegram.ipa` target built successfully, zero errors across the entire project.

**Pattern-consistency note.** Wave 18 is the third wave (after 3 and 9) where the cheapest path requires adding narrow TelegramCore-side typealiases rather than keeping `import Postbox` in the consumer. The threshold is: if the consumer needs to NAME a Postbox-defined type (not just use it via inference), and no engine-prefixed alias exists, adding a narrow typealias is preferred over `import Postbox`. The alternative of refactoring the code to avoid naming the type (e.g., reshaping `var foo: Signal<T, E>?` to infer from first assignment) is usually unwieldy when the var is conditionally-assigned; typealiases win on readability.

Net: 3 files changed.
- `submodules/TelegramCore/Sources/TelegramEngine/Utils/EnginePostboxCoding.swift`: +3 / -0.
- `submodules/ItemListStickerPackItem/Sources/ItemListStickerPackItem.swift`: ~13 lines touched across 9 sites; net +4 / -4.
- `submodules/ItemListStickerPackItem/BUILD`: 0 / -1.
- `CLAUDE.md`: +3 cheat-sheet lines + this outcome paragraph.

Plan / record: `memory/project_postbox_wave18_plan.md` (deleted post-commit per the plan's own housekeeping instructions).

## Wave 19 outcome (2026-04-20)

Single-facade expansion. Additive-only — adds `TelegramEngine.Resources.shortLivedResourceCachePathPrefix(id: EngineMediaResource.Id) -> String` at `submodules/TelegramCore/Sources/TelegramEngine/Resources/TelegramEngineResources.swift:456`. Body: `self.account.postbox.mediaBox.shortLivedResourceCachePathPrefix(MediaResourceId(id.stringRepresentation))`.

No consumer migrations this wave. Known consumers (≥25 call sites across ~15 modules: AvatarVideoNode, DrawingUI, SettingsUI/ThemePickerGridItem, PremiumUI/StickersCarouselComponent, ReactionSelectionNode, ReactionContextNode, ChatSendMessageActionUI, ItemListStickerPackItem, ChatThemeScreen, ThemeCarouselItem, PeerInfoBirthdayOverlay, SettingsThemeWallpaperNode, MediaEditorComposerEntity, ChatQrCodeScreen, ChatMessageAnimatedStickerItemNode, ChatMessageItemView, GiftCompositionComponent) migrate in a follow-up wave using the pattern `X.context.account.postbox.mediaBox.shortLivedResourceCachePathPrefix(Y.resource.id)` → `X.context.engine.resources.shortLivedResourceCachePathPrefix(id: EngineMediaResource.Id(Y.resource.id))`.

**Why not bundle consumer migration in the same wave?** Wave-3's original shape did bundle (3 facades + 1 full consumer module in one commit), but the consumer pool for this particular facade is large (~25 sites) and each call site only partially de-Postboxes its module — the caller modules need full inventory before deciding whether to drop `import Postbox`. Keeping wave 19 narrow (facade-only) lets follow-up waves approach consumer-module migration on a per-module basis without the facade-addition blocking anything.

Net: 1 file changed, +4 / -0.

Plan / record: (no plan doc this wave — single-method addition, target pre-identified in `project_postbox_refactor_next_wave.md`).

## Wave 20 outcome (2026-04-21)

Consumer sweep for the wave-19 `shortLivedResourceCachePathPrefix` facade. 22 call sites across 16 modules migrated atomically. Pattern (repeated identically at every site): `X.context.account.postbox.mediaBox.shortLivedResourceCachePathPrefix(Y.resource.id)` → `X.context.engine.resources.shortLivedResourceCachePathPrefix(id: EngineMediaResource.Id(Y.resource.id))`.

**Modules migrated (alphabetical):**
- `AvatarVideoNode/Sources/AvatarVideoNode.swift` (1 site)
- `ChatSendMessageActionUI/Sources/ChatSendMessageContextScreen.swift` (1 site)
- `DrawingUI/Sources/DrawingStickerEntityView.swift` (1 site)
- `ItemListStickerPackItem/Sources/ItemListStickerPackItem.swift` (1 site; simplified from wave-18's `let rawResource = resource._asResource(); …shortLivedResourceCachePathPrefix(rawResource.id)` + `AnimatedStickerResourceSource(…, resource: rawResource, …)` to `…shortLivedResourceCachePathPrefix(id: resource.id)` + `AnimatedStickerResourceSource(…, resource: resource._asResource(), …)` — drops the intermediate `let rawResource`)
- `PremiumUI/Sources/StickersCarouselComponent.swift` (2 sites)
- `ReactionSelectionNode/Sources/ReactionContextNode.swift` (2 sites)
- `ReactionSelectionNode/Sources/ReactionSelectionNode.swift` (6 sites — 4 unique expression templates, handled via targeted Edits against the unique argument expression at each call)
- `SettingsUI/Sources/ThemePickerGridItem.swift` (1 site)
- `TelegramUI/Components/Chat/ChatMessageAnimatedStickerItemNode/Sources/ChatMessageAnimatedStickerItemNode.swift` (2 sites)
- `TelegramUI/Components/Chat/ChatMessageItemView/Sources/ChatMessageItemView.swift` (1 site)
- `TelegramUI/Components/Chat/ChatQrCodeScreen/Sources/ChatQrCodeScreen.swift` (1 site)
- `TelegramUI/Components/ChatThemeScreen/Sources/ChatThemeScreen.swift` (1 site)
- `TelegramUI/Components/Gifts/GiftAnimationComponent/Sources/GiftCompositionComponent.swift` (3 sites)
- `TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoBirthdayOverlay.swift` (2 sites)
- `TelegramUI/Components/Settings/SettingsThemeWallpaperNode/Sources/SettingsThemeWallpaperNode.swift` (1 site)
- `TelegramUI/Components/Settings/ThemeCarouselItem/Sources/ThemeCarouselItem.swift` (1 site)

**One site intentionally skipped:** `TelegramUI/Components/MediaEditor/Sources/MediaEditorComposerEntity.swift:245`. That site uses a local `postbox: Postbox` init-parameter, not `context.account.postbox`, so the migration would require changing the init's parameter from `postbox:` to something engine-based and fanning out to its callers. Out of scope — handled by a future module-scoped wave.

**No modules became Postbox-free this wave.** Each of the 16 migrated modules still has other Postbox usage (raw `Postbox` types in signatures, `fetchedMediaResource(mediaBox:)` calls, `postbox.transaction`, etc.). Consumer-side `shortLivedResourceCachePathPrefix` closure is just one of several reasons these modules import Postbox. Future wave-shape: module-scoped de-Postbox per-module inventory.

**Pattern validation.** This is the most mechanical consumer sweep to date — all 22 sites followed identical shape, allowing `replace_all=true` for sites with duplicate identical call expressions (ReactionSelectionNode hit this at 3 sites for `largeListAnimation`, 2 for `stillAnimation`, 1 for `listAnimation`). First-pass build was clean (35 actions, 0 errors) — no iteration loop. Confirms the wave-19 facade shape is sound.

**Build verification.** `bazel build Telegram/Telegram --keep_going` — 2042 action cache hits + 35 new actions, 0 errors, `Telegram.ipa` up-to-date.

Net: 16 files changed, all edits mechanical (before → after): +22 insertions / -22 deletions at migrated sites, plus 1 deletion in ItemListStickerPackItem (wave-18 `let rawResource` line dropped). Approximate total: +22 / -23.

Plan / record: (no plan doc this wave — mechanical sweep).

## Wave 21 outcome (2026-04-21)

Combined wave-19+wave-20 shape: facade addition + consumer sweep in a single atomic commit. Adds `TelegramEngine.Resources.completedResourcePath(id: EngineMediaResource.Id, pathExtension: String? = nil) -> String?` facade; sweeps 29 consumer sites across 14 files.

**Facade added at `TelegramCore/Sources/TelegramEngine/Resources/TelegramEngineResources.swift:460`.** Body: `self.account.postbox.mediaBox.completedResourcePath(id: MediaResourceId(id.stringRepresentation), pathExtension: pathExtension)`. Wraps the Postbox `MediaBox.completedResourcePath(id: MediaResourceId, pathExtension: String?)` overload; consumers that previously called the resource-taking overload (`MediaBox.completedResourcePath(_ resource: MediaResource, …)`) migrate through the id path (`.resource.id` is already `MediaResourceId`).

**28 Shape-A consumer sites + 1 Shape-B (already-id-overload) migrated:**
- `SettingsUI/Sources/Themes/EditThemeController.swift` (1 site)
- `BrowserUI/Sources/BrowserPdfContent.swift` (1 site)
- `BrowserUI/Sources/BrowserDocumentContent.swift` (1 site)
- `GalleryUI/Sources/SecretMediaPreviewController.swift` (1 site)
- `TelegramUI/Components/MediaEditor/Sources/MediaEditor.swift` (1 site, `pathExtension: "mp4"`)
- `TelegramUI/Components/Settings/WallpaperGridScreen/Sources/WallpaperUtils.swift` (7 sites across 3 functions; 4 unique expression templates, handled via `replace_all=true` where identical)
- `TelegramUI/Components/Settings/ThemeAccentColorScreen/Sources/ThemeAccentColorController.swift` (1 site)
- `TelegramUI/Components/Settings/WallpaperGalleryScreen/Sources/WallpaperGalleryController.swift` (5 sites; 4 used `resource` expr identically via `replace_all=true`, 1 used `file.file.resource`)
- `TelegramUI/Components/MediaEditorScreen/Sources/MediaEditorScreen.swift` (1 site, `pathExtension: nil`)
- `TelegramUI/Components/Chat/ChatMessageWebpageBubbleContentNode/Sources/ChatMessageWebpageBubbleContentNode.swift` (1 site)
- `TelegramUI/Components/Chat/ChatMessageMediaBubbleContentNode/Sources/ChatMessageMediaBubbleContentNode.swift` (7 sites, all identical `telegramFile.resource` — handled via `replace_all=true`)
- `TelegramUI/Components/Chat/ChatMessageAttachedContentNode/Sources/ChatMessageAttachedContentNode.swift` (1 site)
- `TelegramUI/Sources/OpenChatMessage.swift` (1 site)
- `TelegramUI/Sources/Chat/ChatControllerMediaRecording.swift` (1 site)
- `TelegramUI/Components/Stories/StoryContainerScreen/Sources/StoryItemImageView.swift` (1 site, Shape B — was already using the `id:` overload; migrated identically to `EngineMediaResource.Id(...)`)

**8 sites intentionally skipped (Shape C/D).** Listed in the plan — 5 Shape-C sites that access a raw `account: Account` parameter (no `.engine` on `Account`) and 3 Shape-D sites that carry a local `postbox: Postbox` stored field. Both shapes need module-scoped init-signature rework rather than per-site sweep; defer to future waves.

**No modules became Postbox-free.** Each consumer has other Postbox usage (signatures, transactions, other mediaBox calls). Matches waves 19/20's expectation.

**Build validation.** `bazel build Telegram/Telegram --keep_going` — clean first-pass build (569 processes, 1556 action cache hits + 30 local + 532 worker, 240s, 0 errors, `Telegram.ipa` up-to-date).

**Pattern validation.** Wave-shape G (facade addition + consumer sweep in a single commit) works well when the consumer pool is bounded and mechanical. 29 sites in 14 files is comfortably within the threshold. Kept waves 19 and 20 separate because 25+ sites across that many modules was at the edge of reviewability; wave 21's similar fan-out fits because the plan pre-classified every site by shape. When the plan does the classification work upfront, combined waves are cheaper to review and ship.

Net: 14 files changed. TelegramEngineResources.swift: +4 / -0. Consumer files: +29 / -29 (mechanical rewrite at each site). CLAUDE.md: +outcome paragraph.

Plan / record: `memory/project_postbox_wave21_plan.md` (deleted post-commit per the plan's own housekeeping instructions).

## Wave 22 outcome (2026-04-21)

Follows wave 21's pattern: facade addition + consumer sweep in a single atomic commit. Adds `TelegramEngine.Resources.storeResourceData(id: EngineMediaResource.Id, data: Data, synchronous: Bool = false)` facade; sweeps 46 consumer sites across 17 files.

**Facade added at `TelegramCore/Sources/TelegramEngine/Resources/TelegramEngineResources.swift:464`.** Body: `self.account.postbox.mediaBox.storeResourceData(MediaResourceId(id.stringRepresentation), data: data, synchronous: synchronous)`. Wraps Postbox's `MediaBox.storeResourceData(_ id: MediaResourceId, data: Data, synchronous: Bool)` full-file overload. The range-store overload (`MediaBox.storeResourceData(_:range:data:)`) is used at a single site inside `HLSVideoJSNativeContentNode.swift:302` via a local `postbox: Postbox` field (Shape D), which is out of scope for this wave; the range overload gets no facade wrapper this round.

**46 Shape-A consumer sites migrated:**
- `ImportStickerPackUI/Sources/ImportStickerPackControllerNode.swift` (2)
- `DebugSettingsUI/Sources/DebugController.swift` (8 — 6 identical `gzippedData` batched via `replace_all=true`; `logData`, `allStatsData` handled individually)
- `BrowserUI/Sources/BrowserWebContent.swift` (1)
- `TelegramUI/Sources/CreateChannelController.swift` (4)
- `TelegramUI/Sources/CreateGroupController.swift` (4)
- `TelegramUI/Sources/Chat/ChatControllerPaste.swift` (1)
- `TelegramUI/Sources/Chat/ChatControllerOpenDocumentScanner.swift` (3)
- `TelegramUI/Sources/Chat/ChatControllerMediaRecording.swift` (2)
- `TelegramUI/Components/LegacyInstantVideoController/Sources/LegacyInstantVideoController.swift` (2)
- `TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreenAvatarSetup.swift` (2)
- `TelegramUI/Components/Settings/WallpaperGridScreen/Sources/WallpaperUtils.swift` (6 — 3 `thumbnailResource`, 3 `resource`; both handled via `replace_all=true`)
- `SettingsUI/Sources/Themes/ThemePreviewController.swift` (1)
- `SettingsUI/Sources/Themes/EditThemeController.swift` (1)
- `TelegramUI/Components/Stories/StoryContainerScreen/Sources/StoryItemSetContainerViewSendMessage.swift` (3)
- `TelegramUI/Components/VideoMessageCameraScreen/Sources/VideoMessageCameraScreen.swift` (2)
- `TelegramUI/Components/MediaEditorScreen/Sources/CreateLinkOptions.swift` (1)
- `TelegramUI/Components/MediaEditorScreen/Sources/MediaEditorScreen.swift` (3)

**Out of scope — not migrated this wave:**
- `accountManager.mediaBox.storeResourceData(...)` sites (Account-manager-scoped, not account-scoped) — 13+ sites across WallpaperGalleryItem, WallpaperGalleryController, ThemeAccentColorController, WallpaperUtils, WebBrowserSettingsController, ThemeUpdateManager, OpenResolvedUrl, and others. These are a different migration path entirely (not a `TelegramEngine.Resources.*` target) and stay raw.
- `account.postbox.mediaBox.storeResourceData(...)` (raw `Account`, no `AccountContext`) — ~9 sites in LegacyMediaPickerUI, TelegramCallsUI, InAppPurchaseManager, AuthorizationUI, PeerInfoScreenAvatarSetup closures, WallpaperResources. Shape C from wave-21 taxonomy. Needs per-module rework.
- `self.postbox.mediaBox.storeResourceData(...)` / `postbox.mediaBox.storeResourceData(...)` inside TelegramCore internals (`TransformOutgoingMessageMedia.swift`, `AccountStateManager.swift`, `AvailableReactions.swift`, `SaveSecureIdValue.swift`, `PeerPhotoUpdater.swift`, `NotificationSoundList.swift`, `Stories.swift`, `Authorization.swift`, `WebpagePreview.swift`). These are Postbox-internal layer by design — keep as-is.
- `HLSVideoJSNativeContentNode.swift:302` — uses the range-store overload via local `postbox: Postbox` field. Out of scope.

**No modules became Postbox-free.** Matches waves 19/20/21 expectation — each consumer has other Postbox usage.

**Build validation.** `bazel build Telegram/Telegram --keep_going` — clean first-pass build (571 processes, 1554 action cache hits + 30 local + 532 worker, 229s, 0 errors, `Telegram.ipa` up-to-date).

**Pattern validation.** Wave-shape G (facade + consumer sweep in one commit) scales well up to 46 sites in 17 files when the pattern is mechanical. Heavy `replace_all=true` usage where call-text is identical across sites (DebugController's 6 `gzippedData` sites, WallpaperUtils' 6 sites split into 2 batches by first-arg variable, ChatControllerOpenDocumentScanner's identical `(resource.id, data: data, synchronous: true)` pattern) keeps diff noise to the minimum. 46 sites, mostly done via replace_all + a few individual edits.

Net: 17 consumer files + 1 TelegramCore file + CLAUDE.md. TelegramEngineResources.swift: +4 / -0. Consumer files: +46 / -46 (mechanical rewrite).

Plan / record: (no plan doc this wave — mechanical sweep following wave-21 recipe).

## Wave 23 outcome (2026-04-21)

Smallest wave so far: `cancelInteractiveResourceFetch` facade addition + consumer sweep. Same shape as waves 21/22.

**Facade added at `TelegramCore/Sources/TelegramEngine/Resources/TelegramEngineResources.swift:468`.** Body: `self.account.postbox.mediaBox.cancelInteractiveResourceFetch(resourceId: MediaResourceId(id.stringRepresentation))`. Wraps Postbox's `MediaBox.cancelInteractiveResourceFetch(resourceId: MediaResourceId)` overload (the `_ resource: MediaResource` overload delegates to the id version anyway).

**5 of 7 Shape-A consumer sites migrated:**
- `PeerAvatarGalleryUI/Sources/PeerAvatarImageGalleryItem.swift` (1)
- `GalleryUI/Sources/Items/ChatAnimationGalleryItem.swift` (1)
- `GalleryUI/Sources/Items/ChatImageGalleryItem.swift` (1)
- `GalleryUI/Sources/Items/ChatDocumentGalleryItem.swift` (1)
- `GalleryUI/Sources/Items/ChatExternalFileGalleryItem.swift` (1)

**2 sites intentionally skipped:** `ChatMessageInteractiveMediaNode.swift:1474, 1709` — this file has pre-existing uncommitted WIP (the `allowSticker` validation around secret-chat sticker playback, carried forward since before wave 17). Editing the 2 sites would mix my wave-23 changes with the user's WIP in a single git diff, which `git add` can't cleanly separate. Deferred until the WIP lands or a narrow follow-up wave intentionally includes both. Note: a future wave that aims to drop those 2 sites should first either (a) wait for the WIP to be committed or (b) use `git stash --keep-index` + targeted edits + selective staging to split the diff cleanly.

**Pattern note on WIP interference.** This is the first wave to hit this failure mode — previous waves' mechanical sweeps happened not to touch `ChatMessageInteractiveMediaNode.swift`. Future sweeps should grep their candidate set against `git status`'s modified-files list before starting, and either (a) defer sites in WIP files, (b) wait for the WIP to commit, or (c) stage selectively via `git add --patch`-equivalent paths.

**Build validation.** `bazel build Telegram/Telegram --keep_going` — clean first-pass build (558 processes, 1567 action cache hits + 19 local + 532 worker, 236s, 0 errors, `Telegram.ipa` up-to-date).

Net: 5 consumer files + 1 TelegramCore file + CLAUDE.md. TelegramEngineResources.swift: +4 / -0. Consumer files: +5 / -5.

Plan / record: (no plan doc this wave — mechanical sweep).

## Wave 24 outcome (2026-04-21)

`moveResourceData` facade additions + consumer sweep. Same shape as waves 21-23.

**Two facades added at `TelegramCore/Sources/TelegramEngine/Resources/TelegramEngineResources.swift`:**
- `moveResourceData(id: EngineMediaResource.Id, toTempPath: String)` wraps the `(MediaResourceId, toTempPath:)` overload.
- `moveResourceData(from: EngineMediaResource.Id, to: EngineMediaResource.Id, synchronous: Bool = false)` wraps the `(from: MediaResourceId, to: MediaResourceId, synchronous:)` overload.

Postbox's third overload `(MediaResourceId, fromTempPath:)` has no consumer-side usage; no facade added this wave (YAGNI).

**6 Shape-A consumer sites migrated (5 files):**
- `TelegramUI/Sources/Chat/ChatControllerMediaRecording.swift` (1, `toTempPath:`)
- `TelegramUI/Sources/OverlayAudioPlayerController.swift` (1, `from:to:synchronous:`)
- `TelegramUI/Components/ComposePollScreen/Sources/ComposePollScreen.swift` (2)
- `TelegramUI/Components/Chat/ChatMessagePollBubbleContentNode/Sources/ChatMessagePollBubbleContentNode.swift` (2)

**Build validation.** `bazel build Telegram/Telegram --keep_going` — clean first-pass build (563 processes, 272s, 0 errors).

Net: 5 consumer files + 1 TelegramCore file + CLAUDE.md. TelegramEngineResources.swift: +8 / -0. Consumer files: +6 / -6.

Plan / record: (no plan doc this wave — mechanical sweep).

## Wave 25 outcome (2026-04-21)

`copyResourceData` facade additions + consumer sweep. Same shape as waves 21-24.

**Two facades added:** `copyResourceData(id: EngineMediaResource.Id, fromTempPath: String)` and `copyResourceData(from: EngineMediaResource.Id, to: EngineMediaResource.Id, synchronous: Bool = false)`.

**4 Shape-A consumer sites migrated (3 files):**
- `PeerAvatarGalleryUI/Sources/AvatarGalleryController.swift` (2, `from:to:synchronous:`)
- `ImportStickerPackUI/Sources/ImportStickerPackControllerNode.swift` (1, `from:to:` — simplified from `localResource._asResource().id` to `localResource.id` since operands are `EngineMediaResource`)
- `TelegramUI/Sources/Chat/ChatControllerPaste.swift` (1, `id:fromTempPath:`)

**Minor simplification lesson.** When a consumer already has an `EngineMediaResource`-typed local (e.g., from a wave-18-migrated callee), prefer `localResource.id` over `EngineMediaResource.Id(localResource._asResource().id)` — the two are semantically equivalent since `EngineMediaResource.id` is defined as `Id(self.resource.id)`. This halves the verbosity at the call site and removes a redundant unwrap-and-rewrap.

**Build validation.** Clean first-pass build (563 processes, 242s, 0 errors).

Net: 3 consumer files + 1 TelegramCore file + CLAUDE.md. TelegramEngineResources.swift: +8 / -0.

Plan / record: (no plan doc this wave — mechanical sweep).

## Wave 27 outcome (2026-04-22)

`preferencesView` consumer sweep (wave-9 pattern continuation). No new TelegramCore facades — leverages existing `TelegramEngine.EngineData.Item.Configuration.ApplicationSpecificPreference(key:)`.

**Shape.** Replace `context.account.postbox.preferencesView(keys: [<key>])` — returning `Signal<PreferencesView, NoError>` — with `context.engine.data.subscribe(TelegramEngine.EngineData.Item.Configuration.ApplicationSpecificPreference(key: <key>))` — returning `Signal<PreferencesEntry?, NoError>`. Downstream, rename `<name>.values[<key>]?.get(<Type>.self)` → `<name>?.get(<Type>.self)` at each closure parameter.

**30 consumer files, ~40 call sites migrated** across ChatListUI, ContactListUI, DebugSettingsUI, GalleryUI, PeersNearbyUI, SettingsUI, TelegramCallsUI, TelegramUI, TelegramUI/Components, WebSearchUI. Full list in `git show --stat <wave-27-commit>`.

**Multi-key sites (PresentationCallManager).** 3 sites used `preferencesView(keys: [voipConfiguration, appConfiguration])`. Migrated via the two-arg `engine.data.subscribe(itemA, itemB) |> take(1)` overload, which returns `Signal<(PreferencesEntry?, PreferencesEntry?), NoError>`. Closures that accessed `preferences.values[X]?.get(...)` rewritten to `preferences.0?.get(...)` and `preferences.1?.get(...)`.

**Direct-postbox-param helper migrated.** `AccountContext.swift`'s `getAppConfiguration(postbox: Postbox)` helper (one internal caller only) was rewritten to `getAppConfiguration(engine: TelegramEngine)` in the same commit, switching its single call site from `getAppConfiguration(postbox: account.postbox)` to `getAppConfiguration(engine: self.engine)`.

**Annotation update in NotificationExceptionControllerNode.swift.** An explicit signal type `Signal<(…, PreferencesView, …), NoError>` in a `mapToSignal` return was updated to `Signal<(…, PreferencesEntry?, …), NoError>`. The file still imports Postbox because `PreferencesEntry` is (for now) a Postbox-defined type surfaced through TelegramCore's `EnginePreferencesEntry` typealias — a future wave-6-style `import Postbox` sweep would clean up such imports where they're now the only Postbox reference.

**Deliberately skipped in this wave.**
- `TelegramPermissionsUI/Sources/PermissionSplitTest.swift:100` — `permissionUISplitTest(postbox: Postbox)` is a public API whose product value `PermissionUISplitTest` itself stores `postbox: Postbox` to satisfy the `SplitTest` protocol. Proper migration requires a protocol-level refactor (or wholesale rewrite of the SplitTest abstraction) beyond this wave's scope.
- 5 TelegramCore-internal `postbox.preferencesView(...)` sites (ChatListFiltering × 3, ContentSettings × 1, ManagedGlobalNotificationSettings × 1) — the refactor only migrates consumer modules, not TelegramCore internals.

**Build validation.** Clean first-pass build (748 processes, 227s, 0 errors). No new facades to test, shape was validated across 30 files on the first attempt.

**Lesson — multi-key preferencesView migration.** `engine.data.subscribe(itemA, itemB)` exists and returns a Swift tuple. When a Postbox `preferencesView(keys: [K1, K2])` call is inside a `combineLatest(...)` whose downstream closure accesses `.values[K1]` and `.values[K2]`, prefer the two-arg subscribe form (vs. two separate subscribes combined externally) — it preserves `combineLatest` arity exactly. Rewrite `.values[K1]?.get(T.self)` → `.0?.get(T.self)`, `.values[K2]?.get(T.self)` → `.1?.get(T.self)`. The closure parameter name stays (e.g., `preferences`) because the tuple destructure preserves the variable-name semantics at the call site.

Net: 30 consumer files. No TelegramCore changes. CLAUDE.md facade-inventory table unchanged (no new facades).

Plan / record: `memory/project_postbox_wave27_plan.md` (deleted post-wave).

## Wave 26 outcome (2026-04-21)

`resourceRangesStatus` + `removeCachedResources` facade additions + consumer sweep. Combines two independent small sweeps into one commit.

**Two facades added:**
- `resourceRangesStatus(resource: EngineMediaResource) -> Signal<RangeSet<Int64>, NoError>` wraps the single `(MediaResource) -> Signal<RangeSet<Int64>, NoError>` overload. Takes `EngineMediaResource` (not `id:`) because Postbox's overload only accepts a resource, not an id — consumers pass `.resource` already. Facade unwraps via `_asResource()`.
- `removeCachedResources(ids: [EngineMediaResource.Id], force: Bool = false, notify: Bool = false) -> Signal<Float, NoError>` wraps the `([MediaResourceId], force:, notify:) -> Signal<Float, NoError>` overload. Maps ids internally.

**`import RangeSet` added to `TelegramEngineResources.swift`.** The `RangeSet<Int64>` return type caused a name collision with Swift stdlib's `RangeSet` (iOS 18+ only) until the local `RangeSet` module is imported. `TelegramCore/BUILD` already declared the dep at line 23 (`//submodules/Utils/RangeSet:RangeSet`), so no BUILD change needed.

**4 Shape-A consumer sites migrated (3 files):**
- `PhotoResources/Sources/PhotoResources.swift` (1)
- `TelegramUI/Components/Stories/StoryContainerScreen/Sources/StoryChatContent.swift` (1)
- `ChatListUI/Sources/ChatListSearchContainerNode.swift` (2)

For `ChatListSearchContainerNode.swift:1398`, the caller uses a `Set<MediaResourceId>` local — wave leaves the local as-is and maps at the call site via `resourceIds.map { EngineMediaResource.Id($0) }`. Migrating the local to `Set<EngineMediaResource.Id>` is out of scope (module keeps `import Postbox` for unrelated reasons).

**Build validation.** Clean build (563 processes, 265s, 0 errors) on the second attempt after adding `import RangeSet`.

**Lesson — Swift-stdlib-vs-third-party-module name collisions.** When a facade signature references a type name that exists both in Swift stdlib (potentially availability-restricted) and in a third-party module, the compiler picks the stdlib one by default. Fix: import the third-party module explicitly. In this codebase, `RangeSet` is provided by `submodules/Utils/RangeSet:RangeSet`, and TelegramCore already depends on it. Use `import RangeSet` at the file top.

Net: 3 consumer files + 1 TelegramCore file + CLAUDE.md. TelegramEngineResources.swift: +9 / -0 (including `import RangeSet`).

Plan / record: (no plan doc this wave — mechanical sweep).

## Wave 31 outcome (2026-04-23)

Second build-verified `^import Postbox$` sweep on consumer modules since wave 6 (2026-04-19). Same methodology: speculative-drop + `--continueOnError` build loop with pattern-based preemptive restores.

**Candidate set narrowing.** Initial candidate grep `grep -rl "^import Postbox$" submodules --include="*.swift"` returned **1184** files. 606 of those live in `submodules/TelegramCore/Sources/` — TelegramCore legitimately `import Postbox`; the TelegramCore files were accidentally included and had to be reverted via `git checkout -- submodules/TelegramCore/Sources/` before re-seeding the drop. Final consumer candidate set: **578** files. **Lesson for future sweep invocations: the candidate-set grep must filter out `submodules/TelegramCore/` as well as `submodules/Postbox/` / `submodules/TelegramApi/`.** Wave 6's methodology note at step 1 (line 37) already calls this out, but the TelegramCore carve-out is easy to miss because TelegramCore doesn't `@_exported import Postbox`, so from a pure re-exports perspective it's indistinguishable from a consumer.

**9 build iterations to convergence** (plus 1 aborted first iteration for the TelegramCore scope error). Per-iteration failure counts: 18 → 2 → 9 → 12 → 1 → 1 → 3 → 1 → 4 → 0. Surfacing pattern was typical of a speculative-drop sweep: errors bubble one dependency-graph layer at a time.

**Per-iteration symbol expansion.** The wave-6 preemptive-restore symbol list (CLAUDE.md's "Unused-import sweeps" guidance) needed extensions for this sweep:
- Iter 3 surfaced `CodableEntry`, `CachedMediaResourceRepresentation`, `CachedMediaRepresentationKeepDuration`.
- Iter 4 surfaced `PostboxViewKey`, `OrderedItemListView`, `UnreadMessageCountsItem`, `ChatListEntrySummaryComponents`, `PeerStoryStats`, `ItemCollectionId` (note: typealias `EngineItemCollectionId` exists but raw name still requires `import Postbox`), and broadened `\bMedia\b`, `\bMessage\b`, `\bPeer\b`.
- Iter 5 surfaced `FetchResourceSourceType` (same typealias caveat).
- Iter 6 surfaced `StoryId`.
- Iter 7 surfaced `ChatListIndex`.
- Iter 8 surfaced `PreferencesEntry` (typealias caveat), `PeerView`, `RenderedPeer`.
- Iter 9 surfaced `declareEncodable`.
- Iter 10 surfaced `ItemCollectionItemIndex`, `ValueBoxEncryptionParameters`, `fileSize`, plus a restore-script bug (see below).

**Restore-script bug: `#if canImport(...)` blocks.** The naive restore inserter picks the last `^import ` line and appends `import Postbox` after it. If the last import sits inside an `#if canImport(AppCenter) ... #endif` preprocessor block, the restored `import Postbox` lands inside that block and is only active under that configuration. `AppDelegate.swift` in `submodules/TelegramUI/Sources/` hit this (original had `import Postbox` at line 7; drop + restore put it inside the `#if canImport(AppCenter)` block at line 51); the build failed in iter10 on `cannot find type 'Postbox' in scope` errors even though a literal `grep ^import Postbox$` matched. Fixed by manually moving the import out of the `#if` block. **Lesson for future restore-script work: insert the restored `import Postbox` BEFORE the first `#if` or `#endif` line, not after the last `import` line, to avoid preprocessor-scope traps.**

**Results: 9 source-level surviving drops + 2 duplicate-import dedups.** Final diff: 11 files changed, +2 / -13.

Surviving drops:
- `submodules/AuthorizationUI/Sources/AuthorizationSequencePhoneEntryController.swift`
- `submodules/AuthorizationUI/Sources/AuthorizationSequenceSplashController.swift`
- `submodules/DebugSettingsUI/Sources/DebugAccountsController.swift`
- `submodules/LegacyDataImport/Sources/LegacyPreferencesImport.swift`
- `submodules/MediaPlayer/Sources/ChunkMediaPlayerDirectFetchSourceImpl.swift`
- `submodules/TelegramUI/Components/Stories/StoryContainerScreen/Sources/StoryItemImageView.swift`
- `submodules/TelegramUI/Sources/ChatLinkPreview.swift`
- `submodules/TelegramUI/Sources/ChatSearchResultsController.swift`
- `submodules/TelegramUI/Sources/MediaManager.swift`

Duplicate-import dedups (files had two `^import Postbox$` lines; kept exactly one — unrelated-but-latent cleanup surfaced incidentally by the sweep):
- `submodules/TelegramUI/Components/ChatControllerInteraction/Sources/ChatControllerInteraction.swift` (2 imports → 1)
- `submodules/TelegramUI/Sources/ChatHistoryListNode.swift` (2 imports → 1)

**Spurious-diff cleanup step (new procedure, adopted this wave).** After convergence, `git diff --numstat` showed 564 modified files but only 9 were genuine drops. The other 553 were "1 addition + 1 deletion" — files where the original `import Postbox` at line X was deleted by the drop and re-inserted at line Y by the restore (different position because restore inserts after "last import line" regardless of original placement). These aren't semantic changes but do produce noisy diffs. Identified via `git diff --numstat | awk '$1 == 1 && $2 == 1 {print $3}'` and reverted via `xargs -I{} git checkout -- {}`. **Lesson: the wave-6 methodology should add a post-convergence "revert 1-add-1-del spurious diffs" step before committing. Alternative: improve the restore script to insert at the exact original line. Either way, the final diff should be limited to real semantic changes.**

**No modules became fully Postbox-free this wave.** Each of the five containing modules still has other files importing Postbox (TelegramUI: 350 remaining, LegacyDataImport: 4, MediaPlayer: 9, AuthorizationUI: 2, DebugSettingsUI: 1). By this point most trivially-droppable imports have been drained; the remaining Postbox-importing files mostly carry real usage. **Re-run cadence lesson: yield per re-run is declining.** Wave 6 yielded 183 drops + 189 modules freed; wave 31 yielded 9 drops + 0 modules freed. Consider spacing future sweeps to every 4–6 facade waves rather than 2–3.

**Wave 14 BUILD-dep sweep companion: 0 drops.** Ran the wave-14-style `find submodules -name BUILD | filter-by-no-source-import` check: **0 BUILD candidates**. The 191 BUILDs still listing `//submodules/Postbox` all have at least one Sources/*.swift that actually imports Postbox. One outlier (`submodules/SpotlightSupport/BUILD`) has zero source files but a non-trivial `deps = [...]` list including `//submodules/Postbox`; deliberately left alone (stale-BUILD-on-empty-module is a different class of cleanup and carries unknown side effects).

Net: 11 files changed (9 + 2), +2 / -13 lines. Clean first-attempt verification build without `--continueOnError` (880 actions, 1354 action cache hits, 262s).

Plan / record: (no plan doc this wave — mechanical sweep).

## Wave 32 outcome (2026-04-24)

`resourceStatus` residue sweep. One new facade overload (`status(id:resourceSize:)`) + 4 migrated sites across 2 consumer files. Commit `289fc908bc`.

**Facade added** in `TelegramEngineResources.swift`:
- `status(id: EngineMediaResource.Id, resourceSize: Int64) -> Signal<EngineMediaResource.FetchStatus, NoError>` wraps Postbox's `resourceStatus(MediaResourceId, resourceSize:)` overload. Body mirrors the existing `status(resource:)` facade, converting id via `MediaResourceId(id.stringRepresentation)` and mapping the result via `EngineMediaResource.FetchStatus.init`.

**4 migrated sites (2 files):**
- `ChatListSearchContainerNode.swift:1059` — new `status(id:resourceSize:)` overload. Caller supplies `EngineMediaResource.Id(downloadResource.id)` directly (String initializer; `downloadResource.id: String`) — no raw `MediaResourceId(...)` wrap needed. Mirrors the pre-existing `EngineMediaResource.Id(downloadResource.id)` usage at line 1107.
- `ChatMessageInteractiveMediaNode.swift:1769` — existing `status(resource:)` facade (wave 3).
- `ChatMessageInteractiveMediaNode.swift:1799` — same.
- `ChatMessageInteractiveMediaNode.swift:1809` — existing `resourceRangesStatus(resource:)` facade (wave 26).

**Local preserved deliberately.** `let postbox = context.account.postbox` at `ChatMessageInteractiveMediaNode.swift:1767` stays because line 1793 feeds `postbox` to `HLSVideoContent.minimizedHLSQualityPreloadData(postbox: Postbox, ...)` — that is a third-party-function boundary needing raw `Postbox`. Only the `resourceStatus`/`resourceRangesStatus` call sites within that scope migrate.

**Case-pattern sharing.** `MediaResourceStatus` (raw Postbox) and `EngineMediaResource.FetchStatus` (engine wrapper) have identical case names (`.Fetching`, `.Paused`, `.Local`, `.Remote`). The inner `switch status` at 1770-1779 keeps its `MediaResourceStatus` return type annotation — input case matching works for the engine type, constructed `MediaResourceStatus` return values still compile (`MediaResourceStatus` is in scope via `import Postbox` on line 4). This is the wave-29/30 lesson in action: no enum-case edits required.

**Inventory scope narrowing from memory's prediction.** The memory's `wave 32+ candidates` section predicted ~12 Shape-B/C sites in the residue sweep. Execution-time re-grep reclassified most of them:
- **Coupled to `accountManager.mediaBox.resourceStatus` siblings (6 sites in 3 files):** `ThemePreviewControllerNode:271+277`, `WallpaperGalleryItem:799+805+834+840`, `SettingsThemeWallpaperNode:284+285`. Each pair has an `accountManager`-sourced fallback whose return type is raw `Signal<MediaResourceStatus, NoError>`. Migrating only the `account.postbox` branch breaks the shared sibling type at the `mapToSignal`/`combineLatest` merge point. Deferred until accountManager-side has an engine facade.
- **Shape-C init-param refactor (3 sites in 3 files):** `LegacyWebSearchGallery:248` (free function `legacyWebSearchItem(account: Account, ...)`), `NativeVideoContent:455` (init takes `postbox: Postbox`), `VerticalListContextResultsChatInputPanelItem:229` (item stores `account: Account`). Each needs an init-param change + caller threading — per-module mini-refactor, not wave-shape-G territory.
- **`approximateSynchronousValue` overload:** only call site (`SettingsThemeWallpaperNode:284`) is in the accountManager-coupled bucket above. Adding the facade now would land dead code.

Effective wave scope: 4 sites (the uncoupled subset). Still worth committing as its own wave — closes the `resourceStatus` arc for every site where migration is currently unblocked.

**Build validation.** Clean build (558 processes, 236s, 0 errors). No `--continueOnError` needed — first attempt green.

**Lesson — siblings-define-scope in resource-status migrations.** When an assignment uses `A.resourceStatus(...)` in one branch and `B.resourceStatus(...)` in another (via `if`/`mapToSignal`/`combineLatest`), the branches' return types must match. If `A` has an engine facade but `B` does not (e.g., `accountManager.mediaBox` has no engine wrapper yet), neither branch is migratable in isolation — the whole group must wait. Pre-flight sibling-check for each `resourceStatus` hit: is the enclosing `statusSignal = ...` expression a single source or a multi-source merge?

**Lesson — Shape-B/C classification requires read, not grep.** The memory's wave-32 candidate table classified sites by single-line grep ("`account.postbox.mediaBox.resourceStatus`"). That pattern matches both the fully-migratable `context.account.postbox.mediaBox.X` form (Shape-A via AccountContext) AND the `(local) account.postbox.mediaBox.X` Shape-C form (requires init-param refactor). Distinguishing requires reading 5-10 lines of context to find the `account` binding: field? local? init param? closure capture? Add this as a mandatory step in the per-site inventory for future residue waves.

Plan / record: (no plan doc this wave — small residue sweep).

---

## Wave 33 outcome (2026-04-24)

`loadedPeerWithId` consumer sweep. 60 sites migrated across 37 consumer files. No new facades, no typealiases. Commit `16d017853a`.

**Migration pattern** (per user's explicit direction):

```swift
context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
|> mapToSignal { peer -> Signal<EnginePeer, NoError> in
    if let peer {
        return .single(peer)
    } else {
        return .never()
    }
}
```

This replaces `context.account.postbox.loadedPeerWithId(peerId)` while preserving signature shape. The `mapToSignal` wrapper is critical: Postbox's `loadedPeerWithId` returns `.never()` (signal never emits) when the peer is missing — it does NOT wait for loading. The engine-data equivalent `get(Peer.Peer(id:))` returns `Signal<EnginePeer?, NoError>` (optional snapshot). Unwrapping with `.never()`-on-nil preserves original semantics exactly, while keeping the outer shape `Signal<EnginePeer, NoError>` non-optional so callers' closures don't have to cascade new optional handling.

**Category distribution (per pre-flight Explore catalog, 60 sites):**

| Category | Count | Body change |
|---|---|---|
| Cat-A (trivial) | 22 | Only EnginePeer-compatible members; type swap only. |
| Cat-B (concrete-type cast) | 25 | `peer as? TelegramUser/Group/Channel/SecretChat` → `if case let .user(user)` (etc.). |
| Cat-C (feeds Peer-typed API) | 13 | `peer._asPeer()` at call point (`makePeerInfoController`, `makeChatRecentActionsController`, `makeChatQrCodeScreen`, `FoundPeer.init`, `SendAsPeer.init`). |

(Cat-B + Cat-C bumped slightly from Explore's catalog after in-edit reclassifications.)

**Engine-access variations:**
- Most consumer modules use `context.engine.data.get(...)` on `AccountContext`.
- `ShareSearchContainerNode.swift` uses `context.engineData.get(...)` because `ShareControllerAccountContext` exposes `engineData: TelegramEngine.EngineData` but not a full `engine`.
- `CallStatusBarNode.swift` (has raw `account: Account` from switch case) constructs `TelegramEngine(account: account)` inline.
- `PresentationGroupCall.swift` uses `self.accountContext.engine.data` instead of the stored `self.account.postbox`.

**TelegramCore internal sites (36) unchanged.** `Postbox.swift` (2 defs), `State/AccountViewTracker.swift`, `State/FetchChatList.swift`, `State/SynchronizePeerReadState.swift`, `Suggestions.swift`, and all `TelegramCore/Sources/TelegramEngine/` internal `_internal_*` helpers still call `postbox.loadedPeerWithId(...)` — they are the Postbox-facing layer.

**Pre-flight efficiency.** An Explore subagent cataloged all 60 sites by category from a single prompt (one-line-per-site output). That catalog made the sweep straightforward: most files fell into identical patterns, enabling template-substitution Edits. Total context spent on discovery was small compared to doing 60 per-site full reads in the main thread.

**Build validation.** First-pass clean build (47 actions, 70s) after sweep completion. Earlier pilot (2 sites, 20s) validated pattern before scaling to all 60.

**Lessons:**

- **`loadedPeerWithId` returns `.never()` on missing peer, not a pending Signal.** Old common misreading: treating it as a "wait-until-loaded" primitive. Actual Postbox source at `Postbox.swift:3925`: `if let peer = self.peerTable.get(id) { return .single(peer) } else { return .never() }`. Preserve this by wrapping `engine.data.get` in `mapToSignal` with the `.never()` fallback — don't replace with plain `|> compactMap { $0 }` (which would drop the signal entirely rather than completing immediately when peer exists).

- **"Keep the signatures to help the typechecker" as a migration principle.** The user (2026-04-24) explicitly directed: keep call-site outer Signal signatures stable (`Signal<EnginePeer, NoError>` non-optional), even at the cost of a 6-line inline `mapToSignal` wrapper at each site. Rationale: 60 sites × optional-cascade body changes > 60 × 6-line wrapper. This is a general principle for sweeps — if the alternative is rewriting every body to handle optionals, prefer the signal-level wrapper to contain the change.

- **Pre-flight cataloging via Explore subagent.** For sweeps with variable per-site body shapes (unlike facade-migration-with-identical-call-expression sweeps), a dispatch to `Explore` with a category-classification prompt collapses inventory cost. Explore's output is small (~60 one-line entries); avoids pulling 60 file fragments into the main thread's context. Required for wave shapes where inventory is non-uniform.

- **Shape-C peer-fed-to-API pattern needs `_asPeer()` at call, not facade.** Because `makePeerInfoController(peer: Peer)` / `FoundPeer(peer: Peer, ...)` / `SendAsPeer(peer: Peer, ...)` / `makeChatQrCodeScreen(peer: Peer, ...)` all stay on raw `Peer` (they're AccountContext-protocol or TelegramCore struct-init APIs whose migration is its own multi-wave effort), the bridge is a single `._asPeer()` at the call. Don't try to also migrate those APIs in the sweep — blast radius too large.

- **Engine-access varies by containing context.** Plain `context.engine.data` works for ~85% of sites; the remainder need `TelegramEngine(account: account)` construction or `engineData` protocol property. Build a per-site `context` type check into pre-flight for call-site categories where `AccountContext` isn't guaranteed.

Plan / record: no plan doc this wave — user specified the migration pattern directly; the Explore catalog + commit message captured decisions.

---

## Wave 34 outcome (2026-04-24)

`FoundPeer.peer: Peer → EnginePeer`. Public field-type migration on the struct in `submodules/TelegramCore/Sources/TelegramEngine/Peers/SearchPeers.swift`. Atomic 12-file commit `fdd5b93998`. ~135 insertions / ~134 deletions.

**Migration shape.** The field-type change is necessarily atomic (half-migrated FoundPeer doesn't compile across consumers), so all edits land in one commit. `_internal_searchPeers` keeps `import Postbox` (still calls `postbox.transaction` etc.) and wraps raw peer values with `EnginePeer(peer)` at the FoundPeer constructor sites. `==` body changes from `lhs.peer.isEqual(rhs.peer)` to `lhs.peer == rhs.peer`.

**Final scope (vs planned ~70 semantic edits → actual ~135 line insertions):**
- 5 `._asPeer()` bridge-drops at FoundPeer constructor sites (e.g., `FoundPeer(peer: peer._asPeer(), ...)` → `FoundPeer(peer: peer, ...)`)
- 22+ redundant `EnginePeer(peer.peer)` wrap drops (the field is now EnginePeer; `EnginePeer.init(_ peer: Peer)` doesn't accept an EnginePeer argument so the wrap fails to compile)
- 30+ Postbox-concrete-type downcasts (`peer.peer as? TelegramX` / `is TelegramX`) rewritten to `if case let .X(x) = peer.peer` enum-pattern form
- ~10 `._asPeer()` outflow bridges added where `peer.peer` flows into APIs that still take raw `Peer`: `ContactListPeer.peer(peer:)`, `canSendMessagesToPeer(_:)`, `EngineRenderedPeer(peer:)` legacy paths

**Inventory undercounting — pattern.** Original Explore inventory pass missed 4 of 12 final consumer files. The grep `grep -rln "FoundPeer\b"` only catches files that name `FoundPeer` as a literal type. Files that USE `peer.peer` access on FoundPeer values without naming the type itself were invisible to that grep. The build verification pass surfaced them:

| File | Surfaced by | Edits needed |
|---|---|---|
| `TelegramCore/Calls/GroupCalls.swift` | iter 1 | 2 internal FoundPeer constructors needed `EnginePeer(peer)` wraps |
| `ShareController/ShareSearchContainerNode.swift` | iter 2 | 4 errors: 2 C2 downcasts + 2 outflow-bridge needs |
| `ContactListUI/ContactsSearchContainerNode.swift` | iter 3 | 7 errors: nested `if !(peer is X)` rewrite + multiple downcasts/outflows |
| `PeerInfoUI/ChannelMembersSearchContainerNode.swift` | iter 4 | 6 errors across 2 near-identical loop blocks |
| `ChatListUI/ChatListSearchListPaneNode.swift` (extra site) | iter 5 | 1 missed C2 site at line 3723 (in `.globalPeer(foundPeer, …)` enum case body, far from the other ChatListUI edits) |

5 build iterations total before clean (each iteration: edit → re-build, ~50–60s incremental). First-pass would have needed a much wider pre-flight grep — see lessons.

**Lessons:**

- **Inventory grep must include the access pattern, not just the type name.** For a field-type migration, ALL of:
  - `<Type>(peer:` constructors
  - `<x>.peer.<member>` reads (verify `<x>` type is `<Type>`, not RenderedPeer/SendAsPeer/etc.)
  - `<x>.peer as?` / `<x>.peer is` downcasts
  - `<api>(<x>.peer)` arg passes (where `<api>` may take the old protocol)
  
  Use `for x in Y` binding-tracing to determine if `<x>` is the migrated type. The wave-34 pre-flight ran the first three but not the fourth (outflow-arg sites), and partially missed the second (because the Explore agent classified by literal `FoundPeer` token rather than by `peer.peer` semantics in context).

- **`if !(peer is A || peer is B)` rewrite uses `switch case A, B: break / default: ...`.** When the original Postbox code uses a negated disjunction of type-checks, the cleanest enum-pattern equivalent is a `switch` with combined cases in one arm — not nested `if case`s. (Used in ChatListSearchListPaneNode:1024 and ContactsSearchContainerNode:502/544.)

- **Inner `peer` shadowing.** Many `else if let peer = peer.peer as? TelegramChannel` Postbox patterns shadow the loop variable. The enum-pattern rewrite renames the inner binding to `channel` to avoid double-shadowing the EnginePeer outer loop var. Block-internal references to `.info` etc. then move from `peer.info` to `channel.info`.

- **Build iteration = inventory completion.** When the inventory undercounting becomes apparent (build surfaces 5+ unexpected sites), don't abandon — iterate. Each build is fast (~50s incremental) and each error is actionable (`error: cast from EnginePeer to unrelated type X always fails` → C2 rewrite; `argument type EnginePeer does not conform to expected type Peer` → outflow bridge). The inventory grows by file, fix-then-rebuild converges in 5 iterations even when ~30% of sites were missed up front.

- **Bridge sites generated by this wave point to next-ring migration targets.** The ~10 `._asPeer()` outflow bridges land at `ContactListPeer.peer(peer:)`, `canSendMessagesToPeer(_:)`, and `EngineRenderedPeer(peer:)` (legacy raw-Peer constructor in some paths — e.g., `EngineRenderedPeer(peer: foundPeer.peer)` doesn't need a bridge in newer EnginePeer-aware paths but does where the local var was already raw-Peer-extracted). These three signatures are the obvious wave-35+ candidates for the next ring of migration.

**Plan / record:** `docs/superpowers/plans/2026-04-24-foundpeer-engine-peer-migration.md`. Spec: `docs/superpowers/specs/2026-04-24-foundpeer-engine-peer-migration-design.md`.

---

## Wave 35 outcome (2026-04-24)

`SendAsPeer.peer: Peer → EnginePeer`. Public field-type migration on the struct in `submodules/TelegramCore/Sources/TelegramEngine/Messages/SendAsPeers.swift`. Atomic 7-file commit `583c8b1f7c`. 22 insertions / 26 deletions.

**Migration shape.** Same atomic-field-type pattern as wave 34 but scoped to a smaller consumer surface. The `_internal_*SendAsAvailablePeers` functions keep `import Postbox` and wrap raw peer values with `EnginePeer(peer)` at the 4 SendAsPeer constructor sites. Manual `==` body dropped in favor of synthesized Equatable (`EnginePeer: Equatable`, `Int32?` and `Bool` already Equatable).

**Final scope (vs planned ~15 semantic edits → actual 22/26 line diff):**
- 3 `._asPeer()` bridge-drops at SendAsPeer constructor sites (ChatControllerLoadDisplayNode:772, ChatTextInputPanelComponent:848, StoryItemSetContainerViewSendMessage:249)
- 7 redundant `EnginePeer(peer.peer)` / `EnginePeer($0.peer)` / `EnginePeer(value.peer)` wrap drops across ChatSendAsPeerListContextItem (4 sites), ChatTextInputPanelNode (1), StoryItemSetContainerViewSendMessage (1), StoryItemSetContainerComponent (1)
- 1 `peer.peer as? TelegramChannel` downcast rewritten to `if case let .channel(channel) = peer.peer` (ChatSendAsPeerListContextItem:73) with `peer.info → channel.info` rename in the shadowed scope
- 2 `EnginePeer(channel)` wraps added where raw `TelegramChannel` is constructed into `SendAsPeer(peer: ...)` (ChatControllerLoadDisplayNode:805, 823)
- 1 signal-chain simplification: `(sendAsPeer?.peer).flatMap(EnginePeer.init)` → `sendAsPeer?.peer` at StoryItemSetContainerViewSendMessage:4080
- 1 signal-chain simplification: `.map({ EnginePeer($0.peer) })` → `.map({ $0.peer })` at StoryItemSetContainerViewSendMessage:4081

**Inventory undercount = 1 site (vs wave 34's 5).** The pre-flight Explore catalog missed `StoryItemSetContainerComponent.swift:3069` (`currentPeer: EnginePeer(value.peer)` → `value.peer`). The implementer caught it during the edit phase before the build, so no iteration was needed. The wave-34 explicit pattern grep (including `.peer as?`/`is`/outflow-args/`EnginePeer(.peer)`/`._asPeer()`) dramatically reduced undercounting — 1/7 sites missed (~14%) vs wave 34's 4/12 (~33%).

**First-pass clean build.** No errors surfaced by the Bazel build at all. 461 total actions, 196.583s elapsed, `INFO: Build completed successfully`. Contrast with wave 34's 5 build-iterations-to-converge.

**Lessons:**

- **Wave 34's explicit-pattern pre-flight inventory works.** For future Peer-typed-API waves, the minimum grep pattern set is: `<Type>\b` literal token, `\.<fieldName>\s+(as\?|is)\s+Telegram`, `EnginePeer\(\w+\.<fieldName>\)`, `<api>\(<x>\.<fieldName>` for known outflow APIs, and `\._asPeer\(\)` (to catch bridge-drop opportunities). Wave 35 used this full pattern set and hit ~14% undercount vs wave 34's ~33%.

- **Smaller target + validated pattern = faster wave.** Wave 35 went from spec-commit (`72d4384af0`) to outcome-commit in a single session with one clean build, versus wave 34's multi-iteration convergence. When the wave is a replay of a just-validated pattern on a smaller surface, expect minimal iteration.

- **Inner-peer shadowing rename works.** The wave-34 lesson about renaming `peer` → `channel` in `if case let .channel(channel) = peer.peer` applied cleanly. Single instance this wave (ChatSendAsPeerListContextItem:73) — no issues.

- **Name collisions remain a scope hazard.** Pre-flight identified `sendAsPeers: [EnginePeer]` (LiveStreamSettingsScreen, ShareWithPeersScreen) and `availableSendAsPeers: [EnginePeer]` (ChatSendStarsScreen) as name-only collisions — different type, same identifier. Confirmed these stayed untouched and out of scope. Future Peer-typed-API waves should continue the name-collision disambiguation pass.

- **Bridge sites generated by this wave — zero new outflow bridges.** Unlike wave 34 (which added ~10 `._asPeer()` outflow bridges pointing to `ContactListPeer.peer(peer:)` / `canSendMessagesToPeer(_:)` / `EngineRenderedPeer(peer:)` as next-ring targets), wave 35 added no outflow bridges. All consumer-side `.peer` flows either stayed as `.peer.id` accesses (PeerId unchanged) or were simplifications of existing `EnginePeer(.peer)` wraps. Net: no new next-ring targets surfaced from wave 35.

**Plan / record:** `docs/superpowers/plans/2026-04-24-sendaspeer-engine-peer-migration.md`. Spec: `docs/superpowers/specs/2026-04-24-sendaspeer-engine-peer-migration-design.md`.

---

## Wave 36 outcome (2026-04-24)

`ContactListPeer.peer(peer: Peer, isGlobal:, participantCount:) → peer: EnginePeer`. Enum-case payload migration on the public type in `submodules/AccountContext/Sources/ContactSelectionController.swift`. Atomic 15-file commit `069a060de1`. 57 insertions / 59 deletions.

**Migration shape.** Same atomic-payload-type pattern as wave 34/35 but wider: 15 consumer files vs wave 35's 7, vs wave 34's 12. Beyond the payload change, the cascading `ContactListPeer.indexName` return type changed from `PeerIndexNameRepresentation` to `EnginePeer.IndexName` — an unexpected discovery during plan-writing that dropped 2 additional `EnginePeer.IndexName(...)` wraps at ContactListNode:517.

**Final scope (vs planned 8 files / ~41 semantic edits → actual 15 files / 57/59 diff):**

- **Definition (1 file):** `AccountContext/ContactSelectionController.swift` — case payload type, indexName return type, `==` operator body (`lhsPeer.isEqual(rhsPeer)` → `lhsPeer == rhsPeer`).
- **20 `._asPeer()` outflow bridge-drops** across ContactListNode (12), ContactsSearchContainerNode (3), ContactMultiselectionController (2), ContactMultiselectionControllerNode (1), ContactSelectionControllerNode (2). `replace_all=true` on `._asPeer(), isGlobal:` was the unifying substring.
- **20+ `EnginePeer(peer)` inflow wrap-drops** at destructure sites across ContactListNode (4), ContactsController (1), ContactsSearchContainerNode (4), ContactMultiselectionController (4), ContactMultiselectionControllerNode (1), ContactSelectionController (2), PeerSelectionControllerNode (3), SharedAccountContext (2).
- **2 `EnginePeer.IndexName(...)` wrap-drops** at the sort-comparator at ContactListNode:517 (enabled by the cascading return-type change).
- **8 Postbox-concrete cast rewrites** to EnginePeer case patterns across ContactListNode:182-186/1968 (4 sites, including the 3-branch user/group/channel cast-chain), CallController:524/542 (the intermediate `let peer = EnginePeer(peer)` lines became redundant after migration), StoryItemSetContainerViewSendMessage:2041/2074, DeviceContactInfoController:1419, ChatSendAudioMessageContextPreview:89, ChatControllerOpenAttachmentMenu:557/610/1746/1788 (4 identical sites, `replace_all` on the full line).
- **2 `._asPeer()` outflow bridges ADDED** at ContactMultiselectionController:386/403 where the destructured peer flows into `peerTokenTitle(peer: Peer)` (out-of-scope callee; future-wave bridge target).

**Inventory undercount = 7 files / ~20 sites (vs wave 35's 1 site).** Much higher miss rate than wave 35 — ~46% by file count. Root cause: the pre-flight grep for ContactListPeer destructures used literal `\(peer, _, _\)` binding; binding names varied in practice (`contact`, `lhsPeer`, `rhsPeer`, `contactPeer`, `id`). Files missed:

1. `DeviceContactInfoController.swift:1418/1419` — `case let .peer(contact, _, _)` + `contact as? TelegramUser`
2. `CallController.swift:523/541` — `case let .peer(peer, _, _)` + redundant `let peer = EnginePeer(peer)` pattern
3. `ChatSendAudioMessageContextPreview.swift:88/89` — `case let .peer(contact, _, _)` + `contact as? TelegramUser`
4. `PeerSelectionControllerNode.swift:901-903/1590-1592` — 2 destructures with `EnginePeer(peer)` inflow wraps
5. `StoryItemSetContainerViewSendMessage.swift:2040-2041/2073-2074` — 2 `contact as? TelegramUser` casts
6. `ChatControllerOpenAttachmentMenu.swift:556-1787` — 4 `contact as? TelegramUser` casts
7. `SharedAccountContext.swift:3295-3302` — `case let .peer(peer, _, _)` + 2 `EnginePeer(peer)` inflow wraps

**Six build iterations to converge** vs wave 35's single first-pass-clean. Iterations 1-6 surfaced errors in batches of 2-8 errors; each was a mechanical fix (drop wrap, rewrite cast, add `._asPeer()` bridge for outflow to out-of-scope `peerTokenTitle`). Final iteration (#6) clean.

**Lessons:**

- **Pre-flight grep must use `\(\w+, _, _\)` not `\(peer, _, _\)` for enum-payload destructures.** Swift destructure patterns bind the payload to any legal identifier; the variable name is not semantic. Future Peer-typed-enum-payload waves should use `case let \.<caseName>\((\w+),` (or similar wildcard binding) and then per-destructure scan the next ~15 lines for `<binding> as\?`/`<binding> is`/`EnginePeer\(<binding>\)` / outflow-arg patterns.

- **"No-edit consumer" claims need stricter verification.** Wave 36's "verify-only" list included ChatSendAudioMessageContextPreview because the initial inventory found only `[ContactListPeer]` at collection level. The deeper scan missed a `case let .peer(contact, _, _)` + `contact as? TelegramUser` pattern inside the file's `update(...)` method. For future waves, "no-edit" claims should run the wildcard-binding destructure grep described above, not just a construction-site grep.

- **Outflow-to-out-of-scope-API bridges may need addition during the wave.** ContactMultiselectionController:386/403 needed `._asPeer()` bridges added where none existed pre-migration — the pre-migration code passed raw `Peer` to `peerTokenTitle(peer: Peer)` because the destructured peer was raw Peer. Post-migration, the destructured peer is EnginePeer, so a bridge is required. Future waves with same-scope outflow to not-yet-migrated Peer-typed APIs should pre-flight expect to add bridges.

- **Cascading computed-property return type migration** (here: `ContactListPeer.indexName` from `PeerIndexNameRepresentation` to `EnginePeer.IndexName`) is a legitimate scope expansion when the enum's properties leak Postbox-typed values. Wave 36 caught this during plan-writing, not execution — a successful plan-review win. Future waves should grep the enum's definition file for computed properties returning Postbox-defined types.

- **Build-iteration convergence is acceptable** when the wave's surface is large and pre-flight undercount is non-trivial. The cost of 6 build iterations (~5-20 minutes each in the Telegram-iOS build) is real but manageable. The alternative — exhaustive pre-flight to achieve first-pass-clean — is more expensive in plan-writing tokens and controller wall time. For waves expected to have >5 file touches, plan should explicitly budget for 3-5 build iterations.

- **Ratchet effect confirmed.** Wave 36 was predominantly bridge-removal (20 outflow + 20 inflow + 2 IndexName) with only 2 bridge additions. Matches the expected ratchet behavior: earlier waves 33/34/35 added bridges at Peer/EnginePeer boundaries precisely so wave 36 could drop them atomically. The 2 new bridges added (ContactMultiselectionController:386/403 → peerTokenTitle) become next-wave drop candidates once `peerTokenTitle(peer: Peer)` migrates.

**Plan / record:** `docs/superpowers/plans/2026-04-24-contactlistpeer-engine-peer-migration.md`. Spec: `docs/superpowers/specs/2026-04-24-contactlistpeer-engine-peer-migration-design.md`.

---

## Modules currently free of `import Postbox` (running tally)

Consumer modules that no longer import Postbox, across all waves and standalone commits:

- `ChatInterfaceState` (wave 1)
- `ChatSendMessageActionUI` (wave 1)
- `ContactListUI` (wave 1)
- `DrawingUI` (wave 1)
- `StickerPeekUI` (standalone cleanup, 2026-04-17 — import was unused)
- `PromptUI` (standalone cleanup)
- `PresentationDataUtils` (standalone cleanup)
- `MapResourceToAvatarSizes` (wave 2)
- `SaveToCameraRoll` (wave 3)
- `SecureIdVerificationDocumentsContext` (wave 5)
- **Wave 6 batch: 189 additional modules** — see `git show 7b2b74e79b --stat` for the commit that swept unused `import Postbox` lines across 183 files in 16 consumer submodules. Not individually enumerated here for brevity.
- `StorageUsageScreen` (waves 8–10)
- `ActionSheetPeerItem` (wave 11; revisits wave-1 abandonment)
- `HorizontalPeerItem` (wave 12; applies wave-11 pattern)
- `SelectablePeerNode` (wave 15; applies wave-11 pattern; ShareExtension-boundary stateManager fallback)
- `ItemListAvatarAndNameInfoItem` (wave 17; applies wave-11 pattern; ShareExtension-boundary stateManager fallback)
- `ItemListStickerPackItem` (wave 18; mixed-shape — 3 narrow TelegramCore typealiases + wave-4 enum-payload migration + wave-3 facade swap)
- `AttachmentTextInputPanelNode` BUILD cleanup (wave 13; source was already clean from wave 6)
- **Wave 14 BUILD-dep sweep: 98 modules' BUILDs cleaned** — same modules as the wave-6 batch; this sweep fixed their leftover `//submodules/Postbox:Postbox` BUILD deps. Candidate list in `/tmp/postbox-dep-candidates.txt` at commit time; derivable by the script in "Wave 14 outcome".
