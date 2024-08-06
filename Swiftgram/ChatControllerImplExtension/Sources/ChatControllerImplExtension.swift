import SGSimpleSettings
import Foundation
import UIKit
import Postbox
import SwiftSignalKit
import Display
import AsyncDisplayKit
import TelegramCore
import SafariServices
import MobileCoreServices
import Intents
import LegacyComponents
import TelegramPresentationData
import TelegramUIPreferences
import DeviceAccess
import TextFormat
import TelegramBaseController
import AccountContext
import TelegramStringFormatting
import OverlayStatusController
import DeviceLocationManager
import ShareController
import UrlEscaping
import ContextUI
import ComposePollUI
import AlertUI
import PresentationDataUtils
import UndoUI
import TelegramCallsUI
import TelegramNotices
import GameUI
import ScreenCaptureDetection
import GalleryUI
import OpenInExternalAppUI
import LegacyUI
import InstantPageUI
import LocationUI
import BotPaymentsUI
import DeleteChatPeerActionSheetItem
import HashtagSearchUI
import LegacyMediaPickerUI
import Emoji
import PeerAvatarGalleryUI
import PeerInfoUI
import RaiseToListen
import UrlHandling
import AvatarNode
import AppBundle
import LocalizedPeerData
import PhoneNumberFormat
import SettingsUI
import UrlWhitelist
import TelegramIntents
import TooltipUI
import StatisticsUI
import MediaResources
import GalleryData
import ChatInterfaceState
import InviteLinksUI
import Markdown
import TelegramPermissionsUI
import Speak
import TranslateUI
import UniversalMediaPlayer
import WallpaperBackgroundNode
import ChatListUI
import CalendarMessageScreen
import ReactionSelectionNode
import ReactionListContextMenuContent
import AttachmentUI
import AttachmentTextInputPanelNode
import MediaPickerUI
import ChatPresentationInterfaceState
import Pasteboard
import ChatSendMessageActionUI
import ChatTextLinkEditUI
import WebUI
import PremiumUI
import ImageTransparency
import StickerPackPreviewUI
import TextNodeWithEntities
import EntityKeyboard
import ChatTitleView
import EmojiStatusComponent
import ChatTimerScreen
import MediaPasteboardUI
import ChatListHeaderComponent
import ChatControllerInteraction
import FeaturedStickersScreen
import ChatEntityKeyboardInputNode
import StorageUsageScreen
import AvatarEditorScreen
import ChatScheduleTimeController
import ICloudResources
import StoryContainerScreen
import MoreHeaderButton
import VolumeButtons
import ChatAvatarNavigationNode
import ChatContextQuery
import PeerReportScreen
import PeerSelectionController
import SaveToCameraRoll
import ChatMessageDateAndStatusNode
import ReplyAccessoryPanelNode
import TextSelectionNode
import ChatMessagePollBubbleContentNode
import ChatMessageItem
import ChatMessageItemImpl
import ChatMessageItemView
import ChatMessageItemCommon
import ChatMessageAnimatedStickerItemNode
import ChatMessageBubbleItemNode
import ChatNavigationButton
import WebsiteType
import ChatQrCodeScreen
import PeerInfoScreen
import MediaEditorScreen
import WallpaperGalleryScreen
import WallpaperGridScreen
import VideoMessageCameraScreen
import TopMessageReactions
import AudioWaveform
import PeerNameColorScreen
import ChatEmptyNode
import ChatMediaInputStickerGridItem
import AdsInfoScreen

extension ChatControllerImpl {

    func forwardMessagesToCloud(messageIds: [MessageId], removeNames: Bool, openCloud: Bool, resetCurrent: Bool = false) {
        let _ = (self.context.engine.data.get(EngineDataMap(
            messageIds.map(TelegramEngine.EngineData.Item.Messages.Message.init)
        ))
        |> deliverOnMainQueue).startStandalone(next: { [weak self] messages in
            guard let strongSelf = self else {
                return
            }
            
            if resetCurrent {
                strongSelf.updateChatPresentationInterfaceState(animated: true, interactive: true, { $0.updatedInterfaceState({ $0.withUpdatedForwardMessageIds(nil).withUpdatedForwardOptionsState(nil).withoutSelectionState() }) })
            }

            let sortedMessages = messages.values.compactMap { $0?._asMessage() }.sorted { lhs, rhs in
                return lhs.id < rhs.id
            }
            
            var attributes: [MessageAttribute] = []
            if removeNames {
                attributes.append(ForwardOptionsMessageAttribute(hideNames: true, hideCaptions: false))
            }
            
            if !openCloud {
                Queue.mainQueue().after(0.88) {
                    strongSelf.chatDisplayNode.hapticFeedback.success()
                }
                
                let presentationData = strongSelf.context.sharedContext.currentPresentationData.with { $0 }
                strongSelf.present(UndoOverlayController(presentationData: presentationData, content: .forward(savedMessages: true, text: messages.count == 1 ? presentationData.strings.Conversation_ForwardTooltip_SavedMessages_One : presentationData.strings.Conversation_ForwardTooltip_SavedMessages_Many), elevatedLayout: false, animateInAsReplacement: true, action: { [weak self] value in
                    if case .info = value, let strongSelf = self {
                        let _ = (strongSelf.context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: strongSelf.context.account.peerId))
                        |> deliverOnMainQueue).startStandalone(next: { peer in
                            guard let strongSelf = self, let peer = peer, let navigationController = strongSelf.effectiveNavigationController else {
                                return
                            }
                            
                            strongSelf.context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigationController, context: strongSelf.context, chatLocation: .peer(peer), keepStack: .always, purposefulAction: {}, peekData: nil))
                        })
                        return true
                    }
                    return false
                }), in: .current)
            }

            let _ = (enqueueMessages(account: strongSelf.context.account, peerId: strongSelf.context.account.peerId, messages: sortedMessages.map { message -> EnqueueMessage in
                return .forward(source: message.id, threadId: nil, grouping: .auto, attributes: attributes, correlationId: nil)
            })
            |> deliverOnMainQueue).startStandalone(next: { messageIds in
                guard openCloud else {
                    return
                }
                if let strongSelf = self {
                    let signals: [Signal<Bool, NoError>] = messageIds.compactMap({ id -> Signal<Bool, NoError>? in
                        guard let id = id else {
                            return nil
                        }
                        return strongSelf.context.account.pendingMessageManager.pendingMessageStatus(id)
                        |> mapToSignal { status, _ -> Signal<Bool, NoError> in
                            if status != nil {
                                return .never()
                            } else {
                                return .single(true)
                            }
                        }
                        |> take(1)
                    })
                    if strongSelf.shareStatusDisposable == nil {
                        strongSelf.shareStatusDisposable = MetaDisposable()
                    }
                    strongSelf.shareStatusDisposable?.set((combineLatest(signals)
                    |> deliverOnMainQueue).startStrict(next: { [weak strongSelf] _ in
                        guard let strongSelf = strongSelf else {
                            return
                        }
                        strongSelf.chatDisplayNode.hapticFeedback.success()
                        let _ = (strongSelf.context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: strongSelf.context.account.peerId))
                        |> deliverOnMainQueue).startStandalone(next: { [weak strongSelf] peer in
                            guard let strongSelf = strongSelf, let peer = peer, let navigationController = strongSelf.effectiveNavigationController else {
                                return
                            }

                            var navigationSubject: ChatControllerSubject? = nil
                            for messageId in messageIds {
                                if let messageId = messageId {
                                    navigationSubject = .message(id: .id(messageId), highlight: ChatControllerSubject.MessageHighlight(quote: nil), timecode: nil, setupReply: false)
                                    break
                                }
                            }
                            strongSelf.context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigationController, context: strongSelf.context, chatLocation: .peer(peer), subject: navigationSubject, keepStack: .always, purposefulAction: {}, peekData: nil))
                        })
                    } ))
                }
            })
        })
    }
}
