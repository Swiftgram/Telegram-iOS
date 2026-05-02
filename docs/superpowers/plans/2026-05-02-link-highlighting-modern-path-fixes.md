# Modern Path Link-Highlighting Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix two correctness bugs in `LinkHighlightingNode`'s modern path branch — issue #3 (X-edge snap unreachable after midY snap) and issue #7 (zero-radius arcs from `floor` rounding).

**Architecture:** Two single-token edits in `submodules/Display/Source/LinkHighlightingNode.swift`, each landed as its own commit. Final validation by full project build (no unit tests in this repo per CLAUDE.md).

**Tech Stack:** Swift, Bazel via `Make.py`, iOS simulator (`debug_sim_arm64`).

**Spec:** `docs/superpowers/specs/2026-05-02-link-highlighting-modern-path-fixes-design.md`

---

## File map

- Modify: `submodules/Display/Source/LinkHighlightingNode.swift` — two single-line edits inside the `useModernPathCalculation` branch of `drawRectsImageContent`. No new files, no signature changes, no callers affected.

---

## Task 1: Fix issue #3 — X-edge snap inset direction

The X-snap guard currently uses `insetBy(dx: 0.0, dy: 1.0)`, which *shrinks* `rects[i]` by 1 px on each Y edge. After the preceding midY snap, `rects[i].maxY == rects[i+1].minY`; shrinking then makes them not intersect (`CGRect.intersects` requires positive-area overlap), so the guard is unreachable for the canonical multi-line link case. The fix is to flip the direction so the rect *grows*, producing the 1-px overlap the guard needs.

**Files:**
- Modify: `submodules/Display/Source/LinkHighlightingNode.swift:85`

- [ ] **Step 1: Inspect the target line**

Run:
```bash
sed -n '85p' submodules/Display/Source/LinkHighlightingNode.swift
```

Expected:
```
                    if rects[i].maxY >= rects[i + 1].minY && rects[i].insetBy(dx: 0.0, dy: 1.0).intersects(rects[i + 1]) {
```

If the line content differs, stop and re-read the file — line numbers may have shifted.

- [ ] **Step 2: Apply the edit**

In `submodules/Display/Source/LinkHighlightingNode.swift`, replace the X-snap guard with a negative-dy inset so the temp rect grows by 1 px on each Y edge:

```swift
                    if rects[i].maxY >= rects[i + 1].minY && rects[i].insetBy(dx: 0.0, dy: -1.0).intersects(rects[i + 1]) {
```

The change is a single character: `dy: 1.0` → `dy: -1.0`. No other lines change.

- [ ] **Step 3: Verify the change**

Run:
```bash
sed -n '85p' submodules/Display/Source/LinkHighlightingNode.swift
```

Expected:
```
                    if rects[i].maxY >= rects[i + 1].minY && rects[i].insetBy(dx: 0.0, dy: -1.0).intersects(rects[i + 1]) {
```

- [ ] **Step 4: Commit**

```bash
git add submodules/Display/Source/LinkHighlightingNode.swift
git commit -m "$(cat <<'EOF'
LinkHighlightingNode: fix X-edge snap unreachable after midY snap

In drawRectsImageContent's modern path the snap loop runs midY
trimming first, leaving rects[i].maxY == rects[i+1].minY for
adjacent line rects. The X-edge snap guard then evaluated
rects[i].insetBy(dx: 0.0, dy: 1.0).intersects(rects[i+1]) — but
positive dy shrinks the rect, so after the trim the guarded
rectangle no longer intersects its neighbor (CGRect.intersects
requires positive-area overlap). Flip dy to -1.0 so the temp
rect grows and touching neighbors satisfy the guard.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Fix issue #7 — replace `floor` with `ceil` in nextRadius/prevRadius

`nextRadius` (line 127) and `prevRadius` (line 154) compute the corner-fillet radius for stair-step joins between adjacent line rects: `min(outerRadius, floor(abs(...) * 0.5))`. When `|Δx| < 2`, `floor` produces 0 and the subsequent `addArc(... radius: 0)` is a no-op (the corner stays unsmoothed). After Task 1's fix, the X-snap will catch most `|Δx| < 2` cases — but residual fractional-pixel deltas can still hit floor=0. Switching to `ceil` clamps any non-zero gap up to ≥ 1 px, which is what the corner needs visually. Subpixel `Δx == 0` is not affected because the `else` branch at lines 124 and 151 handles exact equality with a straight `addLine`.

**Files:**
- Modify: `submodules/Display/Source/LinkHighlightingNode.swift:127`
- Modify: `submodules/Display/Source/LinkHighlightingNode.swift:154`

- [ ] **Step 1: Inspect both target lines**

Run:
```bash
sed -n '127p;154p' submodules/Display/Source/LinkHighlightingNode.swift
```

Expected:
```
                    let nextRadius = min(outerRadius, floor(abs(rect.maxX - next.maxX) * 0.5))
                    let prevRadius = min(outerRadius, floor(abs(rect.minX - prev.minX) * 0.5))
```

If either line content differs, stop and re-read the file.

- [ ] **Step 2: Apply edit on line 127**

In `submodules/Display/Source/LinkHighlightingNode.swift`, change:
```swift
                    let nextRadius = min(outerRadius, floor(abs(rect.maxX - next.maxX) * 0.5))
```
to:
```swift
                    let nextRadius = min(outerRadius, ceil(abs(rect.maxX - next.maxX) * 0.5))
```

- [ ] **Step 3: Apply edit on line 154**

In the same file, change:
```swift
                    let prevRadius = min(outerRadius, floor(abs(rect.minX - prev.minX) * 0.5))
```
to:
```swift
                    let prevRadius = min(outerRadius, ceil(abs(rect.minX - prev.minX) * 0.5))
```

- [ ] **Step 4: Verify both changes**

Run:
```bash
sed -n '127p;154p' submodules/Display/Source/LinkHighlightingNode.swift
```

Expected:
```
                    let nextRadius = min(outerRadius, ceil(abs(rect.maxX - next.maxX) * 0.5))
                    let prevRadius = min(outerRadius, ceil(abs(rect.minX - prev.minX) * 0.5))
```

- [ ] **Step 5: Confirm no other `floor(abs(` patterns remain in the modern branch**

Run:
```bash
grep -n "floor(abs(" submodules/Display/Source/LinkHighlightingNode.swift
```

Expected: no matches (the only remaining `floor` should be on line 79, the midY snap, which is intentional).

- [ ] **Step 6: Commit**

```bash
git add submodules/Display/Source/LinkHighlightingNode.swift
git commit -m "$(cat <<'EOF'
LinkHighlightingNode: ceil instead of floor for stair-step radii

drawRectsImageContent's modern path computed nextRadius and
prevRadius as min(outerRadius, floor(|Δx| * 0.5)). When |Δx| < 2
the floor produces 0 and the addArc call becomes a no-op,
leaving an unsmoothed corner at the stair-step. Replace floor
with ceil so any non-zero edge mismatch rounds up to at least
1 px. Exact-equality cases (Δx == 0) are unaffected — they take
the else branch with a straight addLine.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Validate with full project build

The Display module (and most of the chat UI submodules) depend on `LinkHighlightingNode.swift`, so a clean build of the umbrella `Telegram/Telegram` target validates that the edits are syntactically and semantically valid. There are no unit tests in this repo. CLAUDE.md notes that `TELEGRAM_CODESIGNING_GIT_PASSWORD` lives in `~/.zshrc` and must be sourced explicitly because Bash here doesn't read shell config.

**Files:**
- None (build-only validation).

- [ ] **Step 1: Run full project build**

Run from the repo root:
```bash
source ~/.zshrc 2>/dev/null; python3 build-system/Make/Make.py --overrideXcodeVersion \
  --cacheDir ~/telegram-bazel-cache \
  build \
  --configurationPath build-system/appstore-configuration.json \
  --gitCodesigningRepository git@gitlab.com:peter-iakovlev/fastlanematch.git \
  --gitCodesigningType development --gitCodesigningUseCurrent --buildNumber=1 --configuration=debug_sim_arm64
```

Expected: build succeeds (exit code 0). The build is multi-minute; tail the output and confirm completion.

- [ ] **Step 2: If build fails**

If the build fails on `LinkHighlightingNode.swift`:
- A failure on line 85 means the inset edit was malformed — re-check the syntax.
- A failure on lines 127 or 154 means the `floor → ceil` swap introduced a typo.
- A failure elsewhere is unrelated to these edits — investigate before continuing.

If the failure is on `LinkHighlightingNode.swift`, revert the failing commit (`git reset --hard HEAD~1`), re-apply the edit using the `Edit` tool with exact matching strings, and rerun the build.

- [ ] **Step 3: Visual check (manual, optional)**

If the simulator is launched, send a chat message with a long URL that wraps across multiple lines and tap-and-hold to invoke the link highlight. The stair-step joins between line rects should now show smooth fillets where adjacent X edges differ by less than 2 px (previously unsmoothed). This step is informational — the build success is the gating signal for the plan.

---

## Self-Review

- **Spec coverage:** Issue #3 → Task 1. Issue #7 → Task 2. Validation paragraph → Task 3. Out-of-scope items (#1, #2, #5, #6, #8) explicitly excluded — covered by spec, not by tasks.
- **Placeholder scan:** No "TBD" / "TODO" / "similar to" / vague-error-handling. All edits show exact before/after code.
- **Type consistency:** No new symbols introduced; existing `outerRadius`, `nextRadius`, `prevRadius`, `rects[i]`, `CGRect.insetBy(dx:dy:)`, `CGRect.intersects(_:)` all already in scope at the edit sites.
- **Line-number drift:** Each edit task starts with a `sed -n` inspection that bails out if the line content differs from the expected string — protects against drift if the file is touched between plan-write and plan-execute.
