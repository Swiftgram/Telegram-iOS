import Foundation
import UIKit
import Display
import ComponentFlow

public final class WarpView: UIView {
    private final class WarpPartView: UIView {
        let cloneView: PortalView
        
        init?(contentView: PortalSourceView) {
            guard let cloneView = PortalView(matchPosition: false) else {
                return nil
            }
            self.cloneView = cloneView
            
            super.init(frame: CGRect())
            
            self.layer.anchorPoint = CGPoint(x: 0.5, y: 0.0)
            
            self.clipsToBounds = true
            self.addSubview(cloneView.view)
            contentView.addPortal(view: cloneView)
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        func update(containerSize: CGSize, rect: CGRect, transition: ComponentTransition) {
            transition.setFrame(view: self.cloneView.view, frame: CGRect(origin: CGPoint(x: -rect.minX, y: -rect.minY), size: CGSize(width: containerSize.width, height: containerSize.height)))
        }
    }
    
    public let contentView: PortalSourceView
    
    private let clippingView: UIView
    
    private var warpViews: [WarpPartView] = []
    private let warpMaskContainer: UIView
    private let warpMaskGradientLayer: SimpleGradientLayer
    
    public override init(frame: CGRect) {
        self.contentView = PortalSourceView()
        self.clippingView = UIView()
        
        self.warpMaskContainer = UIView()
        self.warpMaskGradientLayer = SimpleGradientLayer()
        self.warpMaskContainer.layer.mask = self.warpMaskGradientLayer
        
        super.init(frame: frame)
        
        self.clippingView.addSubview(self.contentView)
        
        self.clippingView.clipsToBounds = true
        self.addSubview(self.clippingView)
        self.addSubview(self.warpMaskContainer)
        
        for _ in 0 ..< 8 {
            if let warpView = WarpPartView(contentView: self.contentView) {
                self.warpViews.append(warpView)
                self.warpMaskContainer.addSubview(warpView)
            }
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: Swiftgram
    /// The emoji keyboard fades the last 6pt of the bend into its own opaque background. Over a glass
    /// sheet that fade shows whatever is behind the sheet, so the picker turns it off: the bend ends
    /// at the screen edge, where no fade is needed.
    public var fadesBottomEdge: Bool = true
    /// Perspective strength, 1 = the emoji keyboard's. The foreshortening pulls the far rows in
    /// horizontally, so on a full-width photo grid the grid's vertical gaps bow into arcs at the
    /// bottom; a lower value keeps the depth cue with proportionally smaller arcs, 0 is orthographic.
    public var perspectiveStrength: CGFloat = 1.0
    /// The emoji keyboard renders without edge antialiasing (the UIKit default). The picker's bend is
    /// fully visible over the glass sheet, so it turns it on to smooth the slice edges.
    public var allowsEdgeAntialiasing: Bool = false
    //
    
    public func update(size: CGSize, topInset: CGFloat, bottomInset: CGFloat = 0.0, warpHeight: CGFloat, transition: ComponentTransition) {
        transition.setFrame(view: self.contentView, frame: CGRect(origin: CGPoint(), size: size))
        
        let visibleHeight = size.height - bottomInset
        let allItemsHeight = warpHeight * 0.5
        for i in 0 ..< self.warpViews.count {
            let itemHeight = warpHeight / CGFloat(self.warpViews.count)
            let itemFraction = CGFloat(i + 1) / CGFloat(self.warpViews.count)
            let _ = itemHeight
            
            let da = CGFloat.pi * 0.5 / CGFloat(self.warpViews.count)
            let alpha = CGFloat.pi * 0.5 - itemFraction * CGFloat.pi * 0.5
            let endPoint = CGPoint(x: cos(alpha), y: sin(alpha))
            let prevAngle = alpha + da
            let prevPt = CGPoint(x: cos(prevAngle), y: sin(prevAngle))
            var angle: CGFloat
            angle = -atan2(endPoint.y - prevPt.y, endPoint.x - prevPt.x)
            
            let itemLengthVector = CGPoint(x: endPoint.x - prevPt.x, y: endPoint.y - prevPt.y)
            let itemLength = sqrt(itemLengthVector.x * itemLengthVector.x + itemLengthVector.y * itemLengthVector.y) * warpHeight * 0.5
            let _ = itemLength
            
            var transform: CATransform3D
            transform = CATransform3DIdentity
            transform.m34 = self.perspectiveStrength / (240.0 * warpHeight / 50.0) // MARK: Swiftgram
            
            transform = CATransform3DTranslate(transform, 0.0, prevPt.x * allItemsHeight, (1.0 - prevPt.y) * allItemsHeight)
            transform = CATransform3DRotate(transform, angle, 1.0, 0.0, 0.0)
            
            let positionY = visibleHeight - allItemsHeight + 4.0 + CGFloat(i) * itemLength
            let rect = CGRect(origin: CGPoint(x: 0.0, y: positionY), size: CGSize(width: size.width, height: itemLength))
            // MARK: Swiftgram
            // Without the fade every row of the bend is visible: slices overlap by 3pt so the seams
            // between them do not show the background (the steep last slices project a 3pt overlap to
            // well under 1pt), and the whole bend sits 2pt lower so its last slices cover the frame's
            // bottom rows (the top rows it leaves are under the flat content).
            let partHeight = itemLength + (self.fadesBottomEdge ? 0.0 : 3.0)
            // Perspective projects the arc short of the mask height; the offset makes up for it (in
            // proportion to the strength; the orthographic arc spans exactly the mask height from 0).
            let partOffsetY: CGFloat = (self.fadesBottomEdge ? 4.0 : 6.0) * self.perspectiveStrength
            transition.setPosition(view: self.warpViews[i], position: CGPoint(x: rect.midX, y: partOffsetY))
            transition.setBounds(view: self.warpViews[i], bounds: CGRect(origin: CGPoint(), size: CGSize(width: size.width, height: partHeight)))
            self.warpViews[i].layer.allowsEdgeAntialiasing = self.allowsEdgeAntialiasing
            //
            transition.setTransform(view: self.warpViews[i], transform: transform)
            self.warpViews[i].update(containerSize: size, rect: rect, transition: transition)
        }
        
        let clippingTopInset: CGFloat = topInset
        let frame = CGRect(origin: CGPoint(x: 0.0, y: clippingTopInset), size: CGSize(width: size.width, height: -clippingTopInset + visibleHeight - 21.0))
        transition.setPosition(view: self.clippingView, position: frame.center)
        transition.setBounds(view: self.clippingView, bounds: CGRect(origin: CGPoint(x: 0.0, y: clippingTopInset), size: frame.size))
        self.clippingView.clipsToBounds = true
        
        transition.setFrame(view: self.warpMaskContainer, frame: CGRect(origin: CGPoint(x: 0.0, y: visibleHeight - allItemsHeight), size: CGSize(width: size.width, height: allItemsHeight)))
        
        var locations: [NSNumber] = []
        var colors: [CGColor] = []
        let numStops = 6
        for i in 0 ..< numStops {
            let step = CGFloat(i) / CGFloat(numStops - 1)
            locations.append(step as NSNumber)
            colors.append(UIColor.black.withAlphaComponent(self.fadesBottomEdge ? 1.0 - step * step : 1.0).cgColor) // MARK: Swiftgram
        }
        
        let gradientHeight: CGFloat = 6.0
        self.warpMaskGradientLayer.startPoint = CGPoint(x: 0.0, y: (allItemsHeight - gradientHeight) / allItemsHeight)
        self.warpMaskGradientLayer.endPoint = CGPoint(x: 0.0, y: 1.0)
        
        self.warpMaskGradientLayer.locations = locations
        self.warpMaskGradientLayer.colors = colors
        self.warpMaskGradientLayer.type = .axial
        
        transition.setFrame(layer: self.warpMaskGradientLayer, frame: CGRect(origin: CGPoint(x: 0.0, y: 0.0), size: CGSize(width: size.width, height: allItemsHeight)))
    }
    
    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        return self.contentView.hitTest(point, with: event)
    }
}
