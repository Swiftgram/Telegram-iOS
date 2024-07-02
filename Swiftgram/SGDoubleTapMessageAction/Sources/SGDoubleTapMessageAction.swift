import Foundation
import SGSimpleSettings
import Postbox
import TelegramCore


func sgDoubleTapMessageAction(incoming: Bool, message: Message) -> String {
    if incoming {
        return SGSimpleSettings.MessageDoubleTapAction.default.rawValue
    } else {
        return SGSimpleSettings.shared.messageDoubleTapActionOutgoing
    }
}
