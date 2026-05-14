# Context controller — portal-view transition (replaces visible-area clipping)

Date: 2026-05-05
Status: Design approved; pending implementation plan.

## Problem

`ContextControllerExtractedPresentationNode` (CCEPN) animates an extracted bubble in/out of the context menu by reparenting the source's `contentNode`/`contentView` into its own `offsetContainerNode` and then animating a separate `clippingNode` frame to interpolate between the chat's content area and the full screen. The clipping animation is what keeps the bubble from visibly bleeding past chat boundaries (navigation bar above, input panel below) during the transition.

Two problems with that approach:

1. **Boundary artifacts.** Bubbles with shadows or rounded corners get visibly cut at the chat content-area edges during the in/out transition — the manual clip rectangle doesn't honor the actual ancestor masking shape.
2. **No live source-side dynamics.** The clip animation is computed once at animation start using `contentAreaInScreenSpace`. If the chat scrolls, the navigation-bar height changes, the input panel's keyboard rises, etc. mid-animation, the manually animated `clippingNode` frame goes stale; the visible clip drifts away from where the chat would actually clip the bubble.

Both classes of issue go away if the bubble is rendered through a primitive that already exists in the codebase: a `PortalSourceView` whose layer tree is mirrored to a `PortalView` at a different Z position. `ChatMessageTransitionNode` already uses this pattern for message-send animations. CCEPN should use the same primitive for extraction transitions.

## Solution overview

During the in/out transition, the source's `contentNode` is reparented into a `sourceTransitionSurface: UIView` that the source provides — a view in its own hierarchy where ancestor clipping (chat content area) applies naturally. CCEPN wraps it with a `PortalSourceView` and adds a `PortalView(matchPosition: true)` clone into `ItemContentNode.offsetContainerNode` (in the overlay tree). The clone tracks the wrapper's screen-space frame automatically.

CCEPN keeps applying the same spring/position/transform animation values it computes today, but retargets them onto the wrapper's layer instead of `contentNode.layer` / `offsetContainerNode.layer`. Because the wrapper is in the chat tree, its frame changes (and the chat's real-time re-layout) flow through the portal mirror to the visible clone. The manual `clippingNode.layer.animateFrame(...)` calls become unnecessary on this path.

After the in-animation completes, the `contentNode` is reparented out of the wrapper into `offsetContainerNode` (today's resting state). Portal staging is torn down. On dismiss, the inverse: contentNode is reparented from `offsetContainerNode` into the (fresh) `putBackInfo.sourceTransitionSurface`, the wrapper + clone are reconstructed, the dismiss animation runs against the wrapper's layer, and on completion contentNode is reparented home (its original chat-side parent).

The new path is opt-in. When `sourceTransitionSurface == nil`, CCEPN falls back to today's `clippingNode.layer.animateFrame(...)` behavior. Existing `ContextExtractedContentSource` adopters that don't pass a surface keep working unchanged.

## Scope

**In scope.** The `.extracted` `ContentSource` case in CCEPN. Two struct fields. One file-local helper inside CCEPN. Adoption in two of the four `ContextExtractedContentSource` types in `submodules/TelegramUI/Sources/ChatMessageContextControllerContentSource.swift` — `ChatMessageContextExtractedContentSource` (regular bubble long-press) and `ChatMessageReactionContextExtractedContentSource` (reaction context).

**Out of scope.**
- `.reference`, `.location`, `.controller` source cases. They never reparent `contentNode` and don't have analogous boundary issues. Their `clippingNode.animateFrame(...)` calls (where present) stay unchanged.
- `ChatViewOnceMessageContextExtractedContentSource`. Has a private `messageNodeCopy` and a custom dust-effect dismiss path that's structurally different.
- `ChatMessageNavigationButtonContextExtractedContentSource`. Stays on the fallback path; not part of this change.
- The `ChatMessageTransitionNode` portal usage itself. We adopt the same primitive; we do not refactor CMTN.
- `maskView` semantics on `TakeViewInfo`/`PutBackInfo`. Unchanged; the portal path doesn't use it.

## Public-API changes — `submodules/ContextUI/Sources/ContextController.swift`

```swift
public final class ContextControllerTakeViewInfo {
    public enum ContainingItem { case node(...) ; case view(...) }

    public let containingItem: ContainingItem
    public let contentAreaInScreenSpace: CGRect
    public let maskView: UIView?
    public let sourceTransitionSurface: UIView?     // NEW

    public init(
        containingItem: ContainingItem,
        contentAreaInScreenSpace: CGRect,
        maskView: UIView? = nil,
        sourceTransitionSurface: UIView? = nil       // NEW, defaults nil
    )
}

public final class ContextControllerPutBackViewInfo {
    public let contentAreaInScreenSpace: CGRect
    public let maskView: UIView?
    public let sourceTransitionSurface: UIView?     // NEW

    public init(
        contentAreaInScreenSpace: CGRect,
        maskView: UIView? = nil,
        sourceTransitionSurface: UIView? = nil       // NEW, defaults nil
    )
}
```

**Source-side contract** when `sourceTransitionSurface != nil`:

- The view MUST be attached to a window-bearing tree at the moment the source returns it.
- Its on-screen frame MUST already reflect current chat layout (the chat's existing layout pass owns this).
- The source MUST NOT remove or move it before the corresponding transition completes (the in-animation for `TakeViewInfo`; the dismiss animation for `PutBackInfo`). CCEPN owns reparenting cleanup.
- A single surface may be reused across `takeView` and `putBack` (and across multiple presentations). The chat owns one shared `transitionContainer: UIView` per `ChatControllerNode`.

The default `nil` is what makes this a strictly additive change for every existing adopter.

## `PortalTransitionStaging` — file-local helper inside CCEPN

A new private class in `submodules/TelegramUI/Components/ContextControllerImpl/Sources/ContextControllerExtractedPresentationNode.swift`. Single instance per `ItemContentNode`, non-nil only while a transition is in flight. Encapsulates the wrapper + clone lifecycle so CCEPN's animation code never observes a half-staged state.

```swift
private final class PortalTransitionStaging {
    enum OriginalParent {
        case node(ASDisplayNode)        // contentNode.supernode at staging time
        case view(UIView)               // contentView.superview at staging time
    }

    weak var surface: UIView?
    var wrapper: PortalSourceView?
    var clone: PortalView?
    var originalParentSnapshot: OriginalParent?

    /// Sets up staging and returns the layer the caller should animate. Returns nil
    /// (and leaves staging untouched) if `PortalView(matchPosition:)` cannot be
    /// instantiated — caller falls back to the clipping path.
    ///
    /// Side effects on success:
    ///  - records `originalParentSnapshot` from the containingItem's current parent
    ///  - constructs `wrapper = PortalSourceView()` and adds it to `surface`
    ///  - reparents the containingItem's contentNode/contentView into `wrapper`
    ///  - constructs `clone = PortalView(matchPosition: true)` and adds its view into `overlayHost`
    ///  - calls `wrapper.addPortal(view: clone)`
    ///  - sets `wrapper.frame` so the contentNode's screen-space rect equals
    ///    `targetScreenRect` (via `surface.convert(targetScreenRect, from: nil)`)
    func enter(
        for containingItem: ContextControllerTakeViewInfo.ContainingItem,
        in surface: UIView,
        overlayHost: UIView,
        targetScreenRect: CGRect
    ) -> CALayer?

    enum SettleDestination {
        case offsetContainer(ASDisplayNode)         // resting parent for animateIn end
        case original                               // restore from originalParentSnapshot
    }

    /// Tears down staging. Reparents contentNode into the requested destination,
    /// removes the clone from its host, removes the wrapper from `surface`.
    /// All reparenting is synchronous; no CATransaction is needed because all
    /// animations in this codebase are explicit `animate*` calls — there are no
    /// implicit CALayer actions to suppress.
    func settle(into: SettleDestination, presentationScale: CGFloat)
}
```

**Invariant** (asserted on `enter`): `contentNode.portalStaging != nil` ⇒ contentNode parent is `staging.wrapper`.

If CCEPN re-enters animateIn or animateOut while staging is non-nil (defensive case — shouldn't happen at runtime), the new branch tears down the existing staging via `settle(into: .offsetContainer, ...)` first, then proceeds with its own `enter(...)`.

## CCEPN integration

Three edit points in `ContextControllerExtractedPresentationNode.swift`. The portal-mode branch lives next to the existing clipping branch in each animateIn / animateOut path.

### `ItemContentNode` — one new property

```swift
private final class ItemContentNode: ASDisplayNode {
    // ...existing fields unchanged...
    var portalStaging: PortalTransitionStaging?      // NEW
}
```

### `case .animateIn:` (currently lines ~1265–1474)

At the top of `if let contentNode = itemContentNode { ... }`:

```swift
if let surface = takeInfo.sourceTransitionSurface {
    let staging = PortalTransitionStaging()
    // `targetScreenRect`: the bubble's resting end-of-animateIn rect in window coords
    // (i.e. its menu-extracted position) — derived from today's `currentContentLocalFrame`
    // (already in self.view coords) via `self.view.convert(_, to: nil)`.
    let targetScreenRect = self.view.convert(currentContentLocalFrame, to: nil)
    if let _ = staging.enter(
        for: contentNode.containingItem,
        in: surface,
        overlayHost: contentNode.offsetContainerNode.view,
        targetScreenRect: targetScreenRect
    ) {
        contentNode.portalStaging = staging
    }
}

let animatedLayer: CALayer = contentNode.portalStaging?.wrapper?.layer ?? contentNode.layer
```

The existing `if let animateClippingFromContentAreaInScreenSpace = contentNode.animateClippingFromContentAreaInScreenSpace { ... self.clippingNode.layer.animateFrame(...) ... self.clippingNode.layer.animateBoundsOriginYAdditive(...) }` block is wrapped in `if contentNode.portalStaging == nil { ... }` — clip animation only fires on the fallback path.

The four spring `animateSpring(... keyPath: "position.x" / "position.y" ...)` calls today applied to `contentNode.layer` (and the reactionPreview spring twin) target `animatedLayer` instead. Same delta values (`animationInContentXDistance`, `animationInContentYDistance`), same spring params (`damping: springDamping`, `duration: 0.42`, etc.).

A completion handler is attached to the longest-lived spring (`position.y` on the contentNode/wrapper):

```swift
{ [weak self] _ in
    guard let strongSelf = self, let contentNode = strongSelf.itemContentNode else { return }
    contentNode.portalStaging?.settle(
        into: .offsetContainer(contentNode.offsetContainerNode),
        presentationScale: contentNode.presentationScale
    )
    contentNode.portalStaging = nil
}
```

`presentationScale` re-application: while contentNode was inside the wrapper (in chat tree), the chat ancestor's scale was already in effect — the existing `CATransform3DMakeScale(detectedScale, detectedScale, 1.0)` compensation must NOT be applied during staging. After reparenting back into the unscaled `offsetContainerNode`, `settle(...)` reapplies it on `offsetContainerNode.layer.transform`. (Today's code applies it once at construction in lines ~647–649; on the portal path, it shifts to staging-settle time.)

### `case .animateOut:` (currently lines ~1487–1684)

Symmetric. After computing `putBackInfo`:

```swift
if let putBackInfo, let surface = putBackInfo.sourceTransitionSurface {
    let staging = PortalTransitionStaging()
    // `targetScreenRect`: the bubble's resting end-of-animateOut rect in window coords
    // (i.e. its source position back in chat) — derived from `currentContentScreenFrame`
    // (in self.view coords, despite the name) via `self.view.convert(_, to: nil)`.
    let targetScreenRect = self.view.convert(currentContentScreenFrame, to: nil)
    if let _ = staging.enter(
        for: contentNode.containingItem,
        in: surface,
        overlayHost: contentNode.offsetContainerNode.view,
        targetScreenRect: targetScreenRect
    ) {
        contentNode.portalStaging = staging
    }
}

let animatedLayer: CALayer = contentNode.portalStaging?.wrapper?.layer ?? contentNode.offsetContainerNode.layer
```

The two `self.clippingNode.layer.animateFrame(...) / animateBoundsOriginYAdditive(...)` blocks (in the `.location`, `.reference`, `.extracted` arms of the source switch) are guarded by `contentNode.portalStaging == nil`. Note: only the `.extracted` arm can have staging; `.location` and `.reference` never set `sourceTransitionSurface`, so this guard simplifies cleanly.

The dismiss spring on `contentNode.offsetContainerNode.layer` (`position.x` and `position.y`, lines ~1644 and ~1657) targets `animatedLayer` instead. The completion handler at ~1665 currently does:

```swift
switch contentNode.containingItem {
case let .node(containingNode): containingNode.addSubnode(containingNode.contentNode)
case let .view(containingView): containingView.addSubview(containingView.contentView)
}
```

When staging is active, the manual reparenting is replaced by `contentNode.portalStaging?.settle(into: .original, presentationScale: contentNode.presentationScale)` followed by `contentNode.portalStaging = nil`. The flag-clearing (`isExtractedToContextPreview = false` etc.) and `restoreOverlayViews.forEach { $0() }` cleanup stay where they are.

### Unchanged

- `willUpdateIsExtractedToContextPreview?(...)` callbacks at lines 1462 and 1623 fire at the same point, with the same arguments. The chat does not need to know we're using a portal.
- The overlay-views snapshot logic at lines 1476–1486 (animateIn) and 1596–1618 (animateOut) references `itemContentNode.supernode` / `itemContentNode.view` — `itemContentNode` itself stays in the scrollNode regardless of staging, so these blocks need no edits.
- All other animations on `actionsContainerNode`, `additionalActionsStackNode`, `reactionContextNode`, etc. are untouched.

## First adopter — chat message extraction

Two of the three sources in `submodules/TelegramUI/Sources/ChatMessageContextControllerContentSource.swift`:

- `ChatMessageContextExtractedContentSource` (regular bubble long-press menu)
- `ChatMessageReactionContextExtractedContentSource` (reaction context)

Both already return `chatNode.convert(chatNode.frameForVisibleArea(), to: nil)` as their `contentAreaInScreenSpace`. Each gains one new field on the `TakeViewInfo`/`PutBackInfo` constructor: `sourceTransitionSurface: chatNode.ensureContextTransitionContainer()`.

`ChatMessageNavigationButtonContextExtractedContentSource` and `ChatViewOnceMessageContextExtractedContentSource` are NOT adopted in this change; they continue to pass `sourceTransitionSurface = nil` (i.e. the default).

### `ChatControllerNode.contextTransitionContainer`

A single lazy view per chat node, owned by `ChatControllerNode`:

```swift
// in ChatControllerNode (private):
private var contextTransitionContainer: UIView?

func ensureContextTransitionContainer() -> UIView {
    if let existing = self.contextTransitionContainer { return existing }
    let v = UIView()
    v.clipsToBounds = true
    v.isUserInteractionEnabled = false
    self.view.insertSubview(v, aboveSubview: self.historyNode.view)
    self.contextTransitionContainer = v
    return v
}
```

**Frame management.** Sized to `frameForVisibleArea()` and updated whenever the chat's layout changes. The chat's existing layout pass already updates that rect; the container's frame mirrors it. This is what gives us issue B's win: live re-layout flows through the surface, into the wrapped contentNode, into the portal mirror.

**Z-order check.** Inserting above `historyNode.view` matches the bubble's natural Z. When implementing, verify the input panel and navigation chrome render *over* the surface (so an extracted bubble visually tucks under them just as the in-place bubble does). If a chrome element lands below the surface in the live z-order, adjust `insertSubview(_, belowSubview:)` accordingly. This is a per-implementation check, not an open design question.

## Edge cases

- **`PortalView(matchPosition:)` returns nil.** `_UIPortalView` is private API; if it can't be instantiated, `staging.enter(...)` returns nil. CCEPN treats that exactly like `sourceTransitionSurface == nil` and takes the today's-clipping path. No half-staged state.
- **Surface deallocates mid-transition.** `surface` is captured weakly. If it goes away while the spring is running, the portal mirror renders nothing (UIKit handles a missing portal source). The spring completion still fires from the wrapper's layer (still alive in the staging instance) and `settle(...)` walks defensive — if `wrapper.superview == nil` it reparents contentNode into the destination and bails on portal teardown. Visual is degraded for the remainder of the transition; no leaks or crashes.
- **Animation interrupts itself.** If CCEPN is asked to `.animateOut` while `.animateIn` staging is still live (menu dismissed during open), the animateOut branch first calls `settle(into: .offsetContainer, ...)` on the existing staging, clears `portalStaging`, then performs its own `enter(...)`. The "staging non-nil ⇒ contentNode is in wrapper" invariant from above makes this safe.
- **`presentationScale != 1.0`.** Discussed above. The existing scale compensation (lines 642–650) is applied at staging-settle time on the portal path, not at construction time.
- **Chat scrolls during in-animation.** This is the issue-B win: while contentNode is in the wrapper inside `transitionContainer` (whose frame tracks `frameForVisibleArea()`), chat re-layout naturally re-clips the wrapper's content. The portal mirror reflects the live-clipped state.

## Verification

No unit tests exist in this project. Verification is manual.

1. **Build.** Full project build per CLAUDE.md, with `--continueOnError` to surface a multi-file failure set in one pass.
2. **Issue A — boundary clipping.** Long-press a message at the top of the chat (bubble overlapping nav bar) and at the bottom (overlapping input panel). On `master` the bubble visibly cuts at chat content-area edges during the in/out transition. On this branch the cut should follow the chat's actual ancestor mask shape (no straight-line stutter at the manual-clip rect edge).
3. **Issue B — live source dynamics.** Long-press a message and induce a chat layout change mid-animation (e.g. bring up the keyboard, scroll). The visible bubble's clipping should track the chat's live state, not a stale snapshot.
4. **Reaction context.** Open the reaction context on a message; same in/out paths exercised.
5. **Fallback path.** Long-press in a non-bubble extracted source (the search title accessory panel via `ChatSearchTitleAccessoryPanelNode`, the overlay audio player via `OverlayAudioPlayerControllerNode`, and the navigation button via `ChatMessageNavigationButtonContextExtractedContentSource`). All three pass `sourceTransitionSurface = nil` and should behave identically to today.
6. **`ChatViewOnceMessageContextExtractedContentSource`.** Open a play-once voice/video message context. Stays on fallback; dust-effect dismiss path unchanged.

## Files touched

- `submodules/ContextUI/Sources/ContextController.swift` — two struct field additions.
- `submodules/TelegramUI/Components/ContextControllerImpl/Sources/ContextControllerExtractedPresentationNode.swift` — `PortalTransitionStaging` helper, three integration points, one new field on `ItemContentNode`.
- `submodules/TelegramUI/Sources/ChatMessageContextControllerContentSource.swift` — `sourceTransitionSurface` argument added at four call sites (two `takeView`, two `putBack`, across two source classes).
- `submodules/TelegramUI/Sources/ChatControllerNode.swift` — `contextTransitionContainer` storage, `ensureContextTransitionContainer()`, frame updates within the existing layout pass.

## Risks

- The `_UIPortalView` private-API path is already in production use via `ChatMessageTransitionNode`, so no net new private-API surface.
- The biggest risk is a regression on the fallback path — i.e. accidentally changing behavior for sources that don't pass a `sourceTransitionSurface`. The design preserves today's clip-animation block verbatim, gated only on `portalStaging == nil`. Reviewers should confirm every existing animation call site still fires unchanged when staging is nil.
- Z-order between `transitionContainer` and the chat's chrome elements (input panel, nav, overlay audio bar) needs a per-element visual check at implementation time. Listed under "First adopter" above.
