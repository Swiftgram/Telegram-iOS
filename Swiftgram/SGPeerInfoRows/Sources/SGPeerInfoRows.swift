import SGSimpleSettings
import SGStrings
import CountrySelectionUI
import Foundation
import UIKit
import AccountContext
import TelegramPresentationData
import TelegramCore
import TelegramStringFormatting

func sgPeerInfoProfileItems(nearestChatParticipant: (String?, Int32?), data: PeerInfoScreenData, context: AccountContext, presentationData: PresentationData, interaction: PeerInfoInteraction, isMyProfile: Bool) -> [PeerInfoScreenItem] {
    var items: [PeerInfoScreenItem] = []
    var itemId = 0
    var idText = ""
    var isMutualContact = false

    if case let .user(user) = data.peer {
        idText = String(user.id.id._internalGetInt64Value())
        isMutualContact = user.flags.contains(.mutualContact)
    } else if case let .channel(channel) = data.peer {
        idText = "-100" + String(channel.id.id._internalGetInt64Value())
    } else if case let .legacyGroup(group) = data.peer {
        idText = String(group.id.id._internalGetInt64Value())
    }

    if SGSimpleSettings.shared.showProfileId {
        items.append(PeerInfoScreenLabeledValueItem(id: itemId, context: context, label: i18n("Chat.ID", presentationData.strings.baseLanguageCode), text: idText, textColor: .primary, action: { node, _ in
            interaction.openSgContextMenu(node, nil, .copy(text: idText, copyKey: "Chat.ID.Copy", copiedKey: "Chat.ID.Copied"))
        }, longTapAction: nil, contextAction: { node, gesture, _ in
            interaction.openSgContextMenu(node, gesture, .copy(text: idText, copyKey: "Chat.ID.Copy", copiedKey: "Chat.ID.Copied"))
        }, requestLayout: { _ in
            interaction.requestLayout(false)
        }))
        itemId += 1
    }

    if SGSimpleSettings.shared.showDC {
        var dcId: Int? = nil
        var phoneCountryText = ""
        var dcLabel = ""
        var dcText = ""

        if let cachedData = data.cachedData as? CachedUserData, let phoneCountry = cachedData.peerStatusSettings?.phoneCountry {
            var countryName = ""
            let countriesConfiguration = context.currentCountriesConfiguration.with { $0 }
            if let country = countriesConfiguration.countries.first(where: { $0.id == phoneCountry }) {
                countryName = country.localizedName ?? country.name
            } else if phoneCountry == "FT" {
                countryName = presentationData.strings.Chat_NonContactUser_AnonymousNumber
            } else if phoneCountry == "TS" {
                countryName = "Test"
            }
            phoneCountryText = emojiFlagForISOCountryCode(phoneCountry) + " " + countryName
        }
        if let peer = data.peer, let smallProfileImage = peer.smallProfileImage, let cloudResource = smallProfileImage.resource as? CloudPeerPhotoSizeMediaResource {
            dcId = cloudResource.datacenterId
        }

        if let dcId = dcId {
            dcLabel = "dc: \(dcId)"
            if !phoneCountryText.isEmpty {
                dcText = phoneCountryText
            }
        } else if !phoneCountryText.isEmpty {
            dcLabel = "dc: ?"
            dcText = phoneCountryText
        }

        if !dcText.isEmpty || !dcLabel.isEmpty {
            items.append(PeerInfoScreenLabeledValueItem(id: itemId, context: context, label: dcLabel, text: dcText, textColor: .primary, action: { node, _ in
                interaction.openSgContextMenu(node, nil, .openURL(url: "https://core.telegram.org/api/datacenter"))
            }, longTapAction: nil, contextAction: { node, gesture, _ in
                interaction.openSgContextMenu(node, gesture, .openURL(url: "https://core.telegram.org/api/datacenter"))
            }, requestLayout: { _ in
                interaction.requestLayout(false)
            }))
            itemId += 1
        }
    }

    if SGSimpleSettings.shared.showCreationDate, let channelCreationTimestamp = data.channelCreationTimestamp {
        let creationDateString = stringForDate(timestamp: channelCreationTimestamp, strings: presentationData.strings)
        items.append(PeerInfoScreenLabeledValueItem(id: itemId, context: context, label: i18n("Chat.Created.Label", presentationData.strings.baseLanguageCode), text: creationDateString, textColor: .primary, action: { node, _ in
            interaction.openSgContextMenu(node, nil, .copy(text: creationDateString, copyKey: "Chat.Created.Copy", copiedKey: "Chat.Created.Copied"))
        }, longTapAction: nil, contextAction: { node, gesture, _ in
            interaction.openSgContextMenu(node, gesture, .copy(text: creationDateString, copyKey: "Chat.Created.Copy", copiedKey: "Chat.Created.Copied"))
        }, requestLayout: { _ in
            interaction.requestLayout(false)
        }))
        itemId += 1
    }

    if let invitedAt = nearestChatParticipant.1 {
        let joinedDateString = stringForDate(timestamp: invitedAt, strings: presentationData.strings)
        items.append(PeerInfoScreenLabeledValueItem(id: itemId, context: context, label: i18n("Chat.JoinedDateTitle", presentationData.strings.baseLanguageCode, nearestChatParticipant.0 ?? "chat"), text: joinedDateString, textColor: .primary, action: { node, _ in
            interaction.openSgContextMenu(node, nil, .copy(text: joinedDateString, copyKey: "Chat.JoinedDate.Copy", copiedKey: "Chat.JoinedDate.Copied"))
        }, longTapAction: nil, contextAction: { node, gesture, _ in
            interaction.openSgContextMenu(node, gesture, .copy(text: joinedDateString, copyKey: "Chat.JoinedDate.Copy", copiedKey: "Chat.JoinedDate.Copied"))
        }, requestLayout: { _ in
            interaction.requestLayout(false)
        }))
        itemId += 1
    }

    if SGSimpleSettings.shared.showRegDate {
        var regDateString = ""
        if let cachedData = data.cachedData as? CachedUserData, let registrationDate = cachedData.peerStatusSettings?.registrationDate {
            let components = registrationDate.components(separatedBy: ".")
            if components.count == 2, let first = Int32(components[0]), let second = Int32(components[1]) {
                let month = first - 1
                let year = second - 1900
                regDateString = stringForMonth(strings: presentationData.strings, month: month, ofYear: year)
            }
        }
        if let regDate = data.regDate, regDateString.isEmpty {
            let regTimestamp = Int32((regDate.from + regDate.to) / 2)
            switch context.currentAppConfiguration.with({ $0 }).sgWebSettings.global.regdateFormat {
                case "year":
                    regDateString = stringForDateWithoutDayAndMonth(date: Date(timeIntervalSince1970: Double(regTimestamp)), strings: presentationData.strings)
                case "month":
                    regDateString = stringForDateWithoutDay(date: Date(timeIntervalSince1970: Double(regTimestamp)), strings: presentationData.strings)
                default:
                    regDateString = stringForDate(timestamp: regTimestamp, strings: presentationData.strings)
            }
        }
        if !regDateString.isEmpty {
            items.append(PeerInfoScreenLabeledValueItem(id: itemId, context: context, label: i18n("Chat.RegDate", presentationData.strings.baseLanguageCode), text: regDateString, textColor: .primary, action: { node, _ in
                interaction.openSgContextMenu(node, nil, .copy(text: regDateString, copyKey: "Chat.RegDate.Copy", copiedKey: "Chat.RegDate.Copied"))
            }, longTapAction: nil, contextAction: { node, gesture, _ in
                interaction.openSgContextMenu(node, gesture, .copy(text: regDateString, copyKey: "Chat.RegDate.Copy", copiedKey: "Chat.RegDate.Copied"))
            }, requestLayout: { _ in
                interaction.requestLayout(false)
            }))
            itemId += 1
        }
    }
    if isMutualContact && !isMyProfile {
        items.append(PeerInfoScreenLabeledValueItem(id: itemId, label: i18n("MutualContact.Label", presentationData.strings.baseLanguageCode), text: "", action: nil, longTapAction: { _ in }, requestLayout: { _ in
            interaction.requestLayout(false)
        }))
    }

    return items
}

func sgPeerInfoSettingsProfileIdItems(data: PeerInfoScreenData, interaction: PeerInfoInteraction) -> [PeerInfoScreenItem] {
    guard SGSimpleSettings.shared.showProfileId else {
        return []
    }

    let idText = data.peer.map { String($0.id.id._internalGetInt64Value()) } ?? ""
    return [PeerInfoScreenActionItem(id: 100, text: "ID: \(idText)", color: .accent, action: {
        UIPasteboard.general.string = idText
        interaction.notifyTextCopied()
    })]
}

func sgPeerInfoSettingsItems(context: AccountContext, paymentsEnabled: Bool, presentationData: PresentationData, interaction: PeerInfoInteraction) -> [PeerInfoScreenItem] {
    let hasNewFeatures = {
        return false
    }
    let swiftgramLabel: PeerInfoScreenDisclosureItem.Label
    if hasNewFeatures() {
        swiftgramLabel = .titleBadge(presentationData.strings.Settings_New, presentationData.theme.list.itemAccentColor)
    } else {
        swiftgramLabel = .none
    }

    let hasNewProFeatures = {
        return false
    }
    let swiftgramProLabel: PeerInfoScreenDisclosureItem.Label
    if hasNewProFeatures() {
        swiftgramProLabel = .titleBadge(presentationData.strings.Settings_New, presentationData.theme.list.itemAccentColor)
    } else {
        swiftgramProLabel = .none
    }

    var items: [PeerInfoScreenItem] = []
    if paymentsEnabled || context.sharedContext.immediateSGStatus.status > 1 {
        items.append(PeerInfoScreenDisclosureItem(id: 0, label: swiftgramProLabel, text: "Swiftgram Pro", icon: PresentationResourcesSettings.swiftgramPro, action: {
            interaction.openSettings(.swiftgramPro)
        }))
    }
    items.append(PeerInfoScreenDisclosureItem(id: 1, label: swiftgramLabel, text: "Swiftgram", icon: PresentationResourcesSettings.swiftgram, action: {
        interaction.openSettings(.swiftgram)
    }))
    return items
}
