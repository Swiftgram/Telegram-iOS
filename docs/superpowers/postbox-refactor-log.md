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
