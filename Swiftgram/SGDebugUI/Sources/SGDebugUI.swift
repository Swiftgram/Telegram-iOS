import Foundation
import SGItemListUI
import UndoUI
import AccountContext
import Display
import TelegramCore
import ItemListUI
import SwiftSignalKit
import TelegramPresentationData
import PresentationDataUtils

// Optional
import SGSimpleSettings
import SGLogging
import OverlayStatusController
#if DEBUG
import FLEX
#endif

private enum SGDebugControllerSection: Int32, SGItemListSection {
    case base
}

private enum SGDebugActions: String {
    case flexing
    case clearRegDateCache
}

private enum SGDebugToggles: String {
    case forceImmediateShareSheet
    case legacyNotificationsFix
}


private typealias SGDebugControllerEntry = SGItemListUIEntry<SGDebugControllerSection, SGDebugToggles, AnyHashable, AnyHashable, AnyHashable, SGDebugActions>

private func SGDebugControllerEntries(presentationData: PresentationData) -> [SGDebugControllerEntry] {
    var entries: [SGDebugControllerEntry] = []
    
    let id = SGItemListCounter()
    #if DEBUG
    entries.append(.action(id: id.count, section: .base, actionType: .flexing, text: "FLEX", kind: .generic))
    #endif
    entries.append(.action(id: id.count, section: .base, actionType: .clearRegDateCache, text: "Clear Regdate cache", kind: .generic))
    entries.append(.toggle(id: id.count, section: .base, settingName: .forceImmediateShareSheet, value: SGSimpleSettings.shared.forceSystemSharing, text: "Force System Share Sheet", enabled: true))
    entries.append(.toggle(id: id.count, section: .base, settingName: .legacyNotificationsFix, value: SGSimpleSettings.shared.legacyNotificationsFix, text: "[Legacy] Fix empty notifications", enabled: true))
    
    return entries
}
private func okUndoController(_ text: String, _ presentationData: PresentationData) -> UndoOverlayController {
    return UndoOverlayController(presentationData: presentationData, content: .succeed(text: text, timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false })
}


public func sgDebugController(context: AccountContext) -> ViewController {
    var presentControllerImpl: ((ViewController, ViewControllerPresentationArguments?) -> Void)?
    var pushControllerImpl: ((ViewController) -> Void)?

    let simplePromise = ValuePromise(true, ignoreRepeated: false)
    
    let arguments = SGItemListArguments<SGDebugToggles, AnyHashable, AnyHashable, AnyHashable, SGDebugActions>(context: context, setBoolValue: { toggleName, value in
        switch toggleName {
            case .forceImmediateShareSheet:
                SGSimpleSettings.shared.forceSystemSharing = value
            case .legacyNotificationsFix:
                SGSimpleSettings.shared.legacyNotificationsFix = value
        }
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


