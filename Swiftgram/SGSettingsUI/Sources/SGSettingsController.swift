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

private class Counter {
    private var _count = 0
    
    var count: Int {
        _count += 1
        return _count
    }
    
    func increment(_ amount: Int) {
        _count += amount
    }
    
    func countWith(_ amount: Int) -> Int {
        _count += amount
        return count
    }
}


private enum SGControllerSection: Int32 {
    case content
    case tabs
    case folders
    case chatList
    case profiles
    case stories
    case translation
    case photo
    case stickers
    case videoNotes
    case contextMenu
    case accountColors
    case other
}

private enum SGBoolSetting: String {
    case hidePhoneInSettings
    case showTabNames
    case showContactsTab
    case showCallsTab
    case foldersAtBottom
    case startTelescopeWithRearCam
    case hideStories
    case uploadSpeedBoost
    case showProfileId
    case warnOnStoriesOpen
    case sendWithReturnKey
    case rememberLastFolder
    case sendLargePhotos
    case storyStealthMode
    case disableSwipeToRecordStory
    case quickTranslateButton
    case smallReactions
    case showRepostToStory
    case contextShowSelectFromUser
    case contextShowSaveToCloud
    case contextShowHideForwardName
    case contextShowRestrict
    case contextShowReport
    case contextShowReply
    case contextShowPin
    case contextShowSaveMedia
    case contextShowMessageReplies
    case contextShowJson
    case disableScrollToNextChannel
    case disableChatSwipeOptions
    case disableGalleryCamera
    case disableSendAsButton
    case disableSnapDeletionEffect
    case stickerTimestamp
    case hideRecordingButton
    case hideTabBar
    case showDC
    case showCreationDate
    case showRegDate
    case compactChatList
    case compactFolderNames
}

private enum SGOneFromManySetting: String {
    case bottomTabStyle
    case downloadSpeedBoost
    case allChatsTitleLengthOverride
}

private enum SGSliderSetting: String {
    case accountColorsSaturation
    case outgoingPhotoQuality
    case stickerSize
}

private enum SGDisclosureLink: String {
    case contentSettings
    case languageSettings
}

private final class SGControllerArguments {
    let context: AccountContext
    //
    let setBoolValue: (SGBoolSetting, Bool) -> Void
//    let updatePeerColor: (PeerNameColor) -> Void
    let updateSliderValue: (SGSliderSetting, Int32) -> Void
    let setOneFromManyValue: (SGOneFromManySetting) -> Void
    let openDisclosureLink: (SGDisclosureLink) -> Void
    //
    let presentController: (ViewController, ViewControllerPresentationArguments?) -> Void
    let pushController: (ViewController) -> Void
    let getRootController: () -> UIViewController?
    let getNavigationController: () -> NavigationController?

    
    init(
        context: AccountContext,
        //
//        updatePeerColor: @escaping (PeerNameColor) -> Void,
        setBoolValue: @escaping (SGBoolSetting, Bool) -> Void,
        updateSliderValue: @escaping (SGSliderSetting, Int32) -> Void,
        setOneFromManyValue: @escaping (SGOneFromManySetting) -> Void,
        openDisclosureLink: @escaping (SGDisclosureLink) -> Void,
        //
        presentController: @escaping (ViewController, ViewControllerPresentationArguments?) -> Void, pushController: @escaping (ViewController) -> Void, getRootController: @escaping () -> UIViewController?, getNavigationController: @escaping () -> NavigationController?
    ) {
        self.context = context
        //
//        self.updatePeerColor = updatePeerColor
        self.setBoolValue = setBoolValue
        self.updateSliderValue = updateSliderValue
        self.setOneFromManyValue = setOneFromManyValue
        self.openDisclosureLink = openDisclosureLink
        //
        self.presentController = presentController
        self.pushController = pushController
        self.getRootController = getRootController
        self.getNavigationController = getNavigationController
    }
}

private enum SGControllerEntry: ItemListNodeEntry {
    case header(id: Int, section: SGControllerSection, text: String, badge: String?)
    case toggle(id: Int, section: SGControllerSection, settingName: SGBoolSetting, value: Bool, text: String, enabled: Bool)
    case notice(id: Int, section: SGControllerSection, text: String)
    case percentageSlider(id: Int, section: SGControllerSection, settingName: SGSliderSetting, value: Int32)
    case oneFromManySelector(id: Int, section: SGControllerSection, settingName: SGOneFromManySetting, text: String, value: String, enabled: Bool)
    case disclosure(id: Int, section: SGControllerSection, link: SGDisclosureLink, text: String)
    
//    case peerColorPicker(id: Int, section: SGControllerSection, colors: PeerNameColors, currentColor: PeerNameColor, currentSaturation: Int32)
    
    case peerColorDisclosurePreview(id: Int, section: SGControllerSection, name: String, color: UIColor)
    
    var section: ItemListSectionId {
        switch self {
        case let .header(_, sectionId, _, _):
            return sectionId.rawValue
        case let .toggle(_, sectionId, _, _, _, _):
            return sectionId.rawValue
        case let .notice(_, sectionId, _):
            return sectionId.rawValue
            
        case let .disclosure(_, sectionId, _, _):
            return sectionId.rawValue
//        case let .peerColorPicker(_, sectionId, _, _, _):
//            return sectionId.rawValue

        case let .percentageSlider(_, sectionId, _, _):
            return sectionId.rawValue
            
        case let .peerColorDisclosurePreview(_, sectionId, _, _):
            return sectionId.rawValue
        case let .oneFromManySelector(_, sectionId, _, _, _, _):
            return sectionId.rawValue
        }
    }
    
    var stableId: Int {
        switch self {
        case let .header(stableIdValue, _, _, _):
            return stableIdValue
        case let .toggle(stableIdValue, _, _, _, _, _):
            return stableIdValue
        case let .notice(stableIdValue, _, _):
            return stableIdValue
        case let .disclosure(stableIdValue, _, _, _):
            return stableIdValue
//        case let .peerColorPicker(stableIdValue, _, _, _, _):
//            return stableIdValue
        case let .percentageSlider(stableIdValue, _, _, _):
            return stableIdValue
        case let .peerColorDisclosurePreview(stableIdValue, _, _, _):
            return stableIdValue
        case let .oneFromManySelector(stableIdValue, _, _, _, _, _):
            return stableIdValue
        }
    }
    
    static func <(lhs: SGControllerEntry, rhs: SGControllerEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }
    
    static func ==(lhs: SGControllerEntry, rhs: SGControllerEntry) -> Bool {
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
        
//        case let (.peerColorPicker(id1, section1, colors1, currentColor1, currentSaturation1), .peerColorPicker(id2, section2, colors2, currentColor2, currentSaturation2)):
//            return id1 == id2 && section1 == section2 && colors1 == colors2 && currentColor1 == currentColor2 && currentSaturation1 == currentSaturation2
            
        case let (.peerColorDisclosurePreview(id1, section1, name1, currentColor1), .peerColorDisclosurePreview(id2, section2, name2, currentColor2)):
            return id1 == id2 && section1 == section2 && name1 == name2 && currentColor1 == currentColor2
        
        case let (.oneFromManySelector(id1, section1, settingName1, text1, value1, enabled1), .oneFromManySelector(id2, section2, settingName2, text2, value2, enabled2)):
            return id1 == id2 && section1 == section2 && settingName1 == settingName2 && text1 == text2 && value1 == value2 && enabled1 == enabled2

        default:
            return false
        }
    }

    
    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! SGControllerArguments
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
            
//        case let .peerColorPicker(_, _, colors, currentColor, saturation):
//            print("Color picker with saturation \(saturation)")
//            return PeerNameColorItem(
//                theme: presentationData.theme,
//                colors: colors,
//                currentColor: currentColor,
//                updated: { color in
//                    arguments.updatePeerColor(color)
//                },
//                sectionId: self.section
//            )
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
        }
    }
}

private struct PeerNameColorScreenState: Equatable {
    var updatedNameColor: PeerNameColor?
    var updatedBackgroundEmojiId: Int64?
}

private func SGControllerEntries(presentationData: PresentationData, callListSettings: CallListSettings, experimentalUISettings: ExperimentalUISettings, SGSettings: SGUISettings, appConfiguration: AppConfiguration, nameColors: PeerNameColors /*state: PeerNameColorScreenState,*/) -> [SGControllerEntry] {
    var entries: [SGControllerEntry] = []
        
    let id = Counter()
    
    if appConfiguration.sgWebSettings.global.canEditSettings {
        entries.append(.disclosure(id: id.count, section: .content, link: .contentSettings, text: i18n("Settings.ContentSettings", presentationData.strings.baseLanguageCode)))
    } else {
        id.increment(1)
    }
    
    entries.append(.header(id: id.count, section: .tabs, text: i18n("Settings.Tabs.Header", presentationData.strings.baseLanguageCode), badge: nil))
    entries.append(.toggle(id: id.count, section: .tabs, settingName: .hideTabBar, value: SGSimpleSettings.shared.hideTabBar, text: i18n("Settings.Tabs.HideTabBar", presentationData.strings.baseLanguageCode), enabled: true))
    entries.append(.toggle(id: id.count, section: .tabs, settingName: .showContactsTab, value: callListSettings.showContactsTab, text: i18n("Settings.Tabs.ShowContacts", presentationData.strings.baseLanguageCode), enabled: !SGSimpleSettings.shared.hideTabBar))
    entries.append(.toggle(id: id.count, section: .tabs, settingName: .showCallsTab, value: callListSettings.showTab, text: presentationData.strings.CallSettings_TabIcon, enabled: !SGSimpleSettings.shared.hideTabBar))
    entries.append(.toggle(id: id.count, section: .tabs, settingName: .showTabNames, value: SGSimpleSettings.shared.showTabNames, text: i18n("Settings.Tabs.ShowNames", presentationData.strings.baseLanguageCode), enabled: !SGSimpleSettings.shared.hideTabBar))
    
    entries.append(.header(id: id.count, section: .folders, text: presentationData.strings.Settings_ChatFolders.uppercased(), badge: nil))
    entries.append(.toggle(id: id.count, section: .folders, settingName: .foldersAtBottom, value: experimentalUISettings.foldersTabAtBottom, text: i18n("Settings.Folders.BottomTab", presentationData.strings.baseLanguageCode), enabled: true))
    entries.append(.oneFromManySelector(id: id.count, section: .folders, settingName: .bottomTabStyle, text: i18n("Settings.Folders.BottomTabStyle", presentationData.strings.baseLanguageCode), value: i18n("Settings.Folders.BottomTabStyle.\(SGSimpleSettings.shared.bottomTabStyle)", presentationData.strings.baseLanguageCode), enabled: experimentalUISettings.foldersTabAtBottom))
    entries.append(.toggle(id: id.count, section: .folders, settingName: .compactFolderNames, value: SGSimpleSettings.shared.compactFolderNames, text: i18n("Settings.Folders.CompactNames", presentationData.strings.baseLanguageCode), enabled: SGSimpleSettings.shared.bottomTabStyle != SGSimpleSettings.BottomTabStyleValues.ios.rawValue))
    entries.append(.oneFromManySelector(id: id.count, section: .folders, settingName: .allChatsTitleLengthOverride, text: i18n("Settings.Folders.AllChatsTitle", presentationData.strings.baseLanguageCode), value: i18n("Settings.Folders.AllChatsTitle.\(SGSimpleSettings.shared.allChatsTitleLengthOverride)", presentationData.strings.baseLanguageCode), enabled: true))
    entries.append(.toggle(id: id.count, section: .folders, settingName: .rememberLastFolder, value: SGSimpleSettings.shared.rememberLastFolder, text: i18n("Settings.Folders.RememberLast", presentationData.strings.baseLanguageCode), enabled: true))
    entries.append(.notice(id: id.count, section: .folders, text: i18n("Settings.Folders.RememberLast.Notice", presentationData.strings.baseLanguageCode)))
    
    entries.append(.header(id: id.count, section: .chatList, text: i18n("Settings.ChatList.Header", presentationData.strings.baseLanguageCode), badge: nil))
    entries.append(.toggle(id: id.count, section: .chatList, settingName: .compactChatList, value: SGSimpleSettings.shared.compactChatList, text: i18n("Settings.CompactChatList", presentationData.strings.baseLanguageCode), enabled: true))
    entries.append(.toggle(id: id.count, section: .chatList, settingName: .disableChatSwipeOptions, value: !SGSimpleSettings.shared.disableChatSwipeOptions, text: i18n("Settings.ChatSwipeOptions", presentationData.strings.baseLanguageCode), enabled: true))
    
    entries.append(.header(id: id.count, section: .profiles, text: i18n("Settings.Profiles.Header", presentationData.strings.baseLanguageCode), badge: nil))
    entries.append(.toggle(id: id.count, section: .profiles, settingName: .showProfileId, value: SGSettings.showProfileId, text: i18n("Settings.ShowProfileID", presentationData.strings.baseLanguageCode), enabled: true))
    entries.append(.toggle(id: id.count, section: .profiles, settingName: .showDC, value: SGSimpleSettings.shared.showDC, text: i18n("Settings.ShowDC", presentationData.strings.baseLanguageCode), enabled: true))
    entries.append(.toggle(id: id.count, section: .profiles, settingName: .showRegDate, value: SGSimpleSettings.shared.showRegDate, text: i18n("Settings.ShowRegDate", presentationData.strings.baseLanguageCode), enabled: true))
    entries.append(.notice(id: id.count, section: .profiles, text: i18n("Settings.ShowRegDate.Notice", presentationData.strings.baseLanguageCode)))
    entries.append(.toggle(id: id.count, section: .profiles, settingName: .showCreationDate, value: SGSimpleSettings.shared.showCreationDate, text: i18n("Settings.ShowCreationDate", presentationData.strings.baseLanguageCode), enabled: true))
    entries.append(.notice(id: id.count, section: .profiles, text: i18n("Settings.ShowCreationDate.Notice", presentationData.strings.baseLanguageCode)))
    
    entries.append(.header(id: id.count, section: .stories, text: presentationData.strings.AutoDownloadSettings_Stories.uppercased(), badge: nil))
    entries.append(.toggle(id: id.count, section: .stories, settingName: .hideStories, value: SGSettings.hideStories, text: i18n("Settings.Stories.Hide", presentationData.strings.baseLanguageCode), enabled: true))
    entries.append(.toggle(id: id.count, section: .stories, settingName: .disableSwipeToRecordStory, value: SGSimpleSettings.shared.disableSwipeToRecordStory, text: i18n("Settings.Stories.DisableSwipeToRecord", presentationData.strings.baseLanguageCode), enabled: true))
    entries.append(.toggle(id: id.count, section: .stories, settingName: .warnOnStoriesOpen, value: SGSettings.warnOnStoriesOpen, text: i18n("Settings.Stories.WarnBeforeView", presentationData.strings.baseLanguageCode), enabled: true))
    entries.append(.toggle(id: id.count, section: .stories, settingName: .showRepostToStory, value: SGSimpleSettings.shared.showRepostToStory, text: presentationData.strings.Share_RepostToStory.replacingOccurrences(of: "\n", with: " "), enabled: true))
    if SGSimpleSettings.shared.canUseStealthMode {
        entries.append(.toggle(id: id.count, section: .stories, settingName: .storyStealthMode, value: SGSimpleSettings.shared.storyStealthMode, text: presentationData.strings.Story_StealthMode_Title, enabled: true))
        entries.append(.notice(id: id.count, section: .stories, text: presentationData.strings.Story_StealthMode_ControlText))
    } else {
        id.increment(2)
    }

    
    entries.append(.header(id: id.count, section: .translation, text: presentationData.strings.Localization_TranslateMessages.uppercased(), badge: nil))
    entries.append(.toggle(id: id.count, section: .translation, settingName: .quickTranslateButton, value: SGSimpleSettings.shared.quickTranslateButton, text: i18n("Settings.Translation.QuickTranslateButton", presentationData.strings.baseLanguageCode), enabled: true))
    entries.append(.disclosure(id: id.count, section: .translation, link: .languageSettings, text: presentationData.strings.Localization_TranslateEntireChat))
    entries.append(.notice(id: id.count, section: .translation, text: i18n("Common.NoTelegramPremiumNeeded", presentationData.strings.baseLanguageCode, presentationData.strings.Settings_Premium)))
    
    entries.append(.header(id: id.count, section: .photo, text: presentationData.strings.NetworkUsageSettings_MediaImageDataSection, badge: nil))
    entries.append(.header(id: id.count, section: .photo, text: presentationData.strings.PhotoEditor_QualityTool.uppercased(), badge: nil))
    entries.append(.percentageSlider(id: id.count, section: .photo, settingName: .outgoingPhotoQuality, value: SGSimpleSettings.shared.outgoingPhotoQuality))
    entries.append(.notice(id: id.count, section: .photo, text: i18n("Settings.Photo.Quality.Notice", presentationData.strings.baseLanguageCode)))
    entries.append(.toggle(id: id.count, section: .photo, settingName: .sendLargePhotos, value: SGSimpleSettings.shared.sendLargePhotos, text: i18n("Settings.Photo.SendLarge", presentationData.strings.baseLanguageCode), enabled: true))
    entries.append(.notice(id: id.count, section: .photo, text: i18n("Settings.Photo.SendLarge.Notice", presentationData.strings.baseLanguageCode)))
    
    entries.append(.header(id: id.count, section: .stickers, text: presentationData.strings.StickerPacksSettings_Title.uppercased(), badge: nil))
    entries.append(.header(id: id.count, section: .stickers, text: i18n("Settings.Stickers.Size", presentationData.strings.baseLanguageCode), badge: nil))
    entries.append(.percentageSlider(id: id.count, section: .stickers, settingName: .stickerSize, value: SGSimpleSettings.shared.stickerSize))
    entries.append(.toggle(id: id.count, section: .stickers, settingName: .stickerTimestamp, value: SGSimpleSettings.shared.stickerTimestamp, text: i18n("Settings.Stickers.Timestamp", presentationData.strings.baseLanguageCode), enabled: true))
    
    
    entries.append(.header(id: id.count, section: .videoNotes, text: i18n("Settings.VideoNotes.Header", presentationData.strings.baseLanguageCode), badge: nil))
    entries.append(.toggle(id: id.count, section: .videoNotes, settingName: .startTelescopeWithRearCam, value: SGSimpleSettings.shared.startTelescopeWithRearCam, text: i18n("Settings.VideoNotes.StartWithRearCam", presentationData.strings.baseLanguageCode), enabled: true))
    
    entries.append(.header(id: id.count, section: .contextMenu, text: i18n("Settings.ContextMenu", presentationData.strings.baseLanguageCode), badge: nil))
    entries.append(.notice(id: id.count, section: .contextMenu, text: i18n("Settings.ContextMenu.Notice", presentationData.strings.baseLanguageCode)))
    entries.append(.toggle(id: id.count, section: .contextMenu, settingName: .contextShowSaveToCloud, value: SGSimpleSettings.shared.contextShowSaveToCloud, text: i18n("ContextMenu.SaveToCloud", presentationData.strings.baseLanguageCode), enabled: true))
    entries.append(.toggle(id: id.count, section: .contextMenu, settingName: .contextShowHideForwardName, value: SGSimpleSettings.shared.contextShowHideForwardName, text: presentationData.strings.Conversation_ForwardOptions_HideSendersNames, enabled: true))
    entries.append(.toggle(id: id.count, section: .contextMenu, settingName: .contextShowSelectFromUser, value: SGSimpleSettings.shared.contextShowSelectFromUser, text: i18n("ContextMenu.SelectFromUser", presentationData.strings.baseLanguageCode), enabled: true))
    entries.append(.toggle(id: id.count, section: .contextMenu, settingName: .contextShowRestrict, value: SGSimpleSettings.shared.contextShowRestrict, text: presentationData.strings.Conversation_ContextMenuBan, enabled: true))
    entries.append(.toggle(id: id.count, section: .contextMenu, settingName: .contextShowReport, value: SGSimpleSettings.shared.contextShowReport, text: presentationData.strings.Conversation_ContextMenuReport, enabled: true))
    entries.append(.toggle(id: id.count, section: .contextMenu, settingName: .contextShowReply, value: SGSimpleSettings.shared.contextShowReply, text: presentationData.strings.Conversation_ContextMenuReply, enabled: true))
    entries.append(.toggle(id: id.count, section: .contextMenu, settingName: .contextShowPin, value: SGSimpleSettings.shared.contextShowPin, text: presentationData.strings.Conversation_Pin, enabled: true))
    entries.append(.toggle(id: id.count, section: .contextMenu, settingName: .contextShowSaveMedia, value: SGSimpleSettings.shared.contextShowSaveMedia, text: presentationData.strings.Conversation_SaveToFiles, enabled: true))
    entries.append(.toggle(id: id.count, section: .contextMenu, settingName: .contextShowMessageReplies, value: SGSimpleSettings.shared.contextShowMessageReplies, text: presentationData.strings.Conversation_ContextViewThread, enabled: true))
    entries.append(.toggle(id: id.count, section: .contextMenu, settingName: .contextShowJson, value: SGSimpleSettings.shared.contextShowJson, text: "JSON", enabled: true))
    /* entries.append(.toggle(id: id.count, section: .contextMenu, settingName: .contextShowRestrict, value: SGSimpleSettings.shared.contextShowRestrict, text: presentationData.strings.Conversation_ContextMenuBan)) */
    
    entries.append(.header(id: id.count, section: .accountColors, text: i18n("Settings.CustomColors.Header", presentationData.strings.baseLanguageCode), badge: nil))
    entries.append(.header(id: id.count, section: .accountColors, text: i18n("Settings.CustomColors.Saturation", presentationData.strings.baseLanguageCode), badge: nil))
    let accountColorSaturation = SGSimpleSettings.shared.accountColorsSaturation
    entries.append(.percentageSlider(id: id.count, section: .accountColors, settingName: .accountColorsSaturation, value: accountColorSaturation))
//    let nameColor: PeerNameColor
//    if let updatedNameColor = state.updatedNameColor {
//        nameColor = updatedNameColor
//    } else {
//        nameColor = .blue
//    }
//    let _ = nameColors.get(nameColor, dark: presentationData.theme.overallDarkAppearance)
//    entries.append(.peerColorPicker(id: entries.count, section: .other,
//        colors: nameColors,
//        currentColor: nameColor, // TODO: PeerNameColor(rawValue: <#T##Int32#>)
//        currentSaturation: accountColorSaturation
//    ))
    
    if accountColorSaturation == 0 {
        id.increment(100)
        entries.append(.peerColorDisclosurePreview(id: id.count, section: .accountColors, name: "\(presentationData.strings.UserInfo_FirstNamePlaceholder) \(presentationData.strings.UserInfo_LastNamePlaceholder)", color:         presentationData.theme.chat.message.incoming.accentTextColor))
    } else {
        id.increment(200)
        for index in nameColors.displayOrder.prefix(5) {
            let color: PeerNameColor = PeerNameColor(rawValue: index)
            let colors = nameColors.get(color, dark: presentationData.theme.overallDarkAppearance)
            entries.append(.peerColorDisclosurePreview(id: id.count, section: .accountColors, name: "\(presentationData.strings.UserInfo_FirstNamePlaceholder) \(presentationData.strings.UserInfo_LastNamePlaceholder)", color: colors.main))
        }
    }
    entries.append(.notice(id: id.count, section: .accountColors, text: i18n("Settings.CustomColors.Saturation.Notice", presentationData.strings.baseLanguageCode)))
    
    id.increment(10000)
    entries.append(.header(id: id.count, section: .other, text: presentationData.strings.Appearance_Other.uppercased(), badge: nil))
    
    entries.append(.toggle(id: id.count, section: .other, settingName: .hideRecordingButton, value: !SGSimpleSettings.shared.hideRecordingButton, text: i18n("Settings.RecordingButton", presentationData.strings.baseLanguageCode), enabled: true))
    entries.append(.toggle(id: id.count, section: .other, settingName: .disableSnapDeletionEffect, value: !SGSimpleSettings.shared.disableSnapDeletionEffect, text: i18n("Settings.SnapDeletionEffect", presentationData.strings.baseLanguageCode), enabled: true))
    entries.append(.toggle(id: id.count, section: .other, settingName: .disableSendAsButton, value: !SGSimpleSettings.shared.disableSendAsButton, text: i18n("Settings.SendAsButton", presentationData.strings.baseLanguageCode, presentationData.strings.Conversation_SendMesageAs), enabled: true))
    entries.append(.toggle(id: id.count, section: .other, settingName: .disableGalleryCamera, value: !SGSimpleSettings.shared.disableGalleryCamera, text: i18n("Settings.GalleryCamera", presentationData.strings.baseLanguageCode), enabled: true))
    entries.append(.toggle(id: id.count, section: .other, settingName: .disableScrollToNextChannel, value: !SGSimpleSettings.shared.disableScrollToNextChannel, text: i18n("Settings.PullToNextChannel", presentationData.strings.baseLanguageCode), enabled: true))
    entries.append(.toggle(id: id.count, section: .other, settingName: .smallReactions, value: SGSimpleSettings.shared.smallReactions, text: i18n("Settings.SmallReactions", presentationData.strings.baseLanguageCode), enabled: true))
    entries.append(.toggle(id: id.count, section: .other, settingName: .uploadSpeedBoost, value: SGSimpleSettings.shared.uploadSpeedBoost, text: i18n("Settings.UploadsBoost", presentationData.strings.baseLanguageCode), enabled: true))
    entries.append(.oneFromManySelector(id: id.count, section: .other, settingName: .downloadSpeedBoost, text: i18n("Settings.DownloadsBoost", presentationData.strings.baseLanguageCode), value: i18n("Settings.DownloadsBoost.\(SGSimpleSettings.shared.downloadSpeedBoost)", presentationData.strings.baseLanguageCode), enabled: true))
    entries.append(.toggle(id: id.count, section: .other, settingName: .sendWithReturnKey, value: SGSettings.sendWithReturnKey, text: i18n("Settings.SendWithReturnKey", presentationData.strings.baseLanguageCode), enabled: true))
    entries.append(.toggle(id: id.count, section: .other, settingName: .hidePhoneInSettings, value: SGSimpleSettings.shared.hidePhoneInSettings, text: i18n("Settings.HidePhoneInSettingsUI", presentationData.strings.baseLanguageCode), enabled: true))
    entries.append(.notice(id: id.count, section: .other, text: i18n("Settings.HidePhoneInSettingsUI.Notice", presentationData.strings.baseLanguageCode)))
    
    return entries
}

public func sgSettingsController(context: AccountContext/*, focusOnItemTag: Int? = nil*/) -> ViewController {
    var presentControllerImpl: ((ViewController, ViewControllerPresentationArguments?) -> Void)?
    var pushControllerImpl: ((ViewController) -> Void)?
    var getRootControllerImpl: (() -> UIViewController?)?
    var getNavigationControllerImpl: (() -> NavigationController?)?
    var askForRestart: (() -> Void)?
    
//    let statePromise = ValuePromise(PeerNameColorScreenState(), ignoreRepeated: true)
//    let stateValue = Atomic(value: PeerNameColorScreenState())
//    let updateState: ((PeerNameColorScreenState) -> PeerNameColorScreenState) -> Void = { f in
//        statePromise.set(stateValue.modify { f($0) })
//    }
    
//    let sliderPromise = ValuePromise(SGSimpleSettings.shared.accountColorsSaturation, ignoreRepeated: true)
//    let sliderStateValue = Atomic(value: SGSimpleSettings.shared.accountColorsSaturation)
//    let _: ((Int32) -> Int32) -> Void = { f in
//        sliderPromise.set(sliderStateValue.modify( {f($0)}))
//    }
    
    let simplePromise = ValuePromise(true, ignoreRepeated: false)
    
    let arguments = SGControllerArguments(
        context: context,
        /*updatePeerColor: { color in
          updateState { state in
              var updatedState = state
              updatedState.updatedNameColor = color
              return updatedState
          }
        },*/ setBoolValue: { setting, value in
        switch setting {
        case .hidePhoneInSettings:
            SGSimpleSettings.shared.hidePhoneInSettings = value
            askForRestart?()
        case .showTabNames:
            SGSimpleSettings.shared.showTabNames = value
            askForRestart?()
        case .showContactsTab:
            let _ = (
                updateCallListSettingsInteractively(
                    accountManager: context.sharedContext.accountManager, { $0.withUpdatedShowContactsTab(value) }
                )
            ).start()
        case .showCallsTab:
            let _ = (
                updateCallListSettingsInteractively(
                    accountManager: context.sharedContext.accountManager, { $0.withUpdatedShowTab(value) }
                )
            ).start()
        case .foldersAtBottom:
            let _ = (
                updateExperimentalUISettingsInteractively(accountManager: context.sharedContext.accountManager, { settings in
                        var settings = settings
                        settings.foldersTabAtBottom = value
                        return settings
                    }
                )
            ).start()
        case .startTelescopeWithRearCam:
            SGSimpleSettings.shared.startTelescopeWithRearCam = value
        case .hideStories:
            let _ = (
                updateSGUISettings(engine: context.engine, { settings in
                    var settings = settings
                    settings.hideStories = value
                    return settings
                })
            ).start()
        case .showProfileId:
            let _ = (
                updateSGUISettings(engine: context.engine, { settings in
                    var settings = settings
                    settings.showProfileId = value
                    return settings
                })
            ).start()
        case .warnOnStoriesOpen:
            let _ = (
                updateSGUISettings(engine: context.engine, { settings in
                    var settings = settings
                    settings.warnOnStoriesOpen = value
                    return settings
                })
            ).start()
        case .sendWithReturnKey:
            let _ = (
                updateSGUISettings(engine: context.engine, { settings in
                    var settings = settings
                    settings.sendWithReturnKey = value
                    return settings
                })
            ).start()
        case .rememberLastFolder:
            SGSimpleSettings.shared.rememberLastFolder = value
        case .sendLargePhotos:
            SGSimpleSettings.shared.sendLargePhotos = value
        case .storyStealthMode:
            SGSimpleSettings.shared.storyStealthMode = value
        case .disableSwipeToRecordStory:
            SGSimpleSettings.shared.disableSwipeToRecordStory = value
        case .quickTranslateButton:
            SGSimpleSettings.shared.quickTranslateButton = value
        case .uploadSpeedBoost:
            SGSimpleSettings.shared.uploadSpeedBoost = value
        case .smallReactions:
            SGSimpleSettings.shared.smallReactions = value
        case .showRepostToStory:
            SGSimpleSettings.shared.showRepostToStory = value
        case .contextShowSelectFromUser:
            SGSimpleSettings.shared.contextShowSelectFromUser = value
        case .contextShowSaveToCloud:
            SGSimpleSettings.shared.contextShowSaveToCloud = value
        case .contextShowRestrict:
            SGSimpleSettings.shared.contextShowRestrict = value
        case .contextShowHideForwardName:
            SGSimpleSettings.shared.contextShowHideForwardName = value
        case .disableScrollToNextChannel:
            SGSimpleSettings.shared.disableScrollToNextChannel = !value
        case .disableChatSwipeOptions:
            SGSimpleSettings.shared.disableChatSwipeOptions = !value
            askForRestart?()
        case .disableGalleryCamera:
            SGSimpleSettings.shared.disableGalleryCamera = !value
        case .disableSendAsButton:
            SGSimpleSettings.shared.disableSendAsButton = !value
        case .disableSnapDeletionEffect:
            SGSimpleSettings.shared.disableSnapDeletionEffect = !value
        case .contextShowReport:
            SGSimpleSettings.shared.contextShowReport = value
        case .contextShowReply:
            SGSimpleSettings.shared.contextShowReply = value
        case .contextShowPin:
            SGSimpleSettings.shared.contextShowPin = value
        case .contextShowSaveMedia:
            SGSimpleSettings.shared.contextShowSaveMedia = value
        case .contextShowMessageReplies:
            SGSimpleSettings.shared.contextShowMessageReplies = value
        case .stickerTimestamp:
            SGSimpleSettings.shared.stickerTimestamp = value
        case .contextShowJson:
            SGSimpleSettings.shared.contextShowJson = value
        case .hideRecordingButton:
            SGSimpleSettings.shared.hideRecordingButton = !value
        case .hideTabBar:
            SGSimpleSettings.shared.hideTabBar = value
            simplePromise.set(true) // Trigger update for 'enabled' field of other toggles
            askForRestart?()
        case .showDC:
            SGSimpleSettings.shared.showDC = value
        case .showCreationDate:
            SGSimpleSettings.shared.showCreationDate = value
        case .showRegDate:
            SGSimpleSettings.shared.showRegDate = value
        case .compactChatList:
            SGSimpleSettings.shared.compactChatList = value
            askForRestart?()
        case .compactFolderNames:
            SGSimpleSettings.shared.compactFolderNames = value
        }
    }, updateSliderValue: { setting, value in
        switch (setting) {
            case .accountColorsSaturation:
                if SGSimpleSettings.shared.accountColorsSaturation != value {
                    SGSimpleSettings.shared.accountColorsSaturation = value
                    simplePromise.set(true)
                }
            case .outgoingPhotoQuality:
                if SGSimpleSettings.shared.outgoingPhotoQuality != value {
                    SGSimpleSettings.shared.outgoingPhotoQuality = value
                    simplePromise.set(true)
                }
            case .stickerSize:
                if SGSimpleSettings.shared.stickerSize != value {
                    SGSimpleSettings.shared.stickerSize = value
                    simplePromise.set(true)
                }
        }

    }, setOneFromManyValue: { setting in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let actionSheet = ActionSheetController(presentationData: presentationData)
        var items: [ActionSheetItem] = []
        
        switch (setting) {
            case .downloadSpeedBoost:
                let setAction: (String) -> Void = { value in
                    SGSimpleSettings.shared.downloadSpeedBoost = value
                    
                    let enableDownloadX: Bool
                    switch (value) {
                        case SGSimpleSettings.DownloadSpeedBoostValues.none.rawValue:
                            enableDownloadX = false
                        default:
                            enableDownloadX = true
                    }
                    
                    // Updating controller
                    simplePromise.set(true)

                    let _ = updateNetworkSettingsInteractively(postbox: context.account.postbox, network: context.account.network, { settings in
                        var settings = settings
                        settings.useExperimentalDownload = enableDownloadX
                        return settings
                    }).start(completed: {
                        Queue.mainQueue().async {
                            askForRestart?()
                        }
                    })
                }

                for value in SGSimpleSettings.DownloadSpeedBoostValues.allCases {
                    items.append(ActionSheetButtonItem(title: i18n("Settings.DownloadsBoost.\(value.rawValue)", presentationData.strings.baseLanguageCode), color: .accent, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                        setAction(value.rawValue)
                    }))
                }
            case .bottomTabStyle:
                let setAction: (String) -> Void = { value in
                    SGSimpleSettings.shared.bottomTabStyle = value
                    simplePromise.set(true)
                }

                for value in SGSimpleSettings.BottomTabStyleValues.allCases {
                    items.append(ActionSheetButtonItem(title: i18n("Settings.Folders.BottomTabStyle.\(value.rawValue)", presentationData.strings.baseLanguageCode), color: .accent, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                        setAction(value.rawValue)
                    }))
                }
            case .allChatsTitleLengthOverride:
                let setAction: (String) -> Void = { value in
                    SGSimpleSettings.shared.allChatsTitleLengthOverride = value
                    simplePromise.set(true)
                }

                for value in SGSimpleSettings.AllChatsTitleLengthOverride.allCases {
                    let title: String
                    switch (value) {
                        case SGSimpleSettings.AllChatsTitleLengthOverride.short:
                            title = "\"\(presentationData.strings.ChatList_Tabs_All)\""
                        case SGSimpleSettings.AllChatsTitleLengthOverride.long:
                            title = "\"\(presentationData.strings.ChatList_Tabs_AllChats)\""
                        default:
                            title = i18n("Settings.Folders.AllChatsTitle.none", presentationData.strings.baseLanguageCode)
                    }
                    items.append(ActionSheetButtonItem(title: title, color: .accent, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                        setAction(value.rawValue)
                    }))
                }
        }
        
        actionSheet.setItemGroups([ActionSheetItemGroup(items: items), ActionSheetItemGroup(items: [
            ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
            })
        ])])
        presentControllerImpl?(actionSheet, ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
    }, openDisclosureLink: { link in
        switch (link) {
            case .languageSettings:
                pushControllerImpl?(context.sharedContext.makeLocalizationListController(context: context))
            case .contentSettings:
                let _ = (getSGSettingsURL(context: context) |> deliverOnMainQueue).start(next: { [weak context] url in
                    guard let strongContext = context else {
                        return
                    }
                    strongContext.sharedContext.applicationBindings.openUrl(url)
                })
        }
    }, presentController: { controller, arguments in
        presentControllerImpl?(controller, arguments)
    }, pushController: { controller in
        pushControllerImpl?(controller)
    }, getRootController: {
        return getRootControllerImpl?()
    }, getNavigationController: {
        return getNavigationControllerImpl?()
    })
    
    let sharedData = context.sharedContext.accountManager.sharedData(keys: [ApplicationSpecificSharedDataKeys.callListSettings, ApplicationSpecificSharedDataKeys.experimentalUISettings])
    let preferences = context.account.postbox.preferencesView(keys: [ApplicationSpecificPreferencesKeys.SGUISettings, PreferencesKeys.appConfiguration])
    let updatedContentSettingsConfiguration = contentSettingsConfiguration(network: context.account.network)
    |> map(Optional.init)
    let contentSettingsConfiguration = Promise<ContentSettingsConfiguration?>()
    contentSettingsConfiguration.set(.single(nil)
    |> then(updatedContentSettingsConfiguration))
    
    let signal = combineLatest(simplePromise.get(), /*sliderPromise.get(),*/ /*statePromise.get(),*/ context.sharedContext.presentationData, sharedData, preferences, contentSettingsConfiguration.get(),
        context.engine.accountData.observeAvailableColorOptions(scope: .replies),
        context.engine.accountData.observeAvailableColorOptions(scope: .profile)
    )
    |> map { _, /*sliderValue,*/ /*state,*/ presentationData, sharedData, view, contentSettingsConfiguration, availableReplyColors, availableProfileColors ->  (ItemListControllerState, (ItemListNodeState, Any)) in
        
        let sgUISettings: SGUISettings = view.values[ApplicationSpecificPreferencesKeys.SGUISettings]?.get(SGUISettings.self) ?? SGUISettings.default
        let appConfiguration: AppConfiguration = view.values[PreferencesKeys.appConfiguration]?.get(AppConfiguration.self) ?? AppConfiguration.defaultValue
        let callListSettings: CallListSettings = sharedData.entries[ApplicationSpecificSharedDataKeys.callListSettings]?.get(CallListSettings.self) ?? CallListSettings.defaultSettings
        let experimentalUISettings: ExperimentalUISettings = sharedData.entries[ApplicationSpecificSharedDataKeys.experimentalUISettings]?.get(ExperimentalUISettings.self) ?? ExperimentalUISettings.defaultSettings
        
        let entries = SGControllerEntries(presentationData: presentationData, callListSettings: callListSettings, experimentalUISettings: experimentalUISettings, SGSettings: sgUISettings, appConfiguration: appConfiguration, nameColors: PeerNameColors.with(availableReplyColors: availableReplyColors, availableProfileColors: availableProfileColors) /*state: state,*/)
        
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Swiftgram"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        
        /*var index = 0
        var scrollToItem: ListViewScrollToItem?
         if let focusOnItemTag = focusOnItemTag {
            for entry in entries {
                if entry.tag?.isEqual(to: focusOnItemTag) ?? false {
                    scrollToItem = ListViewScrollToItem(index: index, position: .top(0.0), animated: false, curve: .Default(duration: 0.0), directionHint: .Up)
                }
                index += 1
            }
        } */
        
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, ensureVisibleItemTag: /*focusOnItemTag*/ nil, initialScrollToItem: nil /* scrollToItem*/ )
        
        return (controllerState, (listState, arguments))
    }
    
    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c, a in
        controller?.present(c, in: .window(.root), with: a)
    }
    pushControllerImpl = { [weak controller] c in
        (controller?.navigationController as? NavigationController)?.pushViewController(c)
    }
    getRootControllerImpl = { [weak controller] in
        return controller?.view.window?.rootViewController
    }
    getRootControllerImpl = { [weak controller] in
        return controller?.view.window?.rootViewController
    }
    getNavigationControllerImpl = { [weak controller] in
        return controller?.navigationController as? NavigationController
    }
    askForRestart = { [weak context] in
        guard let context = context else {
            return
        }
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let actionSheet = ActionSheetController(presentationData: presentationData)
        actionSheet.setItemGroups([ActionSheetItemGroup(items: [
            ActionSheetTextItem(title: i18n("Common.RestartRequired", presentationData.strings.baseLanguageCode)),
            ActionSheetButtonItem(title: i18n("Common.RestartNow", presentationData.strings.baseLanguageCode), color: .destructive, font: .default, action: {
                exit(0)
            })
        ]), ActionSheetItemGroup(items: [
            ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
            })
        ])])
        presentControllerImpl?(actionSheet, ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
    }
    return controller

}