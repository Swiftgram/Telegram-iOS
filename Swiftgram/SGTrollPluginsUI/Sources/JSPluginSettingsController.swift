import Foundation
import UIKit
import SwiftSignalKit
import AccountContext
import TelegramPresentationData
import ItemListUI
import Display
import PresentationDataUtils
import JSPlugins

/// Settings screen of one JavaScript plugin, built from the `settings` array it declared:
/// `header`, `text`, `switch`, `input` and `button` rows.
private enum JSSettingsEntry: ItemListNodeEntry {
    case header(id: Int32, text: String)
    case text(id: Int32, text: String)
    case toggle(id: Int32, key: String, title: String, value: Bool)
    case input(id: Int32, key: String, title: String, placeholder: String, value: String)
    case button(id: Int32, index: Int, title: String)

    var section: ItemListSectionId {
        return 0
    }

    var stableId: Int32 {
        switch self {
        case let .header(id, _), let .text(id, _), let .toggle(id, _, _, _), let .input(id, _, _, _, _), let .button(id, _, _):
            return id
        }
    }

    static func <(lhs: JSSettingsEntry, rhs: JSSettingsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! JSSettingsArguments
        switch self {
        case let .header(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .text(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .toggle(_, key, title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: { updated in
                arguments.set(key, updated)
            })
        case let .input(_, key, title, placeholder, value):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(string: title, textColor: presentationData.theme.list.itemPrimaryTextColor), text: value, placeholder: placeholder, type: .regular(capitalization: false, autocorrection: false), returnKeyType: .done, spacing: 10.0, clearType: .onFocus, sectionId: self.section, textUpdated: { updated in
                arguments.set(key, updated)
            }, action: {})
        case let .button(_, index, title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.tap(index)
            })
        }
    }
}

private final class JSSettingsArguments {
    let set: (String, Any) -> Void
    let tap: (Int) -> Void

    init(set: @escaping (String, Any) -> Void, tap: @escaping (Int) -> Void) {
        self.set = set
        self.tap = tap
    }
}

public func trollJSPluginSettingsController(context: AccountContext, pluginId: String, title: String) -> ViewController {
    let refresh = ValuePromise<Int>(0, ignoreRepeated: false)
    var revision = 0
    let arguments = JSSettingsArguments(
        set: { key, value in
            JSPluginManager.shared.setSettingValue(forPlugin: pluginId, key: key, value: value)
            // Text fields keep their own state while typing, so only switches need a redraw.
            if value is Bool {
                revision += 1
                refresh.set(revision)
            }
        },
        tap: { index in
            JSPluginManager.shared.tapButton(forPlugin: pluginId, index: index)
        }
    )

    let signal = combineLatest(queue: Queue.mainQueue(), refresh.get(), context.sharedContext.presentationData)
    |> map { _, presentationData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(title),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )

        var entries: [JSSettingsEntry] = []
        var id: Int32 = 0
        for item in JSPluginManager.shared.settingsSchema(forPlugin: pluginId) {
            id += 1
            let value = JSPluginManager.shared.settingValue(forPlugin: pluginId, item: item)
            switch item.kind {
            case .header:
                entries.append(.header(id: id, text: item.title.uppercased()))
            case .text:
                entries.append(.text(id: id, text: item.text))
            case .switch:
                if let key = item.key {
                    entries.append(.toggle(id: id, key: key, title: item.title, value: (value as? Bool) ?? false))
                }
            case .input:
                if let key = item.key {
                    entries.append(.input(id: id, key: key, title: item.title, placeholder: item.placeholder, value: (value as? String) ?? ""))
                }
            case .button:
                entries.append(.button(id: id, index: item.index, title: item.title))
            }
        }
        if entries.isEmpty {
            entries.append(.text(id: 1, text: "This plugin has no settings."))
        }

        let nodeState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks)
        return (controllerState, (nodeState, arguments))
    }

    return ItemListController(context: context, state: signal)
}
