// MARK: Swiftgram
import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import SGSimpleSettings

private enum SGCustomTweaksSection: Int32 {
    case ghost
    case balances
    case media
    case appearance
    case tags
}

private enum SGCustomTweaksToggle: Hashable {
    case ghostMode
    case keepSecretMedia
    case phantomGifts
    case disableLiquidGlass
}

private enum SGCustomTweaksText: Hashable {
    case starsBalance
    case gramBalance
    case tagDraft
}

private enum SGCustomTweaksAction: Hashable {
    case selectTagPeer
    case clearTag
    case clearAllTags
}

private struct SGCustomTweaksControllerState: Equatable {
    var revision: Int = 0
    var tagPeerId: Int64?
    var tagPeerName: String?
    var tagDraft: String = ""
}

private final class SGCustomTweaksControllerArguments {
    let toggle: (SGCustomTweaksToggle, Bool) -> Void
    let updateText: (SGCustomTweaksText, String) -> Void
    let performAction: (SGCustomTweaksAction) -> Void

    init(toggle: @escaping (SGCustomTweaksToggle, Bool) -> Void, updateText: @escaping (SGCustomTweaksText, String) -> Void, performAction: @escaping (SGCustomTweaksAction) -> Void) {
        self.toggle = toggle
        self.updateText = updateText
        self.performAction = performAction
    }
}

private enum SGCustomTweaksEntry: ItemListNodeEntry {
    case header(id: Int32, section: SGCustomTweaksSection, text: String)
    case toggle(id: Int32, section: SGCustomTweaksSection, kind: SGCustomTweaksToggle, value: Bool, text: String, enabled: Bool)
    case notice(id: Int32, section: SGCustomTweaksSection, text: String)
    case textInput(id: Int32, section: SGCustomTweaksSection, kind: SGCustomTweaksText, title: String, text: String, placeholder: String)
    case action(id: Int32, section: SGCustomTweaksSection, kind: SGCustomTweaksAction, text: String, destructive: Bool, enabled: Bool)

    var section: ItemListSectionId {
        switch self {
        case let .header(_, section, _):
            return section.rawValue
        case let .toggle(_, section, _, _, _, _):
            return section.rawValue
        case let .notice(_, section, _):
            return section.rawValue
        case let .textInput(_, section, _, _, _, _):
            return section.rawValue
        case let .action(_, section, _, _, _, _):
            return section.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case let .header(id, _, _):
            return id
        case let .toggle(id, _, _, _, _, _):
            return id
        case let .notice(id, _, _):
            return id
        case let .textInput(id, _, _, _, _, _):
            return id
        case let .action(id, _, _, _, _, _):
            return id
        }
    }

    static func ==(lhs: SGCustomTweaksEntry, rhs: SGCustomTweaksEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.header(lhsId, lhsSection, lhsText), .header(rhsId, rhsSection, rhsText)):
            return lhsId == rhsId && lhsSection == rhsSection && lhsText == rhsText
        case let (.toggle(lhsId, lhsSection, lhsKind, lhsValue, lhsText, lhsEnabled), .toggle(rhsId, rhsSection, rhsKind, rhsValue, rhsText, rhsEnabled)):
            return lhsId == rhsId && lhsSection == rhsSection && lhsKind == rhsKind && lhsValue == rhsValue && lhsText == rhsText && lhsEnabled == rhsEnabled
        case let (.notice(lhsId, lhsSection, lhsText), .notice(rhsId, rhsSection, rhsText)):
            return lhsId == rhsId && lhsSection == rhsSection && lhsText == rhsText
        case let (.textInput(lhsId, lhsSection, lhsKind, lhsTitle, lhsText, lhsPlaceholder), .textInput(rhsId, rhsSection, rhsKind, rhsTitle, rhsText, rhsPlaceholder)):
            return lhsId == rhsId && lhsSection == rhsSection && lhsKind == rhsKind && lhsTitle == rhsTitle && lhsText == rhsText && lhsPlaceholder == rhsPlaceholder
        case let (.action(lhsId, lhsSection, lhsKind, lhsText, lhsDestructive, lhsEnabled), .action(rhsId, rhsSection, rhsKind, rhsText, rhsDestructive, rhsEnabled)):
            return lhsId == rhsId && lhsSection == rhsSection && lhsKind == rhsKind && lhsText == rhsText && lhsDestructive == rhsDestructive && lhsEnabled == rhsEnabled
        default:
            return false
        }
    }

    static func <(lhs: SGCustomTweaksEntry, rhs: SGCustomTweaksEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! SGCustomTweaksControllerArguments
        switch self {
        case let .header(_, _, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .toggle(_, _, kind, value, text, enabled):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: text, value: value, enabled: enabled, maximumNumberOfLines: 0, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggle(kind, value)
            })
        case let .notice(_, _, text):
            return ItemListTextItem(presentationData: presentationData, text: .markdown(text), sectionId: self.section)
        case let .textInput(_, _, kind, title, text, placeholder):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(string: title, textColor: presentationData.theme.list.itemPrimaryTextColor), text: text, placeholder: placeholder, type: .regular(capitalization: false, autocorrection: false), spacing: 0.0, clearType: .always, maxLength: 32, sectionId: self.section, textUpdated: { updatedText in
                arguments.updateText(kind, updatedText)
            }, action: {})
        case let .action(_, _, kind, text, destructive, enabled):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: text, kind: destructive ? .destructive : .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                if enabled {
                    arguments.performAction(kind)
                }
            })
        }
    }
}

private func sgCustomTweaksEntries(presentationData: PresentationData, state: SGCustomTweaksControllerState) -> [SGCustomTweaksEntry] {
    var entries: [SGCustomTweaksEntry] = []
    let settings = SGSimpleSettings.shared

    entries.append(.header(id: 0, section: .ghost, text: "РЕЖИМ ПРИЗРАКА"))
    entries.append(.toggle(id: 1, section: .ghost, kind: .ghostMode, value: settings.ghostMode, text: "Режим призрака", enabled: true))
    entries.append(.notice(id: 2, section: .ghost, text: "Клиент не сообщает серверу, что вы в сети, и не отправляет отметки о прочтении. Собеседники видят вас офлайн, а сообщения остаются непрочитанными."))

    entries.append(.header(id: 10, section: .balances, text: "КАСТОМНЫЙ БАЛАНС"))
    entries.append(.textInput(id: 11, section: .balances, kind: .starsBalance, title: "Звезды", text: settings.customStarsBalance, placeholder: "Реальный баланс"))
    entries.append(.textInput(id: 12, section: .balances, kind: .gramBalance, title: "GRAM", text: settings.customGramBalance, placeholder: "Реальный баланс"))
    entries.append(.notice(id: 13, section: .balances, text: "Это локальный визуальный фейк: значения показываются в профиле и кошельке только на этом устройстве и не меняют реальный баланс. Оставьте поле пустым, чтобы видеть настоящий баланс."))

    entries.append(.header(id: 20, section: .media, text: "ОДНОРАЗОВЫЕ МЕДИА"))
    entries.append(.toggle(id: 21, section: .media, kind: .keepSecretMedia, value: settings.keepSecretMedia, text: "Бесконечный просмотр", enabled: true))
    entries.append(.notice(id: 22, section: .media, text: "Фото, видео и голосовые сообщения с таймером не скрываются и не удаляются из интерфейса после истечения таймера."))
    entries.append(.toggle(id: 23, section: .media, kind: .phantomGifts, value: settings.phantomGifts, text: "Фантомный подарок GRAM", enabled: true))
    entries.append(.notice(id: 24, section: .media, text: "В разделе подарков вашего профиля показывается локальный премиальный подарок с логотипом GRAM. Его видите только вы."))

    entries.append(.header(id: 30, section: .appearance, text: "ИНТЕРФЕЙС"))
    entries.append(.toggle(id: 31, section: .appearance, kind: .disableLiquidGlass, value: settings.disableLiquidGlass, text: "Отключить жидкое стекло", enabled: true))
    entries.append(.notice(id: 32, section: .appearance, text: "Размытие и эффекты жидкого стекла заменяются сплошными полупрозрачными цветами. Это экономит батарею и делает интерфейс плавнее."))

    entries.append(.header(id: 40, section: .tags, text: "ЛОКАЛЬНЫЕ ТЕГИ"))
    if let tagPeerName = state.tagPeerName, state.tagPeerId != nil {
        entries.append(.textInput(id: 41, section: .tags, kind: .tagDraft, title: tagPeerName, text: state.tagDraft, placeholder: "Текст тега"))
        entries.append(.action(id: 42, section: .tags, kind: .clearTag, text: "Удалить тег", destructive: true, enabled: true))
    } else {
        entries.append(.notice(id: 41, section: .tags, text: "Выберите пользователя, чтобы добавить или изменить его локальный тег. Тег отображается плашкой в списке чатов и в заголовке диалога."))
    }
    entries.append(.action(id: 43, section: .tags, kind: .selectTagPeer, text: "Выбрать пользователя", destructive: false, enabled: true))
    entries.append(.action(id: 44, section: .tags, kind: .clearAllTags, text: "Удалить все теги", destructive: true, enabled: !settings.userTags.isEmpty))

    return entries
}

public func sgCustomTweaksController(context: AccountContext) -> ViewController {
    var presentControllerImpl: ((ViewController) -> Void)?

    let initialState = SGCustomTweaksControllerState()
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((SGCustomTweaksControllerState) -> SGCustomTweaksControllerState) -> Void = { f in
        statePromise.set(stateValue.modify { f($0) })
    }

    let arguments = SGCustomTweaksControllerArguments(toggle: { kind, value in
        let settings = SGSimpleSettings.shared
        switch kind {
        case .ghostMode:
            settings.ghostMode = value
            // Re-apply presence immediately instead of waiting for the next presence tick.
            NotificationCenter.default.post(name: .sgGhostModeChanged, object: nil)
        case .keepSecretMedia:
            settings.keepSecretMedia = value
        case .phantomGifts:
            settings.phantomGifts = value
        case .disableLiquidGlass:
            settings.disableLiquidGlass = value
        }
        updateState { state in
            var updatedState = state
            updatedState.revision += 1
            return updatedState
        }
    }, updateText: { kind, text in
        let settings = SGSimpleSettings.shared
        switch kind {
        case .starsBalance:
            settings.customStarsBalance = text
        case .gramBalance:
            settings.customGramBalance = text
        case .tagDraft:
            var peerId: Int64?
            stateValue.with { peerId = $0.tagPeerId }
            if let peerId {
                settings.setUserTag(text, for: peerId)
            }
            // Deliberately does not re-render the list: rebuilding the item while the
            // field is first responder would drop the keyboard and the caret.
            let _ = stateValue.modify { state in
                var updatedState = state
                updatedState.tagDraft = text
                return updatedState
            }
        }
    }, performAction: { action in
        switch action {
        case .selectTagPeer:
            let contactSelectionController = context.sharedContext.makeContactSelectionController(ContactSelectionControllerParams(
                context: context,
                style: .glass,
                title: { $0.Contacts_Title },
                multipleSelection: .disabled
            ))
            contactSelectionController.navigationPresentation = .modal
            let _ = (contactSelectionController.result
            |> take(1)
            |> deliverOnMainQueue).start(next: { result in
                guard let (peers, _, _, _, _, _) = result, let firstPeer = peers.first, case let .peer(peer, _, _) = firstPeer else {
                    return
                }
                let peerId = peer.id.toInt64()
                let existingTag = SGSimpleSettings.shared.userTag(for: peerId) ?? ""
                updateState { state in
                    var updatedState = state
                    updatedState.tagPeerId = peerId
                    updatedState.tagPeerName = peer.compactDisplayTitle
                    updatedState.tagDraft = existingTag
                    return updatedState
                }
            })
            presentControllerImpl?(contactSelectionController)        case .clearTag:
            var peerId: Int64?
            stateValue.with { peerId = $0.tagPeerId }
            if let peerId {
                SGSimpleSettings.shared.setUserTag(nil, for: peerId)
            }
            updateState { state in
                var updatedState = state
                updatedState.tagDraft = ""
                return updatedState
            }
        case .clearAllTags:
            SGSimpleSettings.shared.clearUserTags()
            updateState { state in
                var updatedState = state
                updatedState.tagPeerId = nil
                updatedState.tagPeerName = nil
                updatedState.tagDraft = ""
                return updatedState
            }
        }
    })

    let signal = combineLatest(queue: Queue.mainQueue(), context.sharedContext.presentationData, statePromise.get())
    |> deliverOnMainQueue
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Кастомные твики Swiftgram"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))

        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: sgCustomTweaksEntries(presentationData: presentationData, state: state), style: .blocks, animateChanges: false)

        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    return controller
}
