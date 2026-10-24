import SGLogging
import SGAPIWebSettings
import SGConfig
import SGSettingsUI
import SFSafariViewControllerPlus
//
import AccountContext
import Display
import Foundation
import TelegramPresentationData

func sgOpenUrlWithSafariController(
    parsedUrl: URL,
    originalUrl: String,
    context: AccountContext,
    presentationData: PresentationData,
    navigationController: NavigationController?
) {
    if let window = navigationController?.view.window {
        let controller = SFSafariViewControllerPlusDidFinish(url: parsedUrl)
        controller.preferredBarTintColor = presentationData.theme.rootController.navigationBar.opaqueBackgroundColor
        controller.preferredControlTintColor = presentationData.theme.rootController.navigationBar.accentTextColor
        if parsedUrl.host?.lowercased() == SG_API_WEBAPP_URL_PARSED.host?.lowercased() {
            controller.onDidFinish = {
                SGLogger.shared.log("SafariController", "Closed webapp")
                updateSGWebSettingsInteractivelly(context: context)
            }
        }
        window.rootViewController?.present(controller, animated: true)
    } else {
        context.sharedContext.applicationBindings.openUrl(originalUrl)
    }
}
