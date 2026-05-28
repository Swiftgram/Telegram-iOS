import Postbox
import TelegramApi
import SwiftSignalKit

public enum UpdateChannelJoinToSendError {
    case generic
}

func _internal_toggleChannelJoinToSend(postbox: Postbox, network: Network, accountStateManager: AccountStateManager, peerId: PeerId, enabled: Bool) -> Signal<Never, UpdateChannelJoinToSendError> {
    return postbox.transaction { transaction -> Peer? in
        return transaction.getPeer(peerId)
    }
    |> castError(UpdateChannelJoinToSendError.self)
    |> mapToSignal { peer in
        guard let peer = peer, let inputChannel = apiInputChannel(peer) else {
            return .fail(.generic)
        }
        return network.request(Api.functions.channels.toggleJoinToSend(channel: inputChannel, enabled: enabled ? .boolTrue : .boolFalse))
        |> `catch` { _ -> Signal<Api.Updates, UpdateChannelJoinToSendError> in
            return .fail(.generic)
        }
        |> mapToSignal { updates -> Signal<Never, UpdateChannelJoinToSendError> in
            accountStateManager.addUpdates(updates)
            return .complete()
        }
    }
}

public enum UpdateChannelJoinRequestError {
    case generic
}

func _internal_toggleChannelJoinRequest(postbox: Postbox, network: Network, accountStateManager: AccountStateManager, peerId: PeerId, enabled: Bool, guardBotId: PeerId? = nil) -> Signal<Never, UpdateChannelJoinRequestError> {
    return postbox.transaction { transaction -> (Peer?, Api.InputUser?) in
        let peer = transaction.getPeer(peerId)
        var guardBot: Api.InputUser?
        if let guardBotId, let botPeer = transaction.getPeer(guardBotId) {
            guardBot = apiInputUser(botPeer)
        }
        return (peer, guardBot)
    }
    |> castError(UpdateChannelJoinRequestError.self)
    |> mapToSignal { (peer, guardBot) in
        guard let peer = peer, let inputChannel = apiInputChannel(peer) else {
            return .fail(.generic)
        }
        var flags: Int32 = 0
        if guardBot != nil {
            flags |= (1 << 0)
        }
        return network.request(Api.functions.channels.toggleJoinRequest(flags: flags, channel: inputChannel, enabled: enabled ? .boolTrue : .boolFalse, guardBot: guardBot))
        |> `catch` { _ -> Signal<Api.Updates, UpdateChannelJoinRequestError> in
            return .fail(.generic)
        }
        |> mapToSignal { updates -> Signal<Never, UpdateChannelJoinRequestError> in
            accountStateManager.addUpdates(updates)
            return postbox.transaction { transaction in
                transaction.updatePeerCachedData(peerIds: Set([peerId]), update: { _, current in
                    if let current = current as? CachedChannelData {
                        return current.withUpdatedGuardBotId(guardBotId)
                    } else {
                        return current
                    }
                })
            }
            |> ignoreValues
            |> castError(UpdateChannelJoinRequestError.self)
        }
    }
}

