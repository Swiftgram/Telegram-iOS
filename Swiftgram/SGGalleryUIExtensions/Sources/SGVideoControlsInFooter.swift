import SGSimpleSettings
import ContextUI
import Display
import SwiftSignalKit
import UIKit

var sgVideoControlsInFooterEnabled: Bool {
    return SGSimpleSettings.shared.videoControlsInFooter
}

func sgVideoControlsInFooterMenuItems(
    displayPictureInPicture: Bool,
    displaySettings: Bool,
    displayFullscreen: Bool,
    isLandscape: Bool,
    pictureInPicture: @escaping () -> Void,
    openSettings: @escaping () -> Void,
    toggleFullscreen: @escaping () -> Void
) -> [ContextMenuItem] {
    guard sgVideoControlsInFooterEnabled else {
        return []
    }

    var items: [ContextMenuItem] = []
    if displayPictureInPicture {
        items.append(.action(ContextMenuActionItem(text: "Picture in Picture", textColor: .primary, icon: { theme in
            return generateTintedImage(image: UIImage(bundleImageName: "Media Gallery/PictureInPictureButton"), color: theme.contextMenu.primaryColor)
        }, action: { _, dismiss in
            dismiss(.default)
            pictureInPicture()
        })))
    }
    if displaySettings {
        items.append(.action(ContextMenuActionItem(text: "Settings", textColor: .primary, icon: { theme in
            return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Settings"), color: theme.contextMenu.primaryColor)
        }, action: { _, dismiss in
            dismiss(.default)
            Queue.mainQueue().after(0.12, openSettings)
        })))
    }
    if displayFullscreen {
        items.append(.action(ContextMenuActionItem(text: isLandscape ? "Collapse" : "Fullscreen", textColor: .primary, icon: { theme in
            return generateTintedImage(image: UIImage(bundleImageName: isLandscape ? "Chat/Context Menu/Collapse" : "Chat/Context Menu/Expand"), color: theme.contextMenu.primaryColor)
        }, action: { controller, _ in
            // The context menu locks the current orientation until it is removed from the window.
            controller?.dismiss(result: .default, completion: {
                toggleFullscreen()
            })
        })))
    }
    return items
}
