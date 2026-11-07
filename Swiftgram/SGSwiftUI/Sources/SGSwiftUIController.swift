import AsyncDisplayKit
import Display
import SwiftSignalKit
import SwiftUI
import TelegramPresentationData
import UIKit

/// Cross-screen navigation has one owner: Telegram. Native SwiftUI sheets keep their own dismiss action.
@available(iOS 15.0, *)
public final class SGSwiftUINavigation: NSObject {
    public private(set) weak var controller: ViewController?

    fileprivate override init() {
        super.init()
    }

    fileprivate func bind(_ controller: ViewController) {
        self.controller = controller
    }

    @objc fileprivate func sgClosePressed() {
        self.dismiss()
    }

    public func push(_ controller: ViewController) {
        self.controller?.push(controller)
    }

    public func push<Content: View>(title: String, @ViewBuilder content: () -> Content) {
        guard let source = self.controller as? SGSwiftUIPresentationSource else { return }
        self.push(SGSwiftUIController(title: title, presentationData: source.sgPresentationData, presentationDataSignal: source.sgPresentationDataSignal, content: content))
    }

    public func present(_ controller: ViewController) {
        self.controller?.present(controller, in: .window(.root), with: ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
    }

    public func present<Content: View>(title: String, @ViewBuilder content: () -> Content) {
        guard let source = self.controller as? SGSwiftUIPresentationSource else { return }
        let destination = SGSwiftUIController(title: title, presentationData: source.sgPresentationData, presentationDataSignal: source.sgPresentationDataSignal, content: content)
        // Telegram's bar dispatches target/action, not UIBarButtonItem.primaryAction.
        destination.navigationItem.setHidesBackButton(true, animated: false)
        destination.navigationBar?.hidesBackButton = true
        destination.navigationItem.rightBarButtonItem = UIBarButtonItem(title: source.sgPresentationData.strings.Common_Close, style: .plain, target: destination.swiftUINavigation, action: #selector(SGSwiftUINavigation.sgClosePressed))
        self.present(destination)
    }

    /// Back/Close applies to this Telegram screen, never an arbitrary inner SwiftUI destination.
    public func dismiss() {
        guard let controller = self.controller else { return }
        let proceed = { [weak controller] in
            guard let controller else { return }
            if controller.presentedViewController != nil {
                controller.dismiss(animated: true, completion: { [weak controller] in controller?.dismiss() })
            } else {
                controller.dismiss()
            }
        }
        if controller.attemptNavigation(proceed) {
            proceed()
        }
    }
}

@available(iOS 15.0, *)
private protocol SGSwiftUIPresentationSource: AnyObject {
    var sgPresentationData: PresentationData { get }
    var sgPresentationDataSignal: Signal<PresentationData, NoError>? { get }
}

@available(iOS 15.0, *)
private struct SGSwiftUINavigationKey: EnvironmentKey {
    static let defaultValue: SGSwiftUINavigation? = nil
}

@available(iOS 15.0, *)
private struct SGSwiftUIVisibleKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

@available(iOS 15.0, *)
public extension EnvironmentValues {
    var sgNavigation: SGSwiftUINavigation? {
        get { self[SGSwiftUINavigationKey.self] }
        set { self[SGSwiftUINavigationKey.self] = newValue }
    }

    /// Telegram screen visibility, distinct from an individual SwiftUI view's onAppear.
    var sgIsVisible: Bool {
        get { self[SGSwiftUIVisibleKey.self] }
        set { self[SGSwiftUIVisibleKey.self] = newValue }
    }
}

@available(iOS 15.0, *)
private struct SGSwiftUITitleKey: PreferenceKey {
    static let defaultValue: String? = nil
    static func reduce(value: inout String?, nextValue: () -> String?) {
        value = nextValue() ?? value
    }
}

@available(iOS 15.0, *)
public extension View {
    /// Native navigationTitle/toolbar configure a native NavigationView, not Telegram's bar.
    func sgNavigationTitle(_ title: String) -> some View {
        self.preference(key: SGSwiftUITitleKey.self, value: title)
    }
}

@available(iOS 15.0, *)
private final class SGSwiftUIScreenState: ObservableObject {
    @Published var layout: ContainerViewLayout?
    @Published var navigationHeight: CGFloat = 0.0
    @Published var isVisible: Bool = false
    @Published var presentationData: PresentationData

    init(presentationData: PresentationData) {
        self.presentationData = presentationData
    }
}

@available(iOS 15.0, *)
private struct SGSwiftUIRoot<Content: View>: View {
    let content: Content
    let navigation: SGSwiftUINavigation
    @ObservedObject var state: SGSwiftUIScreenState

    var body: some View {
        self.content
            .environment(\.sgNavigation, self.navigation)
            .environment(\.sgIsVisible, self.state.isVisible)
            .environment(\.containerViewLayout, self.state.layout)
            .environment(\.navigationBarHeight, self.state.navigationHeight)
            .environment(\.lang, self.state.presentationData.strings.baseLanguageCode)
            .environment(\.locale, Locale(identifier: self.state.presentationData.strings.baseLanguageCode))
            .environment(\.layoutDirection, Locale.characterDirection(forLanguage: self.state.presentationData.strings.baseLanguageCode) == .rightToLeft ? .rightToLeft : .leftToRight)
            .environment(\.colorScheme, self.state.presentationData.theme.overallDarkAppearance ? .dark : .light)
            .accentColor(Color(self.state.presentationData.theme.rootController.navigationBar.accentTextColor))
            .onPreferenceChange(SGSwiftUITitleKey.self) { [weak navigation = self.navigation] title in
                if let title, navigation?.controller?.title != title {
                    navigation?.controller?.title = title
                }
            }
    }
}

@available(iOS 15.0, *)
private final class SGScreenHostingController<Content: View>: UIHostingController<Content> {
    var safeAreaChanged: (() -> Void)?

    // Telegram's global getter falls back through parents to its synthetic navigation controller.
    // Native SwiftUI presentation/dismissal must not discover that owner; cross-screen actions use
    // sgNavigation explicitly. A nested native NavigationView still owns its genuine UIKit stack.
    override var navigationController: UINavigationController? { nil }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        self.safeAreaChanged?()
    }
}

/// A full SwiftUI screen in Telegram navigation. No safe-area swizzling, nested navigation controller,
/// or per-screen padding. The hosting view fills the local container; UIKit owns keyboard avoidance.
@available(iOS 15.0, *)
public final class SGSwiftUIController<Content: View>: ViewController, SGSwiftUIPresentationSource {
    private let state: SGSwiftUIScreenState
    private let hostingController: SGScreenHostingController<SGSwiftUIRoot<Content>>
    public let swiftUINavigation: SGSwiftUINavigation
    private let showsNavigationBar: Bool
    private let ownsNavigation: Bool
    private var presentationDataDisposable: Disposable?
    private var updatingSafeArea: Bool = false
    private var pendingAppearance: Bool?
    public private(set) var sgPresentationData: PresentationData
    public let sgPresentationDataSignal: Signal<PresentationData, NoError>?

    /// Set false only for an isolated native SwiftUI NavigationView/NavigationStack flow. Its inner
    /// Back stays native; outer swipe is disabled. Exit the flow explicitly with sgNavigation.dismiss().
    public init(title: String = "", presentationData: PresentationData, presentationDataSignal: Signal<PresentationData, NoError>? = nil, showsNavigationBar: Bool = true, ownsNavigation: Bool = true, @ViewBuilder content: () -> Content) {
        self.sgPresentationData = presentationData
        self.sgPresentationDataSignal = presentationDataSignal
        self.showsNavigationBar = showsNavigationBar
        self.ownsNavigation = ownsNavigation
        let state = SGSwiftUIScreenState(presentationData: presentationData)
        self.state = state
        let navigation = SGSwiftUINavigation()
        self.swiftUINavigation = navigation
        self.hostingController = SGScreenHostingController(rootView: SGSwiftUIRoot(content: content(), navigation: navigation, state: state))
        super.init(navigationBarPresentationData: showsNavigationBar ? NavigationBarPresentationData(theme: NavigationBarTheme(rootControllerTheme: presentationData.theme), strings: NavigationBarStrings(presentationStrings: presentationData.strings)) : nil)
        self.title = title
        self.displayNavigationBar = showsNavigationBar
        navigation.bind(self)
        self.hostingController.safeAreaChanged = { [weak self] in self?.updateSafeArea() }
        self.applyPresentationData(presentationData)
        if let presentationDataSignal {
            self.presentationDataDisposable = (presentationDataSignal |> deliverOnMainQueue).start(next: { [weak self] data in
                self?.applyPresentationData(data)
            })
        }
    }

    required public init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.presentationDataDisposable?.dispose()
    }

    // Telegram calls screen appearance methods itself. Forward once using UIKit's containment API.
    override public var shouldAutomaticallyForwardAppearanceMethods: Bool { false }

    override public func loadDisplayNode() {
        self.displayNode = ViewControllerTracingNode()
        self.displayNode.backgroundColor = self.sgPresentationData.theme.list.blocksBackgroundColor
        self.displayNodeDidLoad()
        self.addChild(self.hostingController)
        let hostView = self.hostingController.view!
        hostView.backgroundColor = .clear
        // Telegram updates its node's bounds and the child's frame independently during transitions.
        // Autoresizing here would apply the same size delta twice (especially on modal entry).
        hostView.autoresizingMask = []
        self.displayNode.view.insertSubview(hostView, at: 0)
        hostView.frame = self.displayNode.bounds
        self.hostingController.didMove(toParent: self)
        if !self.ownsNavigation {
            // The boolean flag only disables center swipes; the dynamic flag also disables edges.
            self.displayNode.view.disablesInteractiveTransitionGestureRecognizerNow = { true }
        }
    }

    override public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        let navigationHeight: CGFloat = self.showsNavigationBar && self.displayNavigationBar ? self.navigationLayout(layout: layout).navigationFrame.maxY : 0.0
        if self.state.layout != layout { self.state.layout = layout }
        if self.state.navigationHeight != navigationHeight { self.state.navigationHeight = navigationHeight }
        transition.updateFrame(view: self.hostingController.view, frame: CGRect(origin: .zero, size: layout.size))
        self.updateSafeArea()
        self.hostingController.view.setNeedsLayout()
    }

    override public func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // A layout update can precede the navigation container's final bounds assignment.
        // Reconcile here too, with no autoresizing-mask second adjustment.
        if let layout = self.currentlyAppliedLayout {
            let frame = CGRect(origin: CGPoint.zero, size: layout.size)
            if self.hostingController.view.frame != frame { self.hostingController.view.frame = frame }
        }
        self.updateSafeArea()
    }

    private func updateSafeArea() {
        guard !self.updatingSafeArea, let layout = self.currentlyAppliedLayout, self.hostingController.isViewLoaded else { return }
        self.updatingSafeArea = true
        defer { self.updatingSafeArea = false }
        let host = self.hostingController
        let current = host.view.safeAreaInsets
        let additional = host.additionalSafeAreaInsets
        // Subtract only our own additions. Preserve larger native device reservations; never count
        // notch/home indicator twice. No keyboard inputHeight here: SwiftUI already handles it.
        let target = UIEdgeInsets(
            top: max(layout.intrinsicInsets.top + layout.safeInsets.top, max(layout.statusBarHeight ?? 0.0, self.state.navigationHeight)),
            left: max(layout.intrinsicInsets.left + layout.safeInsets.left, layout.additionalInsets.left),
            bottom: layout.intrinsicInsets.bottom + layout.safeInsets.bottom,
            right: max(layout.intrinsicInsets.right + layout.safeInsets.right, layout.additionalInsets.right)
        )
        let updated = UIEdgeInsets(
            top: max(0.0, target.top - max(0.0, current.top - additional.top)),
            left: max(0.0, target.left - max(0.0, current.left - additional.left)),
            bottom: max(0.0, target.bottom - max(0.0, current.bottom - additional.bottom)),
            right: max(0.0, target.right - max(0.0, current.right - additional.right))
        )
        if updated != additional { host.additionalSafeAreaInsets = updated }
    }

    private func applyPresentationData(_ data: PresentationData) {
        self.sgPresentationData = data
        if self.state.presentationData != data { self.state.presentationData = data }
        self.setStatusBarStyle(data.theme.rootController.statusBarStyle.style, animated: false)
        self.hostingController.overrideUserInterfaceStyle = data.theme.overallDarkAppearance ? .dark : .light
        if self.showsNavigationBar {
            self.setNavigationBarPresentationData(NavigationBarPresentationData(theme: NavigationBarTheme(rootControllerTheme: data.theme), strings: NavigationBarStrings(presentationStrings: data.strings)), animated: false)
        }
        if self.isNodeLoaded { self.displayNode.backgroundColor = data.theme.list.blocksBackgroundColor }
    }

    private func beginAppearance(_ appearing: Bool, animated: Bool) {
        guard !self.ignoreAppearanceMethodInvocations(), self.pendingAppearance != appearing else { return }
        // beginAppearanceTransition supports reversals (including a cancelled interactive pop).
        self.hostingController.beginAppearanceTransition(appearing, animated: animated)
        self.pendingAppearance = appearing
    }

    private func endAppearance(_ appearing: Bool, animated: Bool) {
        if let pendingAppearance = self.pendingAppearance {
            // A cancelled Telegram swipe sends the final did callback without reversing will.
            // Reverse UIKit's in-flight transition before ending it, for both involved screens.
            if pendingAppearance != appearing {
                self.hostingController.beginAppearanceTransition(appearing, animated: animated)
            }
            self.hostingController.endAppearanceTransition()
            self.pendingAppearance = nil
        }
        if self.state.isVisible != appearing { self.state.isVisible = appearing }
    }

    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.beginAppearance(true, animated: animated)
    }

    override public func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.beginAppearance(false, animated: animated)
    }

    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !self.ignoreAppearanceMethodInvocations() else { return }
        self.endAppearance(true, animated: animated)
    }

    override public func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard !self.ignoreAppearanceMethodInvocations() else { return }
        self.endAppearance(false, animated: animated)
    }

    override public func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        if self.presentedViewController != nil {
            // UIKit promotes a child's native sheet presentation to this container. SwiftUI then
            // dismisses the presenter; Display.ViewController's override would pop this Telegram
            // screen instead. Invoke the public UIKit base implementation for native presentations
            // only (Swift cannot express a super call that skips Display.ViewController).
            let selector = #selector(UIViewController.dismiss(animated:completion:))
            typealias NativeDismiss = @convention(c) (UIViewController, Selector, Bool, (@convention(block) () -> Void)?) -> Void
            let implementation = class_getMethodImplementation(UIViewController.self, selector)!
            let dismiss = unsafeBitCast(implementation, to: NativeDismiss.self)
            let block: @convention(block) () -> Void = { completion?() }
            dismiss(self, selector, flag, block)
        } else {
            super.dismiss(animated: flag, completion: completion)
        }
    }
}
