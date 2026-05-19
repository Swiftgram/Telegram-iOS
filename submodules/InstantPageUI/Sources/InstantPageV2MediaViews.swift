import Foundation
import UIKit
import AsyncDisplayKit
import Display
import SwiftSignalKit
import AccountContext
import TelegramCore
import TelegramPresentationData
import GalleryUI

// Mutable weak box: lets a wrapper hand its `openMedia` closure a back-reference to itself,
// filled in after `super.init` (when `self` becomes usable). SwiftSignalKit's `Weak<T>` requires
// a non-optional value at init time, so it can't be used here.
private final class WrapperRef {
    weak var view: UIView?
}

// MARK: - Shared media node factory

// Hosts a V1 `InstantPageImageNode` inside a V2 UIView wrapper. The caller sizes its own
// frame from `item.frame` and adds the returned node's view as a subview.
private func makeMediaWrapper(
    frame: CGRect,
    media: InstantPageMedia,
    webPage: TelegramMediaWebpage,
    attributes: [InstantPageImageAttribute],
    renderContext: InstantPageV2RenderContext,
    theme: InstantPageTheme,
    openMedia: @escaping (InstantPageMedia) -> Void,
    longPressMedia: @escaping (InstantPageMedia) -> Void
) -> InstantPageImageNode {
    let imageNode = InstantPageImageNode(
        context: renderContext.context,
        sourceLocation: renderContext.sourceLocation,
        theme: theme,
        webPage: webPage,
        media: media,
        attributes: attributes,
        interactive: true,
        roundCorners: false,
        fit: false,
        openMedia: openMedia,
        longPressMedia: longPressMedia,
        activatePinchPreview: nil,
        pinchPreviewFinished: nil,
        imageReferenceForMedia: renderContext.imageReference,
        fileReferenceForMedia: renderContext.fileReference,
        getPreloadedResource: { _ in nil }
    )
    imageNode.frame = CGRect(origin: .zero, size: frame.size)
    return imageNode
}

// Walks up the superview chain from `start` to find the nearest enclosing `InstantPageV2View`.
private func findEnclosingV2View(from start: UIView?) -> InstantPageV2View? {
    var view: UIView? = start
    while view != nil {
        if let v2 = view as? InstantPageV2View {
            return v2
        }
        view = view?.superview
    }
    return nil
}

// Registers `wrapper` in the root V2View's `mediaRegistry` under `mediaIndex`. The root is
// reached by walking up the superview chain to the nearest `InstantPageV2View`, then walking
// its `rootMediaRegistryHost` chain transitively (nested details blocks can leave an inner
// body's host pointing at an intermediate body — see `trueRegistryRoot`). No-op if the wrapper
// isn't yet attached to a V2View ancestor.
private func registerInRootRegistry(wrapper: UIView, mediaIndex: Int) {
    guard let v2 = findEnclosingV2View(from: wrapper.superview) else { return }
    v2.trueRegistryRoot.mediaRegistry[mediaIndex] = Weak(wrapper)
}

// Routes a tap on `tapped` through `openInstantPageMedia`, sourcing sibling medias from the
// root V2View's `currentLayout`. No-op if the wrapper isn't currently in a V2View tree.
private func handleOpenMediaTap(
    tapped: InstantPageMedia,
    wrapper: UIView,
    renderContext: InstantPageV2RenderContext
) {
    guard let v2 = findEnclosingV2View(from: wrapper.superview) else { return }
    let root = v2.trueRegistryRoot
    guard let layout = root.currentLayout else { return }
    openInstantPageMedia(
        media: tapped,
        allMedias: layout.allMedias(),
        webPage: renderContext.webpage,
        context: renderContext.context,
        userLocation: renderContext.sourceLocation.userLocation,
        present: renderContext.present,
        push: renderContext.push,
        openUrl: renderContext.openUrl,
        baseNavigationController: renderContext.baseNavigationController,
        transitionArgsForMedia: { [weak root] tappedSibling -> GalleryTransitionArguments? in
            guard let root else { return nil }
            return root.transitionArgsFor(tappedSibling, addToTransitionSurface: { [weak root] view in
                root?.superview?.addSubview(view)
            })
        },
        hiddenMediaCallback: { [weak root] hidden in
            root?.applyHiddenMedia(hidden)
        }
    )
}

// MARK: - Concrete wrapper classes

final class InstantPageV2MediaImageView: UIView, InstantPageItemView {
    private(set) var item: InstantPageV2MediaImageItem
    var itemFrame: CGRect { return self.item.frame }
    let wrappedNode: InstantPageImageNode

    init(item: InstantPageV2MediaImageItem, renderContext: InstantPageV2RenderContext, theme: InstantPageTheme) {
        self.item = item

        // The tap closure can't capture `[weak self]` before `super.init`, so we route through
        // a `WrapperRef` box that gets filled in after `super.init`. The box's weak storage
        // breaks the wrapper → wrappedNode → closure → wrapper retain cycle that would otherwise
        // form (the wrapper owns wrappedNode, which owns the closure, which holds the wrapper).
        let wrapperRef = WrapperRef()
        let renderContextRef = renderContext
        let openMedia: (InstantPageMedia) -> Void = { tapped in
            guard let wrapper = wrapperRef.view else { return }
            handleOpenMediaTap(tapped: tapped, wrapper: wrapper, renderContext: renderContextRef)
        }
        self.wrappedNode = makeMediaWrapper(
            frame: item.frame,
            media: item.media,
            webPage: item.webPage,
            attributes: item.attributes,
            renderContext: renderContext,
            theme: theme,
            openMedia: openMedia,
            longPressMedia: { _ in }
        )

        super.init(frame: item.frame)
        self.backgroundColor = .clear
        self.layer.cornerRadius = item.cornerRadius
        self.clipsToBounds = item.cornerRadius > 0.0
        self.addSubview(self.wrappedNode.view)
        wrapperRef.view = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard self.window != nil else { return }
        registerInRootRegistry(wrapper: self, mediaIndex: self.item.media.index)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        self.wrappedNode.frame = self.bounds
    }

    func update(item: InstantPageV2MediaImageItem, theme: InstantPageTheme, renderContext: InstantPageV2RenderContext) {
        self.item = item
        self.layer.cornerRadius = item.cornerRadius
        self.clipsToBounds = item.cornerRadius > 0.0
        let strings = renderContext.context.sharedContext.currentPresentationData.with { $0 }.strings
        self.wrappedNode.update(strings: strings, theme: theme)
    }
}

final class InstantPageV2MediaVideoView: UIView, InstantPageItemView {
    private(set) var item: InstantPageV2MediaVideoItem
    var itemFrame: CGRect { return self.item.frame }
    let wrappedNode: InstantPageImageNode

    init(item: InstantPageV2MediaVideoItem, renderContext: InstantPageV2RenderContext, theme: InstantPageTheme) {
        self.item = item

        let wrapperRef = WrapperRef()
        let renderContextRef = renderContext
        let openMedia: (InstantPageMedia) -> Void = { tapped in
            guard let wrapper = wrapperRef.view else { return }
            handleOpenMediaTap(tapped: tapped, wrapper: wrapper, renderContext: renderContextRef)
        }
        self.wrappedNode = makeMediaWrapper(
            frame: item.frame,
            media: item.media,
            webPage: item.webPage,
            attributes: item.attributes,
            renderContext: renderContext,
            theme: theme,
            openMedia: openMedia,
            longPressMedia: { _ in }
        )

        super.init(frame: item.frame)
        self.backgroundColor = .clear
        self.layer.cornerRadius = item.cornerRadius
        self.clipsToBounds = item.cornerRadius > 0.0
        self.addSubview(self.wrappedNode.view)
        wrapperRef.view = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard self.window != nil else { return }
        registerInRootRegistry(wrapper: self, mediaIndex: self.item.media.index)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        self.wrappedNode.frame = self.bounds
    }

    func update(item: InstantPageV2MediaVideoItem, theme: InstantPageTheme, renderContext: InstantPageV2RenderContext) {
        self.item = item
        self.layer.cornerRadius = item.cornerRadius
        self.clipsToBounds = item.cornerRadius > 0.0
        let strings = renderContext.context.sharedContext.currentPresentationData.with { $0 }.strings
        self.wrappedNode.update(strings: strings, theme: theme)
    }
}

final class InstantPageV2MediaMapView: UIView, InstantPageItemView {
    private(set) var item: InstantPageV2MediaMapItem
    var itemFrame: CGRect { return self.item.frame }
    let wrappedNode: InstantPageImageNode

    init(item: InstantPageV2MediaMapItem, renderContext: InstantPageV2RenderContext, theme: InstantPageTheme) {
        self.item = item

        let wrapperRef = WrapperRef()
        let renderContextRef = renderContext
        let openMedia: (InstantPageMedia) -> Void = { tapped in
            guard let wrapper = wrapperRef.view else { return }
            handleOpenMediaTap(tapped: tapped, wrapper: wrapper, renderContext: renderContextRef)
        }
        self.wrappedNode = makeMediaWrapper(
            frame: item.frame,
            media: item.media,
            webPage: item.webPage,
            attributes: item.attributes,
            renderContext: renderContext,
            theme: theme,
            openMedia: openMedia,
            longPressMedia: { _ in }
        )

        super.init(frame: item.frame)
        self.backgroundColor = .clear
        self.layer.cornerRadius = item.cornerRadius
        self.clipsToBounds = item.cornerRadius > 0.0
        self.addSubview(self.wrappedNode.view)
        wrapperRef.view = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard self.window != nil else { return }
        registerInRootRegistry(wrapper: self, mediaIndex: self.item.media.index)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        self.wrappedNode.frame = self.bounds
    }

    func update(item: InstantPageV2MediaMapItem, theme: InstantPageTheme, renderContext: InstantPageV2RenderContext) {
        self.item = item
        self.layer.cornerRadius = item.cornerRadius
        self.clipsToBounds = item.cornerRadius > 0.0
        let strings = renderContext.context.sharedContext.currentPresentationData.with { $0 }.strings
        self.wrappedNode.update(strings: strings, theme: theme)
    }
}

final class InstantPageV2MediaCoverImageView: UIView, InstantPageItemView {
    private(set) var item: InstantPageV2MediaCoverImageItem
    var itemFrame: CGRect { return self.item.frame }
    let wrappedNode: InstantPageImageNode

    init(item: InstantPageV2MediaCoverImageItem, renderContext: InstantPageV2RenderContext, theme: InstantPageTheme) {
        self.item = item

        let wrapperRef = WrapperRef()
        let renderContextRef = renderContext
        let openMedia: (InstantPageMedia) -> Void = { tapped in
            guard let wrapper = wrapperRef.view else { return }
            handleOpenMediaTap(tapped: tapped, wrapper: wrapper, renderContext: renderContextRef)
        }
        self.wrappedNode = makeMediaWrapper(
            frame: item.frame,
            media: item.media,
            webPage: item.webPage,
            attributes: item.attributes,
            renderContext: renderContext,
            theme: theme,
            openMedia: openMedia,
            longPressMedia: { _ in }
        )

        super.init(frame: item.frame)
        self.backgroundColor = .clear
        self.layer.cornerRadius = item.cornerRadius
        self.clipsToBounds = item.cornerRadius > 0.0
        self.addSubview(self.wrappedNode.view)
        wrapperRef.view = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard self.window != nil else { return }
        registerInRootRegistry(wrapper: self, mediaIndex: self.item.media.index)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        self.wrappedNode.frame = self.bounds
    }

    func update(item: InstantPageV2MediaCoverImageItem, theme: InstantPageTheme, renderContext: InstantPageV2RenderContext) {
        self.item = item
        self.layer.cornerRadius = item.cornerRadius
        self.clipsToBounds = item.cornerRadius > 0.0
        let strings = renderContext.context.sharedContext.currentPresentationData.with { $0 }.strings
        self.wrappedNode.update(strings: strings, theme: theme)
    }
}
