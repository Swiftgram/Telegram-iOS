import UIKit
import ComponentFlow

final class SGVideoSeekIconComponent: Component {
    let systemName: String
    let tintColor: UIColor
    let pointSize: CGFloat

    init(systemName: String, tintColor: UIColor = .white, pointSize: CGFloat = 22.0) {
        self.systemName = systemName
        self.tintColor = tintColor
        self.pointSize = pointSize
    }

    static func ==(lhs: SGVideoSeekIconComponent, rhs: SGVideoSeekIconComponent) -> Bool {
        if lhs.systemName != rhs.systemName {
            return false
        }
        if lhs.tintColor != rhs.tintColor {
            return false
        }
        if lhs.pointSize != rhs.pointSize {
            return false
        }
        return true
    }

    final class View: UIImageView {
        private var component: SGVideoSeekIconComponent?

        func update(component: SGVideoSeekIconComponent, availableSize: CGSize, transition: ComponentTransition) -> CGSize {
            if self.component?.systemName != component.systemName || self.component?.tintColor != component.tintColor || self.component?.pointSize != component.pointSize {
                // Ultralight stroke to visually match the adjacent controls.
                let configuration = UIImage.SymbolConfiguration(pointSize: component.pointSize, weight: .ultraLight)
                self.image = UIImage(systemName: component.systemName, withConfiguration: configuration)?.withRenderingMode(.alwaysTemplate)
                self.tintColor = component.tintColor
            }
            self.component = component

            return self.image?.size ?? CGSize()
        }
    }

    func makeView() -> View {
        return View(frame: CGRect())
    }

    func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
        return view.update(component: self, availableSize: availableSize, transition: transition)
    }
}
