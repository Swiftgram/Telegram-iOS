import Foundation
import UniformTypeIdentifiers
import SGItemListUI
import UndoUI
import AccountContext
import Display
import TelegramCore
import Postbox
import ItemListUI
import SwiftSignalKit
import TelegramPresentationData
import PresentationDataUtils
import TelegramUIPreferences

// Optional
import SGSimpleSettings
import SGLogging
import SGPayWall
import OverlayStatusController
#if DEBUG
import FLEX
#endif


private enum SGDebugControllerSection: Int32, SGItemListSection {
    case base
    case notifications
}

private enum SGDebugDisclosureLink: String {
    case sessionBackupManager
    case messageFilter
    case debugIAP
}

private enum SGDebugActions: String {
    case flexing
    case fileManager
    case clearRegDateCache
    case restorePurchases
    case setIAP
    case resetIAP
}

private enum SGDebugToggles: String {
    case forceImmediateShareSheet
    case legacyNotificationsFix
    case inputToolbar
}


private enum SGDebugOneFromManySetting: String {
    case pinnedMessageNotifications
    case mentionsAndRepliesNotifications
}

private typealias SGDebugControllerEntry = SGItemListUIEntry<SGDebugControllerSection, SGDebugToggles, AnyHashable, SGDebugOneFromManySetting, SGDebugDisclosureLink, SGDebugActions>

private func SGDebugControllerEntries(presentationData: PresentationData) -> [SGDebugControllerEntry] {
    var entries: [SGDebugControllerEntry] = []
    
    let id = SGItemListCounter()
    #if DEBUG
    entries.append(.action(id: id.count, section: .base, actionType: .flexing, text: "FLEX", kind: .generic))
    entries.append(.action(id: id.count, section: .base, actionType: .fileManager, text: "FileManager", kind: .generic))
    #endif

    entries.append(.action(id: id.count, section: .base, actionType: .clearRegDateCache, text: "Clear Regdate cache", kind: .generic))
    entries.append(.toggle(id: id.count, section: .base, settingName: .forceImmediateShareSheet, value: SGSimpleSettings.shared.forceSystemSharing, text: "Force System Share Sheet", enabled: true))
    
    entries.append(.action(id: id.count, section: .base, actionType: .restorePurchases, text: "PayWall.RestorePurchases".i18n(presentationData.strings.baseLanguageCode), kind: .generic))
    #if DEBUG
    entries.append(.action(id: id.count, section: .base, actionType: .setIAP, text: "Set Pro", kind: .generic))
    #endif
    entries.append(.action(id: id.count, section: .base, actionType: .resetIAP, text: "Reset Pro", kind: .destructive))

    entries.append(.toggle(id: id.count, section: .notifications, settingName: .legacyNotificationsFix, value: SGSimpleSettings.shared.legacyNotificationsFix, text: "[OLD] Fix empty notifications", enabled: true))
    return entries
}
private func okUndoController(_ text: String, _ presentationData: PresentationData) -> UndoOverlayController {
    return UndoOverlayController(presentationData: presentationData, content: .succeed(text: text, timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false })
}


public func sgDebugController(context: AccountContext) -> ViewController {
    var presentControllerImpl: ((ViewController, ViewControllerPresentationArguments?) -> Void)?
    var pushControllerImpl: ((ViewController) -> Void)?

    let simplePromise = ValuePromise(true, ignoreRepeated: false)
    
    let arguments = SGItemListArguments<SGDebugToggles, AnyHashable, SGDebugOneFromManySetting, SGDebugDisclosureLink, SGDebugActions>(context: context, setBoolValue: { toggleName, value in
        switch toggleName {
            case .forceImmediateShareSheet:
                SGSimpleSettings.shared.forceSystemSharing = value
            case .legacyNotificationsFix:
                SGSimpleSettings.shared.legacyNotificationsFix = value
                SGSimpleSettings.shared.synchronizeShared()
            case .inputToolbar:
                SGSimpleSettings.shared.inputToolbar = value
        }
    }, setOneFromManyValue: { setting in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let actionSheet = ActionSheetController(presentationData: presentationData)
        let items: [ActionSheetItem] = []
//        var items: [ActionSheetItem] = []
        
//        switch (setting) {
//        }
        
        actionSheet.setItemGroups([ActionSheetItemGroup(items: items), ActionSheetItemGroup(items: [
            ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
            })
        ])])
        presentControllerImpl?(actionSheet, ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
    }, openDisclosureLink: { _ in
    }, action: { actionType in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        switch actionType {
            case .clearRegDateCache:
                SGLogger.shared.log("SGDebug", "Regdate cache cleanup init")
                
                /*
                let spinner = OverlayStatusController(theme: presentationData.theme, type: .loading(cancelled: nil))

                presentControllerImpl?(spinner, nil)
                */
                SGSimpleSettings.shared.regDateCache.drop()
                SGLogger.shared.log("SGDebug", "Regdate cache cleanup succesfull")
                presentControllerImpl?(okUndoController("OK: Regdate cache cleaned", presentationData), nil)
                /*
                Queue.mainQueue().async() { [weak spinner] in
                    spinner?.dismiss()
                }
                */
        case .flexing:
            #if DEBUG
            FLEXManager.shared.toggleExplorer()
            #endif
        case .fileManager:
            #if DEBUG
            let baseAppBundleId = Bundle.main.bundleIdentifier!
            let appGroupName = "group.\(baseAppBundleId)"
            let maybeAppGroupUrl = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupName)
            if let maybeAppGroupUrl = maybeAppGroupUrl {
                if let fileManager = FLEXFileBrowserController(path: maybeAppGroupUrl.path) {
                    FLEXManager.shared.showExplorer()
                    let flexNavigation = FLEXNavigationController(rootViewController: fileManager)
                    FLEXManager.shared.presentTool({ return flexNavigation })
                }
            } else {
                presentControllerImpl?(UndoOverlayController(
                    presentationData: presentationData,
                    content: .info(title: nil, text: "Empty path", timeout: nil, customUndoText: nil),
                    elevatedLayout: false,
                    action: { _ in return false }
                ),
                nil)
            }
            #endif
        case .restorePurchases:
            presentControllerImpl?(UndoOverlayController(
                presentationData: presentationData,
                content: .info(title: nil, text: "PayWall.Button.Restoring".i18n(args: context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode), timeout: nil, customUndoText: nil),
                elevatedLayout: false,
                action: { _ in return false }
            ),
            nil)
            context.sharedContext.SGIAP?.restorePurchases {}
        case .setIAP:
            #if DEBUG
            #endif
        case .resetIAP:
            let updateSettingsSignal = updateSGStatusInteractively(accountManager: context.sharedContext.accountManager, { status in
                var status = status
                status.status = SGStatus.default.status
                SGSimpleSettings.shared.primaryUserId = ""
                return status
            })
            let _ = (updateSettingsSignal |> deliverOnMainQueue).start(next: {
                presentControllerImpl?(UndoOverlayController(
                    presentationData: presentationData,
                    content: .info(title: nil, text: "Status reset completed. You can now restore purchases.", timeout: nil, customUndoText: nil),
                    elevatedLayout: false,
                    action: { _ in return false }
                ),
                nil)
            })
        }
    })
    
    let signal = combineLatest(context.sharedContext.presentationData, simplePromise.get())
    |> map { presentationData, _ ->  (ItemListControllerState, (ItemListNodeState, Any)) in
        
        let entries = SGDebugControllerEntries(presentationData: presentationData)
        
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Swiftgram Debug"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, ensureVisibleItemTag: /*focusOnItemTag*/ nil, initialScrollToItem: nil /* scrollToItem*/ )
        
        return (controllerState, (listState, arguments))
    }
    
    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c, a in
        controller?.present(c, in: .window(.root), with: a)
    }
    pushControllerImpl = { [weak controller] c in
        (controller?.navigationController as? NavigationController)?.pushViewController(c)
    }
    // Workaround
    let _ = pushControllerImpl
    
    return controller
}


