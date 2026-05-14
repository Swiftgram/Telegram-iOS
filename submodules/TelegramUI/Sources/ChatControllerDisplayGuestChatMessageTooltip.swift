import Foundation
import TelegramPresentationData
import AccountContext
import TelegramCore
import SwiftSignalKit
import Display
import PresentationDataUtils
import ChatMessageItemView
import TelegramNotices
import TooltipUI

extension ChatControllerImpl {
    func displayGuestChatMessageTooltip(itemNode: ChatMessageItemView) {
        let _ = (ApplicationSpecificNotice.getGuestChatMessageTooltip(accountManager: self.context.sharedContext.accountManager)
        |> deliverOnMainQueue).startStandalone(next: { [weak self, weak itemNode] value in
            guard let self, let itemNode else {
                return
            }
            
            #if DEBUG
            var value = value
            if "".isEmpty {
                value = 0
            }
            #endif
            
            if value >= 2 {
                return
            }
            
            guard let sourceNode = itemNode.getAuthorNameNode() else {
                return
            }
            
            Queue.mainQueue().after(0.5) {
                let sourceRect = sourceNode.view.convert(sourceNode.view.bounds, to: nil).offsetBy(dx: -35.0, dy: 0.0)
                
                self.messageTooltipController?.dismiss()
                self.guestChatMessageTooltipController?.dismiss()
                
                let tooltipScreen = TooltipScreen(
                    account: self.context.account,
                    sharedContext: self.context.sharedContext,
                    text: .plain(text: self.presentationData.strings.Chat_GuestChatMessageTooltip),
                    balancedTextLayout: true,
                    location: .point(sourceRect, .bottom),
                    displayDuration: .custom(3.5),
                    shouldDismissOnTouch: { _, _ in
                        return .dismiss(consume: false)
                    }
                )
                self.guestChatMessageTooltipController = tooltipScreen
                tooltipScreen.becameDismissed = { [weak self, weak tooltipScreen] _ in
                    if let strongSelf = self, let tooltipScreen, strongSelf.guestChatMessageTooltipController === tooltipScreen {
                        strongSelf.guestChatMessageTooltipController = nil
                    }
                }
                
                //            let _ = self.chatDisplayNode.messageTransitionNode.addCustomOffsetHandler(itemNode: itemNode, update: { [weak tooltipScreen] offset, transition in
                //                guard let tooltipScreen, tooltipScreen.isNodeLoaded else {
                //                    return false
                //                }
                //                tooltipScreen.addRelativeScrollingOffset(-offset, transition: transition)
                //
                //                return true
                //            })
                
                self.present(tooltipScreen, in: .current)
                
                let _ = ApplicationSpecificNotice.incrementGuestChatMessageTooltip(accountManager: self.context.sharedContext.accountManager).startStandalone()
            }
        })
    }
}
