import Foundation
import UIKit
import Display
import AsyncDisplayKit
import ContextUI
import UndoUI

enum SGContextMenuAction {
    case copy(text: String, copyTitle: String, copiedTitle: String)
    case copyLink(text: String)
    case openURL(url: String, title: String)
}

private func sgContextExtractedContentContainingNode(for node: ASDisplayNode) -> ContextExtractedContentContainingNode? {
    var currentNode: ASDisplayNode? = node
    while let node = currentNode {
        if let containingNode = node as? ContextExtractedContentContainingNode {
            return containingNode
        }
        currentNode = node.supernode
    }
    return nil
}

extension PeerInfoScreenNode {
    func openSgContextMenu(node: ASDisplayNode, gesture: ContextGesture?, action: SGContextMenuAction) {
        guard let sourceNode = sgContextExtractedContentContainingNode(for: node) else {
            gesture?.cancel()
            return
        }

        var items: [ContextMenuItem] = []
        switch action {
        case let .copy(text, copyTitle, copiedTitle):
            items.append(.action(ContextMenuActionItem(text: copyTitle, icon: { theme in
                generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Copy"), color: theme.contextMenu.primaryColor)
            }, action: { [weak self] c, _ in
                c?.dismiss {
                    guard let self else {
                        return
                    }
                    UIPasteboard.general.string = text
                    self.controller?.present(UndoOverlayController(presentationData: self.presentationData, content: .copy(text: copiedTitle), elevatedLayout: false, animateInAsReplacement: false, action: { _ in return false }), in: .current)
                }
            })))
        case let .copyLink(text):
            items.append(.action(ContextMenuActionItem(text: self.presentationData.strings.Conversation_ContextMenuCopy, icon: { theme in
                generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Copy"), color: theme.contextMenu.primaryColor)
            }, action: { [weak self] c, _ in
                c?.dismiss {
                    guard let self else {
                        return
                    }
                    UIPasteboard.general.string = text
                    self.controller?.present(UndoOverlayController(presentationData: self.presentationData, content: .linkCopied(title: nil, text: self.presentationData.strings.Conversation_LinkCopied), elevatedLayout: false, animateInAsReplacement: false, action: { _ in return false }), in: .current)
                }
            })))
        case let .openURL(url, title):
            items.append(.action(ContextMenuActionItem(text: title, icon: { theme in
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
