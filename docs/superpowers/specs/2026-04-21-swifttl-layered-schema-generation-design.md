# SwiftTL — Optional Layered Schema Generation

**Date:** 2026-04-21
**Tool:** `build-system/SwiftTL`
**Inputs this unblocks:** `telegram-ios-shared/tools/secret_scheme.tl`, invoked by `telegram-ios-shared/tools/generate_and_copy_scheme.sh` with `--api-prefix=SecretApi`.
**Consumers this targets:** `submodules/TelegramCore/Sources/State/ManagedSecretChatOutgoingOperations.swift`, `submodules/TelegramCore/Sources/State/ProcessSecretChatIncomingDecryptedOperations.swift` — both reference `SecretApi{8,46,73,101,144}.<Type>.<ctor>`, symbols currently provided by hand-maintained `submodules/TelegramApi/Sources/SecretApiLayer{8,46,73,101,144}.swift` files.

## Problem

`SwiftTL` parses a flat `.tl` schema and emits one flat `Api` namespace. `secret_scheme.tl` is not flat — it's a multi-version schema separated by `===N===` layer markers (11 layers: 8, 17, 20, 23, 45, 46, 66, 73, 101, 143, 144), where the same constructor name can reappear in later layers with a new constructor ID and new fields (e.g. `decryptedMessage` exists at layers 8, 17, 45, 73, each with a different ID and argument list).

Running `SwiftTL secret_scheme.tl … --api-prefix=SecretApi` today fails: `DescriptionParser` doesn't recognize `===N===` markers, and `Resolver` throws on the first duplicate constructor name. The secret-chat `SecretApi{N}.<Type>.<ctor>` structs that downstream code already uses are hand-maintained and out-of-sync with what SwiftTL would naturally produce.

## Goal

Extend `SwiftTL` with optional layered-schema support so that `secret_scheme.tl` round-trips through the same CLI: one invocation produces one Swift file per declared layer. Flat schemas (`swift_scheme.tl`) continue to produce byte-identical output.

Non-goal: a complete rewrite of the legacy hand-written `SecretApiLayer*.swift` format. Output is "close enough" — same sum-type enums, same constructor IDs, same serialize/parse bodies — not byte-for-byte identical to the legacy files. Existing consumers compile unchanged because they reference the public symbols (`SecretApi8.DecryptedMessage.decryptedMessage(...)`), which the generator preserves.

## Architecture

Four files change in `build-system/SwiftTL/Sources/SwiftTL/`. No new files, no new CLI flags.

### `DescriptionParsing.swift`

The public `parse(data:)` return type changes from a tuple `(constructors, functions)` to a new enum:

```swift
enum ParsedSchema {
    case flat(constructors: [ConstructorDescription], functions: [ConstructorDescription])
    case layered(layers: [(layerNumber: Int, constructors: [ConstructorDescription])])
}
```

**Detection rule.** If any non-empty line matches the regex `^===\d+===\s*$`, the schema is layered. Every non-skipped constructor must sit under a marker; constructors appearing before the first marker are attached to the lowest-numbered layer. Otherwise the schema is flat (today's behavior, unchanged).

**Input validation** (only enforced in the layered branch):
- Layer numbers must be positive integers and appear in strictly ascending order in the source. Parser throws otherwise.
- `---functions---` is forbidden in layered mode. Parser throws if seen.
- Empty layers (marker followed immediately by the next marker or EOF) are allowed. They produce an output file whose cumulative snapshot is identical to the previous layer's.

The existing `skipPrefixes` / `skipContains` filter (for `true`, `vector`, `error`, `null`, `{X:Type}`) applies unchanged to both branches.

### `Resolution.swift`

A new static method on `Resolver`:

```swift
static func resolveLayeredTypes(
    layers: [(layerNumber: Int, constructors: [DescriptionParser.ConstructorDescription])]
) throws -> [(layerNumber: Int, types: [SumType])]
```

Algorithm — walks layers in input order, maintaining a running map `constructorsByName: [QualifiedName: (typeName: QualifiedName, constructor: DescriptionParser.ConstructorDescription)]`. For each layer:

1. For each constructor in the layer: if the name already exists in the running map with a different target type, remove it from the old type's entry before inserting under the new target type.
2. Insert or overwrite the constructor in the running map.
3. At the end of the layer section, build `[SumType]` from the current running map by grouping constructors by their target type and resolving argument type references (same machinery `resolveTypes(constructors:)` already uses, factored into shared helpers).

The output preserves per-layer IDs: layer 8's `decryptedMessage` has ID `0x1f814f1f`, layer 17's has `0x204d3878`, layer 46's has `0x36b091de`, layer 73's has `0x91cc4674` — each landing in its own independent `[SumType]` snapshot.

The existing `resolveTypes(constructors:)` and `resolveFunctions(…)` stay unchanged for the flat path.

### `CodeGeneration.swift`

A new static method on `CodeGenerator`:

```swift
static func generateLayered(
    apiPrefix: String,
    layerNumber: Int,
    types: [SumType]
) throws -> (filename: String, source: String)
```

Returns filename `"\(apiPrefix)Layer\(layerNumber).swift"` and a source string in the shape described below. Reuses the existing private helpers `typeReferenceRepresentation`, `generateFieldSerialization`, `generateFieldParsing`, and `SumType.hasDirectReference(to:typeMap:)` unchanged — the per-argument serialize/parse logic is byte-identical between flat and layered output.

The flat `CodeGenerator.generate(…)` entry point is untouched.

### `main.swift`

Branches on the parser's return value:

```swift
switch try DescriptionParser.parse(data: data) {
case let .flat(constructors, functions):
    // existing flow, unchanged
case let .layered(layers):
    let resolved = try Resolver.resolveLayeredTypes(layers: layers)
    try FileManager.default.createDirectory(
        at: URL(fileURLWithPath: outputDirectoryPath),
        withIntermediateDirectories: true)
    for (layerNumber, types) in resolved {
        let (filename, source) = try CodeGenerator.generateLayered(
            apiPrefix: apiPrefix, layerNumber: layerNumber, types: types)
        let filePath = URL(fileURLWithPath: outputDirectoryPath)
            .appendingPathComponent(filename).path
        _ = try? FileManager.default.removeItem(atPath: filePath)
        try source.write(toFile: filePath, atomically: true, encoding: .utf8)
    }
}
```

## Layer semantics

For each emitted layer `N`, the effective constructor set is the ordered union of all constructors declared in layers `L ≤ N`, where a constructor with a given `QualifiedName` in a later layer **replaces** the earlier entry (new ID, new arguments, potentially new target sum type). The latest winner is the only one that appears in layer `N`'s output; earlier IDs are not included in layer `N`'s dispatch table.

Constructors declared only in layers `> N` do not appear in layer `N`.

Pre-marker constructors (e.g. `boolFalse`, `boolTrue` in `secret_scheme.tl`) are attached to the lowest-numbered layer. Rationale: (1) keeps the rule uniform ("every constructor belongs to exactly one declared layer"), (2) matches the natural reading of the schema file, (3) has no observable effect today since no downstream consumer references `Bool` from a secret-schema layer.

## Output format (per layer)

Matches the shape of the existing hand-written `SecretApiLayer{N}.swift` files. One file per layer, named `{apiPrefix}Layer{N}.swift`.

```
<leading blank line>

fileprivate let parsers: [Int32 : (BufferReader) -> Any?] = {
    var dict: [Int32 : (BufferReader) -> Any?] = [:]
    dict[-1471112230] = { return $0.readInt32() }
    dict[570911930] = { return $0.readInt64() }
    dict[571523412] = { return $0.readDouble() }
    dict[-1255641564] = { return parseString($0) }
    // dict[0x0929C32F] = { return parseInt256($0) } — emitted iff any constructor
    // in this layer's cumulative snapshot has a field of type Int256.
    dict[<sid>] = { return {apiPrefix}{N}.<TypeName>.parse_<ctorName>($0) }
    // ... one entry per (latest) constructor in the cumulative snapshot
    return dict
}()

public struct {apiPrefix}{N} {
    public static func parse(_ buffer: Buffer) -> Any? { ... }
    fileprivate static func parse(_ reader: BufferReader, signature: Int32) -> Any? { ... }
    fileprivate static func parseVector<T>(_ reader: BufferReader, elementSignature: Int32, elementType: T.Type) -> [T]? { ... }
    public static func serializeObject(_ object: Any, buffer: Buffer, boxed: Swift.Bool) { ... }

    public enum <TypeName1> { /* cases, serialize, parse_* */ }
    public enum <TypeName2> { ... }
    // ...
}
```

**Deliberate differences from the flat-mode `Api0/1/….swift` output:**

- Single file instead of `Api0` header + `Api{1..N}` sharded impl files.
- `public struct` for the namespace instead of `public enum`.
- Nested `public enum <TypeName>` declarations instead of extensions.
- No `Cons_*` helper classes; enum cases use the inline-args shape — i.e. `case decryptedMessage(randomId: Int64, randomBytes: Buffer, message: String, media: …)`. Note the flat generator has a dormant inline-args branch guarded by `useStructPattern = false` that is never taken today; the layered generator renders this shape directly rather than sharing that branch.
- No `descriptionFields()` method, no `TypeConstructorDescription` conformance on the enums.
- `parse_*` methods are `fileprivate`, not `public static`.
- No `---functions---` section (rejected upstream).

The `indirect` keyword is still emitted when a type transitively references itself, via the existing `SumType.hasDirectReference(to:typeMap:)` helper.

## CLI

Unchanged. `swift run SwiftTL <schema> <outputDir> [--api-prefix=<prefix>]`. Layered behavior auto-triggers on `===N===` marker presence. With `--api-prefix=SecretApi` on `secret_scheme.tl`, SwiftTL emits 11 files: `SecretApiLayer{8,17,20,23,45,46,66,73,101,143,144}.swift`.

## Out-of-scope follow-ups

### `generate_and_copy_scheme.sh`

Lives in `telegram-ios-shared/tools/` (sibling repo). Currently invokes SwiftTL on both schemas but only copies `NewScheme/Api*.swift` into `submodules/TelegramApi/Sources/`. After this SwiftTL change lands, the script gains:

```sh
rm -f ../../telegram-ios/submodules/TelegramApi/Sources/SecretApiLayer*.swift
cp NewSecretScheme/SecretApiLayer*.swift ../../telegram-ios/submodules/TelegramApi/Sources/
```

The SwiftTL change produces the right files; the shell-script wiring is a follow-up commit in the sibling repo.

### `submodules/TelegramApi/BUILD`

If `submodules/TelegramApi/BUILD` lists the existing `SecretApiLayer{8,46,73,101,144}.swift` explicitly, it must be updated to include the 6 new layer files (17, 20, 23, 45, 66, 143) before the project will build. Implementation step: grep BUILD for `SecretApiLayer` at the start of implementation — if explicit, either add the 6 new file entries or switch to a `glob(["Sources/SecretApiLayer*.swift"])` pattern, in the same commit that introduces the files.

## Verification

No unit tests exist in this repo (per `CLAUDE.md`). Verification steps:

1. **Layered schema compiles.** `swift run SwiftTL <path>/secret_scheme.tl /tmp/out --api-prefix=SecretApi` succeeds and produces 11 files.
2. **Generated files match legacy by semantics.** Spot-check `SecretApiLayer8.swift`, `SecretApiLayer46.swift`, `SecretApiLayer73.swift`, `SecretApiLayer101.swift`, `SecretApiLayer144.swift` against their hand-written counterparts in `submodules/TelegramApi/Sources/`. Confirm:
   - Same set of enum case names per sum type.
   - Same constructor IDs in the dispatch table (latest per name only).
   - Same argument ordering and types.
   - Same indirect-ness for self-referential types.
   Cosmetic differences (whitespace, per-helper indentation quirks, absence of `Cons_*`) are acceptable.
3. **Project builds.** Copy the generated files over the hand-written ones in `submodules/TelegramApi/Sources/`, run the full Bazel build (`source ~/.zshrc 2>/dev/null; Make.py build --continueOnError`), and confirm zero compilation errors. `ManagedSecretChatOutgoingOperations.swift` and `ProcessSecretChatIncomingDecryptedOperations.swift` reference `SecretApi{8,46,73,101,144}.<Type>.<ctor>` symbols that the generator preserves.
4. **Flat schema is unchanged.** `swift run SwiftTL <path>/swift_scheme.tl /tmp/out-main` succeeds; diff the generated `Api*.swift` against `submodules/TelegramApi/Sources/Api*.swift`. Expected: byte-identical (flat codepath untouched).

## Risks

- **Legacy-file semantic drift.** The hand-written `SecretApiLayer*.swift` files may contain micro-deviations from what the schema strictly implies (a constructor sneaked in by hand, an ID typo, an argument order tweak). Any such deviations will surface as compile or runtime-parse errors after regeneration. Mitigation: verification step 2 surfaces these before building; if found, the spec takes the schema as authoritative — legacy hand-edits get reverted, not preserved.
- **BUILD glob vs. explicit file list.** If BUILD lists files explicitly, adding the 6 new layer files (17, 20, 23, 45, 66, 143) requires a BUILD update in the same commit. Verification step during implementation.
- **Pre-marker constructor attribution.** `boolFalse`/`boolTrue` land in layer 8 under the spec. If the existing hand-written `SecretApiLayer8.swift` does not contain `Bool` (likely, since no consumer references it), the generator will add a nested `public enum Bool { case boolFalse; case boolTrue }` to layer-8 (and cumulatively to every subsequent layer) and two entries to each cumulative layer's dispatch dict. Harmless addition — build unaffected; diff noise only.
