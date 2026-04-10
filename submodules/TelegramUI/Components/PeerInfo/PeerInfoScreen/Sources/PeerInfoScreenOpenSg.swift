import Foundation
import UIKit
import Display
import AsyncDisplayKit
import ContextUI
import UndoUI
import SGStrings

enum SGContextMenuAction {
    case copy(text: String, copyKey: String, copiedKey: String)
    case openURL(url: String)
}

extension PeerInfoScreenNode {
    func openSgContextMenu(node: ASDisplayNode, gesture: ContextGesture?, action: SGContextMenuAction) {
        guard let sourceNode = node as? ContextExtractedContentContainingNode else {
            return
        }

        var items: [ContextMenuItem] = []
        switch action {
        case let .copy(text, copyKey, copiedKey):
            items.append(.action(ContextMenuActionItem(text: i18n(copyKey, self.presentationData.strings.baseLanguageCode), icon: { theme in
                generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Copy"), color: theme.contextMenu.primaryColor)
            }, action: { [weak self] c, _ in
                c?.dismiss {
                    guard let self else {
                        return
                    }
                    UIPasteboard.general.string = text
                    self.controller?.present(UndoOverlayController(presentationData: self.presentationData, content: .copy(text: i18n(copiedKey, self.presentationData.strings.baseLanguageCode)), elevatedLayout: false, animateInAsReplacement: false, action: { _ in return false }), in: .current)
                }
            })))
        case let .openURL(url):
            items.append(.action(ContextMenuActionItem(text: self.presentationData.strings.Passport_InfoLearnMore, icon: { theme in
                generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Browser"), color: theme.contextMenu.primaryColor)
            }, action: { [weak self] c, _ in
                c?.dismiss {
                    self?.openUrl(url: url, concealed: false, external: false)
                }
            })))
        }

        let actions = ContextController.Items(content: .list(items))
        let contextController = makeContextController(presentationData: self.presentationData, source: .extracted(PeerInfoContextExtractedContentSource(sourceNode: sourceNode)), items: .single(actions), gesture: gesture)
        self.controller?.present(contextController, in: .window(.root))
    }
}
