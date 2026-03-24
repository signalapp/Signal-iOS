//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import AVFoundation
import Foundation
public import UIKit

public enum OWSMediaError: Error {
    case failure(description: String)
}

public enum OWSMediaUtils {

    public static func thumbnail(forImage image: UIImage, maxDimensionPixels: CGFloat) throws -> UIImage {
        if
            image.pixelSize.width <= maxDimensionPixels,
            image.pixelSize.height <= maxDimensionPixels
        {
            let result = image.withNativeScale
            return result
        }
        guard let thumbnailImage = image.resized(maxDimensionPixels: maxDimensionPixels) else {
            throw OWSMediaError.failure(description: "Could not thumbnail image.")
        }
        guard nil != thumbnailImage.cgImage else {
            throw OWSMediaError.failure(description: "Missing cgImage.")
        }
        let result = thumbnailImage.withNativeScale
        return result
    }

    public static let videoStillFrameMimeType = MimeType.imageJpeg

    public static func generateThumbnail(forVideo asset: AVAsset, maxSizePixels: CGSize) throws -> UIImage {
        try validateVideoAsset(asset)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.maximumSize = maxSizePixels
        generator.appliesPreferredTrackTransform = true
        let time: CMTime = CMTimeMake(value: 1, timescale: 60)
        let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
        return UIImage(cgImage: cgImage, scale: UIScreen.main.scale, orientation: .up)
    }

    public static func validateVideoExtension(ofPath path: String) throws {
        guard let contentType = MimeTypeUtil.mimeTypeForFileExtension((path as NSString).pathExtension) else {
            throw OWSGenericError("video file has unknown content type")
        }
        guard MimeTypeUtil.isSupportedVideoMimeType(contentType) else {
            throw OWSGenericError("video file has invalid content type")
        }
    }

    public static func validateVideoAsset(atPath path: String) throws {
        let asset = AVURLAsset(url: URL(fileURLWithPath: path), options: nil)
        try validateVideoAsset(asset)
    }

    public static func validateVideoAsset(_ asset: AVAsset) throws {
        var maxTrackSize = CGSize.zero
        for track: AVAssetTrack in asset.tracks(withMediaType: .video) {
            let trackSize: CGSize = track.naturalSize
            maxTrackSize.width = max(maxTrackSize.width, trackSize.width)
            maxTrackSize.height = max(maxTrackSize.height, trackSize.height)
        }
        if maxTrackSize.width < 1.0 || maxTrackSize.height < 1.0 {
            throw OWSGenericError("invalid video size: \(maxTrackSize)")
        }
        if maxTrackSize.width > kMaxVideoDimensions || maxTrackSize.height > kMaxVideoDimensions {
            throw OWSGenericError("invalid video dimensions: \(maxTrackSize)")
        }
    }

    // MARK: Constants

    /**
     * Media Size constraints from Signal-Android
     *
     * https://github.com/signalapp/Signal-Android/blob/c4bc2162f23e0fd6bc25941af8fb7454d91a4a35/app/src/main/java/org/thoughtcrime/securesms/mms/PushMediaConstraints.java
     */
    public static let kMaxFileSizeAnimatedImage: UInt64 = 25 * 1024 * 1024
    public static let kMaxFileSizeImage: UInt64 = 8 * 1024 * 1024

    public static let kMaxVideoDimensions: CGFloat = 4096 // 4k video width
    public static let kMaxImageDimensions: CGFloat = 12 * 1024

    /// Text past this size on send (excluding forwarding) is truncated to this length and the rest
    /// is sent as an oversize text attachment.
    /// Text past this side on receive is considered an invalid message and will be dropped.
    public static let kOversizeTextMessageSizeThresholdBytes = 2 * 1024
    /// Oversize text attachments past this size will be truncated on send.
    public static let kMaxOversizeTextMessageSendSizeBytes = 64 * 1024
    /// Oversize text attachments past this size will be rejected on receive. (Larger than send
    /// to support legacy cases)
    public static let kMaxOversizeTextMessageReceiveSizeBytes = 128 * 1024
}
