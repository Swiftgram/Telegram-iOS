# Flush (edge-to-edge) un-rounded InstantPage V2 block media — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every InstantPage **V2** block-media kind except `.audio` render flush with the bubble interior (0 inset) and un-rounded (cornerRadius 0), relying on the bubble's existing rounded-corner clipping container.

**Architecture:** One file changes — `submodules/InstantPageUI/Sources/InstantPageV2Layout.swift`. A new shared helper `instantPageV2MediaFrame(...)` computes the media frame: in `flush` mode it uses full width at `x: 0`, forces `cornerRadius 0`, and bleeds a full-width item a few points past the right edge so the rounded clip container rounds the trailing corners cleanly (the existing `contentSize.width = min(maxX, boundingWidth)` clamp prevents the bleed from widening the bubble). The two media-layout helpers (`layoutTypedMediaWithCaption`, `layoutMediaWithCaption`) route through it and gain a `flush: Bool` parameter; every media call site passes `flush: true` except `.audio`. No renderer change — the V2 media views and the placeholder view already disable their own clip when `cornerRadius == 0`.

**Tech Stack:** Swift, Bazel (full-app build is the only build/compile gate — there are no unit tests in this project).

---

## Spec

See `docs/superpowers/specs/2026-06-01-instantpage-v2-media-flush-design.md`.

## Background an implementer needs

- **This project has no unit tests** (CLAUDE.md: "No tests are used at the moment"). The verification gate is the **full Bazel build** (it compiles every module; the enum/signature changes are compile-enforced) plus a best-effort manual visual check.
- **Build is slow (~minutes) and must be driven from the top-level session**, not a backgrounded subagent (a backgrounded subagent build gets torn down on yield). Prefix with `source ~/.zshrc` to pick up `TELEGRAM_CODESIGNING_GIT_PASSWORD`.
- **Geometry the bleed accounts for:** in `ChatMessageRichDataBubbleContentNode`, the clipping `containerNode` sits at self-`(1, 1)` with `clipsToBounds = true` and `cornerRadius = layoutConstants.image.defaultCornerRadius` (≈ 15–16pt); the `pageView` sits at `x: -1` inside it. So a page-layout item at `x: 0, width: boundingWidth` falls ~1px short of the container's right clip edge, leaving a 1px corner notch. A small symmetric over-bleed on full-width media closes it; the `min(maxX, boundingWidth)` clamp (line 552, active because both callers pass `fitToWidth: true`) keeps `contentSize.width` at `boundingWidth` so the bubble does not widen.
- **Captions stay inset** — `layoutCaptionAndCredit` is called with the page `horizontalInset` and is unchanged.
- **Render side needs no change:** `InstantPageV2MediaImageView/VideoView/MapView/CoverImageView.update(...)` and `InstantPageV2MediaPlaceholderView.update(...)` all do `self.clipsToBounds = item.cornerRadius > 0.0` and `self.layer.cornerRadius = item.cornerRadius`. With `cornerRadius 0` the media view does not clip itself; the `containerNode` clips.

---

## Task 1: Flush media layout in `InstantPageV2Layout.swift`

**Files:**
- Modify: `submodules/InstantPageUI/Sources/InstantPageV2Layout.swift`

All edits are in this one file. Steps 1–3 add the shared helper and route the two layout helpers through it; step 4 updates the 11 call sites. The file will not compile until step 4 is complete (the new required `flush:` parameter) — that is expected; the build is Task 2.

- [ ] **Step 1: Add the bleed constant and shared frame helper**

Insert the following immediately **above** the existing `private func layoutTypedMediaWithCaption(` declaration (currently at line ~1650, just after the closing `}` / `return (items, totalHeight)` of `layoutCaptionAndCredit`'s neighbor at line ~1645):

```swift
// Points a full-width flush media item bleeds past the bubble interior on the trailing
// edge so the rounded `containerNode` clip (see ChatMessageRichDataBubbleContentNode) rounds
// the trailing corners with no 1px background sliver. Harmless: the
// `contentSize.width = min(maxX, boundingWidth)` clamp keeps it from widening the bubble.
private let instantPageV2MediaEdgeBleed: CGFloat = 4.0

// Computes the laid-out frame for a block-media item.
//
// `flush == true` (every block media except audio): the media is edge-to-edge (x = 0, full
// `boundingWidth`) with corner radius forced to 0, relying on the bubble's rounded clipping
// container to round media that meets the bubble's top/bottom edge. A media item that fills the
// full width is widened by `instantPageV2MediaEdgeBleed` on the trailing edge (see the constant).
// A media item narrower than the full width (a small image — NOT upscaled, the `min(_, 1.0)`
// scale cap is kept) stays at its natural size, flush-left at x = 0, with no bleed.
//
// `flush == false` (audio only): legacy behavior — inset by `horizontalInset` on each side with
// the caller-supplied corner radius.
//
// Returns the frame, the un-bled scaled content size (the caption is offset by
// `scaledSize.height`), and the effective corner radius to stamp on the item.
private func instantPageV2MediaFrame(
    naturalSize: CGSize,
    flush: Bool,
    cornerRadius: CGFloat,
    boundingWidth: CGFloat,
    horizontalInset: CGFloat
) -> (frame: CGRect, scaledSize: CGSize, cornerRadius: CGFloat) {
    let availableWidth = flush ? boundingWidth : (boundingWidth - horizontalInset * 2.0)
    let scaledSize: CGSize
    if naturalSize.width > 0.0 && naturalSize.height > 0.0 {
        let scale = min(availableWidth / naturalSize.width, 1.0)
        scaledSize = CGSize(width: floor(naturalSize.width * scale), height: floor(naturalSize.height * scale))
    } else {
        scaledSize = CGSize(width: availableWidth, height: naturalSize.height)
    }

    if flush {
        // `floor(x) > x - 1` always, so a full-width item (scaledSize.width == floor(availableWidth))
        // always trips this; a genuinely smaller image does not.
        let fillsWidth = scaledSize.width >= availableWidth - 1.0
        let frameWidth = fillsWidth ? boundingWidth + instantPageV2MediaEdgeBleed : scaledSize.width
        let frame = CGRect(x: 0.0, y: 0.0, width: frameWidth, height: scaledSize.height)
        return (frame, scaledSize, 0.0)
    } else {
        let frame = CGRect(x: horizontalInset, y: 0.0, width: scaledSize.width, height: scaledSize.height)
        return (frame, scaledSize, cornerRadius)
    }
}
```

- [ ] **Step 2: Route `layoutTypedMediaWithCaption` through the helper + add `flush`**

Replace the head of `layoutTypedMediaWithCaption` — from its signature through the `var result: [InstantPageV2LaidOutItem] = [produceItem(mediaFrame, cornerRadius)]` line (currently lines ~1650–1670). Old:

```swift
private func layoutTypedMediaWithCaption(
    produceItem: (CGRect, CGFloat) -> InstantPageV2LaidOutItem,
    naturalSize: CGSize,
    caption: InstantPageCaption,
    isCover: Bool,
    cornerRadius: CGFloat,
    boundingWidth: CGFloat,
    horizontalInset: CGFloat,
    context: inout LayoutContext
) -> [InstantPageV2LaidOutItem] {
    let availableWidth = boundingWidth - horizontalInset * 2.0
    let scaledSize: CGSize
    if naturalSize.width > 0.0 && naturalSize.height > 0.0 {
        let scale = min(availableWidth / naturalSize.width, 1.0)
        scaledSize = CGSize(width: floor(naturalSize.width * scale), height: floor(naturalSize.height * scale))
    } else {
        scaledSize = CGSize(width: availableWidth, height: naturalSize.height)
    }

    let mediaFrame = CGRect(x: horizontalInset, y: 0.0, width: scaledSize.width, height: scaledSize.height)
    var result: [InstantPageV2LaidOutItem] = [produceItem(mediaFrame, cornerRadius)]
```

New:

```swift
private func layoutTypedMediaWithCaption(
    produceItem: (CGRect, CGFloat) -> InstantPageV2LaidOutItem,
    naturalSize: CGSize,
    caption: InstantPageCaption,
    isCover: Bool,
    cornerRadius: CGFloat,
    flush: Bool,
    boundingWidth: CGFloat,
    horizontalInset: CGFloat,
    context: inout LayoutContext
) -> [InstantPageV2LaidOutItem] {
    let (mediaFrame, scaledSize, effectiveCornerRadius) = instantPageV2MediaFrame(
        naturalSize: naturalSize,
        flush: flush,
        cornerRadius: cornerRadius,
        boundingWidth: boundingWidth,
        horizontalInset: horizontalInset
    )
    var result: [InstantPageV2LaidOutItem] = [produceItem(mediaFrame, effectiveCornerRadius)]
```

The remainder of the function (the `layoutCaptionAndCredit(..., offset: scaledSize.height, ...)` call and the `isCover && captionHeight > 0.0` block) is unchanged — `scaledSize` is still in scope.

- [ ] **Step 3: Route `layoutMediaWithCaption` through the helper + add `flush`**

Replace the head of `layoutMediaWithCaption` — from its signature through the `var result: [InstantPageV2LaidOutItem] = [.mediaPlaceholder(placeholderItem)]` line (currently lines ~1698–1730). Old:

```swift
private func layoutMediaWithCaption(
    kind: InstantPageV2MediaPlaceholderKind,
    naturalSize: CGSize,
    caption: InstantPageCaption,
    isCover: Bool,
    cornerRadius: CGFloat,
    boundingWidth: CGFloat,
    horizontalInset: CGFloat,
    context: inout LayoutContext
) -> [InstantPageV2LaidOutItem] {
    // Scale naturalSize to fit within (boundingWidth - horizontalInset*2) × naturalSize.height.
    let availableWidth = boundingWidth - horizontalInset * 2.0
    let scaledSize: CGSize
    if naturalSize.width > 0.0 && naturalSize.height > 0.0 {
        let scale = min(availableWidth / naturalSize.width, 1.0)
        scaledSize = CGSize(width: floor(naturalSize.width * scale), height: floor(naturalSize.height * scale))
    } else {
        scaledSize = CGSize(width: availableWidth, height: naturalSize.height)
    }

    let placeholderFrame = CGRect(
        x: horizontalInset,
        y: 0.0,
        width: scaledSize.width,
        height: scaledSize.height
    )
    let placeholderItem = InstantPageV2MediaPlaceholderItem(
        frame: placeholderFrame,
        kind: kind,
        cornerRadius: cornerRadius
    )

    var result: [InstantPageV2LaidOutItem] = [.mediaPlaceholder(placeholderItem)]
```

New:

```swift
private func layoutMediaWithCaption(
    kind: InstantPageV2MediaPlaceholderKind,
    naturalSize: CGSize,
    caption: InstantPageCaption,
    isCover: Bool,
    cornerRadius: CGFloat,
    flush: Bool,
    boundingWidth: CGFloat,
    horizontalInset: CGFloat,
    context: inout LayoutContext
) -> [InstantPageV2LaidOutItem] {
    let (placeholderFrame, scaledSize, effectiveCornerRadius) = instantPageV2MediaFrame(
        naturalSize: naturalSize,
        flush: flush,
        cornerRadius: cornerRadius,
        boundingWidth: boundingWidth,
        horizontalInset: horizontalInset
    )
    let placeholderItem = InstantPageV2MediaPlaceholderItem(
        frame: placeholderFrame,
        kind: kind,
        cornerRadius: effectiveCornerRadius
    )

    var result: [InstantPageV2LaidOutItem] = [.mediaPlaceholder(placeholderItem)]
```

The remainder (the `layoutCaptionAndCredit(..., offset: scaledSize.height, ...)` call and the `isCover && captionHeight > 0.0` block) is unchanged.

- [ ] **Step 4: Add `flush:` to all 11 media call sites in `layoutBlock`**

In each call below, insert the `flush:` argument line **immediately after** the existing `cornerRadius:` argument line (so argument order matches the new signatures). Use the listed anchor (the `produceItem` body's `.mediaXxx(...)` or the `kind:` value) to disambiguate the otherwise-similar calls.

`layoutTypedMediaWithCaption` calls — all get `flush: true`:

1. `.image` — `produceItem` returns `.mediaImage(...)`; `cornerRadius: 8.0,` → add `flush: true,`
2. `.video` — `produceItem` returns `.mediaVideo(...)`; `cornerRadius: 8.0,` → add `flush: true,`
3. `.webEmbed` cover — `produceItem` returns `.mediaCoverImage(...)`; `cornerRadius: 0.0,` → add `flush: true,`
4. `.map` — `produceItem` returns `.mediaMap(...)`; `cornerRadius: 8.0,` → add `flush: true,`

`layoutMediaWithCaption` calls:

5. `.audio` — `kind: .audio`; `isCover: false, cornerRadius: 8.0,` → add `flush: false,` (**the only `false`**)
6. `.webEmbed` no-cover — `kind: .webEmbed`; `isCover: false, cornerRadius: 0.0,` → add `flush: true,`
7. `.postEmbed` — `kind: .postEmbed`; `isCover: false, cornerRadius: 8.0,` → add `flush: true,`
8. `.collage` — `kind: .collage`; `isCover: false, cornerRadius: 8.0,` → add `flush: true,`
9. `.slideshow` — `kind: .slideshow`; `isCover: false, cornerRadius: 8.0,` → add `flush: true,`
10. `.channelBanner` — `kind: .channelBanner`; `isCover: false, cornerRadius: 0.0,` → add `flush: true,`
11. `.relatedArticles` — `kind: .relatedArticles`; `isCover: false, cornerRadius: 0.0,` → add `flush: true,`

For example, the `.audio` call becomes:

```swift
    case let .audio(_, caption):
        return layoutMediaWithCaption(kind: .audio,
            naturalSize: CGSize(width: boundingWidth, height: 56.0), caption: caption,
            isCover: false, cornerRadius: 8.0, flush: false, boundingWidth: boundingWidth,
            horizontalInset: horizontalInset, context: &context)
```

and the `.collage` call becomes:

```swift
    case let .collage(_, caption):
        return layoutMediaWithCaption(kind: .collage,
            naturalSize: CGSize(width: boundingWidth, height: 240.0), caption: caption,
            isCover: false, cornerRadius: 8.0, flush: true, boundingWidth: boundingWidth,
            horizontalInset: horizontalInset, context: &context)
```

and the `.image` call's argument tail becomes:

```swift
                naturalSize: naturalSize,
                caption: caption,
                isCover: isCover,
                cornerRadius: 8.0,
                flush: true,
                boundingWidth: boundingWidth,
                horizontalInset: horizontalInset,
                context: &context
```

- [ ] **Step 5: Sanity-grep — exactly one `flush: false` and ten `flush: true`**

Run:

```bash
grep -n "flush:" submodules/InstantPageUI/Sources/InstantPageV2Layout.swift
```

Expected: the two helper signatures (`flush: Bool`), the two `instantPageV2MediaFrame(... flush: flush ...)` calls, **one** `flush: false` (audio), and **ten** `flush: true` (the other media call sites) — i.e. 11 call-site `flush:` arguments total plus the helper-internal references.

---

## Task 2: Build and commit

**Files:** none (verification + commit)

- [ ] **Step 1: Run the full Bazel build (the compile gate)**

Run from the repo root, in the **top-level session** (not a backgrounded subagent), capturing the real exit code:

```bash
source ~/.zshrc 2>/dev/null; python3 build-system/Make/Make.py --overrideXcodeVersion \
 --cacheDir ~/telegram-bazel-cache \
 build \
 --configurationPath build-system/appstore-configuration.json \
 --gitCodesigningRepository git@gitlab.com:peter-iakovlev/fastlanematch.git \
 --gitCodesigningType development --gitCodesigningUseCurrent --buildNumber=1 --configuration=debug_sim_arm64
```

Expected: build succeeds. The signature change makes every media call site a compile-time gate, so a missing/extra `flush:` argument fails here. If a Swift worker fails **without** a surfaced compile error (the known silent-worker failure mode), re-run once; if it persists, re-read the changed hunks for a malformed argument list.

- [ ] **Step 2: Commit**

```bash
git add submodules/InstantPageUI/Sources/InstantPageV2Layout.swift
git commit -m "InstantPage V2: flush, un-rounded block media (except audio)

All block-media kinds except .audio now lay out edge-to-edge (0 inset) with
cornerRadius 0; the bubble's existing rounded containerNode clip rounds media at
the bubble edge. Small images keep natural size (not upscaled); captions stay
inset. Shared instantPageV2MediaFrame helper + flush flag on the two media
layout helpers. V1 unchanged.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Manual visual verification (best-effort)

**Files:** none

- [ ] **Step 1: Verify a rich message with media renders flush + un-rounded**

Block media in rich messages comes from server/AI rich content — the markdown compose path cannot produce `.image`/`.video` blocks (the markdown→InstantPage converter skips media), so a fresh rich-data bubble containing an image is reached via a received AI/server rich message. If such a message is available, confirm:

- The image/video spans the full bubble interior width (no ~11pt side inset).
- No 8pt corner rounding on the media itself; where the media meets the bubble's top/bottom edge, the corner is rounded **to the bubble's radius** (clipped by `containerNode`) with no 1px background sliver on the trailing edge.
- A small image (narrower than the bubble) sits flush-left at the bubble's left edge at its natural size (not upscaled), caption text still inset below it.
- `.audio` blocks (if any) are unchanged (inset + rounded).

If no server/AI rich message with media is reachable in the test environment, record that the visual check was deferred and rely on the build as the gate — note this in the completion summary rather than claiming the visual check passed.

---

## Self-review notes

- **Spec coverage:** scope table (all media except audio, V2 only) → Task 1 step 4; no-upscale → `min(_, 1.0)` kept in `instantPageV2MediaFrame`; square corners + rounded-container clip → `cornerRadius 0` returned by the helper + no renderer change (documented in Background); captions inset → `layoutCaptionAndCredit` untouched; 1px hairline / no-widen → `instantPageV2MediaEdgeBleed` + the `min(maxX, boundingWidth)` clamp (Background + helper).
- **Type consistency:** the helper is named `instantPageV2MediaFrame` and the constant `instantPageV2MediaEdgeBleed` everywhere; both layout helpers gain `flush: Bool` in the same signature position (after `cornerRadius:`, before `boundingWidth:`); call sites insert `flush:` in that same position.
- **No placeholders:** every step shows the exact code/command.
