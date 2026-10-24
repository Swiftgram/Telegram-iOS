import Foundation
import AccountContext
import Display
import ItemListUI
import PresentationDataUtils
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TranslateUI

private final class SGOutgoingTranslationLanguageSelectionArguments {
    let selectLanguage: (String) -> Void
    
    init(selectLanguage: @escaping (String) -> Void) {
        self.selectLanguage = selectLanguage
    }
}

private enum SGOutgoingTranslationLanguageSelectionSection: Int32 {
    case languages
}

private enum SGOutgoingTranslationLanguageSelectionEntry: ItemListNodeEntry {
    case language(Int32, PresentationTheme, String, String, Bool, String)
    
    var section: ItemListSectionId {
        return SGOutgoingTranslationLanguageSelectionSection.languages.rawValue
    }
    
    var stableId: Int32 {
        switch self {
        case let .language(index, _, _, _, _, _):
            return index
        }
    }
    
    static func ==(lhs: SGOutgoingTranslationLanguageSelectionEntry, rhs: SGOutgoingTranslationLanguageSelectionEntry) -> Bool {
        switch lhs {
        case let .language(lhsIndex, lhsTheme, lhsTitle, lhsSubtitle, lhsSelected, lhsCode):
            if case let .language(rhsIndex, rhsTheme, rhsTitle, rhsSubtitle, rhsSelected, rhsCode) = rhs {
                return lhsIndex == rhsIndex && lhsTheme === rhsTheme && lhsTitle == rhsTitle && lhsSubtitle == rhsSubtitle && lhsSelected == rhsSelected && lhsCode == rhsCode
            } else {
                return false
            }
        }
    }
    
    static func <(lhs: SGOutgoingTranslationLanguageSelectionEntry, rhs: SGOutgoingTranslationLanguageSelectionEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }
    
    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! SGOutgoingTranslationLanguageSelectionArguments
        switch self {
        case let .language(_, _, title, subtitle, selected, code):
            return LocalizationListItem(presentationData: presentationData, systemStyle: .glass, id: code, title: title, subtitle: subtitle, checked: selected, activity: false, loading: false, editing: LocalizationListItemEditing(editable: false, editing: false, revealed: false, reorderable: false), sectionId: self.section, alwaysPlain: false, action: {
                arguments.selectLanguage(code)
            }, setItemWithRevealedOptions: { _, _ in }, removeItem: { _ in })
        }
    }
}

private func sgOutgoingTranslationLanguageSelectionEntries(theme: PresentationTheme, selectedLanguage: String?) -> [SGOutgoingTranslationLanguageSelectionEntry] {
    let enLocale = Locale(identifier: "en")
    var entries: [SGOutgoingTranslationLanguageSelectionEntry] = []
    var addedLanguages = Set<String>()
    var index: Int32 = 0
    
    func addLanguage(_ code: String) {
        guard !addedLanguages.contains(code), let title = enLocale.localizedString(forLanguageCode: code) else {
            return
        }
        addedLanguages.insert(code)
        let languageLocale = Locale(identifier: code)
        var subtitle = languageLocale.localizedString(forLanguageCode: code) ?? title
        if code == "zh-hans" || code == "zh-hant" {
            subtitle += " \(code)"
        }
        entries.append(.language(index, theme, title.capitalized, subtitle.capitalized, code == selectedLanguage, code))
        index += 1
    }
    
    if let selectedLanguage {
        addLanguage(selectedLanguage)
    }
    for code in popularTranslationLanguages {
        addLanguage(code)
    }
    for code in supportedTranslationLanguages + ["zh-hans", "zh-hant"] {
        addLanguage(code)
    }
    return entries
}

func sgOutgoingTranslationLanguageSelectionController(context: AccountContext, selectedLanguage: String?, completion: @escaping (String) -> Void) -> ViewController {
    var dismissImpl: (() -> Void)?
    let arguments = SGOutgoingTranslationLanguageSelectionArguments(selectLanguage: { code in
        completion(code)
        dismissImpl?()
    })
    let signal = context.sharedContext.presentationData
    |> map { presentationData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(presentationData.strings.Translate_ChangeLanguage), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: sgOutgoingTranslationLanguageSelectionEntries(theme: presentationData.theme, selectedLanguage: selectedLanguage), style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }
    let controller = ItemListController(context: context, state: signal)
    controller.navigationPresentation = .modal
    dismissImpl = { [weak controller] in
        controller?.dismiss(animated: true)
    }
    return controller
}
