# CLAUDE.md reorganization — design

**Date:** 2026-04-22
**Status:** approved (brainstorm), pending plan

## Problem

`CLAUDE.md` has grown to 804 lines / ~99KB. It is loaded into every AI session in this repository, so its size directly consumes context budget that could be used for actual code work. It is also hard to navigate and maintain — the bulk is a per-wave changelog of the Postbox → TelegramEngine refactor, which obscures the rules, cheat sheets, and patterns that future waves actually need.

Two goals, weighted equally:

1. **Reduce always-loaded context size.** Target: CLAUDE.md shrinks to roughly ~200 lines / ~20KB (an ~80% reduction).
2. **Improve discoverability.** What remains in CLAUDE.md should be tight enough that an AI assistant can scan it and find the applicable rule or pattern without wading through narrative history.

## Current content breakdown

- Build / Code Style / Project Structure: ~35 lines — pure guidance, stays.
- Postbox refactor section: ~750 lines, further split:
  - Standing rules 1–7: ~20 lines — active rules.
  - Engine typealias cheat sheet: ~25 lines — active reference.
  - MediaResource → EngineMediaResource patterns: ~30 lines — active patterns.
  - Wave-selection guidance: ~150 lines — distilled lessons mixed with narrative backstory.
  - Wave 1–26 outcomes: ~500 lines — history.
  - Running tally of Postbox-free modules: ~30 lines — changelog-style enumeration.
  - TelegramEngine.Resources facade inventory table: ~30 lines — active reference table.
  - Known future-wave candidates: ~40 lines — planning state, duplicates memory file.
  - Build command pointer: ~2 lines — duplicate of top-of-file section.

## Final structure

### CLAUDE.md (stays; slimmed)

Sections, in order:

1. **Build** — unchanged.
2. **Code Style Guidelines** — unchanged.
3. **Project Structure** — unchanged.
4. **Postbox → TelegramEngine refactor (in progress)**, containing:
   - A brief intro paragraph plus a pointer: "Wave-by-wave history, full narrative lessons, running tallies, and example scripts live in `docs/superpowers/postbox-refactor-log.md` — read that file when you need wave-specific context or a full worked example."
   - **Standing rules 1–7** — unchanged.
   - **Engine typealias cheat sheet** — unchanged.
   - **MediaResource → EngineMediaResource consumer migration** — unchanged.
   - **Wave-selection guidance** — trimmed. Keep rules and recipes as terse bullets; drop narrative backstory, wave-specific iteration counts, full example scripts. Cross-reference the log file for backstory. Target: ~40–60 lines instead of ~150.
   - **TelegramEngine.Resources facade inventory table** — unchanged (active reference table).
   - The duplicate "Build command" pointer at the end is dropped (already covered at the top).

Everything that gets removed either moves to the log file or (for future-wave candidates) merges into the existing memory file.

### `docs/superpowers/postbox-refactor-log.md` (new file, not loaded by default)

- Short header explaining purpose: "Historical record of the Postbox → TelegramEngine refactor. Not loaded by default into AI sessions. AI assistants should read this file when they need wave-specific context, full worked examples of a pattern, or the running tally of module Postbox-freeness."
- Wave 1–26 outcomes verbatim (no edits).
- Running tally of Postbox-free modules.
- Full self-contained forms of each guidance subsection that gets trimmed in CLAUDE.md — the rule, the backstory, example scripts, iteration-count stories, and pre-migration inventories together, so a reader of the log file doesn't need to jump back to CLAUDE.md to know what rule the backstory supports. Each subsection has a stable anchor that the trimmed CLAUDE.md bullet can cross-reference.

### `project_postbox_refactor_next_wave.md` (existing memory file; updated)

- Merge in the four categories from CLAUDE.md's "Known future-wave candidates" section:
  - Permanently blocked (4 classes conforming to `TelegramMediaResource`).
  - Higher-friction mediaBox methods (cached representations, resourceData/resourceStatus sweeps, storageBox wrapping).
  - Non-mediaBox established patterns (preferencesView sweep, `loadedPeerWithId` sweep).
  - Standalone Postbox-class-move opportunities.
  - Unused-import sweep re-run.
- Keep existing wave-27+ shortlist content.

## What "trim the guidance" concretely means

For each subsection under "Wave-selection guidance", the rule is **keep the actionable rule/recipe; drop the story**.

Worked example — current "Unused-import sweeps are a valid wave shape" is a ~35-line block with numbered methodology (steps 1–7), a script snippet, and an iteration-count anecdote ("18 → 4 → 5 → 3 → 12 → ..."). After trim in CLAUDE.md:

> **Unused-import sweeps** (wave-shape applied in waves 6, 14): speculatively drop `^import Postbox$`, build with `--continueOnError`, restore failures, iterate. After a few iterations, do pattern-based preemptive restores for files naming Postbox-only symbols. Scope never leaves the consumer-module candidate set — halt if errors surface in TelegramCore/Postbox/TelegramApi. Full methodology, scripts, and iteration stats in `postbox-refactor-log.md`.

Same treatment for the other guidance subsections:

- "Wave-selection guidance" (top-level "leaf module, drop Postbox in isolation" commentary)
- "Two feasible wave shapes" paragraph
- "Enum-payload migrations need a full case-site grep" paragraph
- "Public-Postbox-type inventory (wave-11-pattern planning)" paragraph — including the `postbox-public-types.txt` script
- "Wave-shape G: facade addition + consumer sweep in one commit" paragraph — keep the seven-step recipe, drop prose about wave-26 `RangeSet` example

## Implementation approach

Three commits, each self-contained:

1. **Create the log file.** Write `docs/superpowers/postbox-refactor-log.md` containing: header, Wave 1–26 outcomes verbatim, running tally of Postbox-free modules, verbose guidance passages extracted from CLAUDE.md. Commit.
2. **Rewrite CLAUDE.md.** Trim the guidance section to terse bullets with log-file cross-references, drop the wave outcomes and running tally sections, drop the duplicate build-command pointer at the bottom, add the log-file pointer near the start of the Postbox section. Commit.
3. **Update memory files.** Merge "Known future-wave candidates" into `project_postbox_refactor_next_wave.md`. Update `MEMORY.md` one-line index if its description of that file changes materially. Commit.

Commits are ordered so that if anyone reads HEAD at any point between commits, nothing is lost: commit 1 adds content without removing any, commit 2 removes content that's now in the log, commit 3 moves planning state to where it belongs.

## Non-goals

- No pruning or editing of the wave outcomes themselves. Verbatim move.
- No restructuring of the rest of `docs/` or of the `memory/` directory beyond the one-section merge.
- No changes to the build, code style, or project structure sections of CLAUDE.md.

## Success criteria

- CLAUDE.md ≤ ~250 lines / ~25KB. (Hard cap; stretch target ~200 lines / ~20KB.)
- Every guidance bullet in the trimmed CLAUDE.md either stands alone or has an explicit cross-reference to `postbox-refactor-log.md`.
- `postbox-refactor-log.md` contains Wave 1–26 outcomes verbatim — a diff between the removed-from-CLAUDE.md text and the added-to-log text should be empty.
- `project_postbox_refactor_next_wave.md` contains all five categories of future-wave candidates that previously lived in CLAUDE.md.
- No information is lost across the three commits.
