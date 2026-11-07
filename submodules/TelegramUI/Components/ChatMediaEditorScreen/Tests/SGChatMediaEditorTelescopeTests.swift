import Foundation
import UIKit
import XCTest
import TelegramCore
import MediaEditor
import ChatMediaSend
@testable import ChatMediaEditorScreen

final class SGChatMediaEditorTelescopeTests: XCTestCase {
    func testEligibilityMatchesLegacyVideoGallery() {
        XCTAssertTrue(sgChatMediaEditorTelescopeIsVisible(canShow: true, isGallery: true, isVideo: true, isAnimation: false, isFilePreview: false))
        XCTAssertFalse(sgChatMediaEditorTelescopeIsVisible(canShow: false, isGallery: true, isVideo: true, isAnimation: false, isFilePreview: false))
        XCTAssertFalse(sgChatMediaEditorTelescopeIsVisible(canShow: true, isGallery: false, isVideo: true, isAnimation: false, isFilePreview: false))
        XCTAssertFalse(sgChatMediaEditorTelescopeIsVisible(canShow: true, isGallery: true, isVideo: false, isAnimation: false, isFilePreview: false))
        XCTAssertFalse(sgChatMediaEditorTelescopeIsVisible(canShow: true, isGallery: true, isVideo: true, isAnimation: true, isFilePreview: false))
        XCTAssertFalse(sgChatMediaEditorTelescopeIsVisible(canShow: true, isGallery: true, isVideo: true, isAnimation: false, isFilePreview: true))
    }

    func testPaidMediaBlocksEnablingButAllowsRemovingTelescope() {
        XCTAssertTrue(sgChatMediaEditorTelescopeChangeConflictsWithPrice(enabling: true, hasPaidMedia: true))
        XCTAssertFalse(sgChatMediaEditorTelescopeChangeConflictsWithPrice(enabling: true, hasPaidMedia: false))
        XCTAssertFalse(sgChatMediaEditorTelescopeChangeConflictsWithPrice(enabling: false, hasPaidMedia: true))
        XCTAssertFalse(sgChatMediaEditorTelescopeChangeConflictsWithPrice(enabling: false, hasPaidMedia: false))
    }

    func testDeliveryModeHiddenOutsideStandardPolicy() {
        for policy in [ChatMediaEditorTabPolicy.cropOnly, .filePreview] {
            XCTAssertFalse(sgChatMediaEditorTelescopeIsVisible(canShow: true, isGallery: true, isVideo: true, isAnimation: false, isFilePreview: false, policy: policy))
        }
    }

    func testTelescopeDisablesQualityWithoutChangingPreset() {
        let peerId = EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: EnginePeer.Id.Id._internalFromInt64Value(1))
        let original = chatMediaEditorValues(peerId: peerId, originalDimensions: PixelDimensions(width: 1920, height: 1080), qualityPreset: .compressedVeryHigh)
        let telescope = original.withUpdatedSgSendAsTelescope(true)
        XCTAssertTrue(chatMediaEditorVideoQualityIsEnabled(values: original))
        XCTAssertFalse(chatMediaEditorVideoQualityIsEnabled(values: telescope))
        XCTAssertEqual(telescope.qualityPreset, original.qualityPreset)
        XCTAssertTrue(chatMediaEditorVideoQualityIsEnabled(values: telescope.withUpdatedSgSendAsTelescope(false)))
    }

    func testPreviewSquareDoesNotDestroyCrop() {
        let peerId = EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: EnginePeer.Id.Id._internalFromInt64Value(1))
        let original = chatMediaEditorValues(peerId: peerId, originalDimensions: PixelDimensions(width: 1920, height: 1080), qualityPreset: .compressedVeryHigh)
        let crop = CGRect(x: 200.0, y: 100.0, width: 1200.0, height: 800.0)
        let values = original.withUpdatedCrop(rect: crop, rotation: 0.2, orientation: .left, mirroring: true, perspective: original.cropPerspective).withUpdatedSgSendAsTelescope(true)
        let state = sgChatMediaEditorTelescopePreviewState(values: values)
        XCTAssertEqual(state.cropRect, CGRect(x: 400.0, y: 100.0, width: 800.0, height: 800.0))
        XCTAssertEqual(state.rotation, 0.2)
        XCTAssertEqual(state.orientation, .left)
        XCTAssertTrue(state.mirrored)
        XCTAssertEqual(values.cropRect, crop)
        XCTAssertEqual(sgChatMediaEditorTelescopePreviewState(values: values.withUpdatedSgSendAsTelescope(false)).cropRect, crop)
    }
}
