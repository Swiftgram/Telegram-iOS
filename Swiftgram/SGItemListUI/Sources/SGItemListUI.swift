// MARK: Swiftgram
import SGLogging
import SGSimpleSettings
import SGStrings
import SGAPIToken

import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import MtProtoKit
import MessageUI
import TelegramPresentationData
import TelegramUIPreferences
import ItemListUI
import PresentationDataUtils
import OverlayStatusController
import AccountContext
import AppBundle
import WebKit
import PeerNameColorScreen

public class SGItemListCounter {
    private var _count = 0
    
    public init() {}
    
    public var count: Int {
        _count += 1
        return _count
    }
    
    public func increment(_ amount: Int) {
        _count += amount
    }
    
    public func countWith(_ amount: Int) -> Int {
        _count += amount
        return count
    }
}


public protocol SGItemListSection: Equatable {
    var rawValue: Int32 { get }
}

public final class SGItemListArguments<BoolSetting: Hashable, SliderSetting: Hashable, OneFromManySetting: Hashable, DisclosureLink: Hashable, ActionType: Hashable> {
    let context: AccountContext
    //
    let setBoolValue: (BoolSetting, Bool) -> Void
    let updateSliderValue: (SliderSetting, Int32) -> Void
    let setOneFromManyValue: (OneFromManySetting) -> Void
    let openDisclosureLink: (DisclosureLink) -> Void
    let action: (ActionType) -> Void
    let searchInput: (String) -> Void

    
    public init(
        context: AccountContext,
        //
        setBoolValue: @escaping (BoolSetting, Bool) -> Void = { _,_ in },
        updateSliderValue: @escaping (SliderSetting, Int32) -> Void = { _,_ in },
        setOneFromManyValue: @escaping (OneFromManySetting) -> Void = { _ in },
        openDisclosureLink: @escaping (DisclosureLink) -> Void = { _ in},
        action: @escaping (ActionType) -> Void = { _ in },
        searchInput: @escaping (String) -> Void = { _ in }
    ) {
        self.context = context
        //
        self.setBoolValue = setBoolValue
        self.updateSliderValue = updateSliderValue
        self.setOneFromManyValue = setOneFromManyValue
        self.openDisclosureLink = openDisclosureLink
        self.action = action
        self.searchInput = searchInput
    }
}

public enum SGItemListUIEntry<Section: SGItemListSection, BoolSetting: Hashable, SliderSetting: Hashable, OneFromManySetting: Hashable, DisclosureLink: Hashable, ActionType: Hashable>: ItemListNodeEntry {
    case header(id: Int, section: Section, text: String, badge: String?)
    case toggle(id: Int, section: Section, settingName: BoolSetting, value: Bool, text: String, enabled: Bool)
    case notice(id: Int, section: Section, text: String)
    case percentageSlider(id: Int, section: Section, settingName: SliderSetting, value: Int32)
    case oneFromManySelector(id: Int, section: Section, settingName: OneFromManySetting, text: String, value: String, enabled: Bool)
    case disclosure(id: Int, section: Section, link: DisclosureLink, text: String)
    case peerColorDisclosurePreview(id: Int, section: Section, name: String, color: UIColor)
    case action(id: Int, section: Section, actionType: ActionType, text: String, kind: ItemListActionKind)
    case searchInput(id: Int, section: Section, title: NSAttributedString, text: String, placeholder: String)
    
    public var section: ItemListSectionId {
        switch self {
        case let .header(_, sectionId, _, _):
            return sectionId.rawValue
        case let .toggle(_, sectionId, _, _, _, _):
            return sectionId.rawValue
        case let .notice(_, sectionId, _):
            return sectionId.rawValue
            
        case let .disclosure(_, sectionId, _, _):
            return sectionId.rawValue

        case let .percentageSlider(_, sectionId, _, _):
            return sectionId.rawValue
            
        case let .peerColorDisclosurePreview(_, sectionId, _, _):
            return sectionId.rawValue
        case let .oneFromManySelector(_, sectionId, _, _, _, _):
            return sectionId.rawValue
            
        case let .action(_, sectionId, _, _, _):
            return sectionId.rawValue
            
        case let .searchInput(_, sectionId, _, _, _):
            return sectionId.rawValue
        }
    }
    
    public var stableId: Int {
        switch self {
        case let .header(stableIdValue, _, _, _):
            return stableIdValue
        case let .toggle(stableIdValue, _, _, _, _, _):
            return stableIdValue
        case let .notice(stableIdValue, _, _):
            return stableIdValue
        case let .disclosure(stableIdValue, _, _, _):
            return stableIdValue
        case let .percentageSlider(stableIdValue, _, _, _):
            return stableIdValue
        case let .peerColorDisclosurePreview(stableIdValue, _, _, _):
            return stableIdValue
        case let .oneFromManySelector(stableIdValue, _, _, _, _, _):
            return stableIdValue
        case let .action(stableIdValue, _, _, _, _):
            return stableIdValue
        case let .searchInput(stableIdValue, _, _, _, _):
            return stableIdValue
        }
    }
    
    public static func <(lhs: SGItemListUIEntry, rhs: SGItemListUIEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }
    
    public static func ==(lhs: SGItemListUIEntry, rhs: SGItemListUIEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.header(id1, section1, text1, badge1), .header(id2, section2, text2, badge2)):
            return id1 == id2 && section1 == section2 && text1 == text2 && badge1 == badge2
        
        case let (.toggle(id1, section1, settingName1, value1, text1, enabled1), .toggle(id2, section2, settingName2, value2, text2, enabled2)):
            return id1 == id2 && section1 == section2 && settingName1 == settingName2 && value1 == value2 && text1 == text2 && enabled1 == enabled2
        
        case let (.notice(id1, section1, text1), .notice(id2, section2, text2)):
            return id1 == id2 && section1 == section2 && text1 == text2
        
        case let (.percentageSlider(id1, section1, settingName1, value1), .percentageSlider(id2, section2, settingName2, value2)):
            return id1 == id2 && section1 == section2 && value1 == value2 && settingName1 == settingName2
            
        case let (.disclosure(id1, section1, link1, text1), .disclosure(id2, section2, link2, text2)):
            return id1 == id2 && section1 == section2 && link1 == link2 && text1 == text2

        case let (.peerColorDisclosurePreview(id1, section1, name1, currentColor1), .peerColorDisclosurePreview(id2, section2, name2, currentColor2)):
            return id1 == id2 && section1 == section2 && name1 == name2 && currentColor1 == currentColor2
        
        case let (.oneFromManySelector(id1, section1, settingName1, text1, value1, enabled1), .oneFromManySelector(id2, section2, settingName2, text2, value2, enabled2)):
            return id1 == id2 && section1 == section2 && settingName1 == settingName2 && text1 == text2 && value1 == value2 && enabled1 == enabled2
        case let (.action(id1, section1, actionType1, text1, kind1), .action(id2, section2, actionType2, text2, kind2)):
            return id1 == id2 && section1 == section2 && actionType1 == actionType2 && text1 == text2 && kind1 == kind2
            
        case let (.searchInput(id1, lhsValue1, lhsValue2, lhsValue3, lhsValue4), .searchInput(id2, rhsValue1, rhsValue2, rhsValue3, rhsValue4)):
            return id1 == id2 && lhsValue1 == rhsValue1 && lhsValue2 == rhsValue2 && lhsValue3 == rhsValue3 && lhsValue4 == rhsValue4

        default:
            return false
        }
    }

    
    public func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! SGItemListArguments<BoolSetting, SliderSetting, OneFromManySetting, DisclosureLink, ActionType>
        switch self {
        case let .header(_, _, string, badge):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: string, badge: badge, sectionId: self.section)
            
        case let .toggle(_, _, setting, value, text, enabled):
            return ItemListSwitchItem(presentationData: presentationData, title: text, value: value, enabled: enabled, sectionId: self.section, style: .blocks, updated: { value in
                arguments.setBoolValue(setting, value)
            })
        case let .notice(_, _, string):
            return ItemListTextItem(presentationData: presentationData, text: .markdown(string), sectionId: self.section)
        case let .disclosure(_, _, link, text):
            return ItemListDisclosureItem(presentationData: presentationData, title: text, label: "", sectionId: self.section, style: .blocks) {
                arguments.openDisclosureLink(link)
            }
        case let .percentageSlider(_, _, setting, value):
            return SliderPercentageItem(
                theme: presentationData.theme,
                strings: presentationData.strings,
                value: value,
                sectionId: self.section,
                updated: { value in
                    arguments.updateSliderValue(setting, value)
                }
            )
        
        case let .peerColorDisclosurePreview(_, _, name, color):
            return ItemListDisclosureItem(presentationData: presentationData, title: " ", enabled: false, label: name, labelStyle: .semitransparentBadge(color), centerLabelAlignment: true, sectionId: self.section, style: .blocks, disclosureStyle: .none, action: {
            })
        
        case let .oneFromManySelector(_, _, settingName, text, value, enabled):
            return ItemListDisclosureItem(presentationData: presentationData, title: text, enabled: enabled, label: value, sectionId: self.section, style: .blocks, action: {
                arguments.setOneFromManyValue(settingName)
            })
        case let .action(_, _, actionType, text, kind):
            return ItemListActionItem(presentationData: presentationData, title: text, kind: kind, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                    arguments.action(actionType)
            })
        case let .searchInput(_, _, title, text, placeholder):
            return ItemListSingleLineInputItem(presentationData: presentationData, title: title, text: text, placeholder: placeholder, returnKeyType: .done, spacing: 3.0, clearType: .always, selectAllOnFocus: true, secondaryStyle: true, sectionId: self.section, textUpdated: { input in arguments.searchInput(input) }, action: {}, dismissKeyboardOnEnter: true)
        }
    }
}


public func filterSGItemListUIEntrires<Section: SGItemListSection & Hashable, BoolSetting: Hashable, SliderSetting: Hashable, OneFromManySetting: Hashable, DisclosureLink: Hashable, ActionType: Hashable>(
    entries: [SGItemListUIEntry<Section, BoolSetting, SliderSetting, OneFromManySetting, DisclosureLink, ActionType>],
    by searchQuery: String?
) -> [SGItemListUIEntry<Section, BoolSetting, SliderSetting, OneFromManySetting, DisclosureLink, ActionType>] {
    
    guard let query = searchQuery?.lowercased(), !query.isEmpty else {
        return entries
    }
    
    var sectionIdsForEntireIncludion: Set<ItemListSectionId> = []
    var sectionIdsWithMatches: Set<ItemListSectionId> = []
    var filteredEntries: [SGItemListUIEntry<Section, BoolSetting, SliderSetting, OneFromManySetting, DisclosureLink, ActionType>] = []
    
    func entryMatches(_ entry: SGItemListUIEntry<Section, BoolSetting, SliderSetting, OneFromManySetting, DisclosureLink, ActionType>, query: String) -> Bool {
        switch entry {
        case .header(_, _, let text, _):
            return text.lowercased().contains(query)
        case .toggle(_, _, _, _, let text, _):
            return text.lowercased().contains(query)
        case .notice(_, _, let text):
            return text.lowercased().contains(query)
        case .percentageSlider:
            return false // Assuming percentage sliders don't have searchable text
        case .oneFromManySelector(_, _, _, let text, let value, _):
            return text.lowercased().contains(query) || value.lowercased().contains(query)
        case .disclosure(_, _, _, let text):
            return text.lowercased().contains(query)
        case .peerColorDisclosurePreview:
            return false // Never indexed during search
        case .action(_, _, _, let text, _):
            return text.lowercased().contains(query)
        case .searchInput:
            return true // Never hiding search input
        }
    }
    
    // First pass: identify sections with matches
    for entry in entries {
        if entryMatches(entry, query: query) {
            switch entry {
            case .searchInput:
                continue
            default:
                sectionIdsWithMatches.insert(entry.section)
            }
        }
    }
    
    // Second pass: keep matching entries and headers of sections with matches
    for (index, entry) in entries.enumerated() {
        switch entry {
        case .header:
            if entryMatches(entry, query: query) {
                // Will show all entries for the same section
                sectionIdsForEntireIncludion.insert(entry.section)
                if !filteredEntries.contains(entry) {
                    filteredEntries.append(entry)
                }
            }
            // Or show header if something from the section already matched
            if sectionIdsWithMatches.contains(entry.section) {
                if !filteredEntries.contains(entry) {
                    filteredEntries.append(entry)
                }
            }
        default:
            if entryMatches(entry, query: query) {
                if case .notice = entry {
                    // add previous entry to if it's not another notice and if it's not already here
                    // possibly targeting related toggle / setting if we've matched it's description (notice) in search
                    if index > 0 {
                        let previousEntry = entries[index - 1]
                        if case .notice = previousEntry {} else {
                            if !filteredEntries.contains(previousEntry) {
                                filteredEntries.append(previousEntry)
                            }
                        }
                    }
                    if !filteredEntries.contains(entry) {
                        filteredEntries.append(entry)
                    }
                } else {
                    if !filteredEntries.contains(entry) {
                        filteredEntries.append(entry)
                    }
                    // add next entry if it's notice
                    // possibly targeting description (notice) for the currently search-matched toggle/setting
                    if index < entries.count - 1 {
                        let nextEntry = entries[index + 1]
                        if case .notice = nextEntry {
                            if !filteredEntries.contains(nextEntry) {
                                filteredEntries.append(nextEntry)
                            }
                        }
                    }
                }
            } else if sectionIdsForEntireIncludion.contains(entry.section) {
                if !filteredEntries.contains(entry) {
                    filteredEntries.append(entry)
                }
            }
        }
    }
    
    return filteredEntries
}
