import Foundation
import UIKit
import SwiftSignalKit
import AccountContext
import TelegramPresentationData
import ItemListUI
import Display
import PresentationDataUtils
import PythonPlugins
import JSPlugins

/// One row of a plugin's settings screen, independent of where the plugin came from. JavaScript plugins declare
/// `settings: [...]`, Python (exteraGram) plugins return widgets from `create_settings()`; both are mapped here.
struct PluginSettingRow: Equatable {
    enum Kind {
        case header, note, toggle, input, selector, button
    }

    var kind: Kind
    /// The widget's position in the plugin's own list; events are addressed by it.
    var index: Int
    var key: String?
    var title: String
    var placeholder: String = ""
    var items: [String] = []
    var boolValue: Bool = false
    var stringValue: String = ""
    var intValue: Int = 0
}

/// What the screen needs from a plugin host.
private struct PluginSettingsSource {
    /// Current rows with current values. Called on every redraw.
    let rows: () -> [PluginSettingRow]
    let change: (PluginSettingRow, Any) -> Void
    let tap: (PluginSettingRow) -> Void
}

private enum PluginSettingsEntry: ItemListNodeEntry {
    case header(id: Int32, text: String)
    case note(id: Int32, text: String)
    case toggle(id: Int32, row: PluginSettingRow)
    case input(id: Int32, row: PluginSettingRow)
    case selector(id: Int32, row: PluginSettingRow)
    case button(id: Int32, row: PluginSettingRow)

    var section: ItemListSectionId {
        return 0
    }

    var stableId: Int32 {
        switch self {
        case let .header(id, _), let .note(id, _), let .toggle(id, _), let .input(id, _), let .selector(id, _), let .button(id, _):
            return id
        }
    }

    static func <(lhs: PluginSettingsEntry, rhs: PluginSettingsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! PluginSettingsArguments
        switch self {
        case let .header(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .note(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .toggle(_, row):
            return ItemListSwitchItem(presentationData: presentationData, title: row.title, value: row.boolValue, sectionId: self.section, style: .blocks, updated: { updated in
                arguments.change(row, updated)
            })
        case let .input(_, row):
            return ItemListSingleLineInputItem(presentationData: presentationData, title: NSAttributedString(string: row.title, textColor: presentationData.theme.list.itemPrimaryTextColor), text: row.stringValue, placeholder: row.placeholder, type: .regular(capitalization: false, autocorrection: false), returnKeyType: .done, spacing: 10.0, clearType: .onFocus, sectionId: self.section, textUpdated: { updated in
                arguments.change(row, updated)
            }, action: {})
        case let .selector(_, row):
            let label = row.items.indices.contains(row.intValue) ? row.items[row.intValue] : ""
            return ItemListDisclosureItem(presentationData: presentationData, title: row.title, label: label, sectionId: self.section, style: .blocks, action: {
                arguments.choose(row)
            })
        case let .button(_, row):
            return ItemListActionItem(presentationData: presentationData, title: row.title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.tap(row)
            })
        }
    }
}

private final class PluginSettingsArguments {
    let change: (PluginSettingRow, Any) -> Void
    let tap: (PluginSettingRow) -> Void
    let choose: (PluginSettingRow) -> Void

    init(change: @escaping (PluginSettingRow, Any) -> Void, tap: @escaping (PluginSettingRow) -> Void, choose: @escaping (PluginSettingRow) -> Void) {
        self.change = change
        self.tap = tap
        self.choose = choose
    }
}

private func pluginSettingsController(context: AccountContext, title: String, source: PluginSettingsSource) -> ViewController {
    let refresh = ValuePromise<Int>(0, ignoreRepeated: false)
    var revision = 0
    func redraw() {
        revision += 1
        refresh.set(revision)
    }

    weak var controllerReference: ViewController?

    let arguments = PluginSettingsArguments(
        change: { row, value in
            source.change(row, value)
            // Text fields keep their own state while typing; everything else is redrawn from the plugin's values.
            if row.kind != .input {
                redraw()
            }
        },
        tap: { row in
            source.tap(row)
            redraw()
        },
        choose: { row in
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let actionSheet = ActionSheetController(presentationData: presentationData)
            var buttons: [ActionSheetItem] = []
            for (index, name) in row.items.enumerated() {
                buttons.append(ActionSheetButtonItem(title: (index == row.intValue ? "✓ " : "") + name, color: .accent, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                    source.change(row, index)
                    redraw()
                }))
            }
            actionSheet.setItemGroups([
                ActionSheetItemGroup(items: buttons),
                ActionSheetItemGroup(items: [ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                })])
            ])
            controllerReference?.present(actionSheet, in: .window(.root))
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

        var entries: [PluginSettingsEntry] = []
        var id: Int32 = 0
        for row in source.rows() {
            id += 1
            switch row.kind {
            case .header:
                entries.append(.header(id: id, text: row.title.uppercased()))
            case .note:
                entries.append(.note(id: id, text: row.title))
            case .toggle:
                entries.append(.toggle(id: id, row: row))
            case .input:
                entries.append(.input(id: id, row: row))
            case .selector:
                entries.append(.selector(id: id, row: row))
            case .button:
                entries.append(.button(id: id, row: row))
            }
        }
        if entries.isEmpty {
            entries.append(.note(id: 1, text: "This plugin has no settings."))
        }

        let nodeState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks)
        return (controllerState, (nodeState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    controllerReference = controller
    return controller
}

// MARK: - JavaScript plugins

public func trollJSPluginSettingsController(context: AccountContext, pluginId: String, title: String) -> ViewController {
    let manager = JSPluginManager.shared
    let source = PluginSettingsSource(
        rows: {
            return manager.settingsSchema(forPlugin: pluginId).compactMap { item -> PluginSettingRow? in
                let value = manager.settingValue(forPlugin: pluginId, item: item)
                switch item.kind {
                case .header:
                    return PluginSettingRow(kind: .header, index: item.index, title: item.title)
                case .text:
                    return PluginSettingRow(kind: .note, index: item.index, title: item.text)
                case .switch:
                    return PluginSettingRow(kind: .toggle, index: item.index, key: item.key, title: item.title, boolValue: (value as? Bool) ?? false)
                case .input:
                    return PluginSettingRow(kind: .input, index: item.index, key: item.key, title: item.title, placeholder: item.placeholder, stringValue: (value as? String) ?? "")
                case .button:
                    return PluginSettingRow(kind: .button, index: item.index, title: item.title)
                }
            }
        },
        change: { row, value in
            if let key = row.key {
                manager.setSettingValue(forPlugin: pluginId, key: key, value: value)
            }
        },
        tap: { row in
            manager.tapButton(forPlugin: pluginId, index: row.index)
        }
    )
    return pluginSettingsController(context: context, title: title, source: source)
}

// MARK: - Python (exteraGram) plugins

/// Maps exteraGram `ui.settings` widgets to rows. `Divider` and `Custom` have no native counterpart and are skipped.
private func pythonSettingRows(widgets: [[String: Any]], values: [String: Any]) -> [PluginSettingRow] {
    var rows: [PluginSettingRow] = []
    for widget in widgets {
        let index = (widget["index"] as? Int) ?? 0
        let key = widget["key"] as? String
        let text = (widget["text"] as? String) ?? ""
        let subtext = (widget["subtext"] as? String) ?? ""
        let stored = key.flatMap { values[$0] } ?? widget["default"]

        switch (widget["type"] as? String) ?? "" {
        case "Header":
            rows.append(PluginSettingRow(kind: .header, index: index, title: text))
        case "Switch":
            rows.append(PluginSettingRow(kind: .toggle, index: index, key: key, title: text, boolValue: (stored as? Bool) ?? false))
        case "Input":
            rows.append(PluginSettingRow(kind: .input, index: index, key: key, title: text, placeholder: text, stringValue: (stored as? String) ?? ""))
        case "EditText":
            let hint = (widget["hint"] as? String) ?? ""
            rows.append(PluginSettingRow(kind: .input, index: index, key: key, title: hint, placeholder: hint, stringValue: (stored as? String) ?? ""))
        case "Selector":
            rows.append(PluginSettingRow(kind: .selector, index: index, key: key, title: text, items: (widget["items"] as? [String]) ?? [], intValue: (stored as? Int) ?? 0))
        case "Text":
            let isButton = ((widget["actions"] as? [String]) ?? []).contains("on_click")
            rows.append(PluginSettingRow(kind: isButton ? .button : .note, index: index, title: text))
        default:
            continue
        }
        if !subtext.isEmpty {
            rows.append(PluginSettingRow(kind: .note, index: index, title: subtext))
        }
    }
    return rows
}

public func trollPythonPluginSettingsController(context: AccountContext, pluginId: String, title: String) -> ViewController {
    let manager = PythonPluginManager.shared
    let source = PluginSettingsSource(
        rows: {
            let snapshot = manager.settingsSnapshot(forPlugin: pluginId)
            return pythonSettingRows(widgets: snapshot.widgets, values: snapshot.values)
        },
        change: { row, value in
            manager.sendSettingsEvent(forPlugin: pluginId, index: row.index, kind: "change", value: value)
        },
        tap: { row in
            manager.sendSettingsEvent(forPlugin: pluginId, index: row.index, kind: "click", value: nil)
        }
    )
    return pluginSettingsController(context: context, title: title, source: source)
}
