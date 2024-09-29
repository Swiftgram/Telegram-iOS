import AsyncDisplayKit
import Display
import Foundation
import SwiftUI
import UIKit
import LegacyUI
import TelegramPresentationData

public class SwiftUIViewControllerInteraction {
    let push: (ViewController) -> Void
    let present: (
        _ controller: ViewController,
        _ in: PresentationContextType,
        _ with: ViewControllerPresentationArguments?
    ) -> Void
    let dismiss: (_ animated: Bool, _ completion: (() -> Void)?) -> Void

    init(
        push: @escaping (ViewController) -> Void,
        present: @escaping (
            _ controller: ViewController,
            _ in: PresentationContextType,
            _ with: ViewControllerPresentationArguments?
        ) -> Void,
        dismiss: @escaping (_ animated: Bool, _ completion: (() -> Void)?) -> Void
    ) {
        self.push = push
        self.present = present
        self.dismiss = dismiss
    }
}
//
//public protocol SwiftUIView: View {
//    var controllerInteraction: SwiftUIViewControllerInteraction? { get set }
//}
//
//struct MySwiftUIView: SwiftUIView {
//    var controllerInteraction: SwiftUIViewControllerInteraction?
//    
//    
//    var num: Int64
//
//    var body: some View {
//        Color.orange
//    }
//}
//
//struct CustomButtonStyle: ButtonStyle {
//    func makeBody(configuration: Configuration) -> some View {
//        configuration.label
//            .padding()
//            .background(Color.blue)
//            .foregroundColor(.white)
//            .cornerRadius(8)
//            .frame(height: 44) // Set a fixed height for all buttons
//    }
//}
//
//private final class SwiftUIViewControllerNode<Content: SwiftUIView>: ASDisplayNode {
//    private let hostingController: UIHostingController<Content>
//    private var isDismissed = false
//    private var validLayout: (layout: ContainerViewLayout, navigationHeight: CGFloat)?
//
//    init(swiftUIView: Content) {
//        self.hostingController = UIHostingController(rootView: swiftUIView)
//        super.init()
//        
//        // For debugging
//        self.backgroundColor = .red.withAlphaComponent(0.3)
//        hostingController.view.backgroundColor = .blue.withAlphaComponent(0.3)
//    }
//
//    override func didLoad() {
//        super.didLoad()
//        
//        // Defer the setup to ensure we have a valid view controller hierarchy
//        DispatchQueue.main.async { [weak self] in
//            self?.setupHostingController()
//        }
//    }
//
//    private func setupHostingController() {
//        guard let viewController = findViewController() else {
//            assert(true, "Error: Could not find a parent view controller")
//            return
//        }
//        
//        viewController.addChild(hostingController)
//        view.addSubview(hostingController.view)
//        hostingController.didMove(toParent: viewController)
//        
//        // Ensure the hosting controller's view has a size
//        hostingController.view.frame = self.bounds
//        
//        print("SwiftUIViewControllerNode setup - Node frame: \(self.frame), Hosting view frame: \(hostingController.view.frame)")
//    }
//
//    private func findViewController() -> UIViewController? {
//        var responder: UIResponder? = self.view
//        while let nextResponder = responder?.next {
//            if let viewController = nextResponder as? UIViewController {
//                return viewController
//            }
//            responder = nextResponder
//        }
//        return nil
//    }
//
//    override func layout() {
//        super.layout()
//        hostingController.view.frame = self.bounds
//        print("SwiftUIViewControllerNode layout - Node frame: \(self.frame), Hosting view frame: \(hostingController.view.frame)")
//    }
//
//    func containerLayoutUpdated(
//        layout: ContainerViewLayout,
//        navigationHeight: CGFloat,
//        transition: ContainedViewLayoutTransition
//    ) {
//        if self.isDismissed {
//            return
//        }
//        
//        self.validLayout = (layout, navigationHeight)
//
//        let frame = CGRect(
//            origin: CGPoint(x: 0, y: 0),
//            size: CGSize(
//                width: layout.size.width,
//                height: layout.size.height
//            )
//        )
//
//        transition.updateFrame(node: self, frame: frame)
//        
//        print("containerLayoutUpdated - New frame: \(frame)")
//        
//        // Ensure hosting controller view is updated
//        hostingController.view.frame = bounds
//    }
//
//    func animateOut(completion: @escaping () -> Void) {
//        guard let (layout, navigationHeight) = validLayout else {
//            completion()
//            return
//        }
//        self.isDismissed = true
//        let transition: ContainedViewLayoutTransition = .animated(duration: 0.4, curve: .spring)
//    
//        let frame = CGRect(
//            origin: CGPoint(x: 0, y: 0),
//            size: CGSize(
//                width: layout.size.width,
//                height: layout.size.height
//            )
//        )
//
//        transition.updateFrame(node: self, frame: frame, completion: { _ in
//            completion()
//        })
//    }
//    
//    override func didEnterHierarchy() {
//        super.didEnterHierarchy()
//        print("SwiftUIViewControllerNode entered hierarchy")
//    }
//    
//    override func didExitHierarchy() {
//        super.didExitHierarchy()
//        hostingController.willMove(toParent: nil)
//        hostingController.view.removeFromSuperview()
//        hostingController.removeFromParent()
//        print("SwiftUIViewControllerNode exited hierarchy")
//    }
//}
//
//public final class SwiftUIViewController<Content: SwiftUIView>: ViewController {
//    private var swiftUIView: Content
//
//    public init(
//        _ swiftUIView: Content,
//        navigationBarTheme: NavigationBarTheme = NavigationBarTheme(
//            buttonColor: ACCENT_COLOR,
//            disabledButtonColor: .gray,
//            primaryTextColor: .black,
//            backgroundColor: .clear,
//            enableBackgroundBlur: true,
//            separatorColor: .gray,
//            badgeBackgroundColor: THEME.navigationBar.badgeBackgroundColor,
//            badgeStrokeColor: THEME.navigationBar.badgeStrokeColor,
//            badgeTextColor: THEME.navigationBar.badgeTextColor
//        ),
//        navigationBarStrings: NavigationBarStrings = NavigationBarStrings(
//            back: "Back",
//            close: "Close"
//        )
//    ) {
//        self.swiftUIView = swiftUIView
//        super.init(navigationBarPresentationData: NavigationBarPresentationData(
//            theme: navigationBarTheme,
//            strings: navigationBarStrings
//        ))
//
//        self.swiftUIView.controllerInteraction = SwiftUIViewControllerInteraction(
//            push: { [weak self] c in
//                guard let strongSelf = self else { return }
//                strongSelf.push(c)
//            },
//            present: { [weak self] c, context, args in
//                guard let strongSelf = self else { return }
//                strongSelf.present(c, in: context, with: args)
//            },
//            dismiss: { [weak self] animated, completion in
//                guard let strongSelf = self else { return }
//                strongSelf.dismiss(animated: animated, completion: completion)
//            }
//        )
//    }
//
//    @available(*, unavailable)
//    required init(coder _: NSCoder) {
//        fatalError("init(coder:) has not been implemented")
//    }
//
//    override public func loadDisplayNode() {
//        self.displayNode = SwiftUIViewControllerNode<Content>(swiftUIView: swiftUIView)
//    }
//
//    override public func containerLayoutUpdated(
//        _ layout: ContainerViewLayout,
//        transition: ContainedViewLayoutTransition
//    ) {
//        super.containerLayoutUpdated(layout, transition: transition)
//
//        (self.displayNode as! SwiftUIViewControllerNode<Content>).containerLayoutUpdated(
//            layout: layout,
//            navigationHeight: navigationLayout(layout: layout).navigationFrame.maxY,
//            transition: transition
//        )
//    }
//
//    public func animateOut(completion: @escaping () -> Void) {
//        (self.displayNode as! SwiftUIViewControllerNode<Content>)
//            .animateOut(completion: completion)
//    }
//}
//
//
//func mySwiftUIViewController(_ num: Int64) -> ViewController {
//    let controller = SwiftUIViewController(MySwiftUIView(num: num))
//    controller.title = "Controller: \(num)"
//    return controller
//}


public protocol SwiftUIView: View {
    var controllerInteraction: SwiftUIViewControllerInteraction? { get set }
}

struct MySwiftUIView: SwiftUIView {
    var controllerInteraction: SwiftUIViewControllerInteraction?

    var num: Int64

    var body: some View {
        Color.orange
//        VStack {
//            Button("Push") {
//                self.controllerInteraction?.push(mySwiftUIViewController(num + 1))
//            }
//            Button("Modal") {
//                self.controllerInteraction?.present(mySwiftUIViewController(num + 1), .window(.root), ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
//            }
//            Button("Dismiss") {
//                self.controllerInteraction?.dismiss(true, {})
//            }
//        }
    }
}

func mySwiftUIViewController(_ num: Int64) -> ViewController {
    let legacyController = LegacyController(presentation: .navigation, theme: defaultPresentationTheme, strings: defaultPresentationStrings)
    legacyController.statusBar.statusBarStyle = defaultPresentationTheme.rootController.statusBarStyle.style
    legacyController.title = "Controller: root"
    
    let controller = UIHostingController(rootView: MySwiftUIView(num: num))
    legacyController.bind(controller: controller)
    legacyController.addChild(controller)
    controller.didMove(toParent: legacyController)
    
    
    return legacyController
}
