import Foundation
import UIKit
import Display
import TelegramCore
import ContextUI
import AppBundle
import SwiftSignalKit
import SGSimpleSettings
import SGStrings

public func sgHiddenChatListFilterIdsSignal() -> Signal<Set<Int32>, NoError> {
    let key = SGSimpleSettings.Keys.hiddenChatListFilterIds
    let read: () -> Set<Int32> = {
        let raw = UserDefaults.standard.stringArray(forKey: key.rawValue) ?? []
        return Set(raw.compactMap { Int32($0) })
    }
    let initial = Signal<Set<Int32>, NoError>.single(read())
    let changes = Signal<Set<Int32>, NoError> { subscriber in
        let observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: nil
        ) { _ in
            subscriber.putNext(read())
        }
        return ActionDisposable {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    return (initial |> then(changes)) |> distinctUntilChanged
}

public func sgVisibleFilters(_ filters: [ChatListContainerNodeFilter]) -> [ChatListContainerNodeFilter] {
    var filters = filters
    if SGSimpleSettings.shared.allChatsHidden {
        filters.removeAll { $0 == .all }
    }
    let sgHiddenFilterIds = SGSimpleSettings.shared.hiddenChatListFilterIds
    if !sgHiddenFilterIds.isEmpty {
        filters.removeAll {
            if case let .filter(filter) = $0, case let .filter(id, _, _, _) = filter {
                return sgHiddenFilterIds.contains(id)
            }
            return false
        }
    }
    return filters
}

public func sgFilterBadge(for id: Int32, filterItems: [(ChatListFilter, Int, Bool)]) -> ContextMenuActionBadge? {
    for item in filterItems {
        if item.0.id == id && item.1 != 0 {
            return ContextMenuActionBadge(value: "\(item.1)", color: item.2 ? .accent : .inactive)
        }
    }
    return nil
}

public func sgHiddenFoldersDrillDownItems(presetList: [ChatListFilter], sgHiddenIds: Set<Int32>, filterItems: [(ChatListFilter, Int, Bool)], backTitle: String, onBack: @escaping () -> Void, onSelect: @escaping (Int32) -> Void) -> [ContextMenuItem] {
    var items: [ContextMenuItem] = []
    items.append(.action(ContextMenuActionItem(text: backTitle, icon: { theme in
        return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Back"), color: theme.contextMenu.primaryColor)
    }, action: { _, _ in
        onBack()
    })))
    items.append(.separator)

    for case let .filter(id, title, _, _) in presetList where sgHiddenIds.contains(id) {
        items.append(.action(ContextMenuActionItem(text: title.text, entities: title.entities, enableEntityAnimations: title.enableAnimations, badge: sgFilterBadge(for: id, filterItems: filterItems), icon: { theme in
            return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Folder"), color: theme.contextMenu.primaryColor)
        }, action: { _, f in
            f(.dismissWithoutContent)
            onSelect(id)
        })))
    }
    return items
}

public func sgHiddenFoldersSummaryItem(presetList: [ChatListFilter], sgHiddenIds: Set<Int32>, filterItems: [(ChatListFilter, Int, Bool)], baseLanguageCode: String, onTap: @escaping () -> Void) -> ContextMenuItem? {
    var hiddenUnreadTotal = 0
    var hasHidden = false
    for case let .filter(id, _, _, _) in presetList where sgHiddenIds.contains(id) {
        hasHidden = true
        for item in filterItems where item.0.id == id {
            hiddenUnreadTotal += item.1
        }
    }
    guard hasHidden else {
        return nil
    }
    return .action(ContextMenuActionItem(text: i18n("ContextMenu.HiddenFolders", baseLanguageCode), badge: hiddenUnreadTotal != 0 ? ContextMenuActionBadge(value: "\(hiddenUnreadTotal)", color: .accent) : nil, icon: { theme in
        return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Eye"), color: theme.contextMenu.primaryColor)
    }, action: { _, _ in
        onTap()
    }))
}
