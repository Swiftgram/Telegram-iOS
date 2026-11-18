import Foundation
import Postbox
import TelegramCore
import SwiftSignalKit
import Display
import AccountContext
import AlertUI
import PresentationDataUtils
import UndoUI
import TelegramPresentationData
import PythonPlugins
import JSPlugins

/// Connects the plugin hosts to the signed-in account: it runs outgoing-message hooks and serves the
/// `TrollGram.api(...)` calls of JavaScript plugins. Plugins see Bot-API style peer ids (user `id`,
/// group `-id`, channel `-100id`) because Telegram's packed ids do not fit a JavaScript number.
enum TrollPluginsBridge {
    private static let channelOffset: Int64 = 1000000000000

    static func botApiId(_ peerId: PeerId) -> Int64 {
        let raw = peerId.id._internalGetInt64Value()
        if peerId.namespace == Namespaces.Peer.CloudGroup {
            return -raw
        } else if peerId.namespace == Namespaces.Peer.CloudChannel {
            return -channelOffset - raw
        }
        return raw
    }

    static func peerId(botApiId value: Int64) -> PeerId {
        if value <= -channelOffset {
            return PeerId(namespace: Namespaces.Peer.CloudChannel, id: PeerId.Id._internalFromInt64Value(-channelOffset - value))
        } else if value < 0 {
            return PeerId(namespace: Namespaces.Peer.CloudGroup, id: PeerId.Id._internalFromInt64Value(-value))
        }
        return PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(value))
    }

    /// JavaScript plugins run first, then Python plugins see the possibly rewritten text.
    static func dispatchSend(peerId: PeerId, text: String) -> PythonPluginsRuntime.SendResult {
        var current = text
        switch JSPluginsRuntime.dispatchSendHook(peerId: botApiId(peerId), text: current) {
        case .cancel:
            return .cancel
        case let .modify(modified):
            current = modified
        case .pass:
            break
        }
        switch PythonPluginsRuntime.dispatchSendHook(peerId: peerId.toInt64(), text: current) {
        case .cancel:
            return .cancel
        case let .modify(modified):
            return .modify(modified)
        case .pass:
            return current == text ? .pass : .modify(current)
        }
    }

    /// Installs the handlers for toasts, alerts and API calls. `present` shows a controller on top of the chat.
    static func install(context: AccountContext, presentationData: @escaping () -> PresentationData?, present: @escaping (ViewController) -> Void) {
        JSPluginsRuntime.toastHandler = { text, _ in
            guard let presentationData = presentationData() else {
                return
            }
            present(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: text, timeout: nil, customUndoText: nil), action: { _ in return false }))
        }
        JSPluginsRuntime.alertHandler = { title, text in
            guard let presentationData = presentationData() else {
                return
            }
            present(textAlertController(context: context, title: title, text: text, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]))
        }
        JSPluginsRuntime.apiHandler = { [weak context] method, params, completion in
            guard let context else {
                completion(nil, "the account is no longer available")
                return
            }
            handleAPI(context: context, method: method, params: params, completion: completion)
        }
    }

    private static func resolvePeer(_ value: Any?, context: AccountContext) -> PeerId? {
        if let string = value as? String {
            if string == "me" {
                return context.account.peerId
            }
            return Int64(string).map { peerId(botApiId: $0) }
        }
        if let number = value as? NSNumber {
            return peerId(botApiId: number.int64Value)
        }
        return nil
    }

    private static func handleAPI(context: AccountContext, method: String, params: [String: Any], completion: @escaping (Any?, String?) -> Void) {
        guard let peer = resolvePeer(params["peer"], context: context) else {
            completion(nil, "\(method): `peer` is missing or invalid")
            return
        }
        switch method {
        case "sendMessage":
            guard let text = params["text"] as? String, !text.isEmpty else {
                completion(nil, "sendMessage: `text` is missing")
                return
            }
            let _ = context.engine.messages.enqueueOutgoingMessage(to: peer, replyTo: nil, content: .text(text, [])).start()
            completion(["ok": true], nil)
        case "getPeer":
            let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peer))
            |> deliverOnMainQueue).start(next: { result in
                guard let result else {
                    completion(nil, "getPeer: peer not found")
                    return
                }
                completion([
                    "id": botApiId(result.id),
                    "title": result.compactDisplayTitle,
                    "username": result.addressName ?? NSNull()
                ], nil)
            })
        default:
            completion(nil, "unknown API method `\(method)`; available: sendMessage, getPeer")
        }
    }
}
