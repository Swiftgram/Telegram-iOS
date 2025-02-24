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


private enum SGProControllerSection: Int32, SGItemListSection {
    case base
    case notifications
    case footer
}

private enum SGProDisclosureLink: String {
    case sessionBackupManager
    case messageFilter
}

private enum SGProToggles: String {
    case inputToolbar
}

private enum SGProOneFromManySetting: String {
    case pinnedMessageNotifications
    case mentionsAndRepliesNotifications
}

private enum SGProAction {
    case resetIAP
}

private typealias SGProControllerEntry = SGItemListUIEntry<SGProControllerSection, SGProToggles, AnyHashable, SGProOneFromManySetting, SGProDisclosureLink, SGProAction>

private func SGProControllerEntries(presentationData: PresentationData) -> [SGProControllerEntry] {
    var entries: [SGProControllerEntry] = []
    let lang = presentationData.strings.baseLanguageCode
    
    let id = SGItemListCounter()
    
    entries.append(.disclosure(id: id.count, section: .base, link: .sessionBackupManager, text: "SessionBackup.Title".i18n(lang)))
    entries.append(.disclosure(id: id.count, section: .base, link: .messageFilter, text: "MessageFilter.Title".i18n(lang)))
    entries.append(.toggle(id: id.count, section: .base, settingName: .inputToolbar, value: SGSimpleSettings.shared.inputToolbar, text: "InputToolbar.Title".i18n(lang), enabled: true))
    
    entries.append(.header(id: id.count, section: .notifications, text: presentationData.strings.Notifications_Title.uppercased(), badge: nil))
    entries.append(.oneFromManySelector(id: id.count, section: .notifications, settingName: .pinnedMessageNotifications, text: "Notifications.PinnedMessages.Title".i18n(lang), value: "Notifications.PinnedMessages.value.\(SGSimpleSettings.shared.pinnedMessageNotifications)".i18n(lang), enabled: true))
    entries.append(.oneFromManySelector(id: id.count, section: .notifications, settingName: .mentionsAndRepliesNotifications, text: "Notifications.MentionsAndReplies.Title".i18n(lang), value: "Notifications.MentionsAndReplies.value.\(SGSimpleSettings.shared.mentionsAndRepliesNotifications)".i18n(lang), enabled: true))

    #if DEBUG
    entries.append(.action(id: id.count, section: .footer, actionType: .resetIAP, text: "Reset Pro", kind: .destructive))
    #endif
    
    return entries
}

public func okUndoController(_ text: String, _ presentationData: PresentationData) -> UndoOverlayController {
    return UndoOverlayController(presentationData: presentationData, content: .succeed(text: text, timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false })
}

public func sgProController(context: AccountContext) -> ViewController {
    var presentControllerImpl: ((ViewController, ViewControllerPresentationArguments?) -> Void)?
    var pushControllerImpl: ((ViewController) -> Void)?

    let simplePromise = ValuePromise(true, ignoreRepeated: false)
    
    let arguments = SGItemListArguments<SGProToggles, AnyHashable, SGProOneFromManySetting, SGProDisclosureLink, SGProAction>(context: context, setBoolValue: { toggleName, value in
        switch toggleName {
            case .inputToolbar:
                SGSimpleSettings.shared.inputToolbar = value
        }
    }, setOneFromManyValue: { setting in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let lang = presentationData.strings.baseLanguageCode
        let actionSheet = ActionSheetController(presentationData: presentationData)
        var items: [ActionSheetItem] = []
        
        switch (setting) {
            case .pinnedMessageNotifications:
                let setAction: (String) -> Void = { value in
                    SGSimpleSettings.shared.pinnedMessageNotifications = value
                    SGSimpleSettings.shared.synchronizeShared()
                    simplePromise.set(true)
                }

                for value in SGSimpleSettings.PinnedMessageNotificationsSettings.allCases {
                    items.append(ActionSheetButtonItem(title: "Notifications.PinnedMessages.value.\(value.rawValue)".i18n(lang), color: .accent, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                        setAction(value.rawValue)
                    }))
                }
            case .mentionsAndRepliesNotifications:
                let setAction: (String) -> Void = { value in
                    SGSimpleSettings.shared.mentionsAndRepliesNotifications = value
                    SGSimpleSettings.shared.synchronizeShared()
                    simplePromise.set(true)
                }

                for value in SGSimpleSettings.MentionsAndRepliesNotificationsSettings.allCases {
                    items.append(ActionSheetButtonItem(title: "Notifications.MentionsAndReplies.value.\(value.rawValue)".i18n(lang), color: .accent, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                        setAction(value.rawValue)
                    }))
                }
        }
        
        actionSheet.setItemGroups([ActionSheetItemGroup(items: items), ActionSheetItemGroup(items: [
            ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
            })
        ])])
        presentControllerImpl?(actionSheet, ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
    }, openDisclosureLink: { link in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        switch (link) {
            case .sessionBackupManager:
                if #available(iOS 13.0, *) {
                    pushControllerImpl?(sgSessionBackupManagerController(context: context, presentationData: presentationData))
                } else {
                    presentControllerImpl?(context.sharedContext.makeSGUpdateIOSController(), nil)
                }
            case .messageFilter:
                if #available(iOS 13.0, *) {
                    pushControllerImpl?(sgMessageFilterController(presentationData: presentationData))
                } else {
                    presentControllerImpl?(context.sharedContext.makeSGUpdateIOSController(), nil)
                }
        }
    }, action: { action in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        switch action {
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
        
        let entries = SGProControllerEntries(presentationData: presentationData)
        
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Swiftgram Pro"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        
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


