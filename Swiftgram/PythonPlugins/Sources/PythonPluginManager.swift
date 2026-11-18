import Foundation
import SwiftSignalKit

/// exteraGram-compatible plugin host.
///
/// Plugins are `.plugin` (exteraGram) or `.py` files in `Documents/Plugins`, run by an embedded CPython 3.11 (see
/// `//third-party/python` and `stdlib/trollgram_host.py`). Without the interpreter the manager still lists
/// plugins and their enabled state, but nothing runs and each plugin reports why.
///
/// Plugins are **off until the user enables them**: a plugin is arbitrary code with the app's permissions.
///
/// Every call into Python happens on the main thread (see `EmbeddedPython`). Public entry points that
/// touch the interpreter hop to the main queue themselves, so callers may use any thread.
public final class PythonPluginManager {
    public static let shared = PythonPluginManager()

    /// File extensions accepted as plugins. exteraGram's `.plugin` is Python source under another name.
    public static let pluginExtensions = ["plugin", "py"]

    public struct Plugin: Equatable, Identifiable {
        public let id: String
        public let path: String
        public var title: String
        public var description: String
        public var author: String
        public var version: String
        public var isEnabled: Bool
        /// `true` once the plugin's code is loaded and its hooks are live.
        public var isLoaded: Bool
        public var loadError: String?
        /// exteraGram features the plugin asked for that have no iOS backend.
        public var unsupported: [String]
        /// The plugin overrides `create_settings()`, so it has a settings screen.
        public var hasSettings: Bool
    }

    public struct State: Equatable {
        public var plugins: [Plugin] = []
        public var isLoading = false
        public var logs: [String] = []
    }

    private let statePromise = ValuePromise<State>(State(), ignoreRepeated: true)
    private let stateValue: Atomic<State>

    private let pluginsDirectory: String
    private let dataDirectory: String

    /// Main thread only.
    private var hasSynced = false

    private init() {
        self.stateValue = Atomic(value: State())

        let documents = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first ?? NSTemporaryDirectory()
        self.pluginsDirectory = documents + "/Plugins"
        self.dataDirectory = documents + "/PluginsData"

        try? FileManager.default.createDirectory(atPath: self.pluginsDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(atPath: self.dataDirectory, withIntermediateDirectories: true)
    }

    public var state: Signal<State, NoError> {
        return self.statePromise.get()
    }

    public var pluginsDirectoryPath: String {
        return self.pluginsDirectory
    }

    /// `false` when `Python.xcframework` is not linked (stub mode).
    public var isInterpreterAvailable: Bool {
        return EmbeddedPython.shared.isAvailable
    }

    private func onMain<T>(_ f: () -> T) -> T {
        if Thread.isMainThread {
            return f()
        }
        return DispatchQueue.main.sync {
            return f()
        }
    }

    private func ensureInterpreter() -> Bool {
        guard EmbeddedPython.shared.isAvailable else {
            return false
        }
        return EmbeddedPython.shared.start(dataDirectory: self.dataDirectory)
    }

    // MARK: - Discovery and lifecycle

    /// Rescans the plugins folder and brings the loaded set in line with the enabled set.
    public func reload() {
        self.onMain {
            self.syncPlugins()
        }
    }

    private func syncPlugins() {
        self.updateState { state in
            var state = state
            state.isLoading = true
            return state
        }

        let enabled = self.loadEnabledIds()
        var plugins: [Plugin]?

        if self.ensureInterpreter() {
            let request: [String: Any] = [
                "op": "sync",
                "dir": self.pluginsDirectory,
                "enabled": enabled.sorted()
            ]
            if let result = EmbeddedPython.shared.call(request) {
                self.handleActions(result)
                if (result["ok"] as? Bool) == true, let list = result["plugins"] as? [[String: Any]] {
                    plugins = list.compactMap { self.plugin(from: $0, enabled: enabled) }
                } else {
                    self.appendLog("plugin sync failed: \((result["error"] as? String) ?? "unknown error")")
                }
            } else {
                self.appendLog("plugin sync failed: the Python interpreter did not answer")
            }
        }

        let runtimeProblem = self.isInterpreterAvailable ? "the Python runtime could not be started" : "this build has no Python runtime"
        let found = plugins ?? self.filesOnDisk(enabled: enabled, error: runtimeProblem)
        self.hasSynced = true

        self.updateState { state in
            var state = state
            state.plugins = found
            state.isLoading = false
            return state
        }
        let loaded = found.filter { $0.isLoaded }.count
        self.appendLog("\(found.count) plugin(s) found, \(loaded) running")
    }

    private func plugin(from item: [String: Any], enabled: Set<String>) -> Plugin? {
        guard let id = item["id"] as? String, let path = item["path"] as? String else {
            return nil
        }
        return Plugin(
            id: id,
            path: path,
            title: (item["name"] as? String) ?? id,
            description: (item["description"] as? String) ?? "",
            author: (item["author"] as? String) ?? "",
            version: (item["version"] as? String) ?? "",
            isEnabled: enabled.contains(id),
            isLoaded: (item["loaded"] as? Bool) ?? false,
            loadError: item["error"] as? String,
            unsupported: (item["unsupported"] as? [String]) ?? [],
            hasSettings: (item["has_settings"] as? Bool) ?? false
        )
    }

    /// Fallback listing used when Python is unavailable: file names only.
    private func filesOnDisk(enabled: Set<String>, error: String) -> [Plugin] {
        var found: [Plugin] = []
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: self.pluginsDirectory)) ?? []
        for entry in entries.sorted() where PythonPluginManager.pluginExtensions.contains((entry as NSString).pathExtension) {
            let id = (entry as NSString).deletingPathExtension
            found.append(Plugin(
                id: id,
                path: self.pluginsDirectory + "/" + entry,
                title: id,
                description: "",
                author: "",
                version: "",
                isEnabled: enabled.contains(id),
                isLoaded: false,
                loadError: enabled.contains(id) ? error : nil,
                unsupported: [],
                hasSettings: false
            ))
        }
        return found
    }

    /// Installs a `.plugin` or `.py` file picked by the user. The plugin stays disabled until it is switched on.
    @discardableResult
    public func installPlugin(at path: String) -> Bool {
        let fm = FileManager.default
        let name = (path as NSString).lastPathComponent
        guard PythonPluginManager.pluginExtensions.contains((name as NSString).pathExtension) else {
            self.appendLog("rejected \(name): not a .plugin or .py file")
            return false
        }
        let destination = self.pluginsDirectory + "/" + name
        // A plugin id comes from the file name, so drop an older copy under the other extension.
        let stem = (name as NSString).deletingPathExtension
        for ext in PythonPluginManager.pluginExtensions {
            try? fm.removeItem(atPath: self.pluginsDirectory + "/" + stem + "." + ext)
        }
        do {
            try fm.copyItem(atPath: path, toPath: destination)
            self.appendLog("installed \(name) (turn it on to run it)")
            self.reload()
            return true
        } catch {
            self.appendLog("install failed \(name): \(error.localizedDescription)")
            return false
        }
    }

    public func setPlugin(_ id: String, enabled: Bool) {
        var enabledIds = self.loadEnabledIds()
        if enabled {
            enabledIds.insert(id)
        } else {
            enabledIds.remove(id)
        }
        self.saveEnabledIds(enabledIds)
        self.appendLog("\(enabled ? "enabled" : "disabled") \(id)")
        self.reload()
    }

    // MARK: - Settings screen

    /// What the plugin's `create_settings()` returned (JSON objects with `type`, `index`, `key`, `text`, ...) and the
    /// stored values by key. Empty when the plugin is not running.
    public func settingsSnapshot(forPlugin id: String) -> (widgets: [[String: Any]], values: [String: Any]) {
        return self.onMain {
            guard self.ensureInterpreter(),
                  let result = EmbeddedPython.shared.call(["op": "settings", "plugin": id]) else {
                return ([], [:])
            }
            self.handleActions(result)
            guard (result["ok"] as? Bool) == true else {
                self.appendLog("settings of \(id) failed: \((result["error"] as? String) ?? "unknown error")")
                return ([], [:])
            }
            return ((result["widgets"] as? [[String: Any]]) ?? [], (result["values"] as? [String: Any]) ?? [:])
        }
    }

    /// `kind` is `change` (a new `value` for the widget at `index`) or `click`. The plugin's callback runs.
    public func sendSettingsEvent(forPlugin id: String, index: Int, kind: String, value: Any?) {
        self.onMain {
            guard self.ensureInterpreter() else {
                return
            }
            var request: [String: Any] = ["op": "settings_event", "plugin": id, "index": index, "kind": kind]
            if let value {
                request["value"] = value
            }
            if let result = EmbeddedPython.shared.call(request) {
                self.handleActions(result)
            }
        }
    }

    // MARK: - Hooks

    /// Runs the outgoing-message hooks of every loaded plugin. Plugins start on the first send after a
    /// launch, so they work without the plugin screen ever being opened.
    public func dispatchSendHook(peerId: Int64, text: String) -> PythonPluginsRuntime.SendResult {
        return self.onMain { () -> PythonPluginsRuntime.SendResult in
            if !self.hasSynced {
                if self.loadEnabledIds().isEmpty {
                    return .pass
                }
                self.syncPlugins()
            }
            guard self.stateValue.with({ $0.plugins.contains(where: { $0.isLoaded }) }) else {
                return .pass
            }

            let request: [String: Any] = [
                "op": "send_hook",
                "account": 0,
                "peer": peerId,
                "message": text
            ]
            guard let result = EmbeddedPython.shared.call(request) else {
                return .pass
            }
            self.handleActions(result)
            guard (result["ok"] as? Bool) == true else {
                self.appendLog("send hook failed: \((result["error"] as? String) ?? "unknown error")")
                return .pass
            }
            switch (result["action"] as? String) ?? "pass" {
            case "cancel":
                self.appendLog("\((result["by"] as? String) ?? "a plugin") cancelled an outgoing message")
                return .cancel
            case "modify":
                guard let modified = result["message"] as? String, modified != text else {
                    return .pass
                }
                if modified.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.appendLog("a plugin emptied an outgoing message, so it was not sent")
                    return .cancel
                }
                return .modify(modified)
            default:
                return .pass
            }
        }
    }

    /// Carries out what plugins queued during a call: log lines, toasts, messages to send, delayed tasks.
    /// Main thread only.
    private func handleActions(_ result: [String: Any]) {
        guard let actions = result["actions"] as? [[String: Any]] else {
            return
        }
        for action in actions {
            let kind = (action["kind"] as? String) ?? ""
            switch kind {
            case "log":
                let text = (action["text"] as? String) ?? ""
                let level = (action["level"] as? String) ?? "info"
                let source = (action["source"] as? String).map { "[\($0)] " } ?? "[plugin] "
                let marker = (level == "error" || level == "warning") ? level + ": " : ""
                self.appendLog(source + marker + text)
            case "toast":
                let text = (action["text"] as? String) ?? ""
                if let handler = PythonPluginsRuntime.toastHandler {
                    handler(text, (action["style"] as? String) ?? "info")
                } else {
                    self.appendLog("toast: \(text)")
                }
            case "send_text":
                guard let peer = (action["peer"] as? NSNumber)?.int64Value, let text = action["text"] as? String else {
                    continue
                }
                if let handler = PythonPluginsRuntime.sendTextHandler {
                    handler(peer, text)
                } else {
                    self.appendLog("a plugin tried to send a message, but no chat is open yet to send it from")
                }
            case "schedule":
                guard let token = (action["token"] as? NSNumber)?.intValue, let delay = (action["delay_ms"] as? NSNumber)?.intValue else {
                    continue
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delay)) { [weak self] in
                    self?.runScheduled(token: token)
                }
            default:
                break
            }
        }
    }

    private func runScheduled(token: Int) {
        guard let result = EmbeddedPython.shared.call(["op": "run_scheduled", "token": token]) else {
            return
        }
        self.handleActions(result)
    }

    // MARK: - Storage

    public func pluginDataDirectoryPath() -> String {
        return self.dataDirectory
    }

    /// Where `BasePlugin.get_setting` / `set_setting` keep a plugin's values.
    public func settingsPath(forPlugin id: String) -> String {
        return self.dataDirectory + "/settings/" + id + ".json"
    }

    private var enabledIdsPath: String {
        return self.dataDirectory + "/enabled.json"
    }

    private func loadEnabledIds() -> Set<String> {
        guard let data = FileManager.default.contents(atPath: self.enabledIdsPath),
              let json = try? JSONSerialization.jsonObject(with: data, options: []),
              let list = json as? [String] else {
            return []
        }
        return Set(list)
    }

    private func saveEnabledIds(_ ids: Set<String>) {
        guard let data = try? JSONSerialization.data(withJSONObject: ids.sorted(), options: []) else {
            return
        }
        try? data.write(to: URL(fileURLWithPath: self.enabledIdsPath), options: [.atomic])
    }

    // MARK: - Logs

    private func appendLog(_ line: String) {
        let stamped = "[\(Self.timestamp())] \(line)"
        self.updateState { state in
            var state = state
            state.logs.append(stamped)
            if state.logs.count > 500 {
                state.logs.removeFirst(state.logs.count - 500)
            }
            return state
        }
    }

    public func clearLogs() {
        self.updateState { state in
            var state = state
            state.logs = []
            return state
        }
    }

    public var logs: [String] {
        return self.stateValue.with { $0.logs }
    }

    private func updateState(_ f: (State) -> State) {
        let updated = self.stateValue.modify(f)
        self.statePromise.set(updated)
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }
}
