import Foundation
import Postbox
import SwiftSignalKit
import TelegramApi
import MtProtoKit
import SGConfig
import SGLogging


public struct SGIQTPResponse {
    public let status: Int
    public let description: String?
    public let text: String?
}

public func makeIqtpQuery(_ api: Int, _ method: String, _ args: [String] = []) -> String {
    let buildNumber = Bundle.main.infoDictionary?[kCFBundleVersionKey as String] ?? ""
    let baseQuery = "tp:\(api):\(buildNumber):\(method)"
    if args.isEmpty {
        return baseQuery
    }
    return baseQuery + ":" + args.joined(separator: ":")
}

public func sgIqtpQuery(engine: TelegramEngine, query: String, incompleteResults: Bool = false, staleCachedResults: Bool = false) -> Signal<SGIQTPResponse?, NoError> {
    #if DEBUG
    SGLogger.shared.log("SGIQTP", "Query: \(query)")
    #else
    SGLogger.shared.log("SGIQTP", "Query")
    #endif
    return engine.peers.resolvePeerByName(name: SG_CONFIG.botUsername, referrer: nil)
        |> mapToSignal { result -> Signal<EnginePeer?, NoError> in
            guard case let .result(result) = result else {
                SGLogger.shared.log("SGIQTP", "Failed to resolve peer")
                return .complete()
            }
            return .single(result)
        }
        |> mapToSignal { peer -> Signal<ChatContextResultCollection?, NoError> in
            guard let peer = peer else {
                SGLogger.shared.log("SGIQTP", "Empty peer")
                return .single(nil)
            }
            return engine.messages.requestChatContextResults(botId: peer.id, peerId: engine.account.peerId, query: query, offset: "", incompleteResults: incompleteResults, staleCachedResults: staleCachedResults)
            |> map { results -> ChatContextResultCollection? in
                return results?.results
            }
            |> `catch` { error -> Signal<ChatContextResultCollection?, NoError> in
                SGLogger.shared.log("SGIQTP", "Failed to request inline results")
                return .single(nil)
            }
        }
        |> map { contextResult -> SGIQTPResponse? in
            guard let contextResult, let firstResult = contextResult.results.first else {
                SGLogger.shared.log("SGIQTP", "Empty inline result")
                return nil
            }
            
            var t: String?
            if case let .text(text, _, _, _, _) = firstResult.message {
                t = text
            }

            var status = 400
            if let title = firstResult.title {
                status = Int(title) ?? 400
            }
            let response = SGIQTPResponse(
                status: status,
                description: firstResult.description,
                text: t
            )
            SGLogger.shared.log("SGIQTP", "Response: \(response)")
            return response
        }
}
