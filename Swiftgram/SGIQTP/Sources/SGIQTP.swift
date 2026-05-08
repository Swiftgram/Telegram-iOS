import SGConfig
import SGLogging
import CryptoKit
import Foundation
import MtProtoKit
import Postbox
import Security
import SwiftSignalKit
import TelegramApi


public struct SGIQTPResponse {
    public let status: Int
    public let value: String
}


private let sgIqtpTokenPrefix = "sgsig.v1."
private let sgIqtpTokenMinimumParts = 4
private let sgIqtpTokenSeparator: Character = "."
private let sgIqtpTokenMaxPastSkew: Int64 = 30
private let sgIqtpTokenMaxFutureSkew: Int64 = 10 * 60
private let sgIqtpApiVersion = 1

private func sgBase64UrlEncode(_ data: Data) -> String {
    let sgBase64 = data.base64EncodedString()
    return sgBase64
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

public func makeIqtpQuery(_ method: String, _ args: [String] = []) -> String {
    let buildNumber = Bundle.main.infoDictionary?[kCFBundleVersionKey as String] ?? ""
    let nonceLength = 16
    var bytes = [UInt8](repeating: 0, count: nonceLength)
    let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    if status != errSecSuccess {
        for index in 0..<bytes.count {
            bytes[index] = UInt8.random(in: 0...UInt8.max)
        }
    }
    let nonce = sgBase64UrlEncode(Data(bytes)).replacingOccurrences(of: ":", with: "_")
    let queryArgs = [nonce] + args
    let baseQuery = "tp:\(sgIqtpApiVersion):\(buildNumber):\(method)"
    if queryArgs.isEmpty {
        return baseQuery
    }
    return baseQuery + ":" + queryArgs.joined(separator: ":")
}

public func sgIqtpQuery(engine: TelegramEngine, query: String, incompleteResults: Bool = false, staleCachedResults: Bool = false) -> Signal<SGIQTPResponse?, NoError> {
    let queryId = arc4random()
    func sgVerifySignedAnswer(query: String, answer: String, peerId: PeerId) -> String? {
        func sgBase64UrlDecode(_ value: String) -> Data? {
            var sgBase64 = value
                .replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/")
            let sgRemainder = sgBase64.count % 4
            if sgRemainder > 0 {
                sgBase64 += String(repeating: "=", count: 4 - sgRemainder)
            }
            return Data(base64Encoded: sgBase64)
        }

        func sgDecodePublicKey(_ value: String) -> Data? {
            if let sgData = Data(base64Encoded: value) {
                return sgData
            }
            return sgBase64UrlDecode(value)
        }

        func sgExtractSignedToken(from text: String) -> (payload: String, signature: String)? {
            guard let sgRange = text.range(of: sgIqtpTokenPrefix) else {
                return nil
            }
            let sgTokenStart = text[sgRange.lowerBound...]
            guard let sgTokenPart = sgTokenStart.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).first else {
                return nil
            }
            let sgParts = sgTokenPart.split(separator: sgIqtpTokenSeparator, omittingEmptySubsequences: false)
            guard sgParts.count >= sgIqtpTokenMinimumParts else {
                return nil
            }
            guard sgParts[0] == "sgsig", sgParts[1] == "v1" else {
                return nil
            }
            return (payload: String(sgParts[2]), signature: String(sgParts[3]))
        }

        let sgQueryParts = query.split(separator: ":", omittingEmptySubsequences: false)
        guard sgQueryParts.count >= 4, sgQueryParts[0] == "tp" else {
            SGLogger.shared.log("SGIQTP", "Missing IQTP query info")
            return nil
        }
        guard let sgQueryVersion = Int(sgQueryParts[1]), sgQueryVersion == 1 else {
            SGLogger.shared.log("SGIQTP", "Unsupported IQTP version")
            return nil
        }
        let sgQueryBuild = String(sgQueryParts[2])
        let sgQueryMethod = String(sgQueryParts[3])
        let sgQueryArgs = sgQueryParts.count > 4 ? sgQueryParts[4...].map { String($0) } : []
        guard let sgNonce = sgQueryArgs.first, !sgNonce.isEmpty else {
            SGLogger.shared.log("SGIQTP", "Missing IQTP nonce")
            return nil
        }

        guard let sgPublicKey = SG_CONFIG.publicKey, !sgPublicKey.isEmpty else {
            SGLogger.shared.log("SGIQTP", "Missing public key")
            return nil
        }
        guard let sgToken = sgExtractSignedToken(from: answer) else {
            SGLogger.shared.log("SGIQTP", "Missing signed IQTP token")
            return nil
        }
        guard let sgAnswerData = sgBase64UrlDecode(sgToken.payload) else {
            SGLogger.shared.log("SGIQTP", "Invalid IQTP answer encoding")
            return nil
        }
        guard let sgSignatureData = sgBase64UrlDecode(sgToken.signature) else {
            SGLogger.shared.log("SGIQTP", "Invalid IQTP signature encoding")
            return nil
        }
        guard let sgPublicKeyData = sgDecodePublicKey(sgPublicKey) else {
            SGLogger.shared.log("SGIQTP", "Invalid public key")
            return nil
        }
        guard let sgSigningKey = try? Curve25519.Signing.PublicKey(rawRepresentation: sgPublicKeyData) else {
            SGLogger.shared.log("SGIQTP", "Invalid public key bytes")
            return nil
        }
        guard sgSigningKey.isValidSignature(sgSignatureData, for: sgAnswerData) else {
            SGLogger.shared.log("SGIQTP", "Invalid IQTP signature")
            return nil
        }
        guard let sgAnswerString = String(data: sgAnswerData, encoding: .utf8) else {
            SGLogger.shared.log("SGIQTP", "Invalid IQTP answer string")
            return nil
        }
        let sgAnswerParts = sgAnswerString.split(separator: ":", omittingEmptySubsequences: false)
        guard sgAnswerParts.count == 8 else {
            SGLogger.shared.log("SGIQTP", "Invalid IQTP answer parts count")
            return nil
        }
        guard let sgAnswerVersion = Int(sgAnswerParts[0]), sgAnswerVersion == 1 else {
            SGLogger.shared.log("SGIQTP", "Invalid IQTP answer version")
            return nil
        }
        let sgAnswerMethod = String(sgAnswerParts[1])
        guard sgAnswerMethod == sgQueryMethod else {
            SGLogger.shared.log("SGIQTP", "Invalid IQTP answer method")
            return nil
        }
        guard let sgAnswerPeerId = Int64(sgAnswerParts[2]) else {
            SGLogger.shared.log("SGIQTP", "Invalid IQTP answer peer id")
            return nil
        }
        let sgAnswerNonce = String(sgAnswerParts[3])
        guard sgAnswerNonce == sgNonce else {
            SGLogger.shared.log("SGIQTP", "Invalid IQTP answer nonce")
            return nil
        }
        guard let sgIat = Int64(sgAnswerParts[4]), let sgExp = Int64(sgAnswerParts[5]) else {
            SGLogger.shared.log("SGIQTP", "Invalid IQTP answer timing")
            return nil
        }
        let sgValue = String(sgAnswerParts[6])
        let sgAnswerBuild = String(sgAnswerParts[7])
        guard sgAnswerBuild == sgQueryBuild else {
            SGLogger.shared.log("SGIQTP", "Invalid IQTP answer build number")
            return nil
        }
        let sgNow = Int64(Date().timeIntervalSince1970)
        guard sgExp >= sgNow - sgIqtpTokenMaxPastSkew else {
            SGLogger.shared.log("SGIQTP", "Expired IQTP answer")
            return nil
        }
        guard sgExp <= sgNow + sgIqtpTokenMaxFutureSkew else {
            SGLogger.shared.log("SGIQTP", "IQTP answer exp too far in future")
            return nil
        }
        guard sgIat <= sgExp else {
            SGLogger.shared.log("SGIQTP", "Invalid IQTP answer timing order")
            return nil
        }
        let sgCurrentPeerId = peerId.id._internalGetInt64Value()
        guard sgAnswerPeerId == sgCurrentPeerId else {
            SGLogger.shared.log("SGIQTP", "IQTP answer peer id mismatch")
            return nil
        }
        return sgValue
    }
    #if DEBUG
    SGLogger.shared.log("SGIQTP", "[\(queryId)] Query: \(query)")
    #else
    SGLogger.shared.log("SGIQTP", "[\(queryId)] Query")
    #endif
    return engine.peers.resolvePeerByName(name: SG_CONFIG.botUsername, referrer: nil)
        |> mapToSignal { result -> Signal<EnginePeer?, NoError> in
            guard case let .result(result) = result else {
                SGLogger.shared.log("SGIQTP", "[\(queryId)] Failed to resolve peer \(SG_CONFIG.botUsername)")
                return .complete()
            }
            return .single(result)
        }
        |> mapToSignal { peer -> Signal<ChatContextResultCollection?, NoError> in
            guard let peer = peer else {
                SGLogger.shared.log("SGIQTP", "[\(queryId)] Empty peer")
                return .single(nil)
            }
            return engine.messages.requestChatContextResults(IQTP: true, botId: peer.id, peerId: engine.account.peerId, query: query, offset: "", incompleteResults: incompleteResults, staleCachedResults: staleCachedResults)
            |> map { results -> ChatContextResultCollection? in
                return results?.results
            }
            |> `catch` { error -> Signal<ChatContextResultCollection?, NoError> in
                SGLogger.shared.log("SGIQTP", "[\(queryId)] Failed to request inline results")
                return .single(nil)
            }
        }
        |> map { contextResult -> SGIQTPResponse? in
            guard let contextResult, let firstResult = contextResult.results.first else {
                SGLogger.shared.log("SGIQTP", "[\(queryId)] Empty inline result")
                return nil
            }
            
            var t: String?
            if case let .text(text, _, _, _, _) = firstResult.message {
                t = text
            }

            guard let t else {
                SGLogger.shared.log("SGIQTP", "[\(queryId)] Missing signed IQTP answer")
                return nil
            }
            let sgValue: String
            if let sgVerifiedValue = sgVerifySignedAnswer(query: query, answer: t, peerId: engine.account.peerId) {
                sgValue = sgVerifiedValue
            } else {
                SGLogger.shared.log("SGIQTP", "[\(queryId)] Invalid signed IQTP token")
                return nil
            }

            var status = 400
            if let title = firstResult.title {
                status = Int(title) ?? 400
            }
            let response = SGIQTPResponse(status: status, value: sgValue)
            SGLogger.shared.log("SGIQTP", "[\(queryId)] Response status: \(status)")
            return response
        }
}
