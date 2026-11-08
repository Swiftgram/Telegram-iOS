import Display
import Foundation
import SwiftUI

public struct NavigationBarHeightKey: EnvironmentKey {
    public static let defaultValue: CGFloat = 0
}

public struct ContainerViewLayoutKey: EnvironmentKey {
    public static let defaultValue: ContainerViewLayout? = nil
}

public struct LangKey: EnvironmentKey {
    public static let defaultValue: String = "en"
}

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
}


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

public extension Color {
 
    func uiColor() -> UIColor {
        return UIColor(self)
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


public extension View {
    func fontWeightIfAvailable(_ weight: SwiftUI.Font.Weight) -> some View {
        if #available(iOS 16.0, *) {
            return self.fontWeight(weight)
        } else {
            return self
        }
    }
    
    func backgroundIfAvailable(material: BackgroundMaterial) -> some View {
        return self.background(material.material)
    }
}

public extension View {
    func scrollBounceBehaviorIfAvailable(_ behavior: BounceBehavior) -> some View {
        if #available(iOS 16.4, *) {
            return self.scrollBounceBehavior(behavior.behavior)
        } else {
            return self
        }
    }
}

public extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

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

public extension View {
    func trackSize(_ size: Binding<CGSize>) -> some View {
        self.modifier(ContentSizeModifier(size: size))
    }
}
