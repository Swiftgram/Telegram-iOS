# Postbox → TelegramEngine refactor, Wave 5: `uploadSecureIdFile` facade + SecureId context migration

**Date:** 2026-04-18
**Status:** Design approved; awaiting implementation plan.
**Predecessors:** Waves 1–4.

## Goal

Complete the last explicitly-named future-wave candidate from CLAUDE.md: migrate `uploadSecureIdFile`'s public surface to stop leaking the `Postbox`/`Network`/`MediaResource` Postbox-domain types, and refactor its caller `SecureIdVerificationDocumentsContext` so the caller stops importing Postbox.

- `uploadSecureIdFile(context: SecureIdAccessContext, postbox: Postbox, network: Network, resource: MediaResource)` → `(context:, engine: TelegramEngine, resource: EngineMediaResource)`.
- `SecureIdVerificationDocumentsContext` drops its `postbox: Postbox` + `network: Network` stored properties, takes `engine: TelegramEngine` instead, and drops `import Postbox` from the file.
- The one instantiation site updates to pass `engine: self.context.engine`.

## Non-goals

- Migrating `SecureIdAccessContext`, `SecureIdVerificationDocument`, `SecureIdVerificationLocalDocument`, or other SecureId-domain types. They live in TelegramCore (not Postbox) already and do not leak.
- Migrating other SecureId-family functions in TelegramCore (e.g., `_internal_requestSecureIdVerification`, etc.). Future-wave work.
- Dropping `import Postbox` from `SecureIdDocumentFormControllerNode.swift`. That file imports Postbox for unrelated reasons.

## Scope and inventory

### Files touched (3 in the code commit)

1. `submodules/TelegramCore/Sources/TelegramEngine/SecureId/UploadSecureIdFile.swift` — facade signature change, 3-line body bridge.
2. `submodules/PassportUI/Sources/SecureIdVerificationDocumentsContext.swift` — stored props, constructor, internal call, drop `import Postbox`.
3. `submodules/PassportUI/Sources/SecureIdDocumentFormControllerNode.swift` — one-line instantiation call.

### Facade signature migration (`UploadSecureIdFile.swift`)

Before:

```swift
public func uploadSecureIdFile(context: SecureIdAccessContext, postbox: Postbox, network: Network, resource: MediaResource) -> Signal<UploadSecureIdFileResult, UploadSecureIdFileError> {
    return postbox.mediaBox.resourceData(resource)
    |> mapError { _ -> UploadSecureIdFileError in
    }
    |> mapToSignal { next -> Signal<UploadSecureIdFileResult, UploadSecureIdFileError> in
        if !next.complete {
            return .complete()
        }

        guard let data = try? Data(contentsOf: URL(fileURLWithPath: next.path)) else {
            return .fail(.generic)
        }

        guard let encryptedData = encryptedSecureIdFile(context: context, data: data) else {
            return .fail(.generic)
        }

        return multipartUpload(network: network, postbox: postbox, source: .data(encryptedData.data), encrypt: false, tag: TelegramMediaResourceFetchTag(statsCategory: .image, userContentType: .image), hintFileSize: nil, hintFileIsLarge: false, forceNoBigParts: false)
        |> mapError { _ -> UploadSecureIdFileError in
            return .generic
        }
        |> mapToSignal { result -> Signal<UploadSecureIdFileResult, UploadSecureIdFileError> in
            switch result {
                case let .progress(value):
                    return .single(.progress(value))
                case let .inputFile(.inputFile(fileData)):
                    return .single(.result(UploadedSecureIdFile(id: fileData.id, parts: fileData.parts, md5Checksum: fileData.md5Checksum, fileHash: encryptedData.hash, encryptedSecret: encryptedData.encryptedSecret), encryptedData.data))
                default:
                    return .fail(.generic)
            }
        }
    }
}
```

After:

```swift
public func uploadSecureIdFile(context: SecureIdAccessContext, engine: TelegramEngine, resource: EngineMediaResource) -> Signal<UploadSecureIdFileResult, UploadSecureIdFileError> {
    return engine.account.postbox.mediaBox.resourceData(resource._asResource())
    |> mapError { _ -> UploadSecureIdFileError in
    }
    |> mapToSignal { next -> Signal<UploadSecureIdFileResult, UploadSecureIdFileError> in
        if !next.complete {
            return .complete()
        }

        guard let data = try? Data(contentsOf: URL(fileURLWithPath: next.path)) else {
            return .fail(.generic)
        }

        guard let encryptedData = encryptedSecureIdFile(context: context, data: data) else {
            return .fail(.generic)
        }

        return multipartUpload(network: engine.account.network, postbox: engine.account.postbox, source: .data(encryptedData.data), encrypt: false, tag: TelegramMediaResourceFetchTag(statsCategory: .image, userContentType: .image), hintFileSize: nil, hintFileIsLarge: false, forceNoBigParts: false)
        |> mapError { _ -> UploadSecureIdFileError in
            return .generic
        }
        |> mapToSignal { result -> Signal<UploadSecureIdFileResult, UploadSecureIdFileError> in
            switch result {
                case let .progress(value):
                    return .single(.progress(value))
                case let .inputFile(.inputFile(fileData)):
                    return .single(.result(UploadedSecureIdFile(id: fileData.id, parts: fileData.parts, md5Checksum: fileData.md5Checksum, fileHash: encryptedData.hash, encryptedSecret: encryptedData.encryptedSecret), encryptedData.data))
                default:
                    return .fail(.generic)
            }
        }
    }
}
```

Three substantive body changes, all in line with the CLAUDE.md rule that "internal Postbox-facing stays raw" — the body is inside TelegramCore itself so it accesses raw Postbox types through `engine.account.postbox` without going through the wave-3 facades:

- `postbox.mediaBox.resourceData(resource)` → `engine.account.postbox.mediaBox.resourceData(resource._asResource())` (unwrap the engine resource before handing to raw MediaBox).
- `network: network` → `network: engine.account.network`.
- `postbox: postbox` → `postbox: engine.account.postbox`.

The `_internal_*` convention does not apply here because `uploadSecureIdFile` is itself the facade — there is no separate raw-typed `_internal_uploadSecureIdFile` helper, and this wave does not introduce one. The function continues to have a single definition serving both internal TelegramCore wiring and consumer use.

### Caller-class migration (`SecureIdVerificationDocumentsContext.swift`)

Before:

```swift
import Foundation
import Postbox
import TelegramCore
import SwiftSignalKit

private final class DocumentContext {
    private let disposable: Disposable

    init(disposable: Disposable) {
        self.disposable = disposable
    }

    deinit {
        self.disposable.dispose()
    }
}

final class SecureIdVerificationDocumentsContext {
    private let context: SecureIdAccessContext
    private let postbox: Postbox
    private let network: Network
    private let update: (Int64, SecureIdVerificationLocalDocumentState) -> Void
    private var contexts: [Int64: DocumentContext] = [:]
    private(set) var uploadedFiles: [Data: Data] = [:]

    init(postbox: Postbox, network: Network, context: SecureIdAccessContext, update: @escaping (Int64, SecureIdVerificationLocalDocumentState) -> Void) {
        self.postbox = postbox
        self.network = network
        self.context = context
        self.update = update
    }

    func stateUpdated(_ documents: [SecureIdVerificationDocument]) {
        // ...
        disposable.set((uploadSecureIdFile(context: self.context, postbox: self.postbox, network: self.network, resource: info.resource)
        // ...
    }
}
```

After:

```swift
import Foundation
import TelegramCore
import SwiftSignalKit

private final class DocumentContext {
    private let disposable: Disposable

    init(disposable: Disposable) {
        self.disposable = disposable
    }

    deinit {
        self.disposable.dispose()
    }
}

final class SecureIdVerificationDocumentsContext {
    private let context: SecureIdAccessContext
    private let engine: TelegramEngine
    private let update: (Int64, SecureIdVerificationLocalDocumentState) -> Void
    private var contexts: [Int64: DocumentContext] = [:]
    private(set) var uploadedFiles: [Data: Data] = [:]

    init(engine: TelegramEngine, context: SecureIdAccessContext, update: @escaping (Int64, SecureIdVerificationLocalDocumentState) -> Void) {
        self.engine = engine
        self.context = context
        self.update = update
    }

    func stateUpdated(_ documents: [SecureIdVerificationDocument]) {
        // ...
        disposable.set((uploadSecureIdFile(context: self.context, engine: self.engine, resource: EngineMediaResource(info.resource))
        // ...
    }
}
```

Changes:

1. Drop `import Postbox` (line 2).
2. Replace `private let postbox: Postbox` and `private let network: Network` with `private let engine: TelegramEngine`.
3. Constructor: `postbox:, network:, context:, update:` → `engine:, context:, update:`.
4. Constructor body: `self.postbox = postbox; self.network = network` → `self.engine = engine`.
5. Inside `stateUpdated`: `postbox: self.postbox, network: self.network` → `engine: self.engine`; `resource: info.resource` → `resource: EngineMediaResource(info.resource)` (wrap; `info.resource` is `TelegramMediaResource` per `SecureIdVerificationLocalDocument` definition).

`DocumentContext` inner class is untouched. Other methods in the file are untouched.

### Instantiation-site edit (`SecureIdDocumentFormControllerNode.swift`)

Single line, [line 2172](submodules/PassportUI/Sources/SecureIdDocumentFormControllerNode.swift#L2172):

```swift
// Before
self.uploadContext = SecureIdVerificationDocumentsContext(postbox: self.context.account.postbox, network: self.context.account.network, context: self.secureIdContext, update: { id, state in

// After
self.uploadContext = SecureIdVerificationDocumentsContext(engine: self.context.engine, context: self.secureIdContext, update: { id, state in
```

`self.context` is the outer `AccountContext`. `self.context.engine` is the `TelegramEngine` (universally available via the `AccountContext` protocol). `self.secureIdContext` is the unrelated inner `SecureIdAccessContext` — kept as the `context:` argument.

## Execution-time re-inventory

Before editing, re-grep to catch any new call sites:

```bash
grep -rnE "uploadSecureIdFile\(" submodules --include="*.swift" | grep -v "/SecureId/"
grep -rnE "SecureIdVerificationDocumentsContext\(" submodules --include="*.swift" | grep -v "final class SecureIdVerificationDocumentsContext"
```

Expected: exactly 1 match for each — `SecureIdVerificationDocumentsContext.swift:43` and `SecureIdDocumentFormControllerNode.swift:2172` respectively. If either count has drifted, stop and revise the plan.

## Commit plan

**C1 — `SecureId: migrate uploadSecureIdFile + context to TelegramEngine`** (atomic)

- All three files listed above, landing together.

**C2 — `CLAUDE.md: record wave-5 outcome`**

- Add `SecureIdVerificationDocumentsContext` to the "Modules currently free of `import Postbox`" running tally.
- Add a "Wave 5 outcome (2026-04-18)" subsection describing the migration.
- Remove the `uploadSecureIdFile` bullet from "Known future-wave candidates". After this, only the 4 permanently-blocked classes remain.

## Build verification

One full project build after C1's edits, before committing. Bazel command from CLAUDE.md with `source ~/.zshrc 2>/dev/null;` prefix.

## Risks and mitigations

- **Risk:** an additional call site of `uploadSecureIdFile` appears between planning and execution. **Mitigation:** the execution-time re-grep catches this. Expected 1 match.
- **Risk:** `SecureIdDocumentFormControllerNode.swift`'s `self.context` isn't an `AccountContext` at the instantiation site. **Mitigation:** confirm at execution time. The `AccountContext` protocol mandates `var engine: TelegramEngine { get }`, so any concrete `AccountContext` has it.
- **Risk:** behavior regression from `multipartUpload(network: engine.account.network, postbox: engine.account.postbox, …)`. **Mitigation:** these are the same underlying instances as the pre-migration `self.network` / `self.postbox` values (both originate from `self.context.account.network` / `.postbox`). Zero behavior change.
- **Risk:** after `import Postbox` is dropped from `SecureIdVerificationDocumentsContext.swift`, an implicit `Network` type (used elsewhere in the file?) fails to resolve. **Mitigation:** the file's only `Network` usage is in the stored `private let network` and the constructor parameter — both removed. No other `Network` reference survives.
- **Rule-2 compliance:** no `Postbox`/`Account`/`MediaBox` typealias introduced. No new wrapper struct. The facade body's `engine.account.postbox.mediaBox` and `engine.account.network` are internal expressions inside TelegramCore (not public surface). ✅

## Abandonment criteria

If any of the 3 files cannot be migrated mechanically (e.g. `SecureIdDocumentFormControllerNode.swift`'s enclosing class doesn't have an `AccountContext`), abandon the wave and record the reason. The one-commit atomic shape means either the whole thing lands or none of it does.

## Expected outcome

- `uploadSecureIdFile`'s public signature references neither `Postbox` nor `Network` nor `MediaResource`.
- `SecureIdVerificationDocumentsContext` no longer imports Postbox and joins the Postbox-free running tally.
- `SecureIdDocumentFormControllerNode.swift` continues to import Postbox for unrelated reasons (no tally impact).
- `uploadSecureIdFile` bullet is removed from CLAUDE.md's "Known future-wave candidates"; after this wave, only the 4 permanently-blocked `TelegramMediaResource`-conforming classes remain in the candidate list.
- Full build succeeds in `debug_sim_arm64`.
- Zero behavior change.
