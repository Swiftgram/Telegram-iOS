# InstantPage V2 — flush (edge-to-edge) un-rounded block media

## Goal

In the InstantPage **V2** renderer (rich-text chat bubbles), block media is
currently laid out as an **inset rounded rect**: the media frame is inset by the
page `horizontalInset` (11pt) on each side and drawn with an 8pt corner radius.
Change it so block media is **flush with the bubble interior (0-inset)** and
**un-rounded (cornerRadius 0)**, relying on the bubble's existing rounded-corner
clipping container to round media that reaches the bubble's top/bottom edge.

**V1 is out of scope** — only the V2 layout/renderer changes.

## Scope of "block media"

Every block-media kind in the V2 layout goes flush + un-rounded **except
`.audio`**:

| Block | Today | After |
|---|---|---|
| `.image` | inset, r=8 | flush, r=0 |
| `.video` | inset, r=8 | flush, r=0 |
| `.map` | inset, r=8 | flush, r=0 |
| `.webEmbed` (cover image) | inset, r=0 | flush, r=0 |
| `.webEmbed` (grey placeholder) | inset, r=0 | flush, r=0 |
| `.postEmbed` | inset, r=8 | flush, r=0 |
| `.collage` | inset, r=8 | flush, r=0 |
| `.slideshow` | inset, r=8 | flush, r=0 |
| `.channelBanner` | inset, r=0 | flush, r=0 |
| `.relatedArticles` | inset, r=0 | flush, r=0 |
| **`.audio`** | inset, r=8 | **unchanged** (inset, r=8) |

`.audio` is the single exception — it keeps today's inset + 8pt rounding.

## Decisions (from brainstorming)

- **Small images are NOT upscaled.** Keep the existing `scale = min(availableWidth /
  naturalSize.width, 1.0)` cap. A small image renders at its natural pixel size,
  flush-left at x=0 (not stretched to full width). Large images (the common
  AI-generated case) still fill the width.
- **Square corners everywhere.** No per-corner rounding logic. Media views draw
  square; the existing rounded-corner clipping container rounds whatever media
  reaches the bubble's top/bottom edge.
- **Captions stay inset.** Caption/credit text is laid out separately at
  `horizontalInset` and is unchanged — inset text under a full-bleed image.

## Architecture

Two layout helpers in
`submodules/InstantPageUI/Sources/InstantPageV2Layout.swift` are the only places
that compute the inset media frame and carry the corner radius:

- `layoutTypedMediaWithCaption(produceItem:naturalSize:caption:isCover:cornerRadius:boundingWidth:horizontalInset:context:)`
  — used by `.image`, `.video`, `.webEmbed` cover, `.map`.
- `layoutMediaWithCaption(kind:naturalSize:caption:isCover:cornerRadius:boundingWidth:horizontalInset:context:)`
  — used by `.audio`, `.webEmbed` placeholder, `.postEmbed`, `.collage`,
  `.slideshow`, `.channelBanner`, `.relatedArticles`.

Both compute `availableWidth = boundingWidth − horizontalInset*2`, place the
media at `x: horizontalInset`, and pass a caller-supplied `cornerRadius` onto the
produced item.

### Change: add a `flush` parameter to both helpers

Add `flush: Bool` to both helper signatures. When `flush == true`:

- `availableWidth = boundingWidth` (full width, was `boundingWidth − horizontalInset*2`).
- media frame `x: 0` (was `horizontalInset`).
- the produced item's `cornerRadius` is forced to `0` (the per-call-site
  `cornerRadius` argument becomes irrelevant on the flush path).

When `flush == false` (audio only): today's behavior verbatim (inset frame,
caller's corner radius).

The `scale = min(availableWidth / naturalSize.width, 1.0)` cap is **kept** in both
paths — only `availableWidth` and the frame `x` change, so the no-upscale
behavior is preserved.

### Call sites

Every media `case` in `layoutBlock` passes `flush: true` **except `.audio`**,
which passes `flush: false`. The cover-padding logic (`isCover && captionHeight >
0`) and the caption/credit layout (`layoutCaptionAndCredit` at `horizontalInset`)
are unchanged in both helpers.

### Render side — no change

`InstantPageV2MediaViews.swift` already gates clipping on the radius:
`self.clipsToBounds = item.cornerRadius > 0.0` and `self.layer.cornerRadius =
item.cornerRadius` in every media view's `update(...)`. With `cornerRadius 0` the
media view does **not** clip itself; the bubble's container does (below). No edit
to the renderer or the media views is required.

### Rounded clip is the existing `containerNode`

In
`submodules/TelegramUI/Components/Chat/ChatMessageRichDataBubbleContentNode/Sources/ChatMessageRichDataBubbleContentNode.swift`
the `containerNode` already:

- sets `clipsToBounds = true` (init), and
- sets `cornerRadius = layoutConstants.image.defaultCornerRadius` (≈ 15–16pt) on
  every layout pass.

So flush, square-cornered media at the bubble's top/bottom edge is clipped to the
bubble's rounded shape automatically. **No new clipping container is introduced.**

## Implementation detail to resolve in the plan: the 1px hairline

The pageView is positioned at `x: −1` inside the `containerNode` (an existing
hairline that hides the bubble border seam): `containerNode` is at self-(1, 1)
with width `boundingWidth − 2`, and the pageView is at containerNode-`x: −1`.

Consequence: a flush media frame at page-layout `x: 0`, `width: boundingWidth`
covers the container's clip region only to within ~1px on the right, and the
contentSize-width interaction must be handled so the bubble is not widened. The
plan must:

1. Make flush media cover the rounded `containerNode` clip region edge-to-edge
   (small symmetric bleed under the rounded corners is fine — the container
   clips it), leaving no 1px bubble-background sliver, **and**
2. Ensure the flush media frame does **not** inflate the layout's
   `contentSize.width` beyond the bounding width (which would widen the bubble or
   feed back into the suggested width). Clamp `contentSize.width` to the bounding
   width if needed.

This is mechanical; the exact arithmetic is deferred to the plan.

## Out of scope / unchanged

- **V1** renderer (`InstantPageLayout.swift`, V1 `InstantPageRenderer`).
- **`.audio`** block (stays inset + r=8).
- **Captions/credits** (stay inset).
- **Streaming reveal** — media still contributes `frame.width` to the reveal
  cost map; a wider flush frame slightly increases that cost (expected, benign).
- **Status node** (date/time/checks) placement — trails text only when the
  bottom-most item is `.text`; media being flush does not change that logic.
- **Tap / gallery routing, edit / copy / paste round-trips** — the edit and copy
  converters already skip media; nothing changes.

## Testing

No unit tests in this project (per CLAUDE.md). Verification is a full Bazel build
plus a manual check that a rich message containing an image and/or video renders
edge-to-edge with no corner rounding and a correctly-clipped rounded top/bottom
where the media meets the bubble edge, with the caption still inset.
