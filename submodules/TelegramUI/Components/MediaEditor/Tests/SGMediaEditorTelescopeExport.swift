import Foundation
import UIKit
import AVFoundation
import TelegramCore
@testable import MediaEditor

// Export-side regression only: ChatMediaSend owns normalization and cannot be
// imported here without a dependency cycle. These are its normalized equivalents.
let sgMediaEditorTelescopeExportScenarios: [MediaEditorExportScenario] = [
    sgTelescopeScenario(id: "sg-telescope-short", preset: .videoMessageHD, trim: nil, orientation: nil, mirrored: false),
    sgTelescopeScenario(id: "sg-telescope-trim", preset: .compressedLow, trim: 2.0 ..< 8.0, orientation: .left, mirrored: true)
]

private func sgTelescopeScenario(id: String, preset: MediaQualityPreset, trim: Range<Double>?, orientation: MediaCropOrientation?, mirrored: Bool) -> MediaEditorExportScenario {
    return MediaEditorExportScenario(id: id, kind: .video, durationTolerance: 0.1) {
        guard let asset = sgTelescopeSource() else {
            return .unavailable("cannot prepare marked-square telescope source with audio")
        }
        var values = chatMediaEditorValues(peerId: MediaEditorExportFixtures.peerId, originalDimensions: PixelDimensions(width: 512, height: 512), qualityPreset: preset)
            .withUpdatedCrop(rect: CGRect(x: 0, y: 0, width: 512, height: 512), rotation: 0.0, orientation: orientation, mirroring: mirrored, perspective: .zero)
            .withUpdatedSgSendAsTelescope(true)
        if let trim {
            values = values.withUpdatedVideoTrimRange(trim)
        }
        let duration = trim.map { $0.upperBound - $0.lowerBound } ?? 10.0
        let configuration = recommendedVideoExportConfiguration(values: values, duration: duration, frameRate: 30.0)
        return .video(subject: .video(asset: asset, isStory: false), configuration: configuration, textScale: 1.0, expectedFrameCount: Int(duration * 30.0), expectedDuration: duration)
    }
}

private func sgTelescopeSource() -> AVAsset? {
    let video = AVURLAsset(url: MediaEditorExportFixtures.url("video-square.mp4"))
    guard let sourceVideo = video.tracks(withMediaType: .video).first else { return nil }
    let audioURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("sg-telescope-tone-v1.wav")
    // Ten seconds of mono PCM. WAV keeps fixture generation cheap and avoids an
    // additional encoder dependency; the real export must produce an AAC track.
    if !FileManager.default.fileExists(atPath: audioURL.path) {
        let rate = 44100
        let samples = rate * 10
        var data = Data()
        func text(_ value: String) { data.append(contentsOf: value.utf8) }
        func word(_ value: UInt16) {
            var value = value.littleEndian
            withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
        }
        func dword(_ value: UInt32) {
            var value = value.littleEndian
            withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
        }
        text("RIFF"); dword(UInt32(36 + samples * 2)); text("WAVEfmt ")
        dword(16); word(1); word(1); dword(UInt32(rate)); dword(UInt32(rate * 2)); word(2); word(16)
        text("data"); dword(UInt32(samples * 2))
        for index in 0 ..< samples {
            let sample = Int16(sin(Double(index) * 2.0 * .pi * 440.0 / Double(rate)) * 8000.0)
            word(UInt16(bitPattern: sample))
        }
        do { try data.write(to: audioURL, options: .atomic) } catch { return nil }
    }
    let audio = AVURLAsset(url: audioURL)
    let composition = AVMutableComposition()
    guard let sourceAudio = audio.tracks(withMediaType: .audio).first,
        let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
        let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { return nil }
    do {
        for index in 0 ..< 5 {
            try videoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: CMTime(seconds: 2.0, preferredTimescale: 600)), of: sourceVideo, at: CMTime(seconds: Double(index) * 2.0, preferredTimescale: 600))
        }
        videoTrack.preferredTransform = sourceVideo.preferredTransform
        try audioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: CMTime(seconds: 10.0, preferredTimescale: 600)), of: sourceAudio, at: .zero)
    } catch { return nil }
    return composition
}

/// Additional encoded-output checks shared by the CLI harness and XCTest suite.
func sgMediaEditorTelescopeExportFailures(scenario: MediaEditorExportScenario, run: MediaEditorExportRun) -> [String] {
    guard scenario.id == "sg-telescope-short" || scenario.id == "sg-telescope-trim" else { return [] }
    guard let path = run.outputPath else { return ["\(scenario.id): missing telescope output"] }
    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    var failures: [String] = []
    func fail(_ message: String) { failures.append("\(scenario.id): \(message)") }
    let side: CGFloat = scenario.id == "sg-telescope-short" ? 384.0 : 640.0
    if asset.tracks(withMediaType: .video).first?.naturalSize != CGSize(width: side, height: side) {
        fail("expected square \(Int(side))px video track")
    }
    guard let audio = asset.tracks(withMediaType: .audio).first else {
        fail("export lost audio track")
        return failures
    }
    if audio.timeRange.duration.seconds < (run.expectedDuration ?? 0.0) - 0.1 { fail("audio track truncated") }
    if let description = audio.formatDescriptions.first {
        let format = description as! CMAudioFormatDescription
        if CMFormatDescriptionGetMediaSubType(format) != kAudioFormatMPEG4AAC { fail("audio is not AAC") }
    } else { fail("audio has no format description") }
    if let bytes = try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber {
        if bytes.int64Value <= 0 || bytes.int64Value >= 8 * 1024 * 1024 { fail("output size \(bytes) outside (0, 8 MiB)") }
    } else { fail("cannot read output byte size") }
    // Marked fixture corners should survive the crop/orientation/mirror and
    // encoding. Compare decoded corner colours with the actual composed frames;
    // exported PNGs also expose the absolute orientation for visual inspection.
    guard let decoded = MediaEditorExportRunner.decodeVideo(path: path, frameIndices: Set(run.frames.keys)) else {
        fail("cannot decode telescope output")
        return failures
    }
    for (index, frame) in run.frames {
        guard let output = decoded.frames[index] ?? (index >= decoded.frameCount - 1 ? decoded.lastFrame : nil) else { continue }
        let expected = MediaEditorBitmap(frame)
        let actual = MediaEditorBitmap(output)
        guard expected.width == actual.width, expected.height == actual.height else { continue }
        for (x, y) in [(0.04, 0.04), (0.96, 0.04), (0.04, 0.96), (0.96, 0.96)] {
            let offset = (min(actual.height - 1, Int(Double(actual.height) * y)) * actual.width + min(actual.width - 1, Int(Double(actual.width) * x))) * 4
            if (0 ..< 3).contains(where: { abs(Int(expected.bytes[offset + $0]) - Int(actual.bytes[offset + $0])) > 65 }) {
                fail("decoded corner differs from composed frame \(index) at \(x),\(y)")
            }
        }
    }
    return failures
}
