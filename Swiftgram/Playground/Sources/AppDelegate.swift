import UIKit
import SwiftUI
import AsyncDisplayKit
import Display
import LegacyUI

let SHOW_SAFE_AREA = false

@objc(AppDelegate)
final class AppDelegate: NSObject, UIApplicationDelegate {
    var window: UIWindow?
    
    private var mainWindow: Window1?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        let statusBarHost = ApplicationStatusBarHost()
        let (window, hostView) = nativeWindowHostView()
        let mainWindow = Window1(hostView: hostView, statusBarHost: statusBarHost)
        self.mainWindow = mainWindow
        hostView.containerView.backgroundColor = UIColor.white
        self.window = window

        let navigationController = NavigationController(
            mode: .single,
            theme: NavigationControllerTheme(
                statusBar: .black,
                navigationBar: THEME.navigationBar,
                emptyAreaColor: .white
            )
        )
        
        mainWindow.viewController = navigationController
        
        let rootViewController = mySwiftUIViewController(0)

        if SHOW_SAFE_AREA {
            // Add insets visualization
                rootViewController.view.layoutMargins = .zero
                rootViewController.view.subviews.forEach { $0.removeFromSuperview() }
                
                let topInsetView = UIView()
                let leftInsetView = UIView()
                let rightInsetView = UIView()
                let bottomInsetView = UIView()
                
                [topInsetView, leftInsetView, rightInsetView, bottomInsetView].forEach {
                    $0.backgroundColor = .systemRed
                    $0.alpha = 0.3
                    rootViewController.view.addSubview($0)
                    $0.translatesAutoresizingMaskIntoConstraints = false
                }
                
                NSLayoutConstraint.activate([
                    topInsetView.topAnchor.constraint(equalTo: rootViewController.view.topAnchor),
                    topInsetView.leadingAnchor.constraint(equalTo: rootViewController.view.leadingAnchor),
                    topInsetView.trailingAnchor.constraint(equalTo: rootViewController.view.trailingAnchor),
                    topInsetView.bottomAnchor.constraint(equalTo: rootViewController.view.safeAreaLayoutGuide.topAnchor),
                    
                    leftInsetView.topAnchor.constraint(equalTo: rootViewController.view.topAnchor),
                    leftInsetView.leadingAnchor.constraint(equalTo: rootViewController.view.leadingAnchor),
                    leftInsetView.bottomAnchor.constraint(equalTo: rootViewController.view.bottomAnchor),
                    leftInsetView.trailingAnchor.constraint(equalTo: rootViewController.view.safeAreaLayoutGuide.leadingAnchor),
                    
                    rightInsetView.topAnchor.constraint(equalTo: rootViewController.view.topAnchor),
                    rightInsetView.trailingAnchor.constraint(equalTo: rootViewController.view.trailingAnchor),
                    rightInsetView.bottomAnchor.constraint(equalTo: rootViewController.view.bottomAnchor),
                    rightInsetView.leadingAnchor.constraint(equalTo: rootViewController.view.safeAreaLayoutGuide.trailingAnchor),
                    
                    bottomInsetView.bottomAnchor.constraint(equalTo: rootViewController.view.bottomAnchor),
                    bottomInsetView.leadingAnchor.constraint(equalTo: rootViewController.view.leadingAnchor),
                    bottomInsetView.trailingAnchor.constraint(equalTo: rootViewController.view.trailingAnchor),
                    bottomInsetView.topAnchor.constraint(equalTo: rootViewController.view.safeAreaLayoutGuide.bottomAnchor)
                ])
        }
        
        navigationController.setViewControllers([rootViewController], animated: false)
        
        self.window?.makeKeyAndVisible()
        
        return true
    }
}
