import UIKit
import SwiftUI
import AsyncDisplayKit
import Display

public func isKeyboardWindow(window: NSObject) -> Bool {
    let typeName = NSStringFromClass(type(of: window))
    if #available(iOS 9.0, *) {
        if typeName.hasPrefix("UI") && typeName.hasSuffix("RemoteKeyboardWindow") {
            return true
        }
    } else {
        if typeName.hasPrefix("UI") && typeName.hasSuffix("TextEffectsWindow") {
            return true
        }
    }
    return false
}

public func isKeyboardView(view: NSObject) -> Bool {
    let typeName = NSStringFromClass(type(of: view))
    if typeName.hasPrefix("UI") && typeName.hasSuffix("InputSetHostView") {
        return true
    }
    return false
}

public func isKeyboardViewContainer(view: NSObject) -> Bool {
    let typeName = NSStringFromClass(type(of: view))
    if typeName.hasPrefix("UI") && typeName.hasSuffix("InputSetContainerView") {
        return true
    }
    return false
}

public class ApplicationStatusBarHost: StatusBarHost {
    private let application = UIApplication.shared
    private weak var scene: UIWindowScene?

    public init(scene: UIWindowScene) {
        self.scene = scene
    }
    
    public var isApplicationInForeground: Bool {
        return self.scene?.activationState == .foregroundActive || self.scene?.activationState == .foregroundInactive
    }
    
    public var statusBarFrame: CGRect {
        return self.scene?.statusBarManager?.statusBarFrame ?? .zero
    }
    public var statusBarStyle: UIStatusBarStyle {
        get {
            return self.scene?.statusBarManager?.statusBarStyle ?? .default
        } set(value) {
            self.setStatusBarStyle(value, animated: false)
        }
    }
    
    public func setStatusBarStyle(_ style: UIStatusBarStyle, animated: Bool) {
        if self.shouldChangeStatusBarStyle?(style) ?? true {
            self.application.internalSetStatusBarStyle(style, animated: animated)
        }
    }
    
    public var shouldChangeStatusBarStyle: ((UIStatusBarStyle) -> Bool)?
    
    public func setStatusBarHidden(_ value: Bool, animated: Bool) {
        self.application.internalSetStatusBarHidden(value, animation: animated ? .fade : .none)
    }
    
    public var keyboardWindow: UIWindow? {
        if let window = UIApplication.shared.internalGetKeyboard(for: self.scene) {
            return window
        }
        
        for window in self.scene?.windows ?? [] {
            if isKeyboardWindow(window: window) {
                return window
            }
        }
        return nil
    }
    
    public var keyboardView: UIView? {
        guard let keyboardWindow = self.keyboardWindow else {
            return nil
        }
        
        for view in keyboardWindow.subviews {
            if isKeyboardViewContainer(view: view) {
                for subview in view.subviews {
                    if isKeyboardView(view: subview) {
                        return subview
                    }
                }
            }
        }
        return nil
    }
}
