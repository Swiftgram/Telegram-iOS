import SGStrings
import Foundation
import UIKit
import Display
import LegacyComponents
import MediaEditor
import MediaCropComponent

public func sgChatMediaEditorTelescopeIsVisible(canShow: Bool, isGallery: Bool, isVideo: Bool, isAnimation: Bool, isFilePreview: Bool, policy: ChatMediaEditorTabPolicy = .standard) -> Bool {
    return canShow && !isFilePreview && policy == .standard && chatMediaEditorMuteButtonIsVisible(isGallery: isGallery, isVideo: isVideo, isAnimation: isAnimation)
}

public func sgChatMediaEditorTelescopeChangeConflictsWithPrice(enabling: Bool, hasPaidMedia: Bool) -> Bool {
    return enabling && hasPaidMedia
}

// Telescope is a delivery mode, not a destructive crop edit. Keep the user's
// original crop available when switching back or opening any V2 editing tool.
public func sgChatMediaEditorTelescopePreviewState(values: MediaEditorValues) -> MediaCropState {
    var state = chatMediaEditorCropState(values: values)
    if values.sgSendAsTelescope {
        let side = min(state.cropRect.width, state.cropRect.height)
        state.cropRect = CGRect(x: state.cropRect.midX - side / 2.0, y: state.cropRect.midY - side / 2.0, width: side, height: side)
    }
    return state
}

extension ChatMediaEditorScreen.Node {
    var sgShowsTelescopePreview: Bool {
        return self.sgIsTelescopeButtonVisible && self.controller?.sgCanSendTelescope == true && !self.mediaEditor.values.videoIsMuted && self.mediaEditor.values.sgSendAsTelescope && (self.activeTool == nil || self.activeTool == .cover)
    }

    var sgIsTelescopeButtonVisible: Bool {
        return sgChatMediaEditorTelescopeIsVisible(canShow: self.controller?.sgCanShowTelescope == true, isGallery: self.isGallery, isVideo: self.subject.isVideo, isAnimation: self.pageModel.currentItem.isAnimation, isFilePreview: self.isFilePreview, policy: self.tabPolicy)
    }

    func sgUpdateTelescopeButton(layout: ContainerViewLayout, safeInsets: UIEdgeInsets, transition: ContainedViewLayoutTransition) {
        guard self.sgIsTelescopeButtonVisible else {
            self.sgTelescopeButton?.removeFromSuperview()
            self.sgTelescopeButton = nil
            return
        }
        let button: UIButton
        if let current = self.sgTelescopeButton {
            button = current
        } else {
            button = UIButton(type: .custom)
            button.backgroundColor = UIColor(white: 0.0, alpha: 0.5)
            button.layer.cornerRadius = chatMediaEditorMuteButtonSize / 2.0
            button.setImage(TGPhotoEditorInterfaceAssets.telescopeIcon(), for: .normal)
            button.setImage(TGPhotoEditorInterfaceAssets.telescopeActiveIcon(), for: .selected)
            button.accessibilityLabel = "Send as Round Video (Telescope)"
            button.addTarget(self, action: #selector(self.sgTelescopeButtonPressed), for: .touchUpInside)
            self.sgTelescopeButton = button
            self.view.insertSubview(button, aboveSubview: self.pagerView)
        }
        button.isSelected = self.mediaEditor.values.sgSendAsTelescope
        button.accessibilityValue = button.isSelected ? "On" : "Off"
        let toolbarMinY = chatMediaEditorBottomPanelFrame(size: layout.size, safeInsets: safeInsets, toolbarHeight: chatMediaEditorToolbarHeight).minY
        let side = self.toolbarSide(layout: layout)
        let headerFrame = chatMediaEditorVideoHeaderFrame(size: layout.size, toolbarMinY: toolbarMinY, captionBaseHeight: self.captionPanelView?.baseHeight() ?? 0.0, safeInsets: safeInsets, toolbarSide: side, reservedCorners: layout.reservedCorners)
        let frame = chatMediaEditorMuteButtonFrame(headerFrame: headerFrame, safeInsets: safeInsets, toolbarSide: side).offsetBy(dx: chatMediaEditorMuteButtonSize + chatMediaEditorMuteButtonLeftInset, dy: 0.0)
        transition.updateFrame(view: button, frame: frame)
        let hidden = !self.isVideoScrubberShown || self.activeTool != nil || self.isInterfaceHiddenBySwipe || self.isEditingCaption || (layout.inputHeight ?? 0.0) > 0.0 || self.isSending
        transition.updateAlpha(layer: button.layer, alpha: hidden ? 0.0 : 1.0)
        button.isUserInteractionEnabled = !hidden
    }

    @objc func sgTelescopeButtonPressed() {
        guard self.sgIsTelescopeButtonVisible, self.activeTool == nil, !self.isSending, !self.isInvalidated else {
            return
        }
        guard self.controller?.sgCanSendTelescope == true else {
            self.sgPresentTelescopeBotOffer()
            return
        }
        let enabled = !self.mediaEditor.values.sgSendAsTelescope
        if sgChatMediaEditorTelescopeChangeConflictsWithPrice(enabling: enabled, hasPaidMedia: self.controller?.sgHasPaidMedia(self.pageModel.currentItem.uniqueId) == true) {
            self.sgPresentTelescopePaidMediaNotice()
            return
        }
        self.toolStartValues = self.mediaEditor.values
        self.mediaEditor.values = self.mediaEditor.values.withUpdatedSgSendAsTelescope(enabled)
        if enabled {
            self.mediaEditor.setVideoIsMuted(false)
            let duration = self.mediaEditor.originalDuration ?? self.subject.duration
            let range = self.mediaEditor.values.videoTrimRange ?? (0.0 ..< max(0.0, duration))
            if range.upperBound - range.lowerBound > 60.0 {
                self.mediaEditor.setVideoTrimRange(range.lowerBound ..< min(duration, range.lowerBound + 60.0), apply: true)
            }
            self.mediaEditor.seek(self.mediaEditor.values.videoTrimRange?.lowerBound ?? 0.0, andPlay: true)
        }
        self.selectionEditCommitted()
        self.requestLayout(transition: .animated(duration: 0.2, curve: .easeInOut))
    }

    func sgPresentTelescopePaidMediaNotice() {
        guard let controller = self.controller else {
            return
        }
        let strings = self.context.sharedContext.currentPresentationData.with { $0 }.strings
        let text = SGLocalizationManager.shared.localizedString("Telescope.PaidMediaConflict", strings.baseLanguageCode)
        controller.present(textAlertController(context: self.context, title: nil, text: text, actions: [TextAlertAction(type: .defaultAction, title: strings.Common_OK, action: {})]), in: .window(.root))
    }

    private func sgPresentTelescopeBotOffer() {
        guard let controller = self.controller else {
            return
        }
        let strings = self.context.sharedContext.currentPresentationData.with { $0 }.strings
        let alert = UIAlertController(title: "Convert in @TelescopyBot", message: "by Swiftgram", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: strings.Common_Cancel, style: .cancel))
        alert.addAction(UIAlertAction(title: strings.WebApp_OpenBot, style: .default, handler: { [weak controller] _ in
            guard let url = URL(string: "sg://resolve?domain=TelescopyBot&start=sgconvertdemo") else {
                return
            }
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
            controller?.dismiss()
        }))
        controller.present(alert, animated: true)
    }
}
