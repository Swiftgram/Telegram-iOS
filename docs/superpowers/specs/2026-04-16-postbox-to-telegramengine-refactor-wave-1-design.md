# Postbox → TelegramEngine refactor, wave 1

## Goal

Gradually eliminate direct `import Postbox` from consumer submodules by routing all data access through `TelegramEngine` (`.data.get` / `.data.subscribe` and engine-owned functions). Behavior must be preserved exactly — this is a dependency-shape refactor, not a semantic change.

This spec covers **wave 1**: the first 10 single-import leaf modules, refactored in bottom-up dependency order. Subsequent waves will be covered by their own specs.

## Non-goals

- No refactor inside `TelegramCore` itself — it owns `TelegramEngine` and will keep importing Postbox.
- No refactor inside `Postbox`.
- No behavior or UX changes. No unrelated cleanup.
- No edits to modules outside the 10 chosen by the selection rule.
- Within wave-1 modules, switching Postbox-typed names to their engine typealiases (`PeerId` → `EnginePeer.Id`, etc.) is required and in scope; introducing new engine *wrapper types* that re-encode data is out of scope.
- No generic `engine.transaction { postbox in … }` escape hatch.

## Guiding rules

1. Consumers only. `TelegramCore` does **not** `@_exported import Postbox`, so once a module drops its Postbox import every remaining Postbox-type reference must be switched to the engine-typealiased equivalent (`PeerId` → `EnginePeer.Id`, `MessageId` → `EngineMessage.Id`, `MessageIndex` → `EngineMessage.Index`, `MessageTags` → `EngineMessage.Tags`, `MediaId` → `EngineMedia.Id`, etc.). These aliases are identical to their Postbox originals, so the swap is behavior-preserving.
2. Prefer existing `Engine*` wrapper types (`EnginePeer`, `EngineMessage`, `EngineMediaResource`) and engine methods; add new engine wrappers only when a call site clearly needs one.
3. Before adding any new engine wrapper, search `submodules/TelegramCore/Sources/TelegramEngine/` for an equivalent by name and shape. Record the search result in the commit that adds the wrapper.
4. Bottom-up dependency order across modules.
5. Full project build after each module, using the command from the global `CLAUDE.md`.
6. A module is done when: no `import Postbox` in its `.swift` files, no `//submodules/Postbox:Postbox` entry in its `BUILD`, full build green, commits landed.

## Wave-1 scope: selecting the 10 modules

### Candidate pool

The 30 submodules that currently have Postbox imports in exactly one `.swift` file:

`ActionSheetPeerItem, ChatInterfaceState, ChatListSearchRecentPeersNode, ChatSendMessageActionUI, ContactListUI, DirectMediaImageCache, DrawingUI, FetchManagerImpl, GalleryData, HorizontalPeerItem, ICloudResources, InAppPurchaseManager, InstantPageCache, InviteLinksUI, ItemListAvatarAndNameInfoItem, ItemListPeerItem, ItemListStickerPackItem, MapResourceToAvatarSizes, PhotoResources, PlatformRestrictionMatching, PresentationDataUtils, PromptUI, SaveToCameraRoll, SelectablePeerNode, ShareItems, SoftwareVideo, StickerPeekUI, StickerResources, TelegramIntents, TelegramNotices`

### Selection rule

The implementation plan runs a deterministic selection pass up-front:

1. Parse each candidate's `BUILD` to compute a reverse-dependency count over the candidate pool (how many other candidates depend on it). Leaves have count 0.
2. Sort by reverse-dep count ascending, then alphabetical. Take the first 10. Write the chosen list into the plan so execution is reproducible.
3. If during execution a chosen module transitively needs a Postbox type not yet exposed via a `TelegramCore` re-export, stop, record the blocker, and skip to the next candidate in the selection-rule ordering — keeping the wave at 10 completed modules.

### Explicitly deferred (future waves, not this spec)

- `TelegramUI` (478 files), `SettingsUI` (44), `TelegramCallsUI` (23), `GalleryUI` (16), `PassportUI` (14), `ChatListUI` (13), `AccountContext` (13), and every other module not in the chosen 10.
- `TelegramCore` (non-goal, ever).

## Per-module playbook

Each of the 10 modules follows the same deterministic sequence.

### 1. Inventory

List every Postbox API referenced in the module. Each reference falls into one of:

- **Type reference only** — signature or local variable uses a Postbox-defined type (`Peer`, `MessageId`, `Media`, `CachedPeerData`, …). Usually resolvable by `TelegramCore` re-exports or an existing `Engine*` type.
- **`postbox.mediaBox.*`** — media resource access.
- **`account.postbox.transaction { … }`** — read/write transaction.
- **`postbox.combinedView / subscribe(...)` with `PostboxViewKey`** — view subscription.
- **`account.postbox.mediaBox` / `postbox.mediaBox` as a parameter** — plumbing through a public signature.

### 2. Map each call site to its replacement

In this priority order:

1. An existing `TelegramEngine.data.get` / `.subscribe` on a `TelegramEngine.EngineData.Item…`.
2. An existing engine function under `TelegramEngine.{peers, messages, accountData, resources, …}`.
3. An existing re-export from `TelegramCore` (for type-only references).
4. A **new** thin wrapper added to the appropriate `TelegramEngine/<Area>/` file (see wrapper policy below). Added in `TelegramCore` in a separate preparatory commit before the consumer edit.

### 3. Edit the consumer

Replace call sites. Function signatures that took `Postbox` as a parameter become signatures taking `TelegramEngine` (or `AccountContext` where already available in the call site). Public-API changes in these leaf modules are acceptable because no other module currently imports them in a way that depends on Postbox types — verified during step 1. Any break discovered at build time is fixed at the call site in the same commit, or the module is skipped if the fix would require changing a module outside the wave.

### 4. Drop the dependency

- Remove `import Postbox` from every file.
- Remove `"//submodules/Postbox:Postbox"` from the module's `BUILD`.

### 5. Build

Run the full project build from the global `CLAUDE.md`:

```
PATH=/opt/homebrew/opt/ruby/bin:`gem environment gemdir`/bin:$PATH \
  python3 build-system/Make/Make.py --overrideXcodeVersion \
  --cacheDir ~/telegram-bazel-cache \
  build \
  --configurationPath build-system/appstore-configuration.json \
  --gitCodesigningRepository git@gitlab.com:peter-iakovlev/fastlanematch.git \
  --gitCodesigningType development \
  --gitCodesigningUseCurrent \
  --buildNumber 1 \
  --configuration debug_sim_arm64
```

The module is not marked done until the full build is green. Fix failures in place before moving on.

### 6. Commit

Commit structure per module, one or two commits:

1. `TelegramCore: add <wrapper name>` — optional, only if new engine wrappers were needed.
2. `<ModuleName>: drop direct Postbox dependency` — consumer edits plus BUILD change.

## Engine-wrapper policy

When a call site has no existing engine equivalent, the wrapper is added in `TelegramCore` **before** the consumer edit, in a **separate commit**.

### Where wrappers go

- **Data reads and subscriptions** → new `TelegramEngine.EngineData.Item.<Area>.<Name>` struct alongside its peers in `submodules/TelegramCore/Sources/TelegramEngine/Data/<Area>Data.swift`. The item's `extract` maps the underlying `PostboxView` to an engine-typed result.
- **Imperative signal-returning calls** → new method on the matching area class (`Peers`, `Messages`, `Resources`, `AccountData`, …) inside `submodules/TelegramCore/Sources/TelegramEngine/<Area>/`.
- **Media-resource access** → extended on `TelegramEngine.resources` rather than exposing `MediaBox` to consumers. For example: `engine.resources.data(…)`, `engine.resources.fetch(…)`, `engine.resources.status(…)`. Each forwards to `account.postbox.mediaBox.*` internally.
- **Ad-hoc transactions that a consumer was running directly** → a specific purpose-built method on the appropriate area, never a generic transaction escape hatch. If only one call site needs the logic and it's trivial, inline it into a new area method rather than creating a helper.

### Rules for the wrapper itself

- Minimal pass-through. No caching, no extra signal plumbing, no bonus features.
- Return type must be nameable from the consumer **without** importing Postbox. That means: an existing `Engine*` wrapper type (`EnginePeer`, `EngineMessage`, `EngineMediaResource`), an existing engine typealias (`EnginePeer.Id`, `EngineMessage.Id`, …), a Swift primitive, or a new `Engine*` typealias added in the same commit. Do **not** return a bare Postbox type.
- Do not introduce new engine wrapper *structs/classes* that re-encode data (those are out of scope for this wave). A new typealias to make an existing Postbox type reachable under an `Engine*` name is allowed and expected.
- Public.
- Consumer must not need anything else from Postbox after the wrapper is in place.
- No deprecation shim. Existing Postbox-using code paths elsewhere in the codebase stay untouched.

### Discovery step (always runs first)

Before writing any new wrapper, search `submodules/TelegramCore/Sources/TelegramEngine/` for an existing match by name and shape. Document "searched for X, found/not found" in the commit that adds the wrapper, so future waves don't re-invent it.

## Verification

### Per-module static checks (must pass before running the build)

- `grep -R "^import Postbox" submodules/<M>/Sources` returns empty.
- `grep "submodules/Postbox" submodules/<M>/BUILD` returns empty.

### Per-module build check

- Full project build (the command in §Per-module playbook step 5) is green.
- No warnings-as-errors regressions introduced by the refactor.

### Wave-completion check

- All 10 chosen modules satisfy the per-module checks.
- Any new engine wrappers are documented in their respective commits.

## Risks and mitigations

- **Public signature changes in a leaf module break an unexpected caller.** Mitigated by the full build per module. Fix at the call site in the same commit, or skip and move on if the fix would pull in scope beyond the wave.
- **A Postbox view has no equivalent engine data item.** Add a new `EngineData.Item` per the wrapper policy. If the mapping is non-trivial (needs its own result type), skip the module and flag it for a future spec.
- **Transitive Postbox usage through a type the module re-exposes publicly.** Caught during Inventory (step 1). If fixing would require editing another module in the wave's dependency graph, skip.
- **A Postbox type has no engine typealias.** Add the typealias in `TelegramCore` (`EngineXxx = Xxx`) in the preparatory commit, then use it in the consumer. Typealias-only additions are explicitly allowed and cheap.
- **Build times.** Full project build per module is slow but accepted — it gives the strongest signal.

## Follow-ups (not this spec)

- Successive waves for the remaining ~64 modules in bottom-up order, each its own spec.
- `TelegramUI` (478 files) and `SettingsUI` (44) will likely need a bespoke approach because of scale; they get their own spec when the time comes.
- Whether `AccountContext` itself should eventually stop importing Postbox is deferred.

## Done definition for this spec

- 10 leaf modules have zero `import Postbox` in their sources and no `//submodules/Postbox:Postbox` in their `BUILD`.
- Full project build is green at wave end.
- Any new engine wrappers added along the way are documented in their commits.
