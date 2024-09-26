import UIKit
import SwiftUI
import AsyncDisplayKit
import Display


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
        
        navigationController.setViewControllers([PlaygroundScreen()], animated: false)
        
        self.window?.makeKeyAndVisible()
        
        return true
    }
}
