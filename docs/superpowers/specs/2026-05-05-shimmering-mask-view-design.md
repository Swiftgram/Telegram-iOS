# ShimmeringMaskView — design

## Goal

Build a reusable `ShimmeringMaskView` that applies a moving alpha-mask shimmer to its `contentView`, producing a "ChatGPT thinking"-style running effect. First consumer: the `streamingStatusTextNode` in `ChatMessageTextBubbleContentNode`.

## Visual model

Reveal mask with constant baseline:

- Outside the wave, mask alpha = `1.0` (content fully visible).
- A horizontal wave travels across the content; at the wave's center, mask alpha dips to `peakAlpha` (a value < 1.0).
- The wave repeats infinitely while in the view hierarchy.

Conceptually: the wave is a *low-opacity dimming dip* sliding through; rest state is fully visible.

## Module location and BUILD

- File: `submodules/TelegramUI/Components/ShimmeringMask/Sources/ShimmeringMaskView.swift`
- BUILD: `submodules/TelegramUI/Components/ShimmeringMask/BUILD`

Final deps:

```python
deps = [
    "//submodules/ComponentFlow",
    "//submodules/Components/HierarchyTrackingLayer",
],
```

The currently-listed `AsyncDisplayKit`, `Display`, and `ShimmerEffect` deps are removed — none of their types are used. (Re-add `//submodules/Display` if a Display utility is needed during implementation.)

## Public API

```swift
public final class ShimmeringMaskView: UIView {
    public let contentView: UIView

    public init(peakAlpha: CGFloat, duration: Double)

    public func update(
        size: CGSize,
        containerWidth: CGFloat,
        offsetX: CGFloat,
        gradientWidth: CGFloat,
        transition: ComponentTransition
    )
}
```

Init params (chosen once):
- `peakAlpha` — alpha at the center of the wave (e.g. `0.3`).
- `duration` — seconds per cycle.

Update params (per layout):
- `size` — `contentView.frame.size`.
- `containerWidth`, `offsetX` — coordinate space the wave traverses, allowing the wave to extend past `contentView`'s own bounds (matches the `VideoChatVideoLoadingEffectView` API). For an isolated use, pass `containerWidth = size.width, offsetX = 0`.
- `gradientWidth` — width of the dip in container coordinates.

## Internal architecture

```
ShimmeringMaskView (UIView)
├── contentView (UIView, public)
│   └── layer.mask = maskLayer
└── HierarchyTrackingLayer  (pause/resume on hierarchy entry)

maskLayer: CAGradientLayer
  startPoint = (0, 0.5),  endPoint = (1, 0.5)            // horizontal
  colors    = [white@1.0, white@peakAlpha, white@1.0]
  locations = positions placing a gradientWidth-wide dip
              centered in maskLayer.bounds
  bounds.width  = size.width + 2 × travelDistance
                  where travelDistance = containerWidth + gradientWidth
                  (guarantees alpha=1.0 edges always cover contentView)
  bounds.height = size.height
  anchorPoint   = (0.5, 0.5)
  static position.x = −gradientWidth/2 − offsetX
                  (dip parked just off-left of the container in contentView coords;
                   contentView's layer is the mask's reference coord system, so
                   position.x is in contentView coords directly)

  position.x animation (CABasicAnimation, additive, infinite):
    keyPath        = "position.x"
    from           = 0
    to             = containerWidth + gradientWidth
    duration       = duration
    timingFunction = .easeOut
    repeatCount    = .infinity
    isRemovedOnCompletion = true   (safety net; in practice never completes)
```

### Why a single oversized `CAGradientLayer`

- For an additive overlay (the shape of `AnimatedGradientView` inside `VideoChatVideoLoadingEffectView`), the unit-scale + container-scale + offset-scale hierarchy lets you keep animation params constant while changing `containerWidth/gradientWidth` via static transforms. For a *mask*, the layer must always cover `contentView.bounds` at every animation phase — which forces oversize anyway. So the hierarchy stops paying for itself; we'd carry three intermediate layers and still need to oversize.
- Trade-off: when `containerWidth` or `gradientWidth` change, the animation is re-armed with new `to` values. For the streaming-status use case, layout changes are rare (only when the bubble re-lays out), and the re-arm is cheap.

### Why animate `position.x` (not `locations`)

Per direction in the design discussion: `position.x` is GPU-accelerated as a layer translation, matches the proven pattern in `AnimatedGradientView` / `LoadingEffectView`, and produces stable jank-free motion. `additive: true` lets the layer's static `position.x` carry the per-layout offset (offsetX baked in) while the animation contributes the fixed `[0, containerWidth + gradientWidth]` translation delta.

## Lifecycle

- `HierarchyTrackingLayer` is added as a sublayer of `self.layer`. Its `didEnterHierarchy` callback calls `updateAnimations()`.
- `updateAnimations()`: if `maskLayer.animation(forKey: "shimmer") == nil`, build the `CABasicAnimation` and add it to `maskLayer`. This restarts the animation when re-entering the hierarchy.
- `update(...)`:
  1. Build `Params(size, containerWidth, offsetX, gradientWidth)`.
  2. If `params == self.params`, return.
  3. Otherwise store new params; apply layout via the supplied `transition` (frame of `contentView`, bounds + position of `maskLayer`).
  4. Re-arm the animation (remove existing key + add a new `CABasicAnimation` reflecting the updated `to` value).
- Re-arm is unconditional when params change. Visible jump is acceptable since layout changes for the streaming-status use case are rare.

## Integration: `ChatMessageTextBubbleContentNode`

Location: `submodules/TelegramUI/Components/Chat/ChatMessageTextBubbleContentNode/Sources/ChatMessageTextBubbleContentNode.swift` (currently around lines 90 and 961-1006).

1. Add a field alongside `streamingStatusTextNode`:
   ```swift
   private var streamingStatusShimmerView: ShimmeringMaskView?
   ```
2. In the `if let streamingTextFrame, let streamingTextLayoutAndApply { ... }` branch (~line 959):
   - Lazily create `ShimmeringMaskView(peakAlpha: 0.3, duration: 1.0)`; add to `containerNode.view`.
   - Move the streaming text node's view into the shimmer view's `contentView` (instead of adding it directly to `containerNode`).
   - Drive shimmer view position/size with `animation.animator` (currently used directly on `streamingStatusTextNode.textNode.layer`):
     - `animation.animator.updatePosition(layer: shimmerView.layer, position: streamingTextFrame.center, ...)`.
     - `animation.animator.updateBounds(layer: shimmerView.layer, bounds: CGRect(origin: .zero, size: streamingTextFrame.size), ...)`.
     - The textNode inside `contentView` is laid out at `(0, 0, streamingTextFrame.size)`.
   - Call `shimmerView.update(size: streamingTextFrame.size, containerWidth: streamingTextFrame.width, offsetX: 0, gradientWidth: 200, transition: ComponentTransition(animation))`.
3. In the "tear-down" branch (~line 1001) where `streamingStatusTextNode` is being dropped:
   - Animate alpha to 0 on the shimmer view (not the textNode), and remove on completion. The textNode is inside the shimmer view, so removing the shimmer view removes both.
4. The crossfade flow at lines 982-989 continues to work — the textNode's superview is now `shimmerView.contentView` instead of `containerNode`; `sourceView` still gets added to `textNodeContainer` (= `shimmerView.contentView`) and crossfaded in place.

### Constants used at the call site

| Constant       | Value | Notes |
|----------------|------:|-------|
| `peakAlpha`    | `0.3` | Wave dip floor — comfortable contrast against fully visible rest state. |
| `duration`     | `1.0` | Matches `LoadingEffectView` / `VideoChatVideoLoadingEffectView` cadence. |
| `gradientWidth`| `200` | Matches the gradient width used elsewhere in the family. |
| `containerWidth` | `streamingTextFrame.width` | Wave scoped to the streaming text strip; broadenable to bubble width if cross-element synchronization is later required. |
| `offsetX`      | `0`   | Streaming text strip is the container in this scoping. |

## Out of scope

- Synchronizing the wave across multiple separate views — the API supports it via `containerWidth + offsetX`, but no consumer needs it today.
- Border-shimmer companion (analogous to `LoadingEffectView.borderGradientView`) — not required for streaming-status text.
- Color tinting the wave — only alpha is modulated; `contentView` keeps its existing colors.

## Verification

- Build: `python3 build-system/Make/Make.py --overrideXcodeVersion --cacheDir ~/telegram-bazel-cache build --configurationPath build-system/appstore-configuration.json --gitCodesigningRepository git@gitlab.com:peter-iakovlev/fastlanematch.git --gitCodesigningType development --gitCodesigningUseCurrent --buildNumber=1 --configuration=debug_sim_arm64` (with `source ~/.zshrc 2>/dev/null;` prefix to pick up `TELEGRAM_CODESIGNING_GIT_PASSWORD`).
- Manual: open a chat with a streaming AI message and observe the shimmer effect on the streaming-status line. Confirm the wave runs continuously, the text remains fully readable except when the dip passes, and the effect tears down cleanly when the streaming status disappears.
