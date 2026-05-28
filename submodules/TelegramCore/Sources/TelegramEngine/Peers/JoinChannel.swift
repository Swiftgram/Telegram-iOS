import Foundation
import Postbox
import TelegramApi
import SwiftSignalKit
import MtProtoKit


public enum JoinChannelError {
    case generic
    case tooMuchJoined
    case tooMuchUsers
    case inviteRequestSent
}

public enum JoinChannelOutcome {
    case joined(RenderedChannelParticipant?)
    case webView(botId: PeerId, url: String, queryId: Int64)
}

public enum JoinChatBotDecision: Equatable {
    case approved
    case declined
    case queued
    case webView(url: String)
}

public struct JoinChatWebViewDecision: Equatable {
    public let peerId: PeerId
    public let queryId: Int64
    public let result: JoinChatBotDecision

    public init(peerId: PeerId, queryId: Int64, result: JoinChatBotDecision) {
        self.peerId = peerId
        self.queryId = queryId
        self.result = result
    }
}

func extractJoinChatWebViewDecisions(from updates: Api.Updates) -> [JoinChatWebViewDecision] {
    var apiUpdates: [Api.Update] = []
    switch updates {
    case let .updates(data):
        apiUpdates = data.updates
    case let .updatesCombined(data):
        apiUpdates = data.updates
    case let .updateShort(data):
        apiUpdates = [data.update]
    default:
        return []
    }
    var result: [JoinChatWebViewDecision] = []
    for update in apiUpdates {
        if case let .updateJoinChatWebViewDecision(data) = update {
            let decision: JoinChatBotDecision
            switch data.result {
            case .joinChatBotResultApproved:
                decision = .approved
            case .joinChatBotResultDeclined:
                decision = .declined
            case .joinChatBotResultQueued:
                decision = .queued
            case let .joinChatBotResultWebView(webData):
                decision = .webView(url: webData.url)
            }
            result.append(JoinChatWebViewDecision(peerId: data.peer.peerId, queryId: data.queryId, result: decision))
        }
    }
    return result
}

func _internal_joinChannel(account: Account, peerId: PeerId, hash: String?) -> Signal<JoinChannelOutcome, JoinChannelError> {
    return account.postbox.loadedPeerWithId(peerId)
    |> take(1)
    |> castError(JoinChannelError.self)
    |> mapToSignal { peer -> Signal<JoinChannelOutcome, JoinChannelError> in

        let request: Signal<Api.messages.ChatInviteJoinResult, MTRpcError>
        if let hash = hash {
            request = account.network.request(Api.functions.messages.importChatInvite(hash: hash))
        } else if let inputChannel = apiInputChannel(peer) {
            request = account.network.request(Api.functions.channels.joinChannel(channel: inputChannel))
        } else {
            request = .fail(.init())
        }

        return request
        |> mapError { error -> JoinChannelError in
            switch error.errorDescription {
                case "CHANNELS_TOO_MUCH":
                    return .tooMuchJoined
                case "USERS_TOO_MUCH":
                    return .tooMuchUsers
                case "INVITE_REQUEST_SENT":
                    return .inviteRequestSent
                default:
                    return .generic
            }
        }
        |> mapToSignal { result -> Signal<JoinChannelOutcome, JoinChannelError> in
            switch result {
            case let .chatInviteJoinResultOk(result):
                account.stateManager.addUpdates(result.updates)

                let channels = result.updates.chats.compactMap { parseTelegramGroupOrChannel(chat: $0) }.compactMap(apiInputChannel)

                if let inputChannel = channels.first {
                    return account.network.request(Api.functions.channels.getParticipant(channel: inputChannel, participant: .inputPeerSelf))
                    |> map(Optional.init)
                    |> `catch` { _ -> Signal<Api.channels.ChannelParticipant?, JoinChannelError> in
                        return .single(nil)
                    }
                    |> mapToSignal { result -> Signal<JoinChannelOutcome, JoinChannelError> in
                        guard let result = result else {
                            return .fail(.generic)
                        }
                        return account.postbox.transaction { transaction -> JoinChannelOutcome in
                            var peers: [EnginePeer.Id: EnginePeer] = [:]
                            var presences: [PeerId: PeerPresence] = [:]
                            guard let peer = transaction.getPeer(account.peerId) else {
                                return .joined(nil)
                            }
                            peers[account.peerId] = EnginePeer(peer)
                            if let presence = transaction.getPeerPresence(peerId: account.peerId) {
                                presences[account.peerId] = presence
                            }
                            let updatedParticipant: ChannelParticipant
                            switch result {
                                case let .channelParticipant(channelParticipantData):
                                    let participant = channelParticipantData.participant
                                    updatedParticipant = ChannelParticipant(apiParticipant: participant)
                            }
                            if case let .member(_, _, maybeAdminInfo, _, _, _) = updatedParticipant {
                                if let adminInfo = maybeAdminInfo {
                                    if let peer = transaction.getPeer(adminInfo.promotedBy) {
                                        peers[peer.id] = EnginePeer(peer)
                                    }
                                }
                            }

                            return .joined(RenderedChannelParticipant(participant: updatedParticipant, peer: EnginePeer(peer), peers: peers, presences: presences))
                        }
                        |> castError(JoinChannelError.self)
                    }
                } else {
                    return .fail(.generic)
                }
            case let .chatInviteJoinResultWebView(data):
                return account.postbox.transaction { transaction -> Void in
                    updatePeers(transaction: transaction, accountPeerId: account.peerId, peers: AccumulatedPeers(transaction: transaction, chats: [], users: data.users))
                }
                |> castError(JoinChannelError.self)
                |> map { _ -> JoinChannelOutcome in
                    switch data.webview {
                    case let .webViewResultUrl(webViewResultUrl):
                        return .webView(botId: PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(data.botId)), url: webViewResultUrl.url, queryId: webViewResultUrl.queryId ?? 0)
                    }
                }
            }
        }
        |> afterCompleted {
            if hash == nil {
                let _ = _internal_requestRecommendedChannels(account: account, peerId: peerId, forceUpdate: true).startStandalone()
            }
        }
    }
}
