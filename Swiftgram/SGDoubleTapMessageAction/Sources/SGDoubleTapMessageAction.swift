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

func sgHandleDoubleTapMessageAction(incoming: Bool, message: Message, editAction: () -> Void, defaultAction: () -> Void) {
    switch sgDoubleTapMessageAction(incoming: incoming, message: message) {
    case SGSimpleSettings.MessageDoubleTapAction.none.rawValue:
        break
    case SGSimpleSettings.MessageDoubleTapAction.edit.rawValue:
        editAction()
    default:
        defaultAction()
    }
}
