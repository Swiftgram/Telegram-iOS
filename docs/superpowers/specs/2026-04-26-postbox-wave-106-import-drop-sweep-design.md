# Postbox → TelegramEngine wave 106 — speculative `import Postbox` drop sweep (round 2)

## Context

Wave 93 (`72de7c4fd5`) ran the first speculative `import Postbox` drop sweep across the consumer modules in `submodules/`. It used a "drop blindly, restore on build feedback" methodology: 12 files dropped, 5 restored after the first build cycle, 7 net imports removed in a single commit.

Since wave 93, waves 94–105 have removed many further Postbox-typed references from consumer files (storeResourceData/moveResourceData/etc. drains, DeviceContactInfoSubject enum-payload migration, and several Shape-C/D mini-refactors). A second sweep should now find newly-orphaned `import Postbox` lines in files where the last Postbox reference was peeled off by an intervening wave.

This spec covers wave 106: the round-2 sweep applying the same methodology with an expanded pre-flight regex set incorporating wave 93's escape-case lessons.

## Goal

Drop `import Postbox` from any consumer-module Swift file in `submodules/` whose remaining content no longer references a Postbox-only symbol. Single atomic wave commit. No semantic code changes — only `import` and BUILD `deps` lines.

## Out of scope

- `submodules/Postbox/` (the module being phased out — never drop its self-references).
- `submodules/TelegramCore/` (different rules; TelegramCore must not `@_exported import Postbox` per wave-1 rule but its internal files retain `import Postbox` as needed).
- `submodules/TelegramApi/` (out of scope for the refactor).
- New typealiases or facade additions — wave 106 is import-cleanup-only.
- Code changes that swap a remaining Postbox-typed reference for an engine equivalent (those are dedicated waves).

## Methodology

### Step 1. Inventory candidates

```sh
grep -rl "^import Postbox" submodules --include="*.swift" \
  | grep -v "^submodules/Postbox/" \
  | grep -v "^submodules/TelegramCore/" \
  | grep -v "^submodules/TelegramApi/" \
  > /tmp/wave106-candidates.txt
```

Expected size: roughly 1100–1200 files based on wave-93-era counts adjusted for waves 94–105's drops.

### Step 2. Pattern-based preemptive restore

For each candidate file, skip (do NOT drop the import) if it contains any of the following regex patterns. The patterns are split into three tiers; matching ANY one is sufficient to skip.

**Tier 1 — hard Postbox infrastructure tokens:**
- `\bPostbox\b`
- `\bMediaBox\b`
- `\bMediaResource\b` (the protocol; `TelegramMediaResource` does not match because `\b` boundary)
- `\bMediaResourceData\b`
- `\bMediaResourceId\b`
- `\bPostboxCoding\b`
- `\bPostboxDecoder\b` (rarely escapes — `EnginePostboxDecoder` available, but file may still need import)
- `\bPostboxEncoder\b` (same)
- `\bMemoryBuffer\b` (same)
- `\bTempBoxFile\b`
- `\bValueBoxKey\b`
- `\bPostboxView\b`
- `\bcombinedView\b`

**Tier 2 — identifier types still defined in Postbox:**
- `\bPeerId\b`
- `\bMessageId\b`
- `\bMediaId\b`
- `\bMessageIndex\b`
- `\bMessageAndThreadId\b`
- `\bPeerNameIndex\b`
- `\bStoryId\b`
- `\bItemCollectionId\b`
- `\bFetchResourceSourceType\b`
- `\bFetchResourceError\b`

**Tier 3 — bare-name escapes (wave 93 lesson):**
- `\bPeer\b` (the protocol; `EnginePeer` and `TelegramPeer*` and `peer` lowercase do not match)
- `\bMessage\b` (the protocol/struct; `EngineMessage` and `TelegramMessage*` do not match)
- `\bMedia\b` (the protocol; `EngineMedia` and `TelegramMedia*` do not match)

Skip-list construction: build the regex by joining all three tiers with `|` and run a single `grep -E -l "<combined-regex>" $(cat /tmp/wave106-candidates.txt) > /tmp/wave106-skiplist.txt`. The drop-list is `comm -23 <(sort /tmp/wave106-candidates.txt) <(sort /tmp/wave106-skiplist.txt)`. Files in the skip-list keep their `import Postbox`. Over-skipping (false positives from comments or string literals) is safe — it just lowers yield; under-skipping is caught by the build feedback loop in steps 4-5.

### Step 3. Drop imports

For each file in `candidates - skip-list`, drop the `import Postbox` line via `Edit` (one Edit per file). All drops happen in a single batch before the first build — wave 93 validated that build feedback handles a large failure batch without manual triage difficulty (`grep "error:" /tmp/build.log | awk -F: '{print $1}' | sort -u` produces the restore list).

### Step 4. Build with `--continueOnError`

```sh
source ~/.zshrc 2>/dev/null; \
python3 build-system/Make/Make.py --overrideXcodeVersion \
 --cacheDir ~/telegram-bazel-cache \
 build \
 --configurationPath build-system/appstore-configuration.json \
 --gitCodesigningRepository git@gitlab.com:peter-iakovlev/fastlanematch.git \
 --gitCodesigningType development --gitCodesigningUseCurrent --buildNumber=1 \
 --configuration=debug_sim_arm64 \
 --continueOnError 2>&1 | tee /tmp/wave106-build-iter1.log
```

Parse the log for `error:` lines. Group by file path; restore `import Postbox` to any file with a missing-symbol error.

### Step 5. Iterate

Re-run the build. Repeat restore-and-rebuild until clean. Halt-on-iter-5 (see halt conditions).

### Step 6. Final clean build (no `--continueOnError`)

Confirm green build to validate that no inter-module ordering issue was masked.

### Step 7. BUILD-dep sweep (optional, if time permits)

For each Bazel package whose Swift sources no longer reference `import Postbox`:

```sh
# enumerate packages with no remaining Postbox imports
for build in $(find submodules -name BUILD); do
  pkg_dir=$(dirname "$build")
  if ! grep -rq "^import Postbox" "$pkg_dir" --include="*.swift" 2>/dev/null; then
    if grep -q "//submodules/Postbox" "$build"; then
      echo "$build"
    fi
  fi
done
```

For each match: drop the `//submodules/Postbox` entry from the package's `BUILD` `deps` list. Re-run the full clean build to confirm.

### Step 8. Single commit

All file edits and BUILD changes land in one commit:

```
Postbox -> TelegramEngine wave 106 (import drop sweep round 2)

Speculative drop of `import Postbox` in N files where the last
Postbox-typed symbol reference was peeled off by waves 94-105.
Methodology: pattern-based pre-flight skip + drop + build feedback +
restore loop (wave-93-validated recipe). M files restored after build.
+ K BUILD deps removed.
```

## Halt conditions

1. **Scope drift to TelegramCore/Postbox/TelegramApi.** If build errors surface in any of these three modules, halt immediately and `git reset --hard` the wave. The candidate filter is wrong somewhere.
2. **First-pass failure rate > 50%.** Indicates the pre-flight regex set is missing a major escape pattern. Halt, analyze the failure cluster, expand regex, re-run from step 2.
3. **Iteration count > 5.** Diminishing returns; commit what is green and defer the rest to wave 107.

## Pre-flight WIP check

Before any edits:

```sh
git status --short | grep -v "^??" | grep -v "^ m build-system/bazel-rules/sourcekit-bazel-bsp"
```

If output is non-empty, halt — there is unrelated WIP that would get tangled. The known persistent state (untracked `build-system/tulsi/`, `submodules/TgVoip/`, `third-party/libx264/` and the `m` submodule marker) is acceptable and recorded in memory.

## Expected outcome

- 5–30 net `import Postbox` drops in `submodules/`.
- 0–3 BUILD `deps` removals.
- 2–3 build iterations.
- Single commit.
- Wall-clock 30–90 min.

## Risks

- **Regex misses bare type names** → caught by build feedback at cost of 1 extra cycle. Acceptable.
- **A file holds a Postbox reference only inside a comment** that the regex doesn't distinguish from real code → safe (false positive: file would have been skipped unnecessarily; sweep just leaves the import in).
- **Cross-file dependency where dropping module A's import breaks module B compilation** → caught by build cycle; restore in the failing module.
- **Bazel cache state inconsistency** → unlikely with `--cacheDir ~/telegram-bazel-cache` already in steady state, but if surfaces, full clean build will catch it.

## Success criteria

- `git diff --stat` shows only `import Postbox` line removals (and possibly BUILD `deps` line removals).
- Final clean build (no `--continueOnError`) is green.
- No file outside `submodules/` modified.
- No file in `submodules/Postbox/`, `submodules/TelegramCore/`, or `submodules/TelegramApi/` modified.
- Memory file `project_postbox_refactor_next_wave.md` updated to record the wave outcome.
