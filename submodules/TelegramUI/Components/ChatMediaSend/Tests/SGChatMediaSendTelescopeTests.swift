import Foundation
import UIKit
import XCTest
import TelegramCore
import MediaEditor
import LocalMediaResources
@testable import ChatMediaSend

final class SGChatMediaSendTelescopeTests: XCTestCase {
    private func values() -> MediaEditorValues {
        return chatMediaEditorValues(peerId: EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: EnginePeer.Id.Id._internalFromInt64Value(1)), originalDimensions: PixelDimensions(width: 1920, height: 1080), qualityPreset: .compressedMedium).withUpdatedSgSendAsTelescope(true)
    }

    func testFlagSurvivesEditsAndCoding() throws {
        let values = self.values().withUpdatedVideoTrimRange(5.0 ..< 90.0).withUpdatedQualityPreset(.compressedHigh).withUpdatedVideoIsMuted(false)
        let decoded = try JSONDecoder().decode(MediaEditorValues.self, from: JSONEncoder().encode(values))
        XCTAssertTrue(decoded.sgSendAsTelescope)
        XCTAssertEqual(decoded, values)
        XCTAssertFalse(values.withUpdatedSgSendAsTelescope(false).sgSendAsTelescope)
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(values)) as? [String: Any])
        old.removeValue(forKey: "sgSendAsTelescope")
        XCTAssertFalse(try JSONDecoder().decode(MediaEditorValues.self, from: JSONSerialization.data(withJSONObject: old)).sgSendAsTelescope)
    }

    func testTelescopeAloneCountsAsEdited() {
        XCTAssertTrue(chatMediaEditorValuesAreEdited(self.values(), baselineQualityPreset: .compressedMedium))
        XCTAssertFalse(chatMediaEditorValuesAreEdited(self.values().withUpdatedSgSendAsTelescope(false), baselineQualityPreset: .compressedMedium))
    }

    func testCropTrimAndPreset() throws {
        let input = self.values().withUpdatedCrop(rect: CGRect(x: 200, y: 100, width: 1000, height: 800), rotation: 0.2, orientation: .left, mirroring: true, perspective: .zero).withUpdatedVideoTrimRange(5.0 ..< 90.0)
        let values = try XCTUnwrap(sgChatMediaSendTelescopeValues(input, duration: 100.0))
        XCTAssertEqual(values.cropRect, CGRect(x: 300, y: 100, width: 800, height: 800))
        XCTAssertEqual(values.cropRotation, input.cropRotation)
        XCTAssertEqual(values.cropOrientation, .left)
        XCTAssertTrue(values.cropMirroring)
        XCTAssertEqual(values.videoTrimRange, 5.0 ..< 65.0)
        XCTAssertEqual(values.qualityPreset, .compressedLow)
        let dimensions = chatMediaEditorVideoFileDimensions(values: values, duration: 60.0)
        XCTAssertEqual(dimensions.width, dimensions.height)
        XCTAssertEqual(try XCTUnwrap(sgChatMediaSendTelescopeValues(self.values(), duration: 10.0)).qualityPreset, .videoMessageHD)
    }

    func testRotatedViewportIsNotClippedToOriginalBounds() throws {
        // The rotated 1920x1080 canvas is approximately 2121x2121. This
        // viewport fits the rotated content, but extends below original y=1080.
        let crop = CGRect(x: 760.0, y: 810.0, width: 600.0, height: 500.0)
        let expectedSquare = CGRect(x: 810.0, y: 810.0, width: 500.0, height: 500.0)
        let perspective = MediaEditorCropPerspective(vertical: 0.02, horizontal: -0.03)
        for rotation: CGFloat in [.pi / 4.0, -.pi / 4.0] {
            XCTAssertTrue(mediaEditorCropRectFits(crop, originalSize: self.values().originalDimensions.cgSize, rotation: rotation, perspective: perspective))
            for orientation: MediaCropOrientation in [.up, .down, .left, .right] {
                let input = self.values().withUpdatedCrop(rect: crop, rotation: rotation, orientation: orientation, mirroring: true, perspective: perspective)
                let output = try XCTUnwrap(sgChatMediaSendTelescopeValues(input, duration: 10.0))
                XCTAssertEqual(output.cropRect, expectedSquare)
                XCTAssertEqual(output.cropRotation, rotation)
                XCTAssertEqual(output.cropOrientation, orientation)
                XCTAssertEqual(output.cropPerspective, perspective)
                XCTAssertTrue(output.cropMirroring)
                let dimensions = chatMediaEditorVideoFileDimensions(values: output, duration: 10.0)
                XCTAssertEqual(dimensions.width, dimensions.height)
                XCTAssertGreaterThan(dimensions.width, 0)
            }
        }
    }

    func testMissingCropUsesOriginalViewportCentre() throws {
        let output = try XCTUnwrap(sgChatMediaSendTelescopeValues(self.values(), duration: 10.0))
        XCTAssertEqual(output.cropRect, CGRect(x: 420.0, y: 0.0, width: 1080.0, height: 1080.0))
    }

    func testRejectInvalidCropGeometry() {
        let crops: [CGRect] = [
            .null,
            .infinite,
            CGRect(x: CGFloat.nan, y: 0.0, width: 100.0, height: 100.0),
            CGRect(x: 0.0, y: CGFloat.infinity, width: 100.0, height: 100.0),
            CGRect(x: 0.0, y: 0.0, width: CGFloat.nan, height: 100.0),
            CGRect(x: 0.0, y: 0.0, width: 100.0, height: CGFloat.infinity),
            CGRect(x: 0.0, y: 0.0, width: 0.0, height: 100.0),
            CGRect(x: 0.0, y: 0.0, width: -100.0, height: 100.0),
            CGRect(x: 0.0, y: 0.0, width: 100.0, height: -100.0),
            CGRect(x: CGFloat.greatestFiniteMagnitude, y: 0.0, width: CGFloat.greatestFiniteMagnitude, height: 100.0)
        ]
        for crop in crops {
            let input = self.values().withUpdatedCrop(rect: crop, rotation: 0.0, orientation: .up, mirroring: false, perspective: .zero)
            XCTAssertNil(sgChatMediaSendTelescopeValues(input, duration: 10.0))
        }
        for invalid: CGFloat in [.nan, .infinity, -.infinity] {
            let input = self.values().withUpdatedCrop(rect: nil, rotation: invalid, orientation: .up, mirroring: false, perspective: .zero)
            XCTAssertNil(sgChatMediaSendTelescopeValues(input, duration: 10.0))
            for perspective in [MediaEditorCropPerspective(vertical: invalid, horizontal: 0.0), MediaEditorCropPerspective(vertical: 0.0, horizontal: invalid)] {
                let input = self.values().withUpdatedCrop(rect: nil, rotation: 0.0, orientation: .up, mirroring: false, perspective: perspective)
                XCTAssertNil(sgChatMediaSendTelescopeValues(input, duration: 10.0))
            }
        }
    }

    func testRejectInvalidVideo() {
        XCTAssertNil(sgChatMediaSendTelescopeValues(self.values(), duration: .nan))
        XCTAssertNil(sgChatMediaSendTelescopeValues(self.values(), duration: 0.0))
        XCTAssertNil(sgChatMediaSendTelescopeValues(self.values().withUpdatedVideoTrimRange(20.0 ..< 30.0), duration: 10.0))
        XCTAssertNil(sgChatMediaSendTelescopeValues(self.values().withUpdatedQualityPreset(.animation), duration: 10.0))
    }

    func testSingleVideoResourceAndLocalEchoAgree() throws {
        let result = ChatMediaEditorResult(media: .video(path: "/unused.mp4", values: self.values(), duration: 100.0), thumbnail: nil, caption: NSAttributedString(), stickers: [])
        let message = try XCTUnwrap(chatMediaEditorEnqueueMessage(result: result, forceHd: false, storeResourceData: { _, _ in }))
        guard case let .message(_, _, _, reference, _, _, _, _, _, _) = message.message else { return XCTFail() }
        let file = try XCTUnwrap(reference?.media as? TelegramMediaFile)
        let resource = try XCTUnwrap(file.resource as? LocalFileVideoMediaResource)
        let adjustments = try XCTUnwrap(resource.adjustments)
        let values = try JSONDecoder().decode(MediaEditorValues.self, from: adjustments.data.makeData())
        XCTAssertTrue(values.sgSendAsTelescope)
        XCTAssertEqual(values.videoTrimRange, 0.0 ..< 60.0)
        XCTAssertTrue(file.isInstantVideo)
        XCTAssertEqual(file.dimensions?.width, file.dimensions?.height)
    }
}
