import Foundation
import Wrap
import SGLogging
import ChatControllerInteraction
import ChatPresentationInterfaceState
import Postbox
import TelegramCore
import AccountContext

public func showMessageJson(controllerInteraction: ChatControllerInteraction, chatPresentationInterfaceState: ChatPresentationInterfaceState, message: Message, context: AccountContext) {
    if let navigationController = controllerInteraction.navigationController(), let rootController = navigationController.view.window?.rootViewController {
        var writingOptions: JSONSerialization.WritingOptions = [
            .prettyPrinted,
            //.sortedKeys,
        ]
        if #available(iOS 13.0, *) {
            writingOptions.insert(.withoutEscapingSlashes)
        }
        
        var messageData: Data? = nil
        do {
            messageData = try wrap(
                message,
                writingOptions: writingOptions
            )
        } catch {
            SGLogger.shared.log("ShowMessageJSON", "Error parsing data: \(error)")
            messageData = nil
        }
        
        guard let messageData = messageData else { return }
        
        let id = Int64.random(in: Int64.min ... Int64.max)
        let fileResource = LocalFileMediaResource(fileId: id, size: Int64(messageData.count), isSecretRelated: false)
        context.account.postbox.mediaBox.storeResourceData(fileResource.id, data: messageData, synchronous: true)
        
        let file = TelegramMediaFile(fileId: MediaId(namespace: Namespaces.Media.LocalFile, id: id), partialReference: nil, resource: fileResource, previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: nil, mimeType: "application/json; charset=utf-8", size: Int64(messageData.count), attributes: [.FileName(fileName: "message.json")], alternativeRepresentations: [])
        
        presentDocumentPreviewController(rootController: rootController, theme: chatPresentationInterfaceState.theme, strings: chatPresentationInterfaceState.strings, postbox: context.account.postbox, file: file, canShare: !message.isCopyProtected())
        
    }
}

extension MemoryBuffer: @retroactive WrapCustomizable {
    
    public func wrap(context: Any?, dateFormatter: DateFormatter?) -> Any? {
        let hexString = self.description
        return ["string": hexStringToString(hexString) ?? hexString]
    }
}

// There's a chacne we will need it for each empty/weird type, or it will be a runtime crash.
extension ContentRequiresValidationMessageAttribute: @retroactive WrapCustomizable {
    
    public func wrap(context: Any?, dateFormatter: DateFormatter?) -> Any? {
        return ["@type": "ContentRequiresValidationMessageAttribute"]
    }
}

func hexStringToString(_ hexString: String) -> String? {
    var chars = Array(hexString)
    var result = ""

    while chars.count > 0 {
        let c = String(chars[0...1])
        chars = Array(chars.dropFirst(2))
        if let byte = UInt8(c, radix: 16) {
            let scalar = UnicodeScalar(byte)
            result.append(String(scalar))
        } else {
            return nil
        }
    }

    return result
}
