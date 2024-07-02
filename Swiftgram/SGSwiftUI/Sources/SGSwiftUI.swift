import Display
import Foundation
import LegacyUI
import SwiftUI
import TelegramPresentationData


@available(iOS 13.0, *)
public class ObservedValue<T>: ObservableObject {
    @Published public var value: T

    public init(_ value: T) {
        self.value = value
    }
}

@available(iOS 13.0, *)
public struct NavigationBarHeightKey: EnvironmentKey {
    public static let defaultValue: CGFloat = 0
}

@available(iOS 13.0, *)
public struct ContainerViewLayoutKey: EnvironmentKey {
    public static let defaultValue: ContainerViewLayout? = nil
}

@available(iOS 13.0, *)
public struct LangKey: EnvironmentKey {
    public static let defaultValue: String = "en"
}

// Perhaps, affects Performance a lot
//@available(iOS 13.0, *)
//public struct ContainerViewLayoutUpdateCountKey: EnvironmentKey {
//    public static let defaultValue: ObservedValue<Int64> = ObservedValue(0)
//}

@available(iOS 13.0, *)
public extension EnvironmentValues {
    var navigationBarHeight: CGFloat {
        get { self[NavigationBarHeightKey.self] }
        set { self[NavigationBarHeightKey.self] = newValue }
    }
    
    var containerViewLayout: ContainerViewLayout? {
        get { self[ContainerViewLayoutKey.self] }
        set { self[ContainerViewLayoutKey.self] = newValue }
    }

    var lang: String {
        get { self[LangKey.self] }
        set { self[LangKey.self] = newValue }
    }
    
//    var containerViewLayoutUpdateCount: ObservedValue<Int64> {
//        get { self[ContainerViewLayoutUpdateCountKey.self] }
//        set { self[ContainerViewLayoutUpdateCountKey.self] = newValue }
//    }
}


@available(iOS 13.0, *)
public struct SGSwiftUIView<Content: View>: View {
    public let content: Content
    public let manageSafeArea: Bool

    @ObservedObject var navigationBarHeight: ObservedValue<CGFloat>
    @ObservedObject var containerViewLayout: ObservedValue<ContainerViewLayout?>
//    @ObservedObject var containerViewLayoutUpdateCount: ObservedValue<Int64>

    private var lang: String
    
    public init(
        legacyController: LegacySwiftUIController,
        manageSafeArea: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        #if DEBUG
        if manageSafeArea {
            print("WARNING SGSwiftUIView: manageSafeArea is deprecated, use @Environment(\\.navigationBarHeight) and @Environment(\\.containerViewLayout)")
        }
        #endif
        self.navigationBarHeight = legacyController.navigationBarHeightModel
        self.containerViewLayout = legacyController.containerViewLayoutModel
        self.lang = legacyController.lang
//        self.containerViewLayoutUpdateCount = legacyController.containerViewLayoutUpdateCountModel
        self.manageSafeArea = manageSafeArea
        self.content = content()
    }

    public var body: some View {
        content
            .if(manageSafeArea) { $0.modifier(CustomSafeArea()) }
            .environment(\.navigationBarHeight, navigationBarHeight.value)
            .environment(\.containerViewLayout, containerViewLayout.value)
            .environment(\.lang, lang)
//            .environment(\.containerViewLayoutUpdateCount, containerViewLayoutUpdateCount)
//            .onReceive(containerViewLayoutUpdateCount.$value) { _ in
//                // Make sure View is updated when containerViewLayoutUpdateCount changes,
//                // in case it does not depend on containerViewLayout
//            }
    }
    
}

@available(iOS 13.0, *)
public struct CustomSafeArea: ViewModifier {
    @Environment(\.navigationBarHeight) var navigationBarHeight: CGFloat
    @Environment(\.containerViewLayout) var containerViewLayout: ContainerViewLayout?

    public func body(content: Content) -> some View {
        content
            .edgesIgnoringSafeArea(.all)
//            .padding(.top, /*totalTopSafeArea > navigationBarHeight.value ? totalTopSafeArea :*/ navigationBarHeight.value)
            .padding(.top, topInset)
            .padding(.bottom, bottomInset)
            .padding(.leading, leftInset)
            .padding(.trailing, rightInset)
    }

    private var topInset: CGFloat {
        max(
            (containerViewLayout?.safeInsets.top ?? 0) + (containerViewLayout?.intrinsicInsets.top ?? 0),
            navigationBarHeight
        )
    }
    
    private var bottomInset: CGFloat {
        (containerViewLayout?.safeInsets.bottom ?? 0)
// DEPRECATED, do not change
//        + (containerViewLayout.value?.intrinsicInsets.bottom ?? 0)
    }
    
    private var leftInset: CGFloat {
        containerViewLayout?.safeInsets.left ?? 0
    }
    
    private var rightInset: CGFloat {
        containerViewLayout?.safeInsets.right ?? 0
    }
}

@available(iOS 13.0, *)
public extension View {
    func sgTopSafeAreaInset(_ containerViewLayout: ContainerViewLayout?, _ navigationBarHeight: CGFloat) -> CGFloat {
        return max(
            (containerViewLayout?.safeInsets.top ?? 0) + (containerViewLayout?.intrinsicInsets.top ?? 0),
            navigationBarHeight
        )
    }
    
    func sgBottomSafeAreaInset(_ containerViewLayout: ContainerViewLayout?) -> CGFloat {
        return (containerViewLayout?.safeInsets.bottom ?? 0) + (containerViewLayout?.intrinsicInsets.bottom ?? 0)
    }
    
    func sgLeftSafeAreaInset(_ containerViewLayout: ContainerViewLayout?) -> CGFloat {
        return containerViewLayout?.safeInsets.left ?? 0
    }

    func sgRightSafeAreaInset(_ containerViewLayout: ContainerViewLayout?) -> CGFloat {
        return containerViewLayout?.safeInsets.right ?? 0
    }

}


@available(iOS 13.0, *)
public final class LegacySwiftUIController: LegacyController {
    public var navigationBarHeightModel: ObservedValue<CGFloat>
    public var containerViewLayoutModel: ObservedValue<ContainerViewLayout?>
    public var inputHeightModel: ObservedValue<CGFloat?>
    public let lang: String
//    public var containerViewLayoutUpdateCountModel: ObservedValue<Int64>

    override public init(presentation: LegacyControllerPresentation, theme: PresentationTheme? = nil, strings: PresentationStrings? = nil, initialLayout: ContainerViewLayout? = nil) {
        navigationBarHeightModel = ObservedValue<CGFloat>(0.0)
        containerViewLayoutModel = ObservedValue<ContainerViewLayout?>(initialLayout)
        inputHeightModel = ObservedValue<CGFloat?>(nil)
        lang = strings?.baseLanguageCode ?? "en"
//        containerViewLayoutUpdateCountModel = ObservedValue<Int64>(0)
        super.init(presentation: presentation, theme: theme, strings: strings, initialLayout: initialLayout)
    }

    override public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
//        containerViewLayoutUpdateCountModel.value += 1
        
        var newNavigationBarHeight = navigationLayout(layout: layout).navigationFrame.maxY
        if !self.displayNavigationBar || self.navigationPresentation == .modal {
            newNavigationBarHeight = 0.0
        }
        if navigationBarHeightModel.value != newNavigationBarHeight {
            navigationBarHeightModel.value = newNavigationBarHeight
        }
        if containerViewLayoutModel.value != layout {
            containerViewLayoutModel.value = layout
        }
        if inputHeightModel.value != layout.inputHeight {
            inputHeightModel.value = layout.inputHeight
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


@available(iOS 13.0, *)
public struct TGNavigationBackButtonModifier: ViewModifier {
    weak var wrapperController: LegacyController?
    
    public func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(true)
            .navigationBarItems(leading:
                NavigationBarBackButton(action: {
                    wrapperController?.dismiss()
                })
                .padding(.leading, -8)
            )
    }
}

@available(iOS 13.0, *)
public extension View {
    func tgNavigationBackButton(wrapperController: LegacyController?) -> some View {
        modifier(TGNavigationBackButtonModifier(wrapperController: wrapperController))
    }
}


@available(iOS 13.0, *)
public struct NavigationBarBackButton: View {
    let text: String
    let color: Color
    let action: () -> Void
    
    public init(text: String = "Back", color: Color = .accentColor, action: @escaping () -> Void) {
        self.text = text
        self.color = color
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let customBackArrow = NavigationBar.backArrowImage(color: color.uiColor()) {
                    Image(uiImage: customBackArrow)
                } else {
                    Image(systemName: "chevron.left")
                        .font(Font.body.weight(.bold))
                        .foregroundColor(color)
                }
                Text(text)
                    .foregroundColor(color)
            }
            .contentShape(Rectangle())
        }
    }
}

@available(iOS 13.0, *)
public extension View {
    func apply<V: View>(@ViewBuilder _ block: (Self) -> V) -> V { block(self) }
    
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }

    @ViewBuilder
    func `if`<Content: View>(_ condition: @escaping () -> Bool, transform: (Self) -> Content) -> some View {
        if condition() {
            transform(self)
        } else {
            self
        }
    }
}

@available(iOS 13.0, *)
public extension Color {
 
    func uiColor() -> UIColor {

        if #available(iOS 14.0, *) {
            return UIColor(self)
        }

        let components = self.components()
        return UIColor(red: components.r, green: components.g, blue: components.b, alpha: components.a)
    }

    private func components() -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {

        let scanner = Scanner(string: self.description.trimmingCharacters(in: CharacterSet.alphanumerics.inverted))
        var hexNumber: UInt64 = 0
        var r: CGFloat = 0.0, g: CGFloat = 0.0, b: CGFloat = 0.0, a: CGFloat = 0.0

        let result = scanner.scanHexInt64(&hexNumber)
        if result {
            r = CGFloat((hexNumber & 0xff000000) >> 24) / 255
            g = CGFloat((hexNumber & 0x00ff0000) >> 16) / 255
            b = CGFloat((hexNumber & 0x0000ff00) >> 8) / 255
            a = CGFloat(hexNumber & 0x000000ff) / 255
        }
        return (r, g, b, a)
    }
    
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6: // RGB (No alpha)
            (a, r, g, b) = (255, (int >> 16) & 0xff, (int >> 8) & 0xff, int & 0xff)
        case 8: // ARGB
            (a, r, g, b) = ((int >> 24) & 0xff, (int >> 16) & 0xff, (int >> 8) & 0xff, int & 0xff)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}


public enum BackgroundMaterial {
    case ultraThinMaterial
    case thinMaterial
    case regularMaterial
    case thickMaterial
    case ultraThickMaterial
    
    @available(iOS 15.0, *)
    var material: Material {
        switch self {
        case .ultraThinMaterial: return .ultraThinMaterial
        case .thinMaterial: return .thinMaterial
        case .regularMaterial: return .regularMaterial
        case .thickMaterial: return .thickMaterial
        case .ultraThickMaterial: return .ultraThickMaterial
        }
    }
}

public enum BounceBehavior {
    case automatic
    case always
    case basedOnSize
    
    @available(iOS 16.4, *)
    var behavior: ScrollBounceBehavior {
        switch self {
        case .automatic: return .automatic
        case .always: return .always
        case .basedOnSize: return .basedOnSize
        }
    }
}


@available(iOS 13.0, *)
public extension View {
    func fontWeightIfAvailable(_ weight: SwiftUI.Font.Weight) -> some View {
        if #available(iOS 16.0, *) {
            return self.fontWeight(weight)
        } else {
            return self
        }
    }
    
    func backgroundIfAvailable(material: BackgroundMaterial) -> some View {
        if #available(iOS 15.0, *) {
            return self.background(material.material)
        } else {
            return self.background(
                Color(.systemBackground)
                    .opacity(0.75)
                    .blur(radius: 3)
                    .overlay(Color.white.opacity(0.1))
            )
        }
    }
}

@available(iOS 13.0, *)
public extension View {
    func scrollBounceBehaviorIfAvailable(_ behavior: BounceBehavior) -> some View {
        if #available(iOS 16.4, *) {
            return self.scrollBounceBehavior(behavior.behavior)
        } else {
            return self
        }
    }
}

@available(iOS 13.0, *)
public extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

@available(iOS 13.0, *)
public struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    
    public func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

@available(iOS 13.0, *)
public struct ContentSizeModifier: ViewModifier {
    @Binding var size: CGSize
    
    public func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geometry -> Color in
                    if geometry.size != size {
                        DispatchQueue.main.async {
                            self.size = geometry.size
                        }
                    }
                    return Color.clear
                }
            )
    }
}

@available(iOS 13.0, *)
public extension View {
    func trackSize(_ size: Binding<CGSize>) -> some View {
        self.modifier(ContentSizeModifier(size: size))
    }
}
