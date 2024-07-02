import Foundation
import UIKit
import AsyncDisplayKit
import Display

private final class PlaygroundSplashScreenNode: ASDisplayNode {
    private let headerBackgroundNode: ASDisplayNode
    private let headerCornerNode: ASImageNode
    
    private var isDismissed = false
    
    private var validLayout: (layout: ContainerViewLayout, navigationHeight: CGFloat)?
    
    override init() {
        self.headerBackgroundNode = ASDisplayNode()
        self.headerBackgroundNode.backgroundColor = .black
        
        self.headerCornerNode = ASImageNode()
        self.headerCornerNode.displaysAsynchronously = false
        self.headerCornerNode.displayWithoutProcessing = true
        self.headerCornerNode.image = generateImage(CGSize(width: 20.0, height: 10.0), rotatedContext: { size, context in
            context.setFillColor(UIColor.black.cgColor)
            context.fill(CGRect(origin: CGPoint(), size: size))
            context.setBlendMode(.copy)
            context.setFillColor(UIColor.clear.cgColor)
            context.fillEllipse(in: CGRect(origin: CGPoint(x: 0.0, y: 0.0), size: CGSize(width: 20.0, height: 20.0)))
        })?.stretchableImage(withLeftCapWidth: 10, topCapHeight: 1)
        
        super.init()
        
        self.backgroundColor = THEME.list.itemBlocksBackgroundColor
        
        self.addSubnode(self.headerBackgroundNode)
        self.addSubnode(self.headerCornerNode)
    }
    
    func containerLayoutUpdated(layout: ContainerViewLayout, navigationHeight: CGFloat, transition: ContainedViewLayoutTransition) {
        if self.isDismissed {
            return
        }
        self.validLayout = (layout, navigationHeight)
        
        let headerHeight = navigationHeight + 260.0
        
        transition.updateFrame(node: self.headerBackgroundNode, frame: CGRect(origin: CGPoint(x: -1.0, y: 0), size: CGSize(width: layout.size.width + 2.0, height: headerHeight)))
        transition.updateFrame(node: self.headerCornerNode, frame: CGRect(origin: CGPoint(x: 0.0, y: headerHeight), size: CGSize(width: layout.size.width, height: 10.0)))
    }
    
    func animateOut(completion: @escaping () -> Void) {
        guard let (layout, navigationHeight) = self.validLayout else {
            completion()
            return
        }
        self.isDismissed = true
        let transition: ContainedViewLayoutTransition = .animated(duration: 0.4, curve: .spring)
        
        let headerHeight = navigationHeight + 260.0
        
        transition.updateFrame(node: self.headerBackgroundNode, frame: CGRect(origin: CGPoint(x: -1.0, y: -headerHeight - 10.0), size: CGSize(width: layout.size.width + 2.0, height: headerHeight)), completion: { _ in
            completion()
        })
        transition.updateFrame(node: self.headerCornerNode, frame: CGRect(origin: CGPoint(x: 0.0, y: -10.0), size: CGSize(width: layout.size.width, height: 10.0)))
    }
}

public final class PlaygroundSplashScreen: ViewController {
    
    public init() {
        
        let navigationBarTheme = NavigationBarTheme(buttonColor: .white, disabledButtonColor: .white, primaryTextColor: .white, backgroundColor: .clear, enableBackgroundBlur: true, separatorColor: .clear, badgeBackgroundColor: THEME.navigationBar.badgeBackgroundColor, badgeStrokeColor: THEME.navigationBar.badgeStrokeColor, badgeTextColor: THEME.navigationBar.badgeTextColor)
        
        super.init(navigationBarPresentationData: NavigationBarPresentationData(theme: navigationBarTheme, strings: NavigationBarStrings(back: "", close: "")))
        
        self.statusBar.statusBarStyle = .White
    }
    
    required public init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override public func loadDisplayNode() {
        self.displayNode = PlaygroundSplashScreenNode()
    }
    
    override public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        
        (self.displayNode as! PlaygroundSplashScreenNode).containerLayoutUpdated(layout: layout, navigationHeight: self.navigationLayout(layout: layout).navigationFrame.maxY, transition: transition)
    }
    
    public func animateOut(completion: @escaping () -> Void) {
        self.statusBar.statusBarStyle = .Black
        (self.displayNode as! PlaygroundSplashScreenNode).animateOut(completion: completion)
    }
}
