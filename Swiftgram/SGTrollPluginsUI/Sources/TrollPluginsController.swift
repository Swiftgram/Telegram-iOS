import Foundation
import UIKit
import SwiftSignalKit
import AccountContext
import TelegramPresentationData
import ItemListUI
import Display
import PresentationDataUtils
import UndoUI
import PythonPlugins
import JSPlugins

private enum TrollPluginsSection: Int32 {
    case install
    case jsPlugins
    case plugins
    case logs
}

private enum TrollPluginsEntry: ItemListNodeEntry {
    case header(id: Int32, text: String)
    case notice(id: Int32, text: String)
    case jsPlugin(id: Int32, plugin: JSPluginManager.Plugin)
    case jsStatus(id: Int32, text: String)
    case jsSettings(id: Int32, plugin: JSPluginManager.Plugin)
    case plugin(id: Int32, plugin: PythonPluginManager.Plugin)
    case pluginStatus(id: Int32, text: String)
    case importPlugin(id: Int32, text: String)
    case logs(id: Int32, text: String)
    case clearLogs(id: Int32, text: String)

    var section: ItemListSectionId {
        switch self {
        case .header, .notice, .importPlugin:
            return TrollPluginsSection.install.rawValue
        case .jsPlugin, .jsStatus, .jsSettings:
            return TrollPluginsSection.jsPlugins.rawValue
        case .plugin, .pluginStatus:
            return TrollPluginsSection.plugins.rawValue
        case .logs, .clearLogs:
            return TrollPluginsSection.logs.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case let .header(id, _), let .notice(id, _), let .jsPlugin(id, _), let .jsStatus(id, _), let .jsSettings(id, _), let .plugin(id, _), let .pluginStatus(id, _), let .importPlugin(id, _), let .logs(id, _), let .clearLogs(id, _):
            return id
        }
    }

    static func <(lhs: TrollPluginsEntry, rhs: TrollPluginsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! TrollPluginsArguments
        switch self {
        case let .header(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .notice(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .jsPlugin(_, plugin):
            return ItemListSwitchItem(
                presentationData: presentationData,
                title: plugin.title,
                value: plugin.isEnabled,
                enableInteractiveChanges: true,
                sectionId: self.section,
                style: .blocks,
                updated: { value in
                    arguments.toggleJSPlugin(plugin.id, value)
                }
            )
        case let .jsStatus(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .jsSettings(_, plugin):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                title: "Settings",
                label: "",
                sectionId: self.section,
                style: .blocks,
                action: {
                    arguments.openJSSettings(plugin.id, plugin.title)
                }
            )
        case let .plugin(_, plugin):
            return ItemListSwitchItem(
                presentationData: presentationData,
                title: plugin.title,
                value: plugin.isEnabled,
                enableInteractiveChanges: true,
                sectionId: self.section,
                style: .blocks,
                updated: { value in
                    arguments.togglePlugin(plugin.id, value)
                }
            )
        case let .pluginStatus(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .importPlugin(_, text):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                title: text,
                label: "",
                sectionId: self.section,
                style: .blocks,
                action: {
                    arguments.importPlugins()
                }
            )
        case let .logs(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .clearLogs(_, text):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                title: text,
                label: "",
                sectionId: self.section,
                style: .blocks,
                action: {
                    arguments.clearLogs()
                }
            )
        }
    }
}

private final class TrollPluginsArguments {
    let context: AccountContext
    let togglePlugin: (String, Bool) -> Void
    let toggleJSPlugin: (String, Bool) -> Void
    let openJSSettings: (String, String) -> Void
    let clearLogs: () -> Void
    let importPlugins: () -> Void

    init(context: AccountContext, togglePlugin: @escaping (String, Bool) -> Void, toggleJSPlugin: @escaping (String, Bool) -> Void, openJSSettings: @escaping (String, String) -> Void, clearLogs: @escaping () -> Void, importPlugins: @escaping () -> Void) {
        self.context = context
        self.togglePlugin = togglePlugin
        self.toggleJSPlugin = toggleJSPlugin
        self.openJSSettings = openJSSettings
        self.clearLogs = clearLogs
        self.importPlugins = importPlugins
    }
}

private func jsPluginStatusText(_ plugin: JSPluginManager.Plugin) -> String {
    var lines: [String] = []
    let meta = [plugin.author, plugin.version.isEmpty ? "" : "v" + plugin.version].filter { !$0.isEmpty }
    if !meta.isEmpty {
        lines.append(meta.joined(separator: " · "))
    }
    if !plugin.description.isEmpty {
        lines.append(plugin.description)
    }
    if !plugin.commands.isEmpty {
        lines.append("Commands: " + plugin.commands.map { "." + $0 }.joined(separator: " "))
    }
    if let error = plugin.loadError {
        lines.append("Error: " + error)
    } else if plugin.isLoaded {
        lines.append("Running")
    }
    return lines.joined(separator: "\n")
}

private func pluginStatusText(_ plugin: PythonPluginManager.Plugin) -> String {
    var parts: [String] = []
    if !plugin.author.isEmpty {
        parts.append(plugin.author)
    }
    if !plugin.version.isEmpty {
        parts.append("v" + plugin.version)
    }
    var lines: [String] = []
    if !parts.isEmpty {
        lines.append(parts.joined(separator: " · "))
    }
    if !plugin.description.isEmpty {
        lines.append(plugin.description)
    }
    if let error = plugin.loadError {
        lines.append("Error: " + error)
    } else if plugin.isLoaded {
        lines.append("Running")
    } else if plugin.isEnabled {
        lines.append("Enabled, not running yet")
    }
    if !plugin.unsupported.isEmpty {
        lines.append("Not supported on iOS: " + plugin.unsupported.joined(separator: ", "))
    }
    return lines.joined(separator: "\n")
}

public func trollPluginsController(context: AccountContext) -> ViewController {
    let initialState = combineLatest(queue: Queue.mainQueue(), PythonPluginManager.shared.state, JSPluginManager.shared.state)
    PythonPluginManager.shared.reload()
    JSPluginManager.shared.reload()
    weak var controllerReference: ViewController?

    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let installer = PythonPluginsInstaller()
    let arguments = TrollPluginsArguments(
        context: context,
        togglePlugin: { id, enabled in
            PythonPluginManager.shared.setPlugin(id, enabled: enabled)
        },
        toggleJSPlugin: { id, enabled in
            JSPluginManager.shared.setPlugin(id, enabled: enabled)
        },
        openJSSettings: { id, title in
            controllerReference?.push(trollJSPluginSettingsController(context: context, pluginId: id, title: title))
        },
        clearLogs: {
            PythonPluginManager.shared.clearLogs()
            JSPluginManager.shared.clearLogs()
        },
        importPlugins: {
            installer.present(from: context)
        }
    )

    let signal = initialState
    |> map { state, jsState -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let strings = context.sharedContext.currentPresentationData.with { $0 }.strings

        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("TrollGram Plugins"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: strings.Common_Back)
        )

        var entries: [TrollPluginsEntry] = []
        var id: Int32 = 0
        func nextId() -> Int32 {
            id += 1
            return id
        }

        entries.append(.header(id: nextId(), text: "PLUGINS DIRECTORY"))
        entries.append(.notice(id: nextId(), text: PythonPluginManager.shared.pluginsDirectoryPath))
        entries.append(.importPlugin(id: nextId(), text: "Import .js / .py File"))
        entries.append(.notice(id: nextId(), text: "Plugins are off until you turn them on. A plugin is code that runs inside the app with its permissions, so only enable plugins you trust."))
        entries.append(.header(id: nextId(), text: "JAVASCRIPT PLUGINS (\(jsState.plugins.count))"))
        if jsState.plugins.isEmpty {
            entries.append(.notice(id: nextId(), text: "No .js plugins installed."))
        }
        for plugin in jsState.plugins {
            entries.append(.jsPlugin(id: nextId(), plugin: plugin))
            let statusText = jsPluginStatusText(plugin)
            if !statusText.isEmpty {
                entries.append(.jsStatus(id: nextId(), text: statusText))
            }
            if plugin.isLoaded && plugin.hasSettings {
                entries.append(.jsSettings(id: nextId(), plugin: plugin))
            }
        }

        if !PythonPluginsRuntime.isPluginHostAvailable {
            entries.append(.notice(id: nextId(), text: "This build has no Python runtime, so .py plugins cannot run. JavaScript plugins do not need it."))
        }

        entries.append(.header(id: nextId(), text: "PYTHON PLUGINS (\(state.plugins.count))"))
        if state.plugins.isEmpty {
            entries.append(.notice(id: nextId(), text: "No plugins installed."))
        } else {
            for plugin in state.plugins {
                entries.append(.plugin(id: nextId(), plugin: plugin))
                let statusText = pluginStatusText(plugin)
                if !statusText.isEmpty {
                    entries.append(.pluginStatus(id: nextId(), text: statusText))
                }
            }
        }

        entries.append(.header(id: nextId(), text: "LOGGER"))
        let allLogs = (state.logs + jsState.logs).sorted()
        let logText = allLogs.isEmpty ? "No entries." : allLogs.suffix(40).joined(separator: "\n")
        entries.append(.logs(id: nextId(), text: logText))
        entries.append(.clearLogs(id: nextId(), text: "Clear Log"))

        let nodeState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks)
        return (controllerState, (nodeState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    controllerReference = controller
    return controller
}
