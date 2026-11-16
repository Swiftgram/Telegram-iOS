import Foundation

/// Entry point used by `ChatController`. Kept small so the hook in the core TelegramUI module stays
/// readable; the work lives in `PythonPluginManager`.
public enum PythonPluginsRuntime {
    public enum SendResult: Equatable {
        /// Send the message unchanged.
        case pass
        /// A plugin cancelled the message.
        case cancel
        /// A plugin rewrote the text.
        case modify(String)
    }

    /// Performs `send_text` requests made by plugins: `(Bot-API style packed peer id, text)`.
    /// Set by the chat controller, which owns the account context. Always called on the main queue.
    public static var sendTextHandler: ((Int64, String) -> Void)?

    /// Shows a plugin toast: `(text, style)` where style is `info`, `success` or `error`.
    /// Always called on the main queue.
    public static var toastHandler: ((String, String) -> Void)?

    public static var isPluginHostAvailable: Bool {
        return PythonPluginManager.shared.isInterpreterAvailable
    }

    /// Runs the enabled plugins' outgoing-message hooks on the main thread.
    /// `peerId` is the Telegram-iOS `PeerId.toInt64()` value.
    public static func dispatchSendHook(peerId: Int64, text: String) -> SendResult {
        return PythonPluginManager.shared.dispatchSendHook(peerId: peerId, text: text)
    }
}
