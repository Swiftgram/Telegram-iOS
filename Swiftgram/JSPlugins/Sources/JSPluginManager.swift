import Foundation
import JavaScriptCore
import SwiftSignalKit

/// JavaScript plugin host built on the JavaScriptCore that ships with iOS: no embedded interpreter, no
/// native bridge libraries. Plugins are `.js` files in `Documents/Plugins`; each one runs in its own
/// `JSContext` that can only reach what `JSPrelude` and the natives below expose.
///
/// Plugins are **off until the user enables them**. Everything here runs on the main thread.
public final class JSPluginManager {
    public static let shared = JSPluginManager()

    public struct Plugin: Equatable, Identifiable {
        public let id: String
        public let path: String
        public var title: String
        public var description: String
        public var author: String
        public var version: String
        public var isEnabled: Bool
        public var isLoaded: Bool
        public var loadError: String?
        public var commands: [String]
        public var hasSettings: Bool
    }

    public struct State: Equatable {
        public var plugins: [Plugin] = []
        public var logs: [String] = []
    }

    /// One row of a plugin's settings screen, as declared by `TrollGram.plugin({ settings: [...] })`.
    public struct SettingItem {
        public enum Kind: String {
            case header, text, `switch`, input, button
        }
        public let index: Int
        public let kind: Kind
        public let key: String?
        public let title: String
        public let text: String
        public let placeholder: String
        public let defaultValue: Any?
    }

    private final class Instance {
        let context: JSContext
        var settings: [String: Any]
        var schema: [SettingItem] = []
        var commands: [String] = []

        init(context: JSContext, settings: [String: Any]) {
            self.context = context
            self.settings = settings
        }
    }

    private let statePromise = ValuePromise<State>(State(), ignoreRepeated: true)
    private let stateValue = Atomic<State>(value: State())
    private let pluginsDirectory: String
    private let dataDirectory: String
    private var instances: [String: Instance] = [:]
    private var hasSynced = false

    private init() {
        let documents = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first ?? NSTemporaryDirectory()
        self.pluginsDirectory = documents + "/Plugins"
        self.dataDirectory = documents + "/PluginsData"
        try? FileManager.default.createDirectory(atPath: self.pluginsDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(atPath: self.dataDirectory + "/js-settings", withIntermediateDirectories: true)
    }

    public var state: Signal<State, NoError> {
        return self.statePromise.get()
    }

    public var pluginsDirectoryPath: String {
        return self.pluginsDirectory
    }

    private func onMain<T>(_ f: () -> T) -> T {
        return Thread.isMainThread ? f() : DispatchQueue.main.sync(execute: f)
    }

    // MARK: - Discovery and lifecycle

    /// Rescans the folder; loads newly enabled plugins and unloads disabled or removed ones.
    public func reload() {
        self.onMain { self.syncPlugins(reloading: []) }
    }

    private func syncPlugins(reloading: Set<String>) {
        let enabled = self.loadEnabledIds()
        let entries = ((try? FileManager.default.contentsOfDirectory(atPath: self.pluginsDirectory)) ?? []).sorted()
        var found: [Plugin] = []
        var seen = Set<String>()

        for entry in entries where entry.hasSuffix(".js") {
            let id = (entry as NSString).deletingPathExtension
            let path = self.pluginsDirectory + "/" + entry
            seen.insert(id)
            let header = JSPluginManager.parseHeader(path: path)
            var plugin = Plugin(
                id: id, path: path,
                title: header["name"] ?? id, description: header["description"] ?? "",
                author: header["author"] ?? "", version: header["version"] ?? "",
                isEnabled: enabled.contains(id), isLoaded: false, loadError: nil, commands: [], hasSettings: false
            )
            if reloading.contains(id), let old = self.instances.removeValue(forKey: id) {
                self.callHost(old, "unload", [])
            }
            if plugin.isEnabled {
                if self.instances[id] == nil {
                    plugin.loadError = self.load(id: id, path: path)
                }
                if let instance = self.instances[id] {
                    plugin.isLoaded = true
                    plugin.commands = instance.commands
                    plugin.hasSettings = !instance.schema.isEmpty
                }
            } else if let old = self.instances.removeValue(forKey: id) {
                self.callHost(old, "unload", [])
            }
            found.append(plugin)
        }
        for id in Array(self.instances.keys) where !seen.contains(id) {
            if let old = self.instances.removeValue(forKey: id) {
                self.callHost(old, "unload", [])
            }
        }
        self.hasSynced = true
        self.updateState { state in
            var state = state
            state.plugins = found
            return state
        }
    }

    /// Reads `// @key value` lines between `// ==TrollGramPlugin==` and `// ==/TrollGramPlugin==`.
    static func parseHeader(path: String) -> [String: String] {
        guard let handle = FileHandle(forReadingAtPath: path) else {
            return [:]
        }
        let data = handle.readData(ofLength: 4096)
        handle.closeFile()
        guard let text = String(data: data, encoding: .utf8) else {
            return [:]
        }
        var result: [String: String] = [:]
        var inside = false
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("// ==TrollGramPlugin==") {
                inside = true
            } else if line.hasPrefix("// ==/TrollGramPlugin==") {
                break
            } else if inside, line.hasPrefix("// @") {
                let body = line.dropFirst(4)
                let parts = body.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                if parts.count == 2 {
                    result[String(parts[0])] = String(parts[1]).trimmingCharacters(in: .whitespaces)
                }
            }
        }
        return result
    }

    /// Returns an error text, or nil when the plugin is running.
    private func load(id: String, path: String) -> String? {
        guard let source = try? String(contentsOfFile: path, encoding: .utf8) else {
            return "cannot read the file"
        }
        guard let context = JSContext() as JSContext? else {
            return "cannot create a JavaScript context"
        }
        let instance = Instance(context: context, settings: self.readSettings(id: id))
        var firstError: String?
        context.exceptionHandler = { [weak self] _, exception in
            let text = exception?.toString() ?? "unknown error"
            if firstError == nil {
                firstError = text
            }
            self?.appendLog("[\(id)] error: \(text)")
        }
        self.installNatives(into: context, id: id, instance: instance)
        context.evaluateScript(JSPrelude.source)
        context.evaluateScript(source, withSourceURL: URL(fileURLWithPath: path))
        if let firstError {
            return firstError
        }
        guard let infoText = self.callHost(instance, "info", [])?.toString(),
              let info = (try? JSONSerialization.jsonObject(with: Data(infoText.utf8))) as? [String: Any],
              (info["ok"] as? Bool) == true else {
            return "the plugin did not call TrollGram.plugin({ ... })"
        }
        instance.commands = (info["commands"] as? [String]) ?? []
        instance.schema = ((info["settings"] as? [[String: Any]]) ?? []).compactMap { item in
            guard let kind = SettingItem.Kind(rawValue: (item["type"] as? String) ?? "") else {
                return nil
            }
            let defaultValue = item["default"]
            return SettingItem(
                index: (item["index"] as? Int) ?? 0, kind: kind, key: item["key"] as? String,
                title: (item["title"] as? String) ?? "", text: (item["text"] as? String) ?? "",
                placeholder: (item["placeholder"] as? String) ?? "",
                defaultValue: defaultValue is NSNull ? nil : defaultValue
            )
        }
        context.exceptionHandler = { [weak self] _, exception in
            self?.appendLog("[\(id)] error: \(exception?.toString() ?? "unknown error")")
        }
        self.instances[id] = instance
        self.callHost(instance, "load", [])
        self.appendLog("[\(id)] loaded")
        return nil
    }

    @discardableResult
    private func callHost(_ instance: Instance, _ name: String, _ arguments: [Any]) -> JSValue? {
        return instance.context.objectForKeyedSubscript("__host")?.objectForKeyedSubscript(name)?.call(withArguments: arguments)
    }

    // MARK: - Natives exposed to JavaScript

    private func installNatives(into context: JSContext, id: String, instance: Instance) {
        guard let native = JSValue(newObjectIn: context) as JSValue? else {
            return
        }
        let log: @convention(block) (String, String) -> Void = { [weak self] level, text in
            let marker = (level == "error" || level == "warning") ? level + ": " : ""
            self?.appendLog("[\(id)] \(marker)\(text)")
        }
        let toast: @convention(block) (String, String) -> Void = { text, style in
            DispatchQueue.main.async {
                if let handler = JSPluginsRuntime.toastHandler {
                    handler(text, style)
                }
            }
        }
        let alert: @convention(block) (String, String) -> Void = { title, text in
            DispatchQueue.main.async {
                JSPluginsRuntime.alertHandler?(title, text)
            }
        }
        let schedule: @convention(block) (Int, Int) -> Void = { [weak self, weak instance] timerId, delay in
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(max(0, delay))) {
                guard let self, let instance, self.instances[id] === instance else {
                    return
                }
                self.callHost(instance, "timer", [timerId])
            }
        }
        let settingsGet: @convention(block) () -> String = { [weak instance] in
            guard let instance, let data = try? JSONSerialization.data(withJSONObject: instance.settings, options: []) else {
                return "{}"
            }
            return String(data: data, encoding: .utf8) ?? "{}"
        }
        let settingsSet: @convention(block) (String, String) -> Void = { [weak self, weak instance] key, json in
            guard let value = try? JSONSerialization.jsonObject(with: Data(json.utf8), options: [.fragmentsAllowed]) else {
                return
            }
            guard let self, let instance else {
                return
            }
            self.storeSetting(id: id, instance: instance, key: key, value: value)
        }
        let http: @convention(block) (Int, String) -> Void = { [weak self, weak instance] requestId, json in
            self?.performHTTP(id: id, instance: instance, requestId: requestId, json: json)
        }
        let api: @convention(block) (Int, String, String) -> Void = { [weak self, weak instance] requestId, method, paramsJSON in
            self?.performAPI(id: id, instance: instance, requestId: requestId, method: method, paramsJSON: paramsJSON)
        }

        native.setObject(log, forKeyedSubscript: "log" as NSString)
        native.setObject(toast, forKeyedSubscript: "toast" as NSString)
        native.setObject(alert, forKeyedSubscript: "alert" as NSString)
        native.setObject(schedule, forKeyedSubscript: "schedule" as NSString)
        native.setObject(settingsGet, forKeyedSubscript: "settingsGet" as NSString)
        native.setObject(settingsSet, forKeyedSubscript: "settingsSet" as NSString)
        native.setObject(http, forKeyedSubscript: "http" as NSString)
        native.setObject(api, forKeyedSubscript: "api" as NSString)
        context.setObject(native, forKeyedSubscript: "__native" as NSString)
    }

    private func finishRequest(id: String, instance: Instance?, requestId: Int, function: String, payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, let instance, self.instances[id] === instance else {
                return
            }
            self.callHost(instance, function, [requestId, json])
        }
    }

    private func performHTTP(id: String, instance: Instance?, requestId: Int, json: String) {
        guard let spec = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any],
              let urlString = spec["url"] as? String, let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            self.finishRequest(id: id, instance: instance, requestId: requestId, function: "httpDone", payload: ["error": "invalid URL"])
            return
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30.0)
        request.httpMethod = (spec["method"] as? String) ?? "GET"
        for (key, value) in (spec["headers"] as? [String: Any]) ?? [:] {
            request.setValue("\(value)", forHTTPHeaderField: key)
        }
        if let body = spec["body"] as? String {
            request.httpBody = Data(body.utf8)
        }
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            var payload: [String: Any] = [:]
            if let error {
                payload["error"] = error.localizedDescription
            } else {
                payload["status"] = (response as? HTTPURLResponse)?.statusCode ?? 0
                payload["body"] = String(data: data ?? Data(), encoding: .utf8) ?? ""
            }
            self?.finishRequest(id: id, instance: instance, requestId: requestId, function: "httpDone", payload: payload)
        }.resume()
    }

    private func performAPI(id: String, instance: Instance?, requestId: Int, method: String, paramsJSON: String) {
        let params = ((try? JSONSerialization.jsonObject(with: Data(paramsJSON.utf8))) as? [String: Any]) ?? [:]
        guard let handler = JSPluginsRuntime.apiHandler else {
            self.finishRequest(id: id, instance: instance, requestId: requestId, function: "apiDone", payload: ["error": "no account is available yet; open a chat first"])
            return
        }
        DispatchQueue.main.async { [weak self] in
            handler(method, params) { result, error in
                var payload: [String: Any] = [:]
                if let error {
                    payload["error"] = error
                } else {
                    payload["result"] = result ?? NSNull()
                }
                self?.finishRequest(id: id, instance: instance, requestId: requestId, function: "apiDone", payload: payload)
            }
        }
    }

    // MARK: - Install, enable, hooks

    /// Installs a `.js` file picked by the user. It stays disabled until switched on.
    @discardableResult
    public func installPlugin(at path: String) -> Bool {
        let fm = FileManager.default
        let name = (path as NSString).lastPathComponent
        guard name.hasSuffix(".js") else {
            self.appendLog("rejected \(name): not a .js plugin")
            return false
        }
        let destination = self.pluginsDirectory + "/" + name
        try? fm.removeItem(atPath: destination)
        do {
            try fm.copyItem(atPath: path, toPath: destination)
            self.appendLog("installed \(name) (turn it on to run it)")
            let id = (name as NSString).deletingPathExtension
            self.onMain { self.syncPlugins(reloading: [id]) }
            return true
        } catch {
            self.appendLog("install failed \(name): \(error.localizedDescription)")
            return false
        }
    }

    public func setPlugin(_ id: String, enabled: Bool) {
        var ids = self.loadEnabledIds()
        if enabled {
            ids.insert(id)
        } else {
            ids.remove(id)
        }
        if let data = try? JSONSerialization.data(withJSONObject: ids.sorted(), options: []) {
            try? data.write(to: URL(fileURLWithPath: self.enabledIdsPath), options: [.atomic])
        }
        self.appendLog("\(enabled ? "enabled" : "disabled") \(id)")
        self.reload()
    }

    /// Runs the outgoing-message hooks of every running plugin, in file-name order.
    public func dispatchSendHook(peerId: Int64, text: String) -> JSPluginsRuntime.SendResult {
        return self.onMain { () -> JSPluginsRuntime.SendResult in
            if !self.hasSynced {
                if self.loadEnabledIds().isEmpty {
                    return .pass
                }
                self.syncPlugins(reloading: [])
            }
            var current = text
            for id in self.instances.keys.sorted() {
                guard let instance = self.instances[id],
                      let resultText = self.callHost(instance, "send", [NSNumber(value: peerId), current])?.toString(),
                      let result = (try? JSONSerialization.jsonObject(with: Data(resultText.utf8))) as? [String: Any] else {
                    continue
                }
                switch (result["action"] as? String) ?? "pass" {
                case "cancel":
                    self.appendLog("[\(id)] cancelled an outgoing message")
                    return .cancel
                case "modify":
                    if let modified = result["text"] as? String {
                        if modified.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            return .cancel
                        }
                        current = modified
                    }
                default:
                    break
                }
            }
            return current == text ? .pass : .modify(current)
        }
    }

    // MARK: - Settings screen API

    public func settingsSchema(forPlugin id: String) -> [SettingItem] {
        return self.onMain { self.instances[id]?.schema ?? [] }
    }

    public func settingValue(forPlugin id: String, item: SettingItem) -> Any? {
        return self.onMain {
            guard let key = item.key else {
                return nil
            }
            return self.instances[id]?.settings[key] ?? item.defaultValue
        }
    }

    /// Called by the settings screen; also notifies the plugin's `onSettingChange`.
    public func setSettingValue(forPlugin id: String, key: String, value: Any) {
        self.onMain {
            if let instance = self.instances[id] {
                self.storeSetting(id: id, instance: instance, key: key, value: value)
                self.callHost(instance, "settingChanged", [key, value])
            }
        }
    }

    public func tapButton(forPlugin id: String, index: Int) {
        self.onMain {
            if let instance = self.instances[id] {
                self.callHost(instance, "tap", [index])
            }
        }
    }

    // MARK: - Storage

    private var enabledIdsPath: String {
        return self.dataDirectory + "/js-enabled.json"
    }

    private func loadEnabledIds() -> Set<String> {
        guard let data = FileManager.default.contents(atPath: self.enabledIdsPath),
              let list = (try? JSONSerialization.jsonObject(with: data)) as? [String] else {
            return []
        }
        return Set(list)
    }

    private func settingsPath(id: String) -> String {
        return self.dataDirectory + "/js-settings/" + id + ".json"
    }

    private func readSettings(id: String) -> [String: Any] {
        guard let data = FileManager.default.contents(atPath: self.settingsPath(id: id)),
              let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return [:]
        }
        return dict
    }

    private func storeSetting(id: String, instance: Instance, key: String, value: Any) {
        instance.settings[key] = value is NSNull ? nil : value
        if let data = try? JSONSerialization.data(withJSONObject: instance.settings, options: []) {
            try? data.write(to: URL(fileURLWithPath: self.settingsPath(id: id)), options: [.atomic])
        }
    }

    // MARK: - Logs

    private func appendLog(_ line: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let stamped = "[\(formatter.string(from: Date()))] \(line)"
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

    private func updateState(_ f: (State) -> State) {
        let updated = self.stateValue.modify(f)
        self.statePromise.set(updated)
    }
}
