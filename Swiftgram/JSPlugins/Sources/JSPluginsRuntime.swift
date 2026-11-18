import Foundation

/// Entry points used by the app (`ChatController` and the plugin screens). The handlers are installed by
/// the module that owns the account context, so this module stays free of Telegram dependencies.
public enum JSPluginsRuntime {
    public enum SendResult: Equatable {
        case pass
        case cancel
        case modify(String)
    }

    /// Shows a toast: `(text, style)`, style is `info`, `success` or `error`. Called on the main queue.
    public static var toastHandler: ((String, String) -> Void)?

    /// Shows an alert: `(title, text)`. Called on the main queue.
    public static var alertHandler: ((String, String) -> Void)?

    /// Runs `TrollGram.api(method, params)` calls: `(method, params, completion(result, errorText))`.
    /// Peers are Bot-API style ids (user `id`, group `-id`, channel `-100id`) or `"me"`.
    public static var apiHandler: ((String, [String: Any], @escaping (Any?, String?) -> Void) -> Void)?

    /// Runs the enabled plugins' outgoing-message hooks. `peerId` is a Bot-API style id.
    public static func dispatchSendHook(peerId: Int64, text: String) -> SendResult {
        return JSPluginManager.shared.dispatchSendHook(peerId: peerId, text: text)
    }
}
