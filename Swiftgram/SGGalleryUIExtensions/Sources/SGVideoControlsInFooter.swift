import SGSimpleSettings
import ComponentFlow
import ContextUI
import Display
import GlassControls
import SwiftSignalKit
import UIKit

var sgVideoControlsInFooterEnabled: Bool {
    return SGSimpleSettings.shared.videoControlsInFooter
}

func sgVideoControlsInFooterItems(
    isPlaying: Bool,
    displaySeekControls: Bool,
    togglePlayback: @escaping () -> Void,
    seek: @escaping (Bool) -> Void
) -> [GlassControlGroupComponent.Item] {
    guard sgVideoControlsInFooterEnabled else {
        return []
    }

    var items: [GlassControlGroupComponent.Item] = []
    if displaySeekControls {
        items.append(GlassControlGroupComponent.Item(
            id: AnyHashable("sgSeekBackward"),
            content: .customIcon(
                id: AnyHashable("sgSeekBackwardIcon"),
                component: AnyComponent(SGVideoSeekIconComponent(systemName: "gobackward.15")),
                insets: .zero
            ),
            action: {
                seek(false)
            }
        ))
    }
    items.append(GlassControlGroupComponent.Item(
        id: AnyHashable("sgPlayback"),
        content: .icon(isPlaying ? "Media Gallery/PictureInPicturePause" : "Media Gallery/PlayButton"),
        action: togglePlayback
    ))
    if displaySeekControls {
        items.append(GlassControlGroupComponent.Item(
            id: AnyHashable("sgSeekForward"),
            content: .customIcon(
                id: AnyHashable("sgSeekForwardIcon"),
                component: AnyComponent(SGVideoSeekIconComponent(systemName: "goforward.15")),
                insets: .zero
            ),
            action: {
                seek(true)
            }
        ))
    }
    return items
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
