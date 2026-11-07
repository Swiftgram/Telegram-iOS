import Foundation
import UIKit
import AVFoundation
import MediaEditor

/// Normalize at the send boundary, before the same values are encoded into the
/// resource and used for its local echo. Eligibility/entitlement belongs to the host.
public func sgChatMediaSendTelescopeValues(_ values: MediaEditorValues, duration: Double) -> MediaEditorValues? {
    guard values.sgSendAsTelescope else {
        return values
    }
    guard duration.isFinite, duration > 0.0,
        values.originalDimensions.width > 0, values.originalDimensions.height > 0,
        values.collage.isEmpty, values.additionalVideoPath == nil, !values.videoBounce,
        values.coverDimensions == nil,
        !(values.qualityPreset.map { [MediaQualityPreset.animation, .profileLow, .profile, .profileHigh, .profileVeryHigh, .sticker].contains($0) } ?? false) else {
        return nil
    }

    // MediaCrop stores the viewport in the rotated-content canvas, before
    // cropOrientation is applied. Its valid coordinates can exceed the original
    // asset bounds; clipping there would move the centre relative to the preview.
    let crop = values.cropRect ?? CGRect(origin: .zero, size: values.originalDimensions.cgSize)
    guard values.cropRotation.isFinite,
        values.cropPerspective.vertical.isFinite, values.cropPerspective.horizontal.isFinite,
        crop.origin.x.isFinite, crop.origin.y.isFinite,
        crop.size.width.isFinite, crop.size.height.isFinite, crop.size.width > 0.0, crop.size.height > 0.0,
        crop.maxX.isFinite, crop.maxY.isFinite, crop.midX.isFinite, crop.midY.isFinite else {
        return nil
    }
    // Keep the centre of the user's crop, not the centre of the original asset.
    let side = min(crop.width, crop.height)
    let square = CGRect(x: crop.midX - side / 2.0, y: crop.midY - side / 2.0, width: side, height: side)
    let start = max(0.0, values.videoTrimRange?.lowerBound ?? 0.0)
    let end = min(duration, values.videoTrimRange?.upperBound ?? duration, start + 60.0)
    guard start.isFinite, end.isFinite, end > start else {
        return nil
    }
    let result = values.withUpdatedCrop(rect: square, rotation: values.cropRotation, orientation: values.cropOrientation, mirroring: values.cropMirroring, perspective: values.cropPerspective)
        .withUpdatedVideoTrimRange(start ..< end)
        .withUpdatedVideoIsMuted(false)

    // Estimate the actual modern export, including the fork's higher audio bitrate.
    // A little headroom for the MP4 container keeps the estimate below the old 8 MiB cap.
    for preset: MediaQualityPreset in [.videoMessageHD, .videoMessage, .compressedLow] {
        let candidate = result.withUpdatedQualityPreset(preset)
        let configuration = recommendedVideoExportConfiguration(values: candidate, duration: end - start, frameRate: 30.0)
        let compression = configuration.videoSettings[AVVideoCompressionPropertiesKey] as? [String: Any]
        let videoRate = (compression?[AVVideoAverageBitRateKey] as? NSNumber)?.doubleValue ?? 2_000_000.0
        let audioRate = (configuration.audioSettings[AVEncoderBitRateKey] as? NSNumber)?.doubleValue ?? 320_000.0
        let estimatedSize = (videoRate + audioRate) * (end - start) / 8.0
        if estimatedSize < Double(8 * 1024 * 1024) * 0.95 {
            return candidate
        }
    }
    return nil
}

func sgChatMediaSendTelescopeThumbnail(_ image: UIImage?) -> UIImage? {
    guard let image, image.size.width > 0.0, image.size.height > 0.0 else {
        return nil
    }
    let side = min(image.size.width, image.size.height)
    let size = CGSize(width: min(320.0, side), height: min(320.0, side))
    let scale = size.width / side
    return UIGraphicsImageRenderer(size: size).image { _ in
        image.draw(in: CGRect(x: (side - image.size.width) * scale / 2.0, y: (side - image.size.height) * scale / 2.0, width: image.size.width * scale, height: image.size.height * scale))
    }
}
