import Display
import Foundation
import LegacyUI
import SwiftUI
import TelegramPresentationData


@available(iOS 13.0, *)
public class ObservedValue<T>: ObservableObject {
    @Published var value: T

    init(_ value: T) {
        self.value = value
    }
}

@available(iOS 13.0, *)
public struct SGSwiftUIView<Content: View>: View {
    public let content: Content

    @ObservedObject var navigationBarHeight: ObservedValue<CGFloat>
    @ObservedObject var containerViewLayout: ObservedValue<ContainerViewLayout?>

    public init(
        navigationBarHeight: ObservedValue<CGFloat>,
        containerViewLayout: ObservedValue<ContainerViewLayout?>,
        @ViewBuilder content: () -> Content
    ) {
        self.navigationBarHeight = navigationBarHeight
        self.containerViewLayout = containerViewLayout
        self.content = content()
    }

    public var body: some View {
        content
            .modifier(CustomSafeAreaPadding(navigationBarHeight: navigationBarHeight, containerViewLayout: containerViewLayout))
    }
}

@available(iOS 13.0, *)
public struct CustomSafeAreaPadding: ViewModifier {
    @ObservedObject var navigationBarHeight: ObservedValue<CGFloat>
    @ObservedObject var containerViewLayout: ObservedValue<ContainerViewLayout?>

    public func body(content: Content) -> some View {
        content
            .edgesIgnoringSafeArea(.all)
//            .padding(.top, /*totalTopSafeArea > navigationBarHeight.value ? totalTopSafeArea :*/ navigationBarHeight.value)
            .padding(.top, totalTopSafeArea > navigationBarHeight.value ? totalTopSafeArea : navigationBarHeight.value)
            .padding(.bottom, (containerViewLayout.value?.safeInsets.bottom ?? 0) /*+ (containerViewLayout.value?.intrinsicInsets.bottom ?? 0)*/)
            .padding(.leading, containerViewLayout.value?.safeInsets.left ?? 0)
            .padding(.trailing, containerViewLayout.value?.safeInsets.right ?? 0)
    }

    var totalTopSafeArea: CGFloat {
        (containerViewLayout.value?.safeInsets.top ?? 0) +
            (containerViewLayout.value?.intrinsicInsets.top ?? 0)
    }
}

@available(iOS 13.0, *)
public final class LegacySwiftUIController: LegacyController {
    public var navigationBarHeightModel: ObservedValue<CGFloat>
    public var containerViewLayoutModel: ObservedValue<ContainerViewLayout?>

    override public init(presentation: LegacyControllerPresentation, theme: PresentationTheme? = nil, strings: PresentationStrings? = nil, initialLayout: ContainerViewLayout? = nil) {
        navigationBarHeightModel = ObservedValue<CGFloat>(0.0)
        containerViewLayoutModel = ObservedValue<ContainerViewLayout?>(initialLayout)
        super.init(presentation: presentation, theme: theme, strings: strings, initialLayout: initialLayout)
    }

    override public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)

        var newNavigationBarHeight = navigationLayout(layout: layout).navigationFrame.maxY
        if !self.displayNavigationBar {
            newNavigationBarHeight = 0.0
        }
        if navigationBarHeightModel.value != newNavigationBarHeight {
            navigationBarHeightModel.value = newNavigationBarHeight
        }
        if containerViewLayoutModel.value != layout {
            containerViewLayoutModel.value = layout
        }
    }

    override public func bind(controller: UIViewController) {
        super.bind(controller: controller)
        addChild(legacyController)
        legacyController.didMove(toParent: legacyController)
    }

    @available(*, unavailable)
    public required init(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@available(iOS 13.0, *)
extension UIHostingController {
    public convenience init(rootView: Content, ignoreSafeArea: Bool) {
        self.init(rootView: rootView)

        if ignoreSafeArea {
            disableSafeArea()
        }
    }

    func disableSafeArea() {
        guard let viewClass = object_getClass(view) else {
            return
        }

        func encodeText(string: String, key: Int16) -> String {
            let nsString = string as NSString
            let result = NSMutableString()
            for i in 0 ..< nsString.length {
                var c: unichar = nsString.character(at: i)
                c = unichar(Int16(c) + key)
                result.append(NSString(characters: &c, length: 1) as String)
            }
            return result as String
        }

        let viewSubclassName = String(cString: class_getName(viewClass)).appending(encodeText(string: "`JhopsfTbgfBsfb", key: -1))

        if let viewSubclass = NSClassFromString(viewSubclassName) {
            object_setClass(view, viewSubclass)
        } else {
            guard
                let viewClassNameUtf8 = (viewSubclassName as NSString).utf8String,
                let viewSubclass = objc_allocateClassPair(viewClass, viewClassNameUtf8, 0)
            else {
                return
            }

            if let method = class_getInstanceMethod(UIView.self, #selector(getter: UIView.safeAreaInsets)) {
                let safeAreaInsets: @convention(block) (AnyObject) -> UIEdgeInsets = { _ in
                    .zero
                }

                class_addMethod(
                    viewSubclass,
                    #selector(getter: UIView.safeAreaInsets),
                    imp_implementationWithBlock(safeAreaInsets),
                    method_getTypeEncoding(method)
                )
            }

            objc_registerClassPair(viewSubclass)
            object_setClass(view, viewSubclass)
        }
    }
}
