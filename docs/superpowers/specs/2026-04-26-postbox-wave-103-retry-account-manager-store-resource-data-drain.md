# Wave 103 (retry) — accountManager.mediaBox.storeResourceData drain

**Date:** 2026-04-26
**Pattern:** wave-shape-G drain of an existing TelegramCore facade (the wave-94 `AccountManagerResources.storeResourceData(id:data:synchronous:)`).
**Module:** `submodules/TelegramUI/Sources/ThemeUpdateManager.swift` + `submodules/WallpaperResources/Sources/WallpaperResources.swift` only — no TelegramCore touch, no public-API change.

## Goal

Drain the 5 remaining `accountManager.mediaBox.storeResourceData(...)` Shape-A sites that the wave-94/95-99 sweep didn't catch. Migrate each to `accountManager.resources.storeResourceData(id: EngineMediaResource.Id(...), data: ..., synchronous: ...)` against the existing wave-94 facade. Net effect: −5 raw `accountManager.mediaBox.X` accesses, +5 facade calls. Consumer-only build.

This is the wave-103 retry after the abandonment of `ChatRecentActionsControllerNode.peer` migration (see `postbox-refactor-log.md` "Wave 103 outcome (2026-04-26): ABANDONED").

## Wave-71-shadow risk inventory (per `feedback_wave71_shadow_risk.md`)

| Layer | Applicable? | Notes |
|---|---|---|
| 1. Downcasts (`as?` / `is`) | N/A | No Peer migration, no type-level change |
| 2. Peer-protocol extension method calls | N/A | No stored field retype |
| 3. Field flow into Peer-typed function parameters | N/A | No `peer` param involved |
| 4. Message-builder cascade via `SimpleDictionary<PeerId, Peer>` | N/A | No `Message(...)` construction touched |

Wave shape (call-site rewrite against an existing facade) is orthogonal to the wave-71-shadow risk layers. The wave-94 lesson and wave-shape-G recipe are the relevant precedents.

## Sites (5 total)

### ThemeUpdateManager.swift (1 site)

| Line | Existing | Migrated |
|---|---|---|
| 112 | `accountManager.mediaBox.storeResourceData(file.file.resource.id, data: fullSizeData, synchronous: true)` | `accountManager.resources.storeResourceData(id: EngineMediaResource.Id(file.file.resource.id), data: fullSizeData, synchronous: true)` |

`accountManager` flows from the enclosing `presentationThemeSettingsUpdated(_:)` method's closure-captured scope. `accountManager: AccountManager<TelegramAccountManagerTypes>` typed (Shape-A).

### WallpaperResources.swift (4 sites)

All four sites use the same call-text pattern (same arity, no `synchronous:` arg) but different argument expressions:

| Line | Argument expression |
|---|---|
| 973 | `reference.resource.id, data: data` |
| 1214 | `reference.resource.id, data: data` |
| 1260 | `file.file.resource.id, data: fullSizeData` |
| 1523 | `file.file.resource.id, data: fullSizeData` |

Lines 973 and 1214 share identical text (`accountManager.mediaBox.storeResourceData(reference.resource.id, data: data)`) — `Edit replace_all=true` bundles them. Lines 1260 and 1523 share identical text (`accountManager.mediaBox.storeResourceData(file.file.resource.id, data: fullSizeData)`) — same.

Each migrated to: `accountManager.resources.storeResourceData(id: EngineMediaResource.Id(<argument expression>), data: <data expression>)`.

`accountManager` flows from `wallpaperDatas(account:accountManager:...)` and other public functions in the file, all parameter-typed `AccountManager<TelegramAccountManagerTypes>` (Shape-A).

## Edit patterns

### A. ThemeUpdateManager (1 site)

Single Edit:

| File:Line | Before | After |
|---|---|---|
| ThemeUpdateManager.swift:112 | `accountManager.mediaBox.storeResourceData(file.file.resource.id, data: fullSizeData, synchronous: true)` | `accountManager.resources.storeResourceData(id: EngineMediaResource.Id(file.file.resource.id), data: fullSizeData, synchronous: true)` |

### B. WallpaperResources (4 sites in 2 replace_all batches)

Two `Edit` calls, each with `replace_all=true`:

| Pattern | Before | After |
|---|---|---|
| Pattern 1 (lines 973, 1214) | `accountManager.mediaBox.storeResourceData(reference.resource.id, data: data)` | `accountManager.resources.storeResourceData(id: EngineMediaResource.Id(reference.resource.id), data: data)` |
| Pattern 2 (lines 1260, 1523) | `accountManager.mediaBox.storeResourceData(file.file.resource.id, data: fullSizeData)` | `accountManager.resources.storeResourceData(id: EngineMediaResource.Id(file.file.resource.id), data: fullSizeData)` |

**Total edits:** 3 Edit calls (1 single + 2 replace_all batches), 5 sites migrated.

## Facade signature reference

From `submodules/TelegramCore/Sources/AccountManager/AccountManagerResources.swift` (added wave 94):

```swift
public func storeResourceData(id: EngineMediaResource.Id, data: Data, synchronous: Bool = false) {
    self.mediaBox.storeResourceData(MediaResourceId(id.stringRepresentation), data: data, synchronous: synchronous)
}
```

`EngineMediaResource.Id(_ id: MediaResourceId)` constructor at `TelegramCore/Sources/TelegramEngine/Resources/TelegramEngineResources.swift:179`.

`accountManager.resources` is a computed property that constructs a fresh `AccountManagerResources` wrapper holding only a `MediaBox` reference — cheap.

## Risk register

| Risk | Mitigation |
|---|---|
| `replace_all=true` matching the wrong site | Two patterns are scoped narrowly enough (full call expressions including the closing paren). Pre-flight grep confirmed exactly 2 instances of each pattern across the file. |
| `EngineMediaResource.Id(...)` constructor missing for the argument expression's type | Verified: `init(_ id: MediaResourceId)` exists. `MediaResource.id` returns `MediaResourceId` per Postbox protocol. Construction is canonical. |
| `synchronous:` default mismatch | Facade default is `synchronous: false`, matching `MediaBox.storeResourceData`'s underlying default. Sites without explicit `synchronous:` keep behavior. |
| Build cascade beyond touched files | Consumer-only — both files are leaf consumers (no public re-export of touched symbols). No TelegramCore touch. WallpaperResources is foundational so its rebuild fans out, but the public API is unchanged so dependent modules don't need recompilation. |
| WIP-interference at staging | Pre-existing WIP markers (`build-system/bazel-rules/sourcekit-bazel-bsp` + 3 untracked dirs) are in unrelated paths — no overlap. Stage by explicit file list. |

## Wave shape

**Classification:** wave-shape-G drain of an existing TelegramCore facade (waves 84-93 cohort, validated wave 94 + waves 95-99 drains).
**Iteration budget:** 1 (target first-pass-clean given mechanical scope and 5-site footprint).
**Subagent dispatch:** not needed — 3 Edit calls is single-implementer scope.

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

(No `--continueOnError` — small atomic scope.) WallpaperResources is a foundational submodule with a wide rebuild fan-out, but its public API is unchanged so dependents don't recompile. Build cost projection: ~30-60s.

### Post-edit residue grep (expect empty)

```sh
grep -rn "accountManager\.mediaBox\.storeResourceData" \
  submodules/TelegramUI/Sources/ThemeUpdateManager.swift \
  submodules/WallpaperResources/Sources/WallpaperResources.swift
```

Expected: empty output across both files.

## Net delta projection

- **Raw `mediaBox.X` accesses:** −5
- **Facade `resources.X` calls:** +5
- **`EngineMediaResource.Id(...)` wraps:** +5 (these are canonical engine-side constructs, not Postbox bridges — they don't count as `_asPeer()`-style ADD wraps)
- **`import Postbox` drops:** 0 (both files retain `import Postbox` for unrelated symbols — this wave doesn't promise an import drop)
- **Postbox-free module count:** 0 net change

## Out of scope

- 7 `accountManager.mediaBox.resourceData(...)` sites — could use the existing `AccountManagerResources.data(resource:)` facade or a future `data(id:)` facade. Defer to a future drain wave.
- 22 `accountManager.mediaBox.cachedResourceRepresentation(...)` sites — Option A holdover, blocked by `CachedMediaResourceRepresentation` Postbox protocol leak. Needs facade-design pass.
- 3 `accountManager.mediaBox.storeCachedResourceRepresentation(...)` sites — same blocker.
- 2 `accountManager.mediaBox.cachedRepresentationCompletePath(...)` sites — same blocker.
- The `accountManager.mediaBox.cachedResourceRepresentation(...)` call at WallpaperResources:1261 and :1524 — directly adjacent to two of our migrated sites but blocked. Leave in place; the migrated `storeResourceData` call directly above it does not depend on it.

## Memory file update

After landing, update `project_postbox_refactor_next_wave.md`:
- Add wave 103 (retry) outcome line into the recent-waves section.
- Mark the 5 sites as drained; remove from candidate inventories.
- Promote the next candidate (likely the 7-site `resourceData` drain or one of the foundational waves).
