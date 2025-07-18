import Foundation
import UIKit
import AsyncDisplayKit

open class ASImageNode: ASDisplayNode {
    public var image: UIImage? {
        didSet {
            if self.isNodeLoaded {
                if let image = self.image {
                    let capInsets = image.capInsets
                    if capInsets.left.isZero && capInsets.top.isZero && capInsets.right.isZero && capInsets.bottom.isZero {
                        self.contentsScale = image.scale
                        self.contents = image.cgImage
                    } else {
                        ASDisplayNodeSetResizableContents(self.layer, image)
                    }
                } else {
                    self.contents = nil
                }
                if self.image?.size != oldValue?.size {
                    self.invalidateCalculatedLayout()
                }
            }
        }
    }
    
    public var customTintColor: UIColor? {
        didSet {
            self.layer.layerTintColor = self.customTintColor?.cgColor
        }
    }

    public var displayWithoutProcessing: Bool = true

    override public init() {
        super.init()
    }
    
    override open func didLoad() {
        super.didLoad()
        
        if let image = self.image {
            let capInsets = image.capInsets
            if capInsets.left.isZero && capInsets.top.isZero {
                self.contentsScale = image.scale
                self.contents = image.cgImage
            } else {
                ASDisplayNodeSetResizableContents(self.layer, image)
            }
        }
        self.layer.layerTintColor = self.customTintColor?.cgColor
    }
    
    override public func calculateSizeThatFits(_ contrainedSize: CGSize) -> CGSize {
        return self.image?.size ?? CGSize()
    }
}
