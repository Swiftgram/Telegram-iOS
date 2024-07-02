import Foundation
import SwiftSignalKit
import TelegramCore
import TelegramUIPreferences
import AccountContext

// MARK: Swiftgram
public let maximumSwiftgramNumberOfAccounts = 500
public let maximumSafeNumberOfAccounts = 6
public let maximumNumberOfAccounts = maximumSwiftgramNumberOfAccounts
public let maximumPremiumNumberOfAccounts = maximumSwiftgramNumberOfAccounts

public func activeAccountsAndPeers(context: AccountContext, includePrimary: Bool = false) -> Signal<((AccountContext, EnginePeer)?, [(AccountContext, EnginePeer, Int32)]), NoError> {
    let sharedContext = context.sharedContext
    return context.sharedContext.activeAccountContexts
    |> mapToSignal { primary, activeAccounts, _ -> Signal<((AccountContext, EnginePeer)?, [(AccountContext, EnginePeer, Int32)]), NoError> in
        var accounts: [Signal<(AccountContext, EnginePeer, Int32)?, NoError>] = []
        func accountWithPeer(_ context: AccountContext) -> Signal<(AccountContext, EnginePeer, Int32)?, NoError> {
            return combineLatest(context.account.postbox.peerView(id: context.account.peerId), renderedTotalUnreadCount(accountManager: sharedContext.accountManager, engine: context.engine))
            |> map { view, totalUnreadCount -> (EnginePeer?, Int32) in
                return (view.peers[view.peerId].flatMap(EnginePeer.init) ?? EnginePeer.init(TelegramUser(id: view.peerId, accessHash: nil, firstName: "RESTORED", lastName: "\(view.peerId.id._internalGetInt64Value())", username: nil, phone: nil, photo: [], botInfo: nil, restrictionInfo: nil, flags: UserInfoFlags(), emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil)), totalUnreadCount.0)
            }
            |> distinctUntilChanged { lhs, rhs in
                if lhs.0 != rhs.0 {
                    return false
                }
                if lhs.1 != rhs.1 {
                    return false
                }
                return true
            }
            |> map { peer, totalUnreadCount -> (AccountContext, EnginePeer, Int32)? in
                if let peer = peer {
                    return (context, peer, totalUnreadCount)
                } else {
                    return nil
                }
            }
        }
        for (_, context, _) in activeAccounts {
            accounts.append(accountWithPeer(context))
        }
        
        return combineLatest(accounts)
        |> map { accounts -> ((AccountContext, EnginePeer)?, [(AccountContext, EnginePeer, Int32)]) in
            var primaryRecord: (AccountContext, EnginePeer)?
            if let first = accounts.filter({ $0?.0.account.id == primary?.account.id }).first, let (account, peer, _) = first {
                primaryRecord = (account, peer)
            }
            let accountRecords: [(AccountContext, EnginePeer, Int32)] = (includePrimary ? accounts : accounts.filter({ $0?.0.account.id != primary?.account.id })).compactMap({ $0 })
            return (primaryRecord, accountRecords)
        }
    }
}

// MARK: Swiftgram
public func getContextForUserId(context: AccountContext, userId: Int64) -> Signal<AccountContext?, NoError> {
    if context.account.peerId.id._internalGetInt64Value() == userId {
        return .single(context)
    }
    return context.sharedContext.activeAccountContexts
    |> take(1)
    |> map { _, activeAccounts, _ -> AccountContext? in
        if let account = activeAccounts.first(where: { $0.1.account.peerId.id._internalGetInt64Value() == userId }) {
            return account.1
        }
        return nil
    }
}
