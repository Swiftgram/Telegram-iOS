import UIKit
import AsyncDisplayKit
import Display
import NavigationBarNode

@objc(AppDelegate)
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Playground", sessionRole: session.role)
        configuration.delegateClass = PlaygroundSceneDelegate.self
        return configuration
    }
}

@objc(PlaygroundSceneDelegate)
final class PlaygroundSceneDelegate: NSObject, UIWindowSceneDelegate {
    var window: UIWindow?
    private var mainWindow: Window1?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        defaultNavigationBarImpl = { NavigationBarNode(presentationData: $0) }
        let statusBarHost = ApplicationStatusBarHost(scene: windowScene)
        let (window, hostView) = nativeWindowHostView()
        window.windowScene = windowScene
        // Match Telegram's scene attachment: register the root as the scene's rotation client.
        if let rootViewController = window.rootViewController {
            window.rootViewController = nil
            window.rootViewController = rootViewController
        }
        if ProcessInfo.processInfo.arguments.contains("--native-reference") {
            let referenceWindow = UIWindow(windowScene: windowScene)
            referenceWindow.rootViewController = playgroundNativeReferenceController()
            self.window = referenceWindow
            referenceWindow.makeKeyAndVisible()
            return
        }
        let mainWindow = Window1(hostView: hostView, statusBarHost: statusBarHost)
        self.mainWindow = mainWindow
        self.window = window
        hostView.containerView.backgroundColor = .systemBackground

        let navigationController = NavigationController(
            mode: .single,
            theme: NavigationControllerTheme(statusBar: .black, navigationBar: THEME.navigationBar, emptyAreaColor: .systemBackground, separatorColor: .separator, opaqueBackgroundColor: .systemBackground)
        )
        PlaygroundPresentation.shared.navigationController = navigationController
        mainWindow.viewController = navigationController
        navigationController.setViewControllers([playgroundRootController()], animated: false)
        mainWindow.updateDeviceMetrics()
        window.makeKeyAndVisible()
    }
}
