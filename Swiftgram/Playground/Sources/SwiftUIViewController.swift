import AsyncDisplayKit
import Display
import Foundation
import SwiftUI
import UIKit

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

public protocol SwiftUIView: View {
    var controllerInteraction: SwiftUIViewControllerInteraction? { get set }
    var layout: ContainerViewLayout { get set }
    var navigationHeight: CGFloat { get set }
}

private final class SwiftUIViewControllerNode<Content: SwiftUIView>: ASDisplayNode {
    private let hostingController: UIHostingController<Content>
    private let swiftUINode: ASDisplayNode

    private var isDismissed = false

    private var validLayout: (layout: ContainerViewLayout, navigationHeight: CGFloat)?

    init(swiftUIView: Content) {
        self.hostingController = UIHostingController(rootView: swiftUIView)
        self.swiftUINode = ASDisplayNode { [weak hostingController] in
            hostingController?.view ?? UIView()
        }

        super.init()
        addSubnode(self.swiftUINode)
    }

    func containerLayoutUpdated(
        layout: ContainerViewLayout,
        navigationHeight: CGFloat,
        transition: ContainedViewLayoutTransition
    ) {
        if self.isDismissed {
            return
        }
        
        self.validLayout = (layout, navigationHeight)

        transition.updateFrame(
            node: self.swiftUINode,
            frame: CGRect(
                origin: CGPoint(x: 0, y: navigationHeight),
                size: CGSize(
                    width: layout.size.width,
                    height: layout.size.height - navigationHeight - layout.safeInsets.top
                )
            )
        )
    }

    func animateOut(completion: @escaping () -> Void) {
        guard let (layout, navigationHeight) = validLayout else {
            completion()
            return
        }
        self.isDismissed = true
        let transition: ContainedViewLayoutTransition = .animated(duration: 0.4, curve: .spring)
    
        transition.updateFrame(
            node: self.swiftUINode,
            frame: CGRect(
                origin: CGPoint(x: 0, y: navigationHeight),
                size: CGSize(
                    width: layout.size.width,
                    height: layout.size.height - navigationHeight - layout.safeInsets.top
                )
            )
        )
    }
}

public final class SwiftUIViewController<Content: SwiftUIView>: ViewController {
    private var swiftUIView: Content

    public init(
        _ swiftUIView: Content,
        navigationBarTheme: NavigationBarTheme = NavigationBarTheme(
            buttonColor: ACCENT_COLOR,
            disabledButtonColor: .gray,
            primaryTextColor: .black,
            backgroundColor: .clear,
            enableBackgroundBlur: true,
            separatorColor: .gray,
            badgeBackgroundColor: THEME.navigationBar.badgeBackgroundColor,
            badgeStrokeColor: THEME.navigationBar.badgeStrokeColor,
            badgeTextColor: THEME.navigationBar.badgeTextColor
        ),
        navigationBarStrings: NavigationBarStrings = NavigationBarStrings(
            back: "Back",
            close: "Close"
        )
    ) {
        self.swiftUIView = swiftUIView
        super.init(navigationBarPresentationData: NavigationBarPresentationData(
            theme: navigationBarTheme,
            strings: navigationBarStrings
        ))

        self.swiftUIView.controllerInteraction = SwiftUIViewControllerInteraction(
            push: { [weak self] c in
                guard let strongSelf = self else { return }
                strongSelf.push(c)
            },
            present: { [weak self] c, context, args in
                guard let strongSelf = self else { return }
                strongSelf.present(c, in: context, with: args)
            },
            dismiss: { [weak self] animated, completion in
                guard let strongSelf = self else { return }
                strongSelf.dismiss(animated: animated, completion: completion)
            }
        )
    }

    @available(*, unavailable)
    required init(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func loadDisplayNode() {
        self.displayNode = SwiftUIViewControllerNode<Content>(swiftUIView: swiftUIView)
    }

    override public func containerLayoutUpdated(
        _ layout: ContainerViewLayout,
        transition: ContainedViewLayoutTransition
    ) {
        super.containerLayoutUpdated(layout, transition: transition)

        (self.displayNode as! SwiftUIViewControllerNode<Content>).containerLayoutUpdated(
            layout: layout,
            navigationHeight: navigationLayout(layout: layout).navigationFrame.maxY,
            transition: transition
        )
    }

    public func animateOut(completion: @escaping () -> Void) {
        (self.displayNode as! SwiftUIViewControllerNode<Content>)
            .animateOut(completion: completion)
    }
}

struct MySwiftUIView: SwiftUIView {
    @State var layout: ContainerViewLayout
    @State var navigationHeight: CGFloat
    
    var controllerInteraction: SwiftUIViewControllerInteraction?

    var num: Int64

    var body: some View {
        
        Color.orange
            .ignoresSafeArea()
    }
}

struct CustomButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(8)
            .frame(height: 44) // Set a fixed height for all buttons
    }
}

func mySwiftUIViewController(_ num: Int64) -> ViewController {
    let controller = SwiftUIViewController(MySwiftUIView(num: num))
    controller.title = "Controller: \(num)"
    return controller
}
