# Postbox → TelegramEngine refactor, Wave 4: `TelegramEngine.Stickers.uploadSticker` facade migration

**Date:** 2026-04-18
**Status:** Design approved; awaiting implementation plan.
**Predecessors:** Waves 1–3.
- `docs/superpowers/specs/2026-04-16-postbox-to-telegramengine-refactor-wave-1-design.md`
- `docs/superpowers/plans/2026-04-17-mediaresource-to-enginemediaresource-wave-2.md`
- `docs/superpowers/specs/2026-04-18-postbox-to-telegramengine-wave-3-design.md`

## Goal

Migrate the public facade `TelegramEngine.Stickers.uploadSticker` so its signature and its return-enum payload no longer leak Postbox-domain types:

- `peer: Peer → EnginePeer`
- `resource: MediaResource → EngineMediaResource`
- `thumbnail: MediaResource? → EngineMediaResource?`
- `UploadStickerStatus.complete(CloudDocumentMediaResource, String) → .complete(EngineMediaResource, String)`

Follows the validated Wave-2 shape ("per-facade-API migration, modify in place, update call sites in the same commit").

## Non-goals

- Migrating the caller files (`ImportStickerPackUI/Sources/ImportStickerPackController.swift`, `TelegramUI/Components/MediaEditorScreen/Sources/MediaEditorScreen.swift`) to drop `import Postbox`. Each imports Postbox for unrelated reasons; this wave only changes how they invoke `uploadSticker`.
- Migrating other `TelegramEngine.Stickers` facades (e.g. `createStickerSet`, `addStickerToStickerSet`) that have similar Peer/MediaResource leaks. Future-wave work.
- Wrapping or renaming `CloudDocumentMediaResource` itself (it's a TelegramCore-defined class conforming to the `TelegramMediaResource` protocol). It stays usable internally; this wave just stops exposing it in the public enum payload.
- Changes to `_internal_uploadSticker`'s signature. It continues to take raw `Peer` and `MediaResource`, consistent with CLAUDE.md's "internal Postbox-facing layer stays raw" rule — with one intentional one-line exception documented below.

## Scope

### Core change: `UploadStickerStatus` enum

In `submodules/TelegramCore/Sources/TelegramEngine/Stickers/ImportStickers.swift`:

```swift
// Before (line 7-10)
public enum UploadStickerStatus {
    case progress(Float)
    case complete(CloudDocumentMediaResource, String)
}

// After
public enum UploadStickerStatus {
    case progress(Float)
    case complete(EngineMediaResource, String)
}
```

`UploadStickerStatus` is both the public return type of the facade and the return type of `_internal_uploadSticker`. Rather than split it into two enums (one raw for the internal layer, one engine-wrapped for the public facade), this wave keeps one enum and wraps at the single `.complete(...)` construction site inside `_internal_uploadSticker` (line ~97 of the same file):

```swift
// Before
return .single(.complete(uploadedResource, file.mimeType))

// After
return .single(.complete(EngineMediaResource(uploadedResource), file.mimeType))
```

**This one-line construction of `EngineMediaResource` inside `_internal_uploadSticker` is a narrow, spec-allowed exception** to CLAUDE.md's "internal Postbox-facing stays raw" guideline. The alternative (splitting the enum) fragments a simple public surface and duplicates bookkeeping. `EngineMediaResource` is defined in `TelegramCore` and already accessible without additional imports.

### Facade signature migration

In `submodules/TelegramCore/Sources/TelegramEngine/Stickers/TelegramEngineStickers.swift`:

```swift
// Before (line 85-87)
public func uploadSticker(peer: Peer, resource: MediaResource, thumbnail: MediaResource?, alt: String, dimensions: PixelDimensions, duration: Double?, mimeType: String) -> Signal<UploadStickerStatus, UploadStickerError> {
    return _internal_uploadSticker(account: self.account, peer: peer, resource: resource, thumbnail: thumbnail, alt: alt, dimensions: dimensions, duration: duration, mimeType: mimeType)
}

// After
public func uploadSticker(peer: EnginePeer, resource: EngineMediaResource, thumbnail: EngineMediaResource?, alt: String, dimensions: PixelDimensions, duration: Double?, mimeType: String) -> Signal<UploadStickerStatus, UploadStickerError> {
    return _internal_uploadSticker(account: self.account, peer: peer._asPeer(), resource: resource._asResource(), thumbnail: thumbnail?._asResource(), alt: alt, dimensions: dimensions, duration: duration, mimeType: mimeType)
}
```

The facade bridges all three type swaps (`peer._asPeer()`, `resource._asResource()`, `thumbnail?._asResource()`). `_internal_uploadSticker`'s own signature does not change.

### Call-site migration (2 sites, 2 files)

**1. `submodules/ImportStickerPackUI/Sources/ImportStickerPackController.swift:91`** — argument simplification and destructure simplification:

```swift
// Before
signals.append(strongSelf.context.engine.stickers.uploadSticker(peer: peer, resource: resource._asResource(), thumbnail: nil, alt: sticker.emojis.first ?? "", dimensions: PixelDimensions(width: 512, height: 512), duration: nil, mimeType: sticker.mimeType)
    |> map { result -> (UUID, StickerVerificationStatus, EngineMediaResource?) in
        switch result {
            case .progress:
                return (sticker.uuid, .loading, nil)
            case let .complete(resource, mimeType):
                if ["application/x-tgsticker", "video/webm"].contains(mimeType) {
                    return (sticker.uuid, .verified, EngineMediaResource(resource))
                } else {
                    return (sticker.uuid, .declined, nil)
                }
        }
    }
```

becomes:

```swift
signals.append(strongSelf.context.engine.stickers.uploadSticker(peer: peer, resource: resource, thumbnail: nil, alt: sticker.emojis.first ?? "", dimensions: PixelDimensions(width: 512, height: 512), duration: nil, mimeType: sticker.mimeType)
    |> map { result -> (UUID, StickerVerificationStatus, EngineMediaResource?) in
        switch result {
            case .progress:
                return (sticker.uuid, .loading, nil)
            case let .complete(resource, mimeType):
                if ["application/x-tgsticker", "video/webm"].contains(mimeType) {
                    return (sticker.uuid, .verified, resource)
                } else {
                    return (sticker.uuid, .declined, nil)
                }
        }
    }
```

Three changes:
- `peer` in this enclosing closure is a raw `Peer` (from `postbox.loadedPeerWithId(...)`, whose signature is `Signal<Peer, NoError>`). Currently the facade takes `Peer` so the identifier is passed as-is. After the facade moves to `EnginePeer`, wrap at the call: `peer: EnginePeer(peer)`.
- `resource._asResource()` → `resource` (the local `resource` is already `EngineMediaResource`).
- `EngineMediaResource(resource)` → `resource` in the destructure (the destructured `resource` is now `EngineMediaResource` directly).

**2. `submodules/TelegramUI/Components/MediaEditorScreen/Sources/MediaEditorScreen.swift:8099`** — unwrap removed, wraps added:

```swift
// Before
return context.engine.stickers.uploadSticker(peer: peer._asPeer(), resource: resource, thumbnail: file.previewRepresentations.first?.resource, alt: "", dimensions: dimensions, duration: duration, mimeType: mimeType)

// After
return context.engine.stickers.uploadSticker(peer: peer, resource: EngineMediaResource(resource), thumbnail: file.previewRepresentations.first.flatMap { EngineMediaResource($0.resource) }, alt: "", dimensions: dimensions, duration: duration, mimeType: mimeType)
```

The enclosing block is a nested `mapToSignal` chain starting at line ~8084. The `UploadStickerStatus` payload migration cascades through several lines in this block:

- **Line 8097** — `.complete(resource, mimeType)` where `resource` was narrowed via `if let resource = resource as? CloudDocumentMediaResource`. After the payload migration this `.complete(...)` constructor takes `EngineMediaResource`, so wrap: `.complete(EngineMediaResource(resource), mimeType)`.
- **Line 8099** — the main facade call. `peer._asPeer()` → `peer` (the local `peer` is an `EnginePeer`, confirmed by the current `_asPeer()`); `resource` → `EngineMediaResource(resource)` (the local `resource` here is a raw `MediaResource` from the outer enum's `.complete(resource)` case); `file.previewRepresentations.first?.resource` → `file.previewRepresentations.first.flatMap { EngineMediaResource($0.resource) }`.
- **Line 8105** — `case let .complete(resource, _):` destructures the inner `UploadStickerStatus`. After migration, `resource` has type `EngineMediaResource`.
- **Line 8106** — `stickerFile(resource: resource, thumbnailResource: file.previewRepresentations.first?.resource, …)` — `stickerFile` is declared with `resource: TelegramMediaResource, thumbnailResource: TelegramMediaResource?, …`, so unwrap: `stickerFile(resource: resource._asResource(), thumbnailResource: file.previewRepresentations.first?.resource, …)`. The `thumbnailResource` argument is already a `TelegramMediaResource?` and needs no change.
- **Line 8119** — `ImportSticker(resource: .standalone(resource: resource), …)`. `MediaResourceReference.standalone(resource:)` takes `MediaResource`, so unwrap: `.standalone(resource: resource._asResource())`.
- **Line 8138** — same as 8119 inside the `.addToStickerPack` case.
- **Line 8178** — outer-handler destructure `case let .complete(resource, _):`. After migration, `resource` is `EngineMediaResource`.
- **Line 8180** — `stickerFile(resource: resource, thumbnailResource: file.previewRepresentations.first?.resource, size: resource.size ?? 0, …)`. Two unwrap sites here: `resource: resource._asResource()` for the first argument, and `size: resource._asResource().size ?? 0` for the size read (`EngineMediaResource` does not expose `.size`; only `MediaResource` does). Introduce a local `let rawResource = resource._asResource()` at the top of the `case` to avoid calling `_asResource()` twice.

**Execution-time check:** before editing MediaEditorScreen, re-read the full block (roughly lines 8080–8190) and the `stickerFile` function signature (line 9196) to confirm these assumptions. If any additional downstream use of the destructured `resource` appears that wasn't caught above, decide inline whether it needs `._asResource()` or can take `EngineMediaResource` directly.

## Execution-time re-inventory

Before editing, re-grep to catch any new call sites:

```bash
grep -rnE "\.uploadSticker\(" submodules --include="*.swift" | grep -v "/TelegramEngine/Stickers/"
```

Expected output lines that pattern-match the facade (not the `MediaEditorScreen`'s private `self.uploadSticker(file, action:)` helper):

- `submodules/ImportStickerPackUI/Sources/ImportStickerPackController.swift:91`
- `submodules/TelegramUI/Components/MediaEditorScreen/Sources/MediaEditorScreen.swift:8099`

Other `self.uploadSticker(...)` lines in `MediaEditorScreen.swift` (7771, 7808, 7852, 7896, 7913, 7931, 8019) are calls to a private helper method, not the engine facade — leave those untouched.

If the facade call-site count drifts beyond these two, stop and revise the plan.

## Commit plan

One atomic commit covering all four files:

**C1 — `TelegramEngine.Stickers.uploadSticker: migrate to EnginePeer + EngineMediaResource`**

- `submodules/TelegramCore/Sources/TelegramEngine/Stickers/ImportStickers.swift` — enum payload + one `.complete(...)` construction site.
- `submodules/TelegramCore/Sources/TelegramEngine/Stickers/TelegramEngineStickers.swift` — facade signature.
- `submodules/ImportStickerPackUI/Sources/ImportStickerPackController.swift` — 1 call site + destructure.
- `submodules/TelegramUI/Components/MediaEditorScreen/Sources/MediaEditorScreen.swift` — 1 call site.

Atomicity is required because the enum payload change, facade signature change, and call-site changes are all mutually breaking.

**C2 — `CLAUDE.md: record wave-4 outcome`**

- Add a "Wave 4 outcome (2026-04-18)" subsection documenting the facade migrated.
- Remove the `uploadSticker` bullet from "Known future-wave candidates".
- No change to the "Modules currently free of `import Postbox`" running tally (no module is de-Postboxed in this wave).

## Build verification

One full project build after the edits, before committing C1. The bazel command from CLAUDE.md, prefixed with `source ~/.zshrc 2>/dev/null;` to pick up `TELEGRAM_CODESIGNING_GIT_PASSWORD`.

## Risks and mitigations

- **Risk:** a new call site of `engine.stickers.uploadSticker` appears between planning and execution. **Mitigation:** the re-grep above catches this; abandon or extend the plan if so.
- **Risk:** `UploadStickerStatus.complete` is destructured somewhere that accesses `CloudDocumentMediaResource`-specific members. **Mitigation:** grep confirms both known sites use the value generically (wrap or assign directly); no `.stringRepresentation`-style `CloudDocumentMediaResource`-specific access is expected. If found, abandon the wave.
- **Risk:** `MediaEditorScreen:8099`'s `resource` local is already an `EngineMediaResource`. **Mitigation:** inspect the enclosing function at execution time and adjust the wrap accordingly.
- **Risk:** the one-line `EngineMediaResource(uploadedResource)` wrap inside `_internal_uploadSticker` is a narrow deviation from "Postbox-facing layer stays raw". **Mitigation:** spec explicitly calls this out. The alternative (splitting the enum) is worse for a single-line gain; documented and accepted.
- **Rule-2 compliance:** no `Postbox`/`Account`/`MediaBox` typealias introduced; no new wrapper struct. ✅

## Abandonment criteria

If any call-site edit turns out to require a cascading type change elsewhere (e.g. a struct field or signature typed as `CloudDocumentMediaResource`), abandon the wave and record the reason. The single-commit shape means either the whole thing lands or none of it does.

## Expected outcome

- `TelegramEngine.Stickers.uploadSticker`'s public surface no longer references `Peer`, `MediaResource`, or `CloudDocumentMediaResource`.
- `UploadStickerStatus.complete`'s payload becomes `(EngineMediaResource, String)`.
- `_internal_uploadSticker`'s signature stays as-is (raw `Peer`/`MediaResource`), with one inline `EngineMediaResource(uploadedResource)` wrap at the result-construction site.
- Two call sites updated; no caller module becomes Postbox-free.
- CLAUDE.md records the outcome and removes the `uploadSticker` entry from "Known future-wave candidates".
- Zero behavior change.
