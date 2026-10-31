import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import ItemListPeerItem
import AccountContext
import AccountUtils
import SGStrings

private final class SGAccountOrderArguments {
    let context: AccountContext

    init(context: AccountContext) {
        self.context = context
    }
}

private enum SGAccountOrderEntryStableId: Hashable {
    case account(AccountRecordId)
    case notice
}

private enum SGAccountOrderEntry: ItemListNodeEntry {
    case account(index: Int, context: AccountContext, peer: EnginePeer)
    case notice(text: String)

    var section: ItemListSectionId {
        return 0
    }

    var stableId: SGAccountOrderEntryStableId {
        switch self {
        case let .account(_, context, _):
            return .account(context.account.id)
        case .notice:
            return .notice
        }
    }

    private var sortIndex: Int {
        switch self {
        case let .account(index, _, _):
            return index
        case .notice:
            return Int.max
        }
    }

    static func ==(lhs: SGAccountOrderEntry, rhs: SGAccountOrderEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.account(lhsIndex, lhsContext, lhsPeer), .account(rhsIndex, rhsContext, rhsPeer)):
            return lhsIndex == rhsIndex && lhsContext === rhsContext && lhsPeer == rhsPeer
        case let (.notice(lhsText), .notice(rhsText)):
            return lhsText == rhsText
        default:
            return false
        }
    }

    static func <(lhs: SGAccountOrderEntry, rhs: SGAccountOrderEntry) -> Bool {
        return lhs.sortIndex < rhs.sortIndex
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! SGAccountOrderArguments
        switch self {
        case let .account(_, context, peer):
            let currentPresentationData = arguments.context.sharedContext.currentPresentationData.with { $0 }
            // Each row reads its peer from its own account.
            let itemContext = ItemListPeerItem.Context.custom(ItemListPeerItem.Context.Custom(
                accountPeerId: context.account.peerId,
                engine: context.engine,
                animationCache: arguments.context.animationCache,
                animationRenderer: arguments.context.animationRenderer,
                isPremiumDisabled: false,
                resolveInlineStickers: { fileIds in
                    return arguments.context.engine.stickers.resolveInlineStickers(fileIds: fileIds)
                }
            ))
            return ItemListPeerItem(
                presentationData: presentationData,
                dateTimeFormat: currentPresentationData.dateTimeFormat,
                nameDisplayOrder: currentPresentationData.nameDisplayOrder,
                context: itemContext,
                peer: peer,
                presence: nil,
                text: .none,
                label: .none,
                editing: ItemListPeerItemEditing(editable: false, editing: true, canBeReordered: true, revealed: false),
                switchValue: nil,
                enabled: true,
                selectable: false,
                sectionId: self.section,
                action: nil,
                setPeerIdWithRevealedOptions: { _, _ in },
                removePeer: { _ in }
            )
        case let .notice(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private func sgAccountsWithAppliedOrder(_ accounts: [(AccountContext, EnginePeer)], order: [AccountRecordId]?) -> [(AccountContext, EnginePeer)] {
    guard let order else {
        return accounts
    }
    var result: [(AccountContext, EnginePeer)] = []
    for id in order {
        if let account = accounts.first(where: { $0.0.account.id == id }) {
            result.append(account)
        }
    }
    // An account added while this screen is open goes last, as it would on login.
    for account in accounts where !order.contains(account.0.account.id) {
        result.append(account)
    }
    return result
}

/// Numbers every record, not only the listed ones: accounts with equal numbers would swap between launches.
private func sgUpdateAccountOrder(accountManager: AccountManager<TelegramAccountManagerTypes>, currentId: AccountRecordId, orderedIds: [AccountRecordId]) -> Signal<Void, NoError> {
    return accountManager.transaction { transaction -> Void in
        // Without a stored current id the first account is treated as current, so the new order would switch accounts.
        if transaction.getCurrent() == nil {
            transaction.setCurrentId(currentId)
        }
        let unlistedIds = transaction.getRecords().map(\.id).filter { !orderedIds.contains($0) }
        for (order, id) in (orderedIds + unlistedIds).enumerated() {
            transaction.updateRecord(id, { record in
                guard let record else {
                    return nil
                }
                var attributes = record.attributes.filter { attribute in
                    if case .sortOrder = attribute {
                        return false
                    } else {
                        return true
                    }
                }
                attributes.append(.sortOrder(AccountSortOrderAttribute(order: Int32(order))))
                return AccountRecord(id: record.id, attributes: attributes, temporarySessionId: record.temporarySessionId)
            })
        }
    }
}

public func sgAccountOrderController(context: AccountContext) -> ViewController {
    let arguments = SGAccountOrderArguments(context: context)

    let accounts = Promise<[(AccountContext, EnginePeer)]>()
    accounts.set(activeAccountsAndPeers(context: context, includePrimary: true)
    |> map { _, accounts -> [(AccountContext, EnginePeer)] in
        return accounts.map { ($0.0, $0.1) }
    })
    // Written to the account manager only on drop: every write makes the app re-emit its account list.
    let updatedOrder = Promise<[AccountRecordId]?>(nil)

    let signal = combineLatest(
        queue: .mainQueue(),
        context.sharedContext.presentationData,
        accounts.get(),
        updatedOrder.get()
    )
    |> map { presentationData, accounts, order -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let lang = presentationData.strings.baseLanguageCode
        var entries: [SGAccountOrderEntry] = []
        for (index, account) in sgAccountsWithAppliedOrder(accounts, order: order).enumerated() {
            entries.append(.account(index: index, context: account.0, peer: account.1))
        }
        entries.append(.notice(text: i18n("Settings.AccountOrder.Notice", lang)))

        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(i18n("Settings.AccountOrder", lang)), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    controller.setReorderEntry({ (fromIndex: Int, toIndex: Int, entries: [SGAccountOrderEntry]) -> Signal<Bool, NoError> in
        guard case let .account(_, fromContext, _) = entries[fromIndex] else {
            return .single(false)
        }
        let fromId = fromContext.account.id
        var referenceId: AccountRecordId?
        if toIndex < entries.count, case let .account(_, referenceContext, _) = entries[toIndex] {
            referenceId = referenceContext.account.id
        }

        return combineLatest(
            accounts.get() |> take(1),
            updatedOrder.get() |> take(1)
        )
        |> mapToSignal { accounts, order -> Signal<Bool, NoError> in
            let initialIds = sgAccountsWithAppliedOrder(accounts, order: order).map { $0.0.account.id }
            var ids = initialIds.filter { $0 != fromId }
            if let referenceId, let index = ids.firstIndex(of: referenceId) {
                ids.insert(fromId, at: fromIndex < toIndex ? index + 1 : index)
            } else {
                ids.append(fromId)
            }
            if ids != initialIds {
                updatedOrder.set(.single(ids))
                return .single(true)
            } else {
                return .single(false)
            }
        }
    })
    controller.setReorderCompleted({ (_: [SGAccountOrderEntry]) -> Void in
        let _ = (updatedOrder.get()
        |> take(1)
        |> deliverOnMainQueue).start(next: { order in
            guard let order else {
                return
            }
            let _ = sgUpdateAccountOrder(accountManager: context.sharedContext.accountManager, currentId: context.account.id, orderedIds: order).start()
        })
    })
    return controller
}
