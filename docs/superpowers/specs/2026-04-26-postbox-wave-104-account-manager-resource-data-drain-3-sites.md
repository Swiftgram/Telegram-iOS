# Wave 104 — accountManager.mediaBox.resourceData drain (3 clean sites)

**Date:** 2026-04-26
**Pattern:** wave-shape-G drain of an existing TelegramCore facade (the wave-32 / wave-94 `AccountManagerResources.data(resource:pathExtension:waitUntilFetchStatus:attemptSynchronously:)`) with a documented field rename at consumer sites (`.complete` → `.isComplete`).
**Module:** `submodules/WallpaperResources/Sources/WallpaperResources.swift` only.

## Goal

Drain 3 of 8 `accountManager.mediaBox.resourceData(...)` Shape-A sites against the existing facade. Net effect: −3 raw `accountManager.mediaBox.X` accesses, +3 facade calls, +3 `EngineMediaResource(...)` wraps, +3 consumer `.complete` → `.isComplete` renames.

The remaining 5 sites are deferred: 2 (`FetchCachedRepresentations.swift:482, 490`) flow `data: MediaResourceData` into `fetchCachedScaledImageRepresentation` / `fetchCachedBlurredWallpaperRepresentation` — both expect raw Postbox `MediaResourceData`, so migration would force a cascade or boundary reconstruction. 3 (`WallpaperResources.swift:33, 59, 401`) are coupled to postbox-side via `combineLatest(accountManager.mediaBox.resourceData, account.postbox.mediaBox.resourceData)` returning typed `Signal<(MediaResourceData, MediaResourceData), NoError>` — migrating one side without the other breaks the tuple type.

## Wave-71-shadow risk inventory (per `feedback_wave71_shadow_risk.md`)

| Layer | Applicable? | Notes |
|---|---|---|
| 1. Downcasts | N/A | No type-level migration |
| 2. Peer-protocol extension method calls | N/A | Not a peer migration |
| 3. Field flow into Peer-typed function parameters | Adapted: result-type flow into MediaResourceData-typed params | **Cleared:** all 3 sites consume `maybeData.complete` and `maybeData.path` inline within the closure — no flow-out to functions taking raw `MediaResourceData`. Sites that DO flow out (482/490) are deferred. |
| 4. Message-builder cascade | N/A | No `Message(...)` construction touched |

The "data: MediaResourceData" parameter at `fetchCachedScaledImageRepresentation:311` / `fetchCachedBlurredWallpaperRepresentation:453, 502` is the analogue of the wave-103 `Message.peers` constructor barrier — a Postbox-typed function-parameter barrier that forces ADD bridges if upstream migrates. The 3 chosen sites do not cross this barrier; the deferred 2 sites do.

## Sites (3 total)

### Call rewrites

| Line | Existing call | Migrated call |
|---|---|---|
| 957 | `let maybeFetched = accountManager.mediaBox.resourceData(reference.resource, option: .complete(waitUntilFetchStatus: false), attemptSynchronously: synchronousLoad)` | `let maybeFetched = accountManager.resources.data(resource: EngineMediaResource(reference.resource), attemptSynchronously: synchronousLoad)` |
| 1164 | `let maybeFetched = accountManager.mediaBox.resourceData(fileReference.media.resource, option: .complete(waitUntilFetchStatus: false), attemptSynchronously: synchronousLoad)` | `let maybeFetched = accountManager.resources.data(resource: EngineMediaResource(fileReference.media.resource), attemptSynchronously: synchronousLoad)` |
| 1264 | `return accountManager.mediaBox.resourceData(file.file.resource)` | `return accountManager.resources.data(resource: EngineMediaResource(file.file.resource))` |

**`waitUntilFetchStatus: false` is omitted** in the migrated form — the facade signature has `waitUntilFetchStatus: Bool = false` as default. Sites 957/1164 explicitly pass `false`; site 1264 uses the underlying default.

### Consumer-side renames (`.complete` → `.isComplete`)

| Line | Existing | Migrated |
|---|---|---|
| 961 | `        if maybeData.complete {` | `        if maybeData.isComplete {` |
| 1168 | `                if maybeData.complete && isSupportedTheme {` | `                if maybeData.isComplete && isSupportedTheme {` |
| 1266 | `                                    if data.complete, let imageData = try? Data(contentsOf: URL(fileURLWithPath: data.path)) {` | `                                    if data.isComplete, let imageData = try? Data(contentsOf: URL(fileURLWithPath: data.path)) {` |

### Sites NOT migrated (deferred)

- L33, L59, L401 — `combineLatest(accountManager.mediaBox.resourceData(X), account.postbox.mediaBox.resourceData(X))` (typed tuple return)
- L482, L490 (in FetchCachedRepresentations.swift, not WallpaperResources.swift) — `data: MediaResourceData` flow-out cascade
- The closure bodies at sites 957, 1164 contain INNER `account.postbox.mediaBox.resourceData(...)` calls and inner `data.complete` accesses on a different binding (the postbox-side result) — those stay raw and are NOT touched by this wave. Only the OUTER `maybeFetched`-typed result is migrated.

## Type reference

Facade signature (existing, wave-32 / wave-94):

```swift
public func data(
    resource: EngineMediaResource,
    pathExtension: String? = nil,
    waitUntilFetchStatus: Bool = false,
    attemptSynchronously: Bool = false
) -> Signal<EngineMediaResource.ResourceData, NoError>
```

`EngineMediaResource.ResourceData` (final class at `TelegramCore/Sources/TelegramEngine/Resources/TelegramEngineResources.swift:149`):
- `public let path: String` (matches `MediaResourceData.path`)
- `public let availableSize: Int64`
- `public let isComplete: Bool` (renamed from `MediaResourceData.complete`)

`EngineMediaResource(_ resource: MediaResource)` constructor — canonical wrap (CLAUDE.md cheat sheet).

## Edit patterns

6 separate Edit calls in 1 file. No `replace_all=true` opportunity — each call/rename has unique surrounding text.

**Order (recommended):** call rewrites first (3 edits), then consumer renames (3 edits). This sequence keeps the file in a half-migrated but compilable state between batches if interrupted (call site uses new facade, consumer still on old field name → swift compile error caught quickly).

Alternative order: per-site bundled (call + rename pair, then next pair) — also fine.

## Risk register

| Risk | Mitigation |
|---|---|
| `EngineMediaResource(rawResource)` constructor missing | Verified: constructor exists per CLAUDE.md cheat sheet ("EngineMediaResource(rawResource) — wrap a raw MediaResource"). |
| `.path` field mismatch | Verified: both `MediaResourceData.path` and `EngineMediaResource.ResourceData.path` are `String`. No edit needed at any `data.path` usage site. |
| `.availableSize` not exposed by `MediaResourceData` | None of the 3 consumers use `.availableSize`. Only `.complete` (renamed) and `.path` (unchanged) are used. |
| Inner `data.complete` accesses on postbox-side bindings get renamed by accident | The 3 renames are on distinct bindings (`maybeData`, `maybeData`, `data`) within distinct outer scopes. The inner `data.complete` at L968 (postbox-side closure body inside site 957) is on a DIFFERENT `data` binding — its surrounding text differs (`return data.complete ? try? Data(...)` vs the migrated `if data.complete, let imageData = try? Data(...)`). Each Edit's `old_string` includes enough surrounding text to disambiguate. |
| `Signal.complete()` confused with field rename | The renames target `<binding>.complete` (property access). `Signal.complete()` is a method call, syntactically distinct (`return .complete()`). No regex collision. |
| `attemptSynchronously: synchronousLoad` arg flows | Facade exposes `attemptSynchronously: Bool = false`. Site 957/1164 pass `synchronousLoad` (a function param of the same name, Bool-typed) — flows through unchanged. |
| Build cascade beyond touched file | WallpaperResources is foundational with wide rebuild fan-out, but the public API is unchanged so dependents don't recompile. Build cost projection: ~30-60s. |

## Wave shape

**Classification:** wave-shape-G drain of an existing TelegramCore facade with a documented consumer field rename. Mid-difficulty between wave-103-retry (pure mechanical) and wave-71-shadow (cascade-prone).
**Iteration budget:** 1 (target first-pass-clean given small footprint and verified pre-flight inventory).
**Subagent dispatch:** not needed — 6 edits in 1 file is single-implementer scope.

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

(No `--continueOnError` — small atomic scope.) Build cost projection: ~30-60s.

### Post-edit residue grep (expect specific output, NOT empty)

```sh
grep -rn "accountManager\.mediaBox\.resourceData" submodules/WallpaperResources/Sources/WallpaperResources.swift
```

Expected: 3 lines remaining (L33, L59, L401 — the deferred combineLatest sites). Sites 957, 1164, 1264 should NOT appear.

```sh
grep -nE "maybeData\.complete\b|^.*\bdata\.complete\b" submodules/WallpaperResources/Sources/WallpaperResources.swift
```

Expected: a small number of lines remaining at unrelated sites (the postbox-side inner closure at site-957's L968 still uses `data.complete` on a postbox-side binding — that stays). Lines 961, 1168, 1266 should NOT appear.

## Net delta projection

| Category | Count | Sites |
|---|---|---|
| Raw `mediaBox.resourceData` accesses dropped | −3 | WR:957, 1164, 1264 |
| Facade calls added | +3 | same sites, migrated form |
| `EngineMediaResource(...)` wraps added | +3 | canonical engine-side wraps, not Postbox bridges |
| Consumer `.complete` → `.isComplete` renames | +3 | WR:961, 1168, 1266 |
| `import Postbox` drops | 0 | WallpaperResources retains Postbox import for unrelated symbols |
| Postbox-free module count | 0 | unchanged |

## Out of scope

- Sites 482/490 in FetchCachedRepresentations.swift — `data: MediaResourceData` cascade through `fetchCachedScaled*Representation` family. Defer to a session that designs the appropriate facade or migrates the cascade as a co-wave.
- Sites 33/59/401 in WallpaperResources.swift — `combineLatest(accountManager.mediaBox.resourceData, account.postbox.mediaBox.resourceData)` typed-tuple coupling. Defer until postbox-side `account.postbox.mediaBox.resourceData` is also drainable (Shape-C territory) or a paired-resource facade is designed.
- The 22 `cachedResourceRepresentation` accountManager-side sites — blocked by `CachedMediaResourceRepresentation` Postbox protocol leak.

## Memory file update

After landing, update `project_postbox_refactor_next_wave.md`:
- Add wave 104 outcome line into the recent-waves section.
- Update accountManager-side facade drain status table: `resourceData` count drops from 8 → 5 (3 drained, 5 deferred).
- Note the `fetchCachedScaled*Representation` cascade barrier — adds it to the list of "Postbox-typed-function-parameter barriers" alongside `Message.peers: SimpleDictionary<PeerId, Peer>`.
