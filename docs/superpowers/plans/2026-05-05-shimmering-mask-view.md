# ShimmeringMaskView Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a reusable `ShimmeringMaskView` (alpha-mask "running shimmer" effect) and wire it as the host for `streamingStatusTextNode` in `ChatMessageTextBubbleContentNode` to give the streaming-status line a ChatGPT-style "thinking" effect.

**Architecture:** Single `CAGradientLayer` set as `contentView.layer.mask`. Horizontal three-stop gradient `[white@1.0, white@peakAlpha, white@1.0]` with the dip parked at the layer's bounds center; layer is oversized (`size.width + 2 × travelDistance`) so its `alpha=1.0` edges keep `contentView` covered at every animation phase. A `position.x` `CABasicAnimation` (`additive: true`, `repeatCount: .infinity`, `easeOut`) shifts the dip across the wave path. `HierarchyTrackingLayer` re-arms the animation when the view re-enters the hierarchy. API mirrors `VideoChatVideoLoadingEffectView` (init takes appearance constants; `update` takes layout values + a `ComponentTransition`).

**Tech Stack:** Swift, UIKit, `CAGradientLayer`, `CABasicAnimation`, `HierarchyTrackingLayer`, `ComponentFlow.ComponentTransition`, Bazel (`swift_library`).

**Reference reading (no edits needed):**
- Spec: `docs/superpowers/specs/2026-05-05-shimmering-mask-view-design.md`
- Pattern reference: `submodules/TelegramCallsUI/Sources/VideoChatVideoLoadingEffectView.swift`
- Pattern reference: `submodules/TelegramUI/Components/VideoMessageCameraScreen/Sources/LoadingEffectView.swift`
- Pattern reference: `submodules/TelegramUI/Components/TextLoadingEffect/Sources/TextLoadingEffect.swift`

**Important context — no unit tests in this project:**
This codebase has no unit-test harness (see `CLAUDE.md`: *"No tests are used at the moment"*). Verification is done by running the full Bazel build and visually inspecting the result. The "test" steps in this plan therefore replace per-task pytest-style verification with **build steps** that compile the affected modules, plus one explicit manual run-the-app step at the end.

**Build invocation used throughout this plan:**

```sh
source ~/.zshrc 2>/dev/null; \
python3 build-system/Make/Make.py --overrideXcodeVersion \
  --cacheDir ~/telegram-bazel-cache \
  build \
  --configurationPath build-system/appstore-configuration.json \
  --gitCodesigningRepository git@gitlab.com:peter-iakovlev/fastlanematch.git \
  --gitCodesigningType development --gitCodesigningUseCurrent --buildNumber=1 \
  --configuration=debug_sim_arm64
```

The `source ~/.zshrc 2>/dev/null;` prefix is required to pick up `TELEGRAM_CODESIGNING_GIT_PASSWORD`. Bazel is the only supported build path; there is no per-module build target — the full `Telegram/Telegram` app is built. First build of a fresh worktree may take 10+ minutes; incremental builds during this plan are typically 30s–2min.

---

## File Structure

| Action | Path | Responsibility |
|---|---|---|
| **Modify** | `submodules/TelegramUI/Components/ShimmeringMask/Sources/ShimmeringMaskView.swift` | Replace stub with full implementation. |
| **Modify** | `submodules/TelegramUI/Components/ShimmeringMask/BUILD` | Trim deps to `ComponentFlow` + `Components/HierarchyTrackingLayer`. |
| **Modify** | `submodules/TelegramUI/Components/Chat/ChatMessageTextBubbleContentNode/Sources/ChatMessageTextBubbleContentNode.swift` | Wrap `streamingStatusTextNode` in a `ShimmeringMaskView`; route position/bounds/alpha animation to the wrapper. |

The `ShimmeringMask` module is already wired as a dep on the `ChatMessageTextBubbleContentNode` library (we confirmed `submodules/TelegramUI/Components/Chat/ChatMessageTextBubbleContentNode/BUILD` has `"//submodules/TelegramUI/Components/ShimmeringMask"`), and the consumer file already has `import ShimmeringMask`. No BUILD edits are needed for the consumer side.

---

### Task 1: Trim BUILD deps for ShimmeringMask

**Files:**
- Modify: `submodules/TelegramUI/Components/ShimmeringMask/BUILD`

- [ ] **Step 1: Open the BUILD file**

Read `submodules/TelegramUI/Components/ShimmeringMask/BUILD` to confirm current contents.

- [ ] **Step 2: Replace deps with the trimmed list**

Replace the existing `deps` block in `submodules/TelegramUI/Components/ShimmeringMask/BUILD` so the file matches:

```python
load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "ShimmeringMask",
    module_name = "ShimmeringMask",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/ComponentFlow",
        "//submodules/Components/HierarchyTrackingLayer",
    ],
    visibility = [
        "//visibility:public",
    ],
)
```

The removed deps (`AsyncDisplayKit`, `Display`, `ShimmerEffect`) are not used by the new implementation. The added dep (`Components/HierarchyTrackingLayer`) is needed for the pause/resume-on-hierarchy pattern.

- [ ] **Step 3: Build to confirm BUILD parses**

The current stub `ShimmeringMaskView.swift` imports `Display`, `ShimmerEffect`, `AsyncDisplayKit`, and `ComponentFlow`. Trimming the BUILD deps without first updating the source would break the build. Skip building until Task 2's source replacement lands. (We'll build after Task 2.)

- [ ] **Step 4: Stage but don't commit yet**

```sh
git add submodules/TelegramUI/Components/ShimmeringMask/BUILD
```

The commit will happen at the end of Task 2 to keep the BUILD + source change atomic.

---

### Task 2: Replace ShimmeringMaskView stub with full implementation

**Files:**
- Modify: `submodules/TelegramUI/Components/ShimmeringMask/Sources/ShimmeringMaskView.swift`

- [ ] **Step 1: Verify the stub matches what we expect**

Read `submodules/TelegramUI/Components/ShimmeringMask/Sources/ShimmeringMaskView.swift`. Confirm it contains the stub (a `ShimmeringMaskView` class with `public let contentView: UIView`, `init(frame:)`, and an empty `update(size:transition:)`). If it has diverged, stop and ask for direction; otherwise proceed.

- [ ] **Step 2: Rewrite the file**

Replace the entire contents of `submodules/TelegramUI/Components/ShimmeringMask/Sources/ShimmeringMaskView.swift` with:

```swift
import Foundation
import UIKit
import ComponentFlow
import HierarchyTrackingLayer

public final class ShimmeringMaskView: UIView {
    private struct Params: Equatable {
        var size: CGSize
        var containerWidth: CGFloat
        var offsetX: CGFloat
        var gradientWidth: CGFloat
    }

    public let contentView: UIView

    private let peakAlpha: CGFloat
    private let duration: Double

    private let hierarchyTrackingLayer: HierarchyTrackingLayer
    private let maskLayer: CAGradientLayer

    private var params: Params?

    public init(peakAlpha: CGFloat, duration: Double) {
        self.peakAlpha = peakAlpha
        self.duration = duration

        self.contentView = UIView()

        self.hierarchyTrackingLayer = HierarchyTrackingLayer()

        self.maskLayer = CAGradientLayer()
        self.maskLayer.startPoint = CGPoint(x: 0.0, y: 0.5)
        self.maskLayer.endPoint = CGPoint(x: 1.0, y: 0.5)
        self.maskLayer.colors = [
            UIColor(white: 1.0, alpha: 1.0).cgColor,
            UIColor(white: 1.0, alpha: peakAlpha).cgColor,
            UIColor(white: 1.0, alpha: 1.0).cgColor
        ]
        self.maskLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)

        super.init(frame: CGRect())

        self.addSubview(self.contentView)
        self.contentView.layer.mask = self.maskLayer

        self.layer.addSublayer(self.hierarchyTrackingLayer)
        self.hierarchyTrackingLayer.didEnterHierarchy = { [weak self] in
            guard let self else {
                return
            }
            self.updateAnimations()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func updateAnimations() {
        guard let params = self.params else {
            return
        }
        if self.maskLayer.animation(forKey: "shimmer") != nil {
            return
        }
        let travelDelta = params.containerWidth + params.gradientWidth
        let animation = self.maskLayer.makeAnimation(
            from: 0.0 as NSNumber,
            to: travelDelta as NSNumber,
            keyPath: "position.x",
            timingFunction: CAMediaTimingFunctionName.easeOut.rawValue,
            duration: self.duration,
            delay: 0.0,
            mediaTimingFunction: nil,
            removeOnCompletion: true,
            additive: true
        )
        animation.repeatCount = Float.infinity
        self.maskLayer.add(animation, forKey: "shimmer")
    }

    public func update(
        size: CGSize,
        containerWidth: CGFloat,
        offsetX: CGFloat,
        gradientWidth: CGFloat,
        transition: ComponentTransition
    ) {
        let params = Params(
            size: size,
            containerWidth: containerWidth,
            offsetX: offsetX,
            gradientWidth: gradientWidth
        )
        if self.params == params {
            return
        }
        self.params = params

        transition.setFrame(view: self.contentView, frame: CGRect(origin: CGPoint(), size: size))

        let travelDistance = containerWidth + gradientWidth
        let maskWidth = size.width + 2.0 * travelDistance

        let dipHalfFraction: CGFloat
        if maskWidth > 0.0 {
            dipHalfFraction = (gradientWidth * 0.5) / maskWidth
        } else {
            dipHalfFraction = 0.0
        }
        self.maskLayer.locations = [
            (0.5 - dipHalfFraction) as NSNumber,
            0.5 as NSNumber,
            (0.5 + dipHalfFraction) as NSNumber
        ]

        let maskBounds = CGRect(origin: CGPoint(), size: CGSize(width: maskWidth, height: size.height))
        let staticPositionX = -gradientWidth * 0.5 - offsetX
        let maskPosition = CGPoint(x: staticPositionX, y: size.height * 0.5)

        transition.setBounds(layer: self.maskLayer, bounds: maskBounds)
        transition.setPosition(layer: self.maskLayer, position: maskPosition)

        self.maskLayer.removeAnimation(forKey: "shimmer")
        self.updateAnimations()
    }
}
```

Notes on the code (do not alter):
- `super.init(frame: CGRect())` is intentional — callers always size via `update(...)`; init takes appearance constants only.
- `maskLayer.anchorPoint = (0.5, 0.5)` and the mask is parented in `contentView.layer`'s coord system (because `contentView.layer.mask = maskLayer`). So `maskLayer.position.x = -gradientWidth/2 - offsetX` puts the dip just off-left of the container in `contentView` coords.
- `dipHalfFraction` is `(gradientWidth/2) / maskWidth` because `CAGradientLayer.locations` are normalized to the *layer's* bounds. With locations `[0.5 − Δ, 0.5, 0.5 + Δ]` the dip occupies `gradientWidth` pixels centered in `maskWidth`.
- The `if maskWidth > 0.0` guard avoids divide-by-zero on a zero-sized first call.
- Animation re-arm is unconditional whenever params change (intentionally — tradeoff documented in the spec).
- `makeAnimation(...)` is a `CALayer` extension provided by `Display`/`ComponentFlow` (it's used identically in the reference files). It *is* available without importing `Display` because the helper is on `ComponentFlow`'s import surface that we already pull in. If the build complains that `makeAnimation` is unresolved, add `import Display` and `"//submodules/Display"` to the BUILD deps — but check first.

- [ ] **Step 3: Verify the `makeAnimation` symbol resolves**

Before a full build, run a quick grep to be sure of the source of `makeAnimation`:

```sh
grep -rn "func makeAnimation" submodules/Display/ submodules/ComponentFlow/ submodules/Components/HierarchyTrackingLayer/ 2>/dev/null
```

Expected: at least one hit. If the only hit is in `submodules/Display/`, then `import Display` and the `Display` BUILD dep ARE required. Update Task 2's source file (add `import Display` after `import UIKit`) and Task 1's BUILD (add `"//submodules/Display",` to deps) before building. If hits exist in `ComponentFlow` or `HierarchyTrackingLayer` we're fine without `Display`.

- [ ] **Step 4: Build the affected target**

Run the full Bazel build (see "Build invocation" above). Bazel will compile the `ShimmeringMask` library as part of building `Telegram/Telegram`.

Expected: build succeeds. Watch for `-warnings-as-errors` failures in `ShimmeringMaskView.swift` (e.g. unused-let, always-false casts) — fix them inline before re-running.

- [ ] **Step 5: Commit Task 1 + Task 2 together**

```sh
git add submodules/TelegramUI/Components/ShimmeringMask/BUILD \
        submodules/TelegramUI/Components/ShimmeringMask/Sources/ShimmeringMaskView.swift
git commit -m "$(cat <<'EOF'
ShimmeringMask: implement ShimmeringMaskView reveal-mask shimmer

CAGradientLayer mask with horizontal [white@1.0, white@peakAlpha,
white@1.0] gradient; oversized so alpha=1.0 edges always cover
contentView. Animates position.x (additive, infinite, easeOut) so the
dip travels across containerWidth. HierarchyTrackingLayer pauses /
resumes the animation on hierarchy entry. API mirrors
VideoChatVideoLoadingEffectView.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Wrap streamingStatusTextNode in ShimmeringMaskView

**Files:**
- Modify: `submodules/TelegramUI/Components/Chat/ChatMessageTextBubbleContentNode/Sources/ChatMessageTextBubbleContentNode.swift`

This task touches three regions of the file. The line numbers below are accurate as of the time the spec was written; if the file has shifted by a handful of lines, locate by surrounding text (the code excerpts shown are the unique anchors).

- [ ] **Step 1: Add a sibling field for the shimmer view**

Find the existing field declaration:

```swift
    private var streamingStatusTextNode: InteractiveTextNodeWithEntities?
```

(approximately line 90). Insert a new line directly after it:

```swift
    private var streamingStatusTextNode: InteractiveTextNodeWithEntities?
    private var streamingStatusShimmerView: ShimmeringMaskView?
```

- [ ] **Step 2: Wrap the streaming-text branch — locate**

Find this block (approximately lines 959-1000):

```swift
                            if let streamingTextFrame, let streamingTextLayoutAndApply {
                                var animation = animation
                                if strongSelf.streamingStatusTextNode == nil {
                                    animation = .None
                                }
                                let streamingStatusTextNode = streamingTextLayoutAndApply.apply(InteractiveTextNodeWithEntities.Arguments(
                                    context: item.context,
                                    cache: item.controllerInteraction.presentationContext.animationCache,
                                    renderer: item.controllerInteraction.presentationContext.animationRenderer,
                                    placeholderColor: messageTheme.mediaPlaceholderColor,
                                    attemptSynchronous: synchronousLoads,
                                    textColor: messageTheme.primaryTextColor,
                                    spoilerEffectColor: messageTheme.secondaryTextColor,
                                    applyArguments: InteractiveTextNode.ApplyArguments(
                                        animation: animation,
                                        spoilerTextColor: messageTheme.primaryTextColor,
                                        spoilerEffectColor: messageTheme.secondaryTextColor,
                                        areContentAnimationsEnabled: item.context.sharedContext.energyUsageSettings.loopEmoji,
                                        spoilerExpandRect: nil,
                                        crossfadeContents: { [weak strongSelf] sourceView in
                                            guard let strongSelf, let streamingStatusTextNode = strongSelf.streamingStatusTextNode else {
                                                return
                                            }
                                            if let textNodeContainer = streamingStatusTextNode.textNode.view.superview {
                                                sourceView.frame = CGRect(origin: streamingStatusTextNode.textNode.frame.origin, size: sourceView.bounds.size)
                                                textNodeContainer.addSubview(sourceView)
                                                
                                                sourceView.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.12, removeOnCompletion: false, completion: { [weak sourceView] _ in
                                                    sourceView?.removeFromSuperview()
                                                })
                                                streamingStatusTextNode.textNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.1)
                                            }
                                        }
                                    )
                                ))
                                if streamingStatusTextNode !== strongSelf.streamingStatusTextNode {
                                    strongSelf.streamingStatusTextNode?.textNode.removeFromSupernode()
                                    strongSelf.streamingStatusTextNode = streamingStatusTextNode
                                    strongSelf.containerNode.addSubnode(streamingStatusTextNode.textNode)
                                }
                                animation.animator.updatePosition(layer: streamingStatusTextNode.textNode.layer, position: streamingTextFrame.center, completion: nil)
                                animation.animator.updateBounds(layer: streamingStatusTextNode.textNode.layer, bounds: CGRect(origin: CGPoint(), size: streamingTextFrame.size), completion: nil)
                            } else if let streamingStatusTextNode = strongSelf.streamingStatusTextNode {
                                strongSelf.streamingStatusTextNode = nil
                                let streamingStatusTextNodeNode = streamingStatusTextNode.textNode
                                animation.animator.updateAlpha(layer: streamingStatusTextNodeNode.layer, alpha: 0.0, completion: { [weak streamingStatusTextNodeNode] _ in
                                    streamingStatusTextNodeNode?.removeFromSupernode()
                                })
                            }
```

This is the region we will replace.

- [ ] **Step 3: Wrap the streaming-text branch — replace**

Replace the entire block from Step 2 with:

```swift
                            if let streamingTextFrame, let streamingTextLayoutAndApply {
                                var animation = animation
                                if strongSelf.streamingStatusTextNode == nil {
                                    animation = .None
                                }
                                let streamingStatusTextNode = streamingTextLayoutAndApply.apply(InteractiveTextNodeWithEntities.Arguments(
                                    context: item.context,
                                    cache: item.controllerInteraction.presentationContext.animationCache,
                                    renderer: item.controllerInteraction.presentationContext.animationRenderer,
                                    placeholderColor: messageTheme.mediaPlaceholderColor,
                                    attemptSynchronous: synchronousLoads,
                                    textColor: messageTheme.primaryTextColor,
                                    spoilerEffectColor: messageTheme.secondaryTextColor,
                                    applyArguments: InteractiveTextNode.ApplyArguments(
                                        animation: animation,
                                        spoilerTextColor: messageTheme.primaryTextColor,
                                        spoilerEffectColor: messageTheme.secondaryTextColor,
                                        areContentAnimationsEnabled: item.context.sharedContext.energyUsageSettings.loopEmoji,
                                        spoilerExpandRect: nil,
                                        crossfadeContents: { [weak strongSelf] sourceView in
                                            guard let strongSelf, let streamingStatusTextNode = strongSelf.streamingStatusTextNode else {
                                                return
                                            }
                                            if let textNodeContainer = streamingStatusTextNode.textNode.view.superview {
                                                sourceView.frame = CGRect(origin: streamingStatusTextNode.textNode.frame.origin, size: sourceView.bounds.size)
                                                textNodeContainer.addSubview(sourceView)
                                                
                                                sourceView.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.12, removeOnCompletion: false, completion: { [weak sourceView] _ in
                                                    sourceView?.removeFromSuperview()
                                                })
                                                streamingStatusTextNode.textNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.1)
                                            }
                                        }
                                    )
                                ))

                                let streamingStatusShimmerView: ShimmeringMaskView
                                if let current = strongSelf.streamingStatusShimmerView {
                                    streamingStatusShimmerView = current
                                } else {
                                    streamingStatusShimmerView = ShimmeringMaskView(peakAlpha: 0.3, duration: 1.0)
                                    strongSelf.streamingStatusShimmerView = streamingStatusShimmerView
                                    strongSelf.containerNode.view.addSubview(streamingStatusShimmerView)
                                }

                                if streamingStatusTextNode !== strongSelf.streamingStatusTextNode {
                                    strongSelf.streamingStatusTextNode?.textNode.view.removeFromSuperview()
                                    strongSelf.streamingStatusTextNode = streamingStatusTextNode
                                    streamingStatusShimmerView.contentView.addSubview(streamingStatusTextNode.textNode.view)
                                }
                                animation.animator.updatePosition(layer: streamingStatusShimmerView.layer, position: streamingTextFrame.center, completion: nil)
                                animation.animator.updateBounds(layer: streamingStatusShimmerView.layer, bounds: CGRect(origin: CGPoint(), size: streamingTextFrame.size), completion: nil)
                                animation.animator.updatePosition(layer: streamingStatusTextNode.textNode.layer, position: CGPoint(x: streamingTextFrame.size.width * 0.5, y: streamingTextFrame.size.height * 0.5), completion: nil)
                                animation.animator.updateBounds(layer: streamingStatusTextNode.textNode.layer, bounds: CGRect(origin: CGPoint(), size: streamingTextFrame.size), completion: nil)
                                streamingStatusShimmerView.update(
                                    size: streamingTextFrame.size,
                                    containerWidth: streamingTextFrame.size.width,
                                    offsetX: 0.0,
                                    gradientWidth: 200.0,
                                    transition: ComponentTransition(animation.transition)
                                )
                            } else if let streamingStatusTextNode = strongSelf.streamingStatusTextNode {
                                strongSelf.streamingStatusTextNode = nil
                                let streamingStatusShimmerView = strongSelf.streamingStatusShimmerView
                                strongSelf.streamingStatusShimmerView = nil
                                let streamingStatusTextNodeNode = streamingStatusTextNode.textNode
                                if let streamingStatusShimmerView {
                                    animation.animator.updateAlpha(layer: streamingStatusShimmerView.layer, alpha: 0.0, completion: { [weak streamingStatusShimmerView] _ in
                                        streamingStatusShimmerView?.removeFromSuperview()
                                    })
                                } else {
                                    animation.animator.updateAlpha(layer: streamingStatusTextNodeNode.layer, alpha: 0.0, completion: { [weak streamingStatusTextNodeNode] _ in
                                        streamingStatusTextNodeNode?.removeFromSupernode()
                                    })
                                }
                            }
```

What changed:
- Lazy-create `ShimmeringMaskView(peakAlpha: 0.3, duration: 1.0)` and add it to `containerNode.view`.
- When the streaming text node is created/replaced, add `streamingStatusTextNode.textNode.view` to `streamingStatusShimmerView.contentView` (UIView hierarchy) **instead of** `containerNode.addSubnode(streamingStatusTextNode.textNode)`. Mixing `view`/`Subview` and `Subnode`/`Supernode` is fine here: ASDisplayNode's `view` is a real UIView, and adding it via `addSubview` from another UIView reparents it.
- Animate the **shimmer view's** layer to `streamingTextFrame.center`/size — this is the position where the streaming-text strip lives in the bubble's container.
- Animate the inner textNode's layer to the shimmer view's local bounds (`origin = .zero`, same size). Without this, after we reparent the textNode under contentView, the textNode keeps its old `containerNode`-relative frame and ends up offset by `streamingTextFrame.origin`. We're explicitly placing it at `(0, 0, streamingTextFrame.size)` inside `contentView`.
- Call `streamingStatusShimmerView.update(...)` with `containerWidth = streamingTextFrame.size.width` and `offsetX = 0.0` (wave scoped to the streaming-text strip itself; broadenable later).
- The teardown branch animates alpha on the shimmer view (with the textNode inside it). When the shimmer view exists, we use it as the alpha-animation target and do `removeFromSuperview` in the completion; the textNode rides along because it's a subview of `contentView`. We keep a fallback `else` branch animating the textNode directly in case some path produces a streamingStatusTextNode without a shimmer view (defensive — should be unreachable today, but it's a one-line cost and matches the previous behavior exactly).
- The replacement step uses `view.removeFromSuperview()` (not `removeFromSupernode()`) because the inner textNode is now hosted inside `streamingStatusShimmerView.contentView` (a plain UIView) via `addSubview`. ASDisplayKit's `addSubview`/`removeFromSupernode` paths don't sync; using the UIView pair ensures replacements actually unhook the previous textNode's view from the shimmer view.

Notes on the `transition: ComponentTransition(animation.transition)` — the existing call sites in this file use `animation.animator.update*` (where `animator` is a `Display`-flavored animator) but our `ShimmeringMaskView.update` takes a `ComponentFlow.ComponentTransition`. The `animation` value flowing through is a `ListViewItemUpdateAnimation`; it exposes `.transition` as a `ContainedViewLayoutTransition`. `ComponentTransition` has a public initializer accepting `ContainedViewLayoutTransition`. **Verify this initializer exists** before building (see Step 4); if not, fall back to `ComponentTransition.immediate` (the only consequence is that the mask layer's bounds/position aren't animated to their new values, which is rare and benign).

- [ ] **Step 4: Verify the ComponentTransition initializer exists**

```sh
grep -rn "init.*ContainedViewLayoutTransition" submodules/ComponentFlow/Source/ 2>/dev/null
grep -rn "extension ComponentTransition" submodules/ComponentFlow/Source/ 2>/dev/null
```

Expected: at least one hit indicating an initializer or static helper that converts a `ContainedViewLayoutTransition` to a `ComponentTransition`. If you find one named differently (e.g. `ComponentTransition(transition:)` or `ComponentTransition.init(legacyAnimation:)`), use that exact name in the call from Step 3.

If neither exists, replace the `transition:` argument in Step 3's call with `.immediate`:

```swift
                                streamingStatusShimmerView.update(
                                    size: streamingTextFrame.size,
                                    containerWidth: streamingTextFrame.size.width,
                                    offsetX: 0.0,
                                    gradientWidth: 200.0,
                                    transition: .immediate
                                )
```

- [ ] **Step 5: Build**

Run the full Bazel build (see "Build invocation" above). Expected: build succeeds.

If you get `-warnings-as-errors` failures specifically about an unused `streamingStatusShimmerView` variable in the teardown branch, that means a compiler-flagged path: re-check the diff against the Step 3 source.

- [ ] **Step 6: Commit**

```sh
git add submodules/TelegramUI/Components/Chat/ChatMessageTextBubbleContentNode/Sources/ChatMessageTextBubbleContentNode.swift
git commit -m "$(cat <<'EOF'
ChatMessageTextBubbleContentNode: wrap streaming-status text in ShimmeringMaskView

Hosts streamingStatusTextNode inside a ShimmeringMaskView so the
streaming line gets a "thinking"-style running shimmer (alpha-mask wave
with peakAlpha=0.3, duration=1.0, gradientWidth=200). Layout/teardown
animations target the shimmer view's layer; the text node lives inside
contentView at the wrapper's local bounds.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Manual verification

**Files:** none (build + run only)

- [ ] **Step 1: Confirm clean build state**

```sh
git status --short
```

Expected: empty (or only the unrelated `m`/`M` entries that were present before this work began — see `gitStatus` in the conversation context).

- [ ] **Step 2: Build for the simulator**

Run the full Bazel build (see "Build invocation" above). Expected: build succeeds with no warnings-as-errors.

- [ ] **Step 3: Manual run**

Launch the built app in the simulator. Open a chat with an in-progress AI streaming message (or trigger a streaming-status placeholder if one exists in the test environment). Confirm:

- The streaming-status line shows a smooth horizontal wave that runs continuously while streaming.
- Outside the wave, the text is fully readable (alpha=1.0).
- At the wave's center, the text dims to ~30% (the `peakAlpha = 0.3` value).
- When the streaming status disappears (message finishes streaming), the shimmer view fades out cleanly with the text inside it.
- Scrolling the streaming message off-screen pauses the animation; scrolling it back on resumes (`HierarchyTrackingLayer` doing its job).

If the wave is too fast / too slow / too subtle, adjust the constants `peakAlpha`, `duration`, `gradientWidth` at the call site in `ChatMessageTextBubbleContentNode.swift` (Task 3, Step 3, where `ShimmeringMaskView(peakAlpha: 0.3, duration: 1.0)` and `gradientWidth: 200.0` appear) and rebuild. Don't commit tuning changes as part of this plan — leave them for a follow-up.

- [ ] **Step 4: No commit (verification only)**

This task produces no code changes.

---

## Notes for the implementer

- **`-warnings-as-errors`** is enabled on both modules. Common gotchas: unused locals, always-false `is` checks, always-failing `as?` casts. If a build fails with these, fix them inline rather than adding `// swiftlint:disable` or `_ = unused`.
- **No unit tests, no UI snapshot tests** in this project. The full Bazel build is the only automated gate. Be diligent about the manual verification step.
- **Bazel cache:** the plan assumes `~/telegram-bazel-cache` is reusable across builds. If you're working in a fresh worktree (no shared cache), the first build will take meaningfully longer.
- **`HierarchyTrackingLayer` BUILD path** is `//submodules/Components/HierarchyTrackingLayer` (note the `Components/` prefix — there's no top-level `submodules/HierarchyTrackingLayer/`).
- If `streamingTextLayoutAndApply` ends up being non-nil in fast succession (streaming status flickers), the same `ShimmeringMaskView` instance is reused — `update(...)`'s `params != self.params` short-circuit avoids re-arming the animation when nothing changed.
- The wave's containerWidth is currently scoped to the streaming-text strip itself, not the bubble. If a future change wants the wave to traverse the full bubble width (or sync across multiple bubbles), pass a larger `containerWidth` and a non-zero `offsetX` (the streaming-text strip's `minX` within the chosen container) to `update(...)`.
