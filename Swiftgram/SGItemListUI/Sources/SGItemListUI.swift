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

    
    public init(
        context: AccountContext,
        //
        setBoolValue: @escaping (BoolSetting, Bool) -> Void = { _,_ in },
        updateSliderValue: @escaping (SliderSetting, Int32) -> Void = { _,_ in },
        setOneFromManyValue: @escaping (OneFromManySetting) -> Void = { _ in },
        openDisclosureLink: @escaping (DisclosureLink) -> Void = { _ in},
        action: @escaping (ActionType) -> Void = { _ in }
    ) {
        self.context = context
        //
        self.setBoolValue = setBoolValue
        self.updateSliderValue = updateSliderValue
        self.setOneFromManyValue = setOneFromManyValue
        self.openDisclosureLink = openDisclosureLink
        self.action = action
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
        }
    }
}
