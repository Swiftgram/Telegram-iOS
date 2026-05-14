# Context Controller Portal-View Transition Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `ContextControllerExtractedPresentationNode`'s manual visible-area clipping animation with a portal-based transition so the chat's natural ancestor clipping (and live re-layout) drives the bubble's in/out edges, fixing two issues: shadow/rounded-corner cutoff at chat-content-area edges, and stale clipping when chat re-layouts mid-animation.

**Architecture:** Optional `sourceTransitionSurface: UIView?` on `ContextControllerTakeViewInfo` / `ContextControllerPutBackViewInfo`. When non-nil, CCEPN parks the source's `contentNode` inside that surface (via a `PortalSourceView` wrapper) for the duration of the in/out animation, mirrors it through a `PortalView(matchPosition: true)` clone in `ItemContentNode.offsetContainerNode`, and retargets the existing spring/position deltas onto the wrapper's layer instead of the overlay-side layer. The manual `clippingNode.layer.animateFrame(...)` calls are bypassed on this path. Resting state is unchanged from today (contentNode lives in `offsetContainerNode` while the menu is up). When the surface is nil, today's clipping path is preserved verbatim. First adopter: chat message bubbles (regular long-press + reaction context).

**Tech Stack:** Swift, AsyncDisplayKit, UIKit. `PortalSourceView` / `PortalView` from `submodules/Display/Source/`. Build via Bazel (`Make.py` wrapper).

**Reference spec:** `docs/superpowers/specs/2026-05-05-context-controller-portal-view-design.md`.

**Build verification command** (used at the end of each task):

```sh
source ~/.zshrc 2>/dev/null; python3 build-system/Make/Make.py --overrideXcodeVersion \
  --cacheDir ~/telegram-bazel-cache build \
  --configurationPath build-system/appstore-configuration.json \
  --gitCodesigningRepository git@gitlab.com:peter-iakovlev/fastlanematch.git \
  --gitCodesigningType development --gitCodesigningUseCurrent \
  --buildNumber=1 --configuration=debug_sim_arm64 --continueOnError
```

Expected: build succeeds (no compile errors). The project has no unit tests; verification is the build plus manual checks in Task 8.

---

## Task 1: Add `sourceTransitionSurface` field to `ContextUI` structs

**Files:**
- Modify: `submodules/ContextUI/Sources/ContextController.swift:347-372`

The change is purely additive. Default values are `nil`, so every existing producer of `ContextControllerTakeViewInfo` / `ContextControllerPutBackViewInfo` keeps compiling unchanged and falls back to today's clipping path.

- [ ] **Step 1: Replace the two struct definitions**

Open `submodules/ContextUI/Sources/ContextController.swift`. Find lines 347–372 (the existing `ContextControllerTakeViewInfo` and `ContextControllerPutBackViewInfo` declarations). Replace exactly:

Find:
```swift
public final class ContextControllerTakeViewInfo {
    public enum ContainingItem {
        case node(ContextExtractedContentContainingNode)
        case view(ContextExtractedContentContainingView)
    }
    
    public let containingItem: ContainingItem
    public let contentAreaInScreenSpace: CGRect
    public let maskView: UIView?
    
    public init(containingItem: ContainingItem, contentAreaInScreenSpace: CGRect, maskView: UIView? = nil) {
        self.containingItem = containingItem
        self.contentAreaInScreenSpace = contentAreaInScreenSpace
        self.maskView = maskView
    }
}

public final class ContextControllerPutBackViewInfo {
    public let contentAreaInScreenSpace: CGRect
    public let maskView: UIView?
    
    public init(contentAreaInScreenSpace: CGRect, maskView: UIView? = nil) {
        self.contentAreaInScreenSpace = contentAreaInScreenSpace
        self.maskView = maskView
    }
}
```

Replace with:
```swift
public final class ContextControllerTakeViewInfo {
    public enum ContainingItem {
        case node(ContextExtractedContentContainingNode)
        case view(ContextExtractedContentContainingView)
    }
    
    public let containingItem: ContainingItem
    public let contentAreaInScreenSpace: CGRect
    public let maskView: UIView?
    public let sourceTransitionSurface: UIView?
    
    public init(containingItem: ContainingItem, contentAreaInScreenSpace: CGRect, maskView: UIView? = nil, sourceTransitionSurface: UIView? = nil) {
        self.containingItem = containingItem
        self.contentAreaInScreenSpace = contentAreaInScreenSpace
        self.maskView = maskView
        self.sourceTransitionSurface = sourceTransitionSurface
    }
}

public final class ContextControllerPutBackViewInfo {
    public let contentAreaInScreenSpace: CGRect
    public let maskView: UIView?
    public let sourceTransitionSurface: UIView?
    
    public init(contentAreaInScreenSpace: CGRect, maskView: UIView? = nil, sourceTransitionSurface: UIView? = nil) {
        self.contentAreaInScreenSpace = contentAreaInScreenSpace
        self.maskView = maskView
        self.sourceTransitionSurface = sourceTransitionSurface
    }
}
```

- [ ] **Step 2: Build to confirm no caller broke**

Run the full build verification command from the plan header. Expected: succeeds (existing init calls keep working because the new parameter is defaulted).

- [ ] **Step 3: Commit**

```bash
git add submodules/ContextUI/Sources/ContextController.swift
git commit -m "$(cat <<'EOF'
ContextUI: add sourceTransitionSurface to TakeViewInfo / PutBackInfo

Optional UIView field provided by extracted-content sources to opt
into the upcoming portal-based transition path in CCEPN. Defaults to
nil, so existing callers are unchanged.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Add `PortalTransitionStaging` helper + `portalStaging` field on `ItemContentNode`

**Files:**
- Modify: `submodules/TelegramUI/Components/ContextControllerImpl/Sources/ContextControllerExtractedPresentationNode.swift` (top of file, near other private types; and inside `ItemContentNode`)

The class is unused at this point — Task 3 / Task 4 wire it in. Splitting this out is intentional: a buildable commit that adds the new abstraction with no behavior change makes review easier.

- [ ] **Step 1: Insert the helper class definition**

Open `submodules/TelegramUI/Components/ContextControllerImpl/Sources/ContextControllerExtractedPresentationNode.swift`. Imports already include `Display`, `AsyncDisplayKit`, and `UIKit` (line 1–14), which are sufficient for `PortalSourceView` / `PortalView`.

After the closing `}` of the `private extension ContextControllerTakeViewInfo.ContainingItem { ... }` block (it ends at line 124, just before the start of `final class ContextControllerExtractedPresentationNode` at line 126), insert this new file-local helper:

```swift
private final class PortalTransitionStaging {
    enum SettleDestination {
        case offsetContainer(ASDisplayNode)
        case original
    }
    
    enum OriginalParent {
        case node(ASDisplayNode)
        case view(UIView)
    }
    
    weak var surface: UIView?
    var wrapper: PortalSourceView?
    var clone: PortalView?
    var originalParent: OriginalParent?
    var containingItem: ContextControllerTakeViewInfo.ContainingItem?
    
    /// Reparents the source's contentNode/contentView into a freshly-created
    /// `PortalSourceView` inside `surface`, attaches a `PortalView(matchPosition: true)`
    /// clone to `overlayHost`, sizes the wrapper so contentNode appears at
    /// `targetScreenRect` in window coords, and returns the wrapper's layer.
    ///
    /// Returns nil if `PortalView(matchPosition:)` cannot be instantiated. In that
    /// case staging is left empty and the caller takes the clipping fallback path.
    func enter(
        for containingItem: ContextControllerTakeViewInfo.ContainingItem,
        in surface: UIView,
        overlayHost: UIView,
        targetScreenRect: CGRect
    ) -> CALayer? {
        guard let clone = PortalView(matchPosition: true) else {
            return nil
        }
        
        let wrapper = PortalSourceView()
        
        let originalParent: OriginalParent
        switch containingItem {
        case let .node(containingNode):
            if let supernode = containingNode.contentNode.supernode {
                originalParent = .node(supernode)
            } else {
                originalParent = .node(containingNode)
            }
        case let .view(containingView):
            if let superview = containingView.contentView.superview {
                originalParent = .view(superview)
            } else {
                originalParent = .view(containingView)
            }
        }
        
        // Place wrapper so that the bubble (= containingItem.contentRect, in
        // containingItem.view coords) lands at `targetScreenRect` on screen.
        //
        // After reparenting contentNode/contentView into wrapper (preserving its
        // frame value), the bubble's rect in wrapper-local coords numerically
        // equals containingItem.contentRect (since the bubble was at
        // contentNode.frame.origin + bubbleOffsetInContentNode == contentRect.origin
        // in the original parent). So:
        //     bubble.screen.origin = wrapper.screen.origin + contentRect.origin
        // and we want bubble.screen.origin == targetScreenRect.origin, hence:
        //     wrapper.screen.origin = targetScreenRect.origin - contentRect.origin
        let bubbleOffsetInContainer = containingItem.contentRect.origin
        let wrapperOriginInWindow = CGPoint(
            x: targetScreenRect.origin.x - bubbleOffsetInContainer.x,
            y: targetScreenRect.origin.y - bubbleOffsetInContainer.y
        )
        let wrapperFrameInWindow = CGRect(origin: wrapperOriginInWindow, size: containingItem.view.bounds.size)
        wrapper.frame = surface.convert(wrapperFrameInWindow, from: nil)
        surface.addSubview(wrapper)
        
        switch containingItem {
        case let .node(containingNode):
            wrapper.addSubview(containingNode.contentNode.view)
        case let .view(containingView):
            wrapper.addSubview(containingView.contentView)
        }
        
        wrapper.addPortal(view: clone)
        overlayHost.addSubview(clone.view)
        
        self.surface = surface
        self.wrapper = wrapper
        self.clone = clone
        self.originalParent = originalParent
        self.containingItem = containingItem
        
        return wrapper.layer
    }
    
    /// Tears down staging. Reparents contentNode into the requested destination,
    /// removes clone from its overlay host, removes wrapper from surface.
    /// All operations are explicit; we rely on Telegram's manual-animation policy
    /// (no implicit CALayer actions) — no CATransaction wrapping needed.
    func settle(into destination: SettleDestination) {
        guard let wrapper = self.wrapper, let containingItem = self.containingItem else {
            return
        }
        
        switch destination {
        case let .offsetContainer(offsetContainerNode):
            switch containingItem {
            case let .node(containingNode):
                offsetContainerNode.addSubnode(containingNode.contentNode)
            case let .view(containingView):
                offsetContainerNode.view.addSubview(containingView.contentView)
            }
        case .original:
            switch (containingItem, self.originalParent) {
            case let (.node(containingNode), .some(.node(parent))):
                parent.addSubnode(containingNode.contentNode)
            case let (.view(containingView), .some(.view(parent))):
                parent.addSubview(containingView.contentView)
            case let (.node(containingNode), _):
                // Surface lost; restore to the source's containing node as a fallback.
                containingNode.addSubnode(containingNode.contentNode)
            case let (.view(containingView), _):
                containingView.addSubview(containingView.contentView)
            }
        }
        
        if let clone = self.clone {
            wrapper.removePortal(view: clone)
            clone.view.removeFromSuperview()
        }
        wrapper.removeFromSuperview()
        
        self.surface = nil
        self.wrapper = nil
        self.clone = nil
        self.originalParent = nil
        self.containingItem = nil
    }
}
```

- [ ] **Step 2: Add `portalStaging` field on `ItemContentNode`**

Find the `ItemContentNode` class declaration starting at line 134. The existing fields are:

```swift
private final class ItemContentNode: ASDisplayNode {
    let offsetContainerNode: ASDisplayNode
    var containingItem: ContextControllerTakeViewInfo.ContainingItem

    var animateClippingFromContentAreaInScreenSpace: CGRect?
    var storedGlobalFrame: CGRect?
    var storedGlobalBoundsFrame: CGRect?
    var presentationScale: CGFloat = 1.0
```

Insert after the `presentationScale` line:

```swift
    var portalStaging: PortalTransitionStaging?
```

- [ ] **Step 3: Build to confirm helper compiles**

Run the build verification command from the plan header. Expected: succeeds. The new class and field are unreferenced; the build only validates syntax/types.

- [ ] **Step 4: Commit**

```bash
git add submodules/TelegramUI/Components/ContextControllerImpl/Sources/ContextControllerExtractedPresentationNode.swift
git commit -m "$(cat <<'EOF'
CCEPN: add PortalTransitionStaging helper

File-local class that owns the transient PortalSourceView wrapper
+ PortalView clone lifecycle for the upcoming portal-based transition
path. Adds an unused portalStaging field on ItemContentNode. Wired
up in subsequent commits.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Wire portal path into `case .animateIn:`

**Files:**
- Modify: `submodules/TelegramUI/Components/ContextControllerImpl/Sources/ContextControllerExtractedPresentationNode.swift:1265-1474` (the `.animateIn` arm of the `stateTransition` switch).

The portal path is opt-in: only fires when `takeInfo.sourceTransitionSurface != nil` AND `presentationScale == 1.0` AND `staging.enter(...)` succeeds. Otherwise the today's-clipping path runs unchanged.

CCEPN's `update(state:transition:)` does not have direct access to the takeInfo at `case .animateIn` time — `takeInfo` is consumed earlier at the `case let .extracted(source):` block (line ~631) where `ItemContentNode` is constructed. We thread `sourceTransitionSurface` through the `ItemContentNode` so `.animateIn` can see it.

- [ ] **Step 1: Stash `sourceTransitionSurface` on `ItemContentNode` at construction time**

Find the construction site at line 631–656 (`case let .extracted(source):` block). Inside the `if-let` for `takeInfo` (around line 632–655), after the existing line `contentNodeValue.animateClippingFromContentAreaInScreenSpace = takeInfo.contentAreaInScreenSpace` (line 636), add:

```swift
contentNodeValue.sourceTransitionSurface = takeInfo.sourceTransitionSurface
```

Then add a matching field on `ItemContentNode` (next to `animateClippingFromContentAreaInScreenSpace`, line 138):

```swift
weak var sourceTransitionSurface: UIView?
```

The field is `weak` because the surface's lifetime is owned by the source side, not by CCEPN.

- [ ] **Step 2: Bypass `takeContainingNode()` when staging is active**

Find line 1269–1271:

```swift
if let contentNode = itemContentNode {
    contentNode.takeContainingNode()
}
```

The portal path needs contentNode to NOT be reparented into `offsetContainerNode` here — it'll go into the wrapper instead (next step). Replace with:

```swift
if let contentNode = itemContentNode {
    if let surface = contentNode.sourceTransitionSurface, contentNode.presentationScale == 1.0 {
        // Defer reparenting to staging.enter (Step 3 below).
        let _ = surface
    } else {
        contentNode.takeContainingNode()
    }
}
```

- [ ] **Step 3: Add the staging-enter / animation-target retargeting block**

Find line 1280: `if let contentNode = itemContentNode { ... }`. The block currently begins with the clipping animation guard (lines 1281–1284). Insert this BEFORE that guard, as the new very-first thing inside the block:

```swift
let portalAnimationLayer: CALayer?
if let surface = contentNode.sourceTransitionSurface, contentNode.presentationScale == 1.0 {
    let staging = PortalTransitionStaging()
    let currentContentLocalFrameInWindow = self.view.convert(
        convertFrame(contentRect, from: self.scrollNode.view, to: self.view),
        to: nil
    )
    if let layer = staging.enter(
        for: contentNode.containingItem,
        in: surface,
        overlayHost: contentNode.offsetContainerNode.view,
        targetScreenRect: currentContentLocalFrameInWindow
    ) {
        contentNode.portalStaging = staging
        portalAnimationLayer = layer
    } else {
        // Staging refused (PortalView nil); fall back to clipping by reparenting now.
        contentNode.takeContainingNode()
        portalAnimationLayer = nil
    }
} else {
    portalAnimationLayer = nil
}
```

- [ ] **Step 4: Gate the existing clipping animation on no-staging**

Find lines 1281–1284:

```swift
if let animateClippingFromContentAreaInScreenSpace = contentNode.animateClippingFromContentAreaInScreenSpace {
    self.clippingNode.layer.animateFrame(from: CGRect(origin: CGPoint(x: 0.0, y: animateClippingFromContentAreaInScreenSpace.minY), size: CGSize(width: layout.size.width, height: animateClippingFromContentAreaInScreenSpace.height)), to: CGRect(origin: CGPoint(), size: layout.size), duration: 0.2)
    self.clippingNode.layer.animateBoundsOriginYAdditive(from: animateClippingFromContentAreaInScreenSpace.minY, to: 0.0, duration: 0.2)
}
```

Replace with:

```swift
if portalAnimationLayer == nil, let animateClippingFromContentAreaInScreenSpace = contentNode.animateClippingFromContentAreaInScreenSpace {
    self.clippingNode.layer.animateFrame(from: CGRect(origin: CGPoint(x: 0.0, y: animateClippingFromContentAreaInScreenSpace.minY), size: CGSize(width: layout.size.width, height: animateClippingFromContentAreaInScreenSpace.height)), to: CGRect(origin: CGPoint(), size: layout.size), duration: 0.2)
    self.clippingNode.layer.animateBoundsOriginYAdditive(from: animateClippingFromContentAreaInScreenSpace.minY, to: 0.0, duration: 0.2)
}
```

- [ ] **Step 5: Retarget the position springs onto `portalAnimationLayer` when present**

Find the two `contentNode.layer.animateSpring(...)` calls at lines 1313–1322 and 1324–1332. They animate `contentNode.layer` (= the `ItemContentNode`'s layer). When `portalAnimationLayer` is non-nil, the springs need to target the wrapper's layer instead.

Replace lines 1312–1332 (the X-distance spring guard + X spring + Y spring) with:

```swift
let animateLayer: CALayer = portalAnimationLayer ?? contentNode.layer

if animationInContentXDistance != 0.0 {
    animateLayer.animateSpring(
        from: -animationInContentXDistance as NSNumber, to: 0.0 as NSNumber,
        keyPath: "position.x",
        duration: duration,
        delay: 0.0,
        initialVelocity: 0.0,
        damping: springDamping,
        additive: true
    )
}

animateLayer.animateSpring(
    from: -animationInContentYDistance as NSNumber, to: 0.0 as NSNumber,
    keyPath: "position.y",
    duration: duration,
    delay: 0.0,
    initialVelocity: 0.0,
    damping: springDamping,
    additive: true
)
```

(Net change: replace each `contentNode.layer.animateSpring(...)` with `animateLayer.animateSpring(...)`, keeping every other parameter identical.)

The `reactionPreviewView` springs at lines 1334–1355 stay unchanged — `reactionPreviewView` lives in CCEPN's own tree, never inside the source-side surface.

- [ ] **Step 6: Attach a settle completion to the Y-spring**

The Y-distance spring is the longest-lived in the animateIn animation set. Add a completion handler that calls `staging.settle(into: .offsetContainer(...))` when staging is active. Replace the just-edited Y-spring (the one at the bottom of the block from Step 5):

```swift
animateLayer.animateSpring(
    from: -animationInContentYDistance as NSNumber, to: 0.0 as NSNumber,
    keyPath: "position.y",
    duration: duration,
    delay: 0.0,
    initialVelocity: 0.0,
    damping: springDamping,
    additive: true
)
```

with:

```swift
animateLayer.animateSpring(
    from: -animationInContentYDistance as NSNumber, to: 0.0 as NSNumber,
    keyPath: "position.y",
    duration: duration,
    delay: 0.0,
    initialVelocity: 0.0,
    damping: springDamping,
    additive: true,
    completion: { [weak contentNode] _ in
        guard let contentNode else { return }
        if let staging = contentNode.portalStaging {
            staging.settle(into: .offsetContainer(contentNode.offsetContainerNode))
            contentNode.portalStaging = nil
        }
    }
)
```

(The `Display` module's `animateSpring` already accepts a `completion:` parameter — the dismiss path uses it at line 1665.)

- [ ] **Step 7: Build to confirm everything compiles**

Run the build verification command from the plan header. Expected: succeeds. Existing source-callers don't pass `sourceTransitionSurface`, so portal path is dormant; visual behavior is unchanged.

- [ ] **Step 8: Commit**

```bash
git add submodules/TelegramUI/Components/ContextControllerImpl/Sources/ContextControllerExtractedPresentationNode.swift
git commit -m "$(cat <<'EOF'
CCEPN: portal-mode animateIn (gated on sourceTransitionSurface)

When a source provides sourceTransitionSurface (and presentationScale
is 1.0), reparent the source's contentNode into a PortalSourceView
inside the surface, mirror it via PortalView(matchPosition: true) into
ItemContentNode.offsetContainerNode, and retarget the position springs
onto the wrapper's layer. The clipping animation is bypassed in this
mode. On animation completion, contentNode is reparented home into
offsetContainerNode (today's resting state). Fallback path unchanged.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Wire portal path into `case .animateOut:`

**Files:**
- Modify: `submodules/TelegramUI/Components/ContextControllerImpl/Sources/ContextControllerExtractedPresentationNode.swift:1487-1684` (the `.animateOut` arm of the `stateTransition` switch).

Mirror of Task 3 but in reverse direction: contentNode goes from `offsetContainerNode` back into the source-side surface, animation runs in chat tree, and on completion contentNode is reparented to its original parent (chat-side).

- [ ] **Step 1: Declare `portalAnimationLayer` at the top of the animateOut block**

Find line 1507 (`let currentContentScreenFrame: CGRect`), inside `case .animateOut(...)`. Insert immediately before that line:

```swift
            var portalAnimationLayer: CALayer? = nil
```

The local is `var` because the `.extracted` arm of the source switch (next step) populates it. It must be declared up here — outside the source switch — because the dismiss-spring code further down (the `if let contentNode = itemContentNode { ... }` block around line 1622) needs to read it.

- [ ] **Step 2: Replace the `.extracted` arm of the source switch**

Find lines 1528–1543 (the `.extracted` arm of the source switch inside `.animateOut`). The current code:

```swift
case let .extracted(source):
    let putBackInfo = source.putBack()
    
    if let putBackInfo = putBackInfo {
        self.clippingNode.layer.animateFrame(from: CGRect(origin: CGPoint(), size: layout.size), to: CGRect(origin: CGPoint(x: 0.0, y: putBackInfo.contentAreaInScreenSpace.minY), size: CGSize(width: layout.size.width, height: putBackInfo.contentAreaInScreenSpace.height)), duration: duration, timingFunction: timingFunction, removeOnCompletion: false)
        self.clippingNode.layer.animateBoundsOriginYAdditive(from: 0.0, to: putBackInfo.contentAreaInScreenSpace.minY, duration: duration, timingFunction: timingFunction, removeOnCompletion: false)
    }
    
    if let contentNode = itemContentNode {
        currentContentScreenFrame = convertFrame(contentNode.containingItem.contentRect, from: contentNode.containingItem.view, to: self.view)
        if currentContentScreenFrame.origin.x < 0.0 {
            contentParentGlobalFrameOffsetX = layout.size.width
        }
    } else {
        return
    }
```

Replace with (note: assigns into the `portalAnimationLayer` declared in Step 1, no re-declaration here):

```swift
case let .extracted(source):
    let putBackInfo = source.putBack()
    
    if let putBackInfo = putBackInfo,
       let surface = putBackInfo.sourceTransitionSurface,
       let contentNode = itemContentNode,
       contentNode.presentationScale == 1.0
    {
        let preStagingScreenFrame = convertFrame(contentNode.containingItem.contentRect, from: contentNode.containingItem.view, to: self.view)
        let preStagingScreenFrameInWindow = self.view.convert(preStagingScreenFrame, to: nil)
        let staging = PortalTransitionStaging()
        if let layer = staging.enter(
            for: contentNode.containingItem,
            in: surface,
            overlayHost: contentNode.offsetContainerNode.view,
            targetScreenRect: preStagingScreenFrameInWindow
        ) {
            contentNode.portalStaging = staging
            portalAnimationLayer = layer
        }
    }
    
    if portalAnimationLayer == nil, let putBackInfo = putBackInfo {
        self.clippingNode.layer.animateFrame(from: CGRect(origin: CGPoint(), size: layout.size), to: CGRect(origin: CGPoint(x: 0.0, y: putBackInfo.contentAreaInScreenSpace.minY), size: CGSize(width: layout.size.width, height: putBackInfo.contentAreaInScreenSpace.height)), duration: duration, timingFunction: timingFunction, removeOnCompletion: false)
        self.clippingNode.layer.animateBoundsOriginYAdditive(from: 0.0, to: putBackInfo.contentAreaInScreenSpace.minY, duration: duration, timingFunction: timingFunction, removeOnCompletion: false)
    }
    
    if let contentNode = itemContentNode {
        currentContentScreenFrame = convertFrame(contentNode.containingItem.contentRect, from: contentNode.containingItem.view, to: self.view)
        if currentContentScreenFrame.origin.x < 0.0 {
            contentParentGlobalFrameOffsetX = layout.size.width
        }
    } else {
        return
    }
```

- [ ] **Step 3: Retarget the dismiss springs onto `portalAnimationLayer` when present**

Find lines 1643–1684 (the X spring at 1644, the position adjustment at 1655, and the Y spring at 1657). Currently:

```swift
if animationInContentXDistance != 0.0 {
    contentNode.offsetContainerNode.layer.animate(
        from: -animationInContentXDistance as NSNumber,
        to: 0.0 as NSNumber,
        keyPath: "position.x",
        timingFunction: timingFunction,
        duration: duration,
        delay: 0.0,
        additive: true
    )
}

contentNode.offsetContainerNode.position = contentNode.offsetContainerNode.position.offsetBy(dx: animationInContentXDistance, dy: -animationInContentYDistance)
let reactionContextNodeIsAnimatingOut = self.reactionContextNodeIsAnimatingOut
contentNode.offsetContainerNode.layer.animate(
    from: animationInContentYDistance as NSNumber,
    to: 0.0 as NSNumber,
    keyPath: "position.y",
    timingFunction: timingFunction,
    duration: duration,
    delay: 0.0,
    additive: true,
    completion: { [weak self] _ in
        Queue.mainQueue().after(reactionContextNodeIsAnimatingOut ? 0.2 * UIView.animationDurationFactor() : 0.0, {
            if let strongSelf = self, let contentNode = strongSelf.itemContentNode {
                switch contentNode.containingItem {
                case let .node(containingNode):
                    containingNode.addSubnode(containingNode.contentNode)
                case let .view(containingView):
                    containingView.addSubview(containingView.contentView)
                }
            }
            
            contentNode.containingItem.isExtractedToContextPreview = false
            contentNode.containingItem.isExtractedToContextPreviewUpdated?(false)
            contentNode.containingItem.onDismiss?()
            
            restoreOverlayViews.forEach({ $0() })
            completion()
        })
    }
)
```

Replace with the staging-aware variant:

```swift
let animateLayer: CALayer = portalAnimationLayer ?? contentNode.offsetContainerNode.layer

if animationInContentXDistance != 0.0 {
    animateLayer.animate(
        from: -animationInContentXDistance as NSNumber,
        to: 0.0 as NSNumber,
        keyPath: "position.x",
        timingFunction: timingFunction,
        duration: duration,
        delay: 0.0,
        additive: true
    )
}

if portalAnimationLayer == nil {
    contentNode.offsetContainerNode.position = contentNode.offsetContainerNode.position.offsetBy(dx: animationInContentXDistance, dy: -animationInContentYDistance)
}

let reactionContextNodeIsAnimatingOut = self.reactionContextNodeIsAnimatingOut
animateLayer.animate(
    from: animationInContentYDistance as NSNumber,
    to: 0.0 as NSNumber,
    keyPath: "position.y",
    timingFunction: timingFunction,
    duration: duration,
    delay: 0.0,
    additive: true,
    completion: { [weak self] _ in
        Queue.mainQueue().after(reactionContextNodeIsAnimatingOut ? 0.2 * UIView.animationDurationFactor() : 0.0, {
            if let strongSelf = self, let contentNode = strongSelf.itemContentNode {
                if let staging = contentNode.portalStaging {
                    staging.settle(into: .original)
                    contentNode.portalStaging = nil
                } else {
                    switch contentNode.containingItem {
                    case let .node(containingNode):
                        containingNode.addSubnode(containingNode.contentNode)
                    case let .view(containingView):
                        containingView.addSubview(containingView.contentView)
                    }
                }
            }
            
            if let strongSelf = self, let contentNode = strongSelf.itemContentNode {
                contentNode.containingItem.isExtractedToContextPreview = false
                contentNode.containingItem.isExtractedToContextPreviewUpdated?(false)
                contentNode.containingItem.onDismiss?()
            }
            
            restoreOverlayViews.forEach({ $0() })
            completion()
        })
    }
)
```

Three substantive changes:
- The X / Y spring `animate(...)` calls target `animateLayer` instead of `contentNode.offsetContainerNode.layer`.
- The `offsetContainerNode.position = ...` mutation is skipped on the portal path (offsetContainerNode is not the visible animation layer in that case; mutating it would be a no-op visually but is unnecessary).
- The completion's reparent step branches on `contentNode.portalStaging` — staging owns the reparent on the portal path.

- [ ] **Step 4: Build**

Run the build verification command. Expected: succeeds.

- [ ] **Step 5: Commit**

```bash
git add submodules/TelegramUI/Components/ContextControllerImpl/Sources/ContextControllerExtractedPresentationNode.swift
git commit -m "$(cat <<'EOF'
CCEPN: portal-mode animateOut (gated on sourceTransitionSurface)

Symmetric to portal-mode animateIn: when putBackInfo provides a
surface (and presentationScale is 1.0), reparent contentNode out of
offsetContainerNode into a PortalSourceView in the surface, mirror
via PortalView clone in offsetContainerNode, retarget dismiss springs
onto the wrapper's layer, skip the manual clip animation. On
completion, staging reparents contentNode to its original chat-side
parent. Fallback path unchanged.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Add `contextTransitionContainer` to `ChatControllerNode`

**Files:**
- Modify: `submodules/TelegramUI/Sources/ChatControllerNode.swift` (private storage near other view fields; `ensureContextTransitionContainer()` accessor; frame update inside `containerLayoutUpdated`).

`ChatControllerNode` is a 4400+ line file. The exact line numbers below are anchors — search for the surrounding code to locate the precise insertion point if your local copy has drifted.

- [ ] **Step 1: Add private storage**

Open `submodules/TelegramUI/Sources/ChatControllerNode.swift`. Find a section of private view fields near the top of the class (after `class ChatControllerNode: ASDisplayNode, ASScrollViewDelegate {` at line 171). A natural location is just after other private optional view fields. Search for `private var` near the start of the class body and insert this declaration alongside them — for example, immediately before `weak var node: ChatControllerNode?` is *not* applicable (that's on a different type at line 80); look in the body of `ChatControllerNode` itself.

Concretely: after the existing private property block (anywhere in the first 250 lines after class start), add:

```swift
    private var contextTransitionContainer: UIView?
```

If you cannot find an obvious spot, place it directly above the `historyNode` property — `grep -n "self.historyNode = historyNode"` (line 166) is one anchor; the property declaration itself is nearby.

- [ ] **Step 2: Add the accessor**

Find the `frameForVisibleArea()` function at line 4038. Immediately before its `func frameForVisibleArea() -> CGRect {` line, insert:

```swift
    func ensureContextTransitionContainer() -> UIView {
        if let existing = self.contextTransitionContainer {
            existing.frame = self.frameForVisibleArea()
            return existing
        }
        let v = UIView()
        v.clipsToBounds = true
        v.isUserInteractionEnabled = false
        v.frame = self.frameForVisibleArea()
        self.view.insertSubview(v, aboveSubview: self.historyNodeContainer.view)
        self.contextTransitionContainer = v
        return v
    }
```

The choice `aboveSubview: self.historyNodeContainer.view` puts the container at the same Z position as the chat history. If a future visual check shows the input panel or navigation chrome rendering UNDER the staged bubble (when it should render OVER), change to `belowSubview:` against the appropriate subview. The first visual smoke test in Task 8 will surface this.

- [ ] **Step 3: Wire frame update into the layout pass**

Find the end of `containerLayoutUpdated(...)` at line 3530–3533:

```swift
        self.derivedLayoutState = ChatControllerNodeDerivedLayoutState(inputContextPanelsFrame: inputContextPanelsFrame, inputContextPanelsOverMainPanelFrame: inputContextPanelsOverMainPanelFrame, inputNodeHeight: inputNodeHeightAndOverflow?.0, inputNodeAdditionalHeight: inputNodeHeightAndOverflow?.1, upperInputPositionBound: inputNodeHeightAndOverflow?.0 != nil ? self.upperInputPositionBound : nil)
        
        //self.notifyTransitionCompletionListeners(transition: transition)
    }
```

Just before the closing `}` of `containerLayoutUpdated`, insert:

```swift
        if let contextTransitionContainer = self.contextTransitionContainer {
            contextTransitionContainer.frame = self.frameForVisibleArea()
        }
```

This makes the surface track the chat's visible-area rect on every layout pass, which is what gives Issue B (live source-side dynamics) its win.

- [ ] **Step 4: Build**

Run the build verification command. Expected: succeeds. Nothing references `ensureContextTransitionContainer()` yet, so this is a no-op behaviorally.

- [ ] **Step 5: Commit**

```bash
git add submodules/TelegramUI/Sources/ChatControllerNode.swift
git commit -m "$(cat <<'EOF'
ChatControllerNode: add contextTransitionContainer

Lazy UIView sized to frameForVisibleArea(), updated in
containerLayoutUpdated, used as the sourceTransitionSurface for
extracted-content context menus in subsequent commits.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Adopt `sourceTransitionSurface` in `ChatMessageContextExtractedContentSource`

**Files:**
- Modify: `submodules/TelegramUI/Sources/ChatMessageContextControllerContentSource.swift:76-120` (the `takeView` and `putBack` of `ChatMessageContextExtractedContentSource`).

This is the regular bubble long-press path. After this task, that path uses the portal transition.

- [ ] **Step 1: Update `takeView()`**

Find lines 76–99 (the `func takeView()` body of `ChatMessageContextExtractedContentSource`). The relevant single line is line 90:

```swift
                result = ContextControllerTakeViewInfo(containingItem: .node(contentNode), contentAreaInScreenSpace: chatNode.convert(chatNode.frameForVisibleArea(), to: nil))
```

Replace with:

```swift
                result = ContextControllerTakeViewInfo(containingItem: .node(contentNode), contentAreaInScreenSpace: chatNode.convert(chatNode.frameForVisibleArea(), to: nil), sourceTransitionSurface: chatNode.ensureContextTransitionContainer())
```

- [ ] **Step 2: Update `putBack()`**

Find lines 101–120 (`func putBack()`). The relevant single line is line 115:

```swift
                result = ContextControllerPutBackViewInfo(contentAreaInScreenSpace: chatNode.convert(chatNode.frameForVisibleArea(), to: nil))
```

Replace with:

```swift
                result = ContextControllerPutBackViewInfo(contentAreaInScreenSpace: chatNode.convert(chatNode.frameForVisibleArea(), to: nil), sourceTransitionSurface: chatNode.ensureContextTransitionContainer())
```

- [ ] **Step 3: Build**

Run the build verification command. Expected: succeeds.

- [ ] **Step 4: Commit**

```bash
git add submodules/TelegramUI/Sources/ChatMessageContextControllerContentSource.swift
git commit -m "$(cat <<'EOF'
Adopt sourceTransitionSurface in ChatMessage extraction source

ChatMessageContextExtractedContentSource (regular long-press menu)
now passes the chat's contextTransitionContainer as the surface for
take/putBack, enabling CCEPN's portal transition path.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Adopt `sourceTransitionSurface` in `ChatMessageReactionContextExtractedContentSource`

**Files:**
- Modify: `submodules/TelegramUI/Sources/ChatMessageContextControllerContentSource.swift:452-490` (the reaction-context source's `takeView` and `putBack`).

This is the reaction context menu path on a bubble. After this task, that path also uses the portal transition.

- [ ] **Step 1: Update `takeView()`**

Find lines 452–470 (the `func takeView()` body of `ChatMessageReactionContextExtractedContentSource`). Line 466:

```swift
                result = ContextControllerTakeViewInfo(containingItem: .view(self.contentView), contentAreaInScreenSpace: chatNode.convert(chatNode.frameForVisibleArea(), to: nil))
```

Replace with:

```swift
                result = ContextControllerTakeViewInfo(containingItem: .view(self.contentView), contentAreaInScreenSpace: chatNode.convert(chatNode.frameForVisibleArea(), to: nil), sourceTransitionSurface: chatNode.ensureContextTransitionContainer())
```

- [ ] **Step 2: Update `putBack()`**

Find lines 472–490. Line 486:

```swift
                result = ContextControllerPutBackViewInfo(contentAreaInScreenSpace: chatNode.convert(chatNode.frameForVisibleArea(), to: nil))
```

Replace with:

```swift
                result = ContextControllerPutBackViewInfo(contentAreaInScreenSpace: chatNode.convert(chatNode.frameForVisibleArea(), to: nil), sourceTransitionSurface: chatNode.ensureContextTransitionContainer())
```

- [ ] **Step 3: Build**

Run the build verification command. Expected: succeeds.

- [ ] **Step 4: Commit**

```bash
git add submodules/TelegramUI/Sources/ChatMessageContextControllerContentSource.swift
git commit -m "$(cat <<'EOF'
Adopt sourceTransitionSurface in ChatMessage reaction source

ChatMessageReactionContextExtractedContentSource (reaction context
menu on a bubble) now passes the chat's contextTransitionContainer
as the surface for take/putBack, enabling CCEPN's portal transition
path.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Manual visual verification

**Files:** None modified. This task is hands-on testing.

The project has no unit tests; the design's claims (Issue A, Issue B fixes, fallback unchanged) need to be verified by exercising the app in a simulator. The four checks below correspond to the four spec verification items.

- [ ] **Step 1: Final build (no `--continueOnError`)**

```sh
source ~/.zshrc 2>/dev/null; python3 build-system/Make/Make.py --overrideXcodeVersion \
  --cacheDir ~/telegram-bazel-cache build \
  --configurationPath build-system/appstore-configuration.json \
  --gitCodesigningRepository git@gitlab.com:peter-iakovlev/fastlanematch.git \
  --gitCodesigningType development --gitCodesigningUseCurrent \
  --buildNumber=1 --configuration=debug_sim_arm64
```

Expected: clean build (zero errors).

- [ ] **Step 2: Issue A — boundary clipping check**

Run the app on the iOS simulator. Open a chat with messages. Long-press a message that is positioned near the top of the chat (so its bubble overlaps the navigation bar) and another that is positioned near the bottom (overlapping the input panel). Compare the in/out animation against `master`:

- On `master`: the bubble visibly cuts at the chat content-area edge during the in/out transition (a straight horizontal line where shadow/rounded corner is sliced).
- On this branch: the cut should follow the chat's actual ancestor mask shape — no straight-line stutter at the manual-clip rect edge. The shadow / rounded corner should clip exactly as the in-place bubble does at rest.

If the bubble appears NOT to be clipped at all (i.e., it visibly extends OVER the navigation bar / input panel during the animation), check Z-order — see Task 5 Step 2 note about `aboveSubview` vs `belowSubview`.

- [ ] **Step 3: Issue B — live source dynamics check**

Long-press a message. Mid-animation (during the spring's ~0.42s duration), induce a chat layout change — easiest method: tap the input field to bring up the keyboard right at the moment of long-press. Visually watch the bubble. The clipping should track the chat's live state, not a frozen snapshot taken at animation start.

- [ ] **Step 4: Reaction context check**

On a message in the same chat, open the reaction context menu (long-press to bring up the menu, then tap an empty area or whatever invokes the reactions). Confirm the in/out animation looks correct (same as Step 2's criteria).

- [ ] **Step 5: Fallback path regression check**

Exercise three sources that pass `sourceTransitionSurface = nil` (i.e., still on the today's-clipping path):

- A play-once voice or video message context (`ChatViewOnceMessageContextExtractedContentSource`).
- A chat-message-navigation-button context (`ChatMessageNavigationButtonContextExtractedContentSource`).
- The overlay audio player context (`OverlayAudioPlayerControllerNode`).
- The chat search title accessory context (`ChatSearchTitleAccessoryPanelNode`).

Confirm each looks identical to `master` — no visible regressions.

- [ ] **Step 6: Take notes on any visible regressions**

If any regression is observed in steps 2–5, capture (a) the source it occurred in, (b) the exact visual symptom, (c) whether it reproduces on `master`. File these against this plan; do not silently land regressions.

---

## Limitation noted in the design

The portal path is gated on `presentationScale == 1.0`. When CCEPN detects ancestor scale on the source view (e.g., a chat shown inside a sheet with a container transform), it falls back to the clipping path. Lifting this restriction is future work — the animation deltas would need to be divided by `presentationScale` before being applied to the wrapper's layer (since the wrapper sits in scaled chat-tree-local coords, while deltas are computed in screen coords). None of the first adopters in this plan trigger that case.

## Files touched (summary)

- `submodules/ContextUI/Sources/ContextController.swift` — Task 1.
- `submodules/TelegramUI/Components/ContextControllerImpl/Sources/ContextControllerExtractedPresentationNode.swift` — Tasks 2, 3, 4.
- `submodules/TelegramUI/Sources/ChatControllerNode.swift` — Task 5.
- `submodules/TelegramUI/Sources/ChatMessageContextControllerContentSource.swift` — Tasks 6, 7.
