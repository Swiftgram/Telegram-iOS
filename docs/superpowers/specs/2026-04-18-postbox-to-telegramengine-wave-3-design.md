# Postbox → TelegramEngine refactor, Wave 3: MediaBox fetch/status/data facades + SaveToCameraRoll

**Date:** 2026-04-18
**Status:** Design approved; awaiting implementation plan.
**Predecessors:** Waves 1 and 2 (`docs/superpowers/specs/2026-04-16-postbox-to-telegramengine-refactor-wave-1-design.md`, `docs/superpowers/plans/2026-04-17-mediaresource-to-enginemediaresource-wave-2.md`).

## Goal

1. Unblock the full-module de-Postboxing of `submodules/SaveToCameraRoll` (abandoned in Wave 2) by adding engine-side facades for the `mediaBox` methods it uses.
2. Migrate `SaveToCameraRoll`'s three public functions to use those facades, drop `import Postbox` from the module, and update all call sites.

This wave follows the validated Wave-2 shape ("per-API migration, modify in place, update all call sites in one commit"), not the Wave-1 shape ("per-module Postbox drop").

## Non-goals

- Migrating any caller file (`InstantPageUI`, `BrowserUI`, `GalleryUI`, `ShareController`, `TelegramUI`, etc.) to drop its `import Postbox`. Each imports Postbox for many unrelated reasons; this wave only changes how they invoke `SaveToCameraRoll`.
- Adding facades for other `mediaBox` methods beyond the three SaveToCameraRoll needs (`cachedResourceRepresentation`, `completedResourcePath`, `storeResourceData`, etc.). Additive work belongs in future waves when a consumer needs them.
- Wrapping `FetchResourceSourceType` / `FetchResourceError` — these remain Postbox types, exposed by the `fetch` facade as a documented accepted leak. SaveToCameraRoll does not inspect these values.
- Adding `.incremental(waitUntilFetchStatus:)` to the `data` facade, or any of `range` / `statsCategory` / `reportResultStatus` / `preferBackgroundReferenceRevalidation` / `continueInBackground` to the `fetch` facade.

## Scope and inventory

### New engine surface

Three thin forwarding methods added to `TelegramEngine.Resources` in `submodules/TelegramCore/Sources/TelegramEngine/Resources/TelegramEngineResources.swift`. No new wrapper structs or classes.

```swift
public extension TelegramEngine {
    final class Resources {
        // ...existing methods...

        public func fetch(
            reference: MediaResourceReference,
            userLocation: MediaResourceUserLocation,
            userContentType: MediaResourceUserContentType
        ) -> Signal<FetchResourceSourceType, FetchResourceError> {
            return fetchedMediaResource(
                mediaBox: self.account.postbox.mediaBox,
                userLocation: userLocation,
                userContentType: userContentType,
                reference: reference
            )
        }

        public func status(
            resource: EngineMediaResource
        ) -> Signal<EngineMediaResource.FetchStatus, NoError> {
            return self.account.postbox.mediaBox.resourceStatus(resource._asResource())
            |> map { EngineMediaResource.FetchStatus($0) }
        }

        public func data(
            resource: EngineMediaResource,
            pathExtension: String?,
            waitUntilFetchStatus: Bool
        ) -> Signal<EngineMediaResource.ResourceData, NoError> {
            return self.account.postbox.mediaBox.resourceData(
                resource._asResource(),
                pathExtension: pathExtension,
                option: .complete(waitUntilFetchStatus: waitUntilFetchStatus)
            )
            |> map { EngineMediaResource.ResourceData($0) }
        }
    }
}
```

Design choices:

- **`data` takes a `waitUntilFetchStatus: Bool`**, not Postbox's `ResourceDataRequestOption` enum. SaveToCameraRoll only ever uses `.complete(waitUntilFetchStatus:)`. If a future consumer needs `.incremental(...)`, extend the facade at that point.
- **`fetch` takes only the 4 parameters SaveToCameraRoll uses.** `range`, `statsCategory`, `reportResultStatus`, `preferBackgroundReferenceRevalidation`, `continueInBackground` can be added additively when a consumer requires them.
- **`reference:` keeps the `MediaResourceReference` Postbox type.** Callers construct it inline via `mediaReference.resourceReference(resource)` and pass it without a local binding; no `import Postbox` is induced at the call site.
- **No wrapping of `FetchResourceSourceType` / `FetchResourceError`.** SaveToCameraRoll calls `.start()` on the `fetch` signal without inspecting the value; it does not import Postbox merely to use these types. Recorded here as an accepted leak.

### SaveToCameraRoll public API changes

The enum payload and three public function signatures change. Every caller breaks until updated.

Before:

```swift
public enum FetchMediaDataState {
    case progress(Float)
    case data(MediaResourceData)
}

public func fetchMediaData(
    context: AccountContext, postbox: Postbox,
    userLocation: MediaResourceUserLocation,
    customUserContentType: MediaResourceUserContentType? = nil,
    mediaReference: AnyMediaReference, forceVideo: Bool = false
) -> Signal<(FetchMediaDataState, Bool), NoError>

public func saveToCameraRoll(
    context: AccountContext, postbox: Postbox,
    userLocation: MediaResourceUserLocation,
    customUserContentType: MediaResourceUserContentType? = nil,
    mediaReference: AnyMediaReference, video: AnyMediaReference? = nil
) -> Signal<Float, NoError>

public func copyToPasteboard(
    context: AccountContext, postbox: Postbox,
    userLocation: MediaResourceUserLocation,
    mediaReference: AnyMediaReference
) -> Signal<Void, NoError>
```

After:

```swift
public enum FetchMediaDataState {
    case progress(Float)
    case data(EngineMediaResource.ResourceData)
}

public func fetchMediaData(
    context: AccountContext,
    userLocation: MediaResourceUserLocation,
    customUserContentType: MediaResourceUserContentType? = nil,
    mediaReference: AnyMediaReference, forceVideo: Bool = false
) -> Signal<(FetchMediaDataState, Bool), NoError>

public func saveToCameraRoll(
    context: AccountContext,
    userLocation: MediaResourceUserLocation,
    customUserContentType: MediaResourceUserContentType? = nil,
    mediaReference: AnyMediaReference, video: AnyMediaReference? = nil
) -> Signal<Float, NoError>

public func copyToPasteboard(
    context: AccountContext,
    userLocation: MediaResourceUserLocation,
    mediaReference: AnyMediaReference
) -> Signal<Void, NoError>
```

### SaveToCameraRoll internal changes

- `var resource: MediaResource?` → `var resource: TelegramMediaResource?` (TelegramCore protocol; matches CLAUDE.md cheat-sheet guidance). `representation.resource` and `file.resource` already return `TelegramMediaResource`, so no wrapping is needed at assignment.
- `fetchedMediaResource(mediaBox: postbox.mediaBox, …)` → `context.engine.resources.fetch(reference: mediaReference.resourceReference(resource), userLocation: userLocation, userContentType: userContentType)`.
- `postbox.mediaBox.resourceStatus(resource)` → `context.engine.resources.status(resource: EngineMediaResource(resource))`. The `switch status { case .Local … }` body is unchanged because `EngineMediaResource.FetchStatus` has the same cases (`.Local`, `.Remote(progress:)`, `.Fetching(isActive:progress:)`, `.Paused(progress:)`).
- `postbox.mediaBox.resourceData(resource, pathExtension: fileExtension, option: .complete(waitUntilFetchStatus: true))` → `context.engine.resources.data(resource: EngineMediaResource(resource), pathExtension: fileExtension, waitUntilFetchStatus: true)`.
- Local `MediaResourceData` bindings (`mainData: MediaResourceData?`, `videoData: MediaResourceData?`) and `case let .data(data):` destructurings → use `EngineMediaResource.ResourceData`.
- Field renames inside SaveToCameraRoll: `data.complete` → `data.isComplete`. `data.path` unchanged. `data.size` is not used internally.
- `import Postbox` removed from the file.

### Call-site migration (23 sites, 14 files)

Two mechanical edits per site.

Edit A — drop the `postbox:` argument:

```swift
// Before
saveToCameraRoll(context: context, postbox: context.account.postbox, userLocation: …, mediaReference: …)
// After
saveToCameraRoll(context: context, userLocation: …, mediaReference: …)
```

Edit B — update `FetchMediaDataState.data` field accesses at the ~7 sites that destructure `fetchMediaData` results:

- `data.complete` → `data.isComplete`
- `data.path` → unchanged
- `data.size` → `data.availableSize` (if used; likely not)

Inventory (captured 2026-04-18):

| Module | File | Calls |
|---|---|---|
| InstantPageUI | `Sources/InstantPageControllerNode.swift` | 2 |
| LegacyMediaPickerUI | `Sources/LegacyAttachmentMenu.swift` | 2 (destructures) |
| LegacyMediaPickerUI | `Sources/LegacyAvatarPicker.swift` | 2 (destructures) |
| BrowserUI | `Sources/BrowserInstantPageContent.swift` | 2 |
| GalleryUI | `Sources/Items/ChatImageGalleryItem.swift` | 2 (one destructures) |
| GalleryUI | `Sources/Items/UniversalVideoGalleryItem.swift` | 3 |
| TelegramUI (MediaEditorScreen) | `Components/MediaEditorScreen/Sources/MediaEditorScreen.swift` | 1 (destructures) |
| TelegramUI (MediaEditorScreen) | `Components/MediaEditorScreen/Sources/EditStories.swift` | 1 (destructures) |
| TelegramUI (ChatQrCodeScreen) | `Components/Chat/ChatQrCodeScreen/Sources/ChatQrCodeScreen.swift` | 1 (destructures) |
| TelegramUI (StoryContainer) | `Components/Stories/StoryContainerScreen/Sources/StoryItemSetContainerComponent.swift` | 1 |
| TelegramUI (PeerInfoStoryGrid) | `Components/PeerInfo/PeerInfoStoryGridScreen/Sources/PeerInfoStoryGridScreen.swift` | 1 |
| TelegramUI | `Sources/ChatInterfaceStateContextMenus.swift` | 1 |
| TelegramUI | `Sources/SaveMediaToFiles.swift` | 1 (destructures) |
| ShareController | `Sources/ShareController.swift` | 3 |

**Execution-time re-inventory:** before editing any code, the executor must re-grep for `fetchMediaData|saveToCameraRoll|copyToPasteboard` call sites across `submodules/`. If the count or file list drifts meaningfully from this table, abandon editing and revise the plan.

### Postbox-drop tally update

- `SaveToCameraRoll` joins the tally of modules free of `import Postbox`.
- No caller file is expected to drop `import Postbox` in this wave.

## Commit plan

Two commits, landing in order on `refactor/postbox-to-engine-wave-3`.

### C1 — `TelegramEngine.Resources: add fetch/status/data facades`

- Touches only `submodules/TelegramCore/Sources/TelegramEngine/Resources/TelegramEngineResources.swift`.
- Adds the three methods from the "New engine surface" section above. No behavior changes; no consumer changes.
- Buildable in isolation.

### C2 — `SaveToCameraRoll: drop import Postbox via engine.resources facades`

Atomic; must land as one commit because signature changes break every unmigrated caller.

- `submodules/SaveToCameraRoll/Sources/SaveToCameraRoll.swift`: public signature changes, `FetchMediaDataState.data` payload switch, internal rewrites, `import Postbox` removal.
- All 23 call sites in the inventory table updated in the same commit.
- ~7 destructuring sites also get the `data.complete` → `data.isComplete` rename.

## Build verification

Per CLAUDE.md, the only verification available is a full project build. No unit tests exist in the repo.

- After C1: full build.
- After C2: full build.

Both builds use the standard command from `CLAUDE.md` (Telegram build recipe with `--configuration debug_sim_arm64`), prefixed with `source ~/.zshrc 2>/dev/null;` to pick up `TELEGRAM_CODESIGNING_GIT_PASSWORD`.

## Risks and mitigations

- **New call site appears between planning and execution.** Mitigation: re-grep at execution time before editing; abandon & revise if count drifts meaningfully.
- **`FetchResourceSourceType` / `FetchResourceError` are Postbox types.** Mitigation: SaveToCameraRoll never inspects these; future consumers that need to pattern-match will wrap these types in a later wave.
- **A consumer turns out to need a mediaBox facade not in this spec** (e.g., `cachedResourceRepresentation`). Mitigation: out of scope. Abandon that caller's migration; the facade commit still stands on its own.
- **`context.engine` unavailable at some call site.** Risk minimal: `AccountContext.engine` is a protocol requirement in `submodules/AccountContext/Sources/AccountContext.swift`, so it is universally available at any site that already has `context: AccountContext`. All 23 sites match.
- **ShareController:2406 uses a non-`context.account.postbox` Postbox.** At `submodules/ShareController/Sources/ShareController.swift:2406`, the call reads `let postbox = self.currentContext.stateManager.postbox` and passes that as `postbox:`. After migration, SaveToCameraRoll internally uses `context.account.postbox.mediaBox` via the engine. In the gated `ShareControllerAppAccountContext` path, `accountContext.context.account.stateManager` should match `self.currentContext.stateManager`, so the two postboxes are equivalent; verify this at execution time before editing. If they can diverge (e.g., during share-extension account switching), this specific call site must be abandoned with a recorded reason — the rest of the wave is unaffected.
- **Umbrella-type rule-2 compliance.** No `Postbox` / `Account` / `MediaBox` typealias is added. No new wrapper struct is introduced. ✅

## Abandonment criteria

If any call site cannot be migrated mechanically — for example, it passes a non-`context.account.postbox` custom `Postbox`, or constructs a `MediaResourceReference` in a way that forces a retained `import Postbox` in a file the wave intends to de-Postbox — abandon that specific call site with a recorded reason in the plan. The facade commit (C1) still stands on its own; SaveToCameraRoll's internal migration still lands if at least the other callers migrate. If too many call sites abandon, abandon the whole wave and record lessons.

## Expected outcome

- `TelegramEngine.Resources` has three new thin forwarders.
- `SaveToCameraRoll` no longer imports Postbox.
- Running tally of Postbox-free consumer modules: Wave 1 cohort + `StickerPeekUI`, `PromptUI`, `PresentationDataUtils` (standalone) + `MapResourceToAvatarSizes` (Wave 2) + **`SaveToCameraRoll` (Wave 3)**.
- Zero behavior change.
