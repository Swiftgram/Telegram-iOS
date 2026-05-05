import Foundation
import UIKit
import AsyncDisplayKit
import Display
import ShimmerEffect
import ComponentFlow

public final class ShimmeringMaskView: UIView {
    public let contentView: UIView

    override public init(frame: CGRect) {
        self.contentView = UIView()

        super.init(frame: frame)

        self.addSubview(self.contentView)
    }
    
    required public init(coder: NSCoder) {
        preconditionFailure()
    }

    public func update(size: CGSize, transition: ComponentTransition) {

    }
}
