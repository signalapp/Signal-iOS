//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import AVFoundation

public enum OWSMediaError: Error {
    case failure(description: String)
}

@objc
public class OWSMediaUtils: NSObject {

    @available(*, unavailable, message: "do not instantiate this class.")
    private override init() {
    }

    private class func thumbnail(forImage image: UIImage, maxDimensionPixels: CGFloat) throws -> UIImage {
        if image.pixelSize.width <= maxDimensionPixels,
           image.pixelSize.height <= maxDimensionPixels {
            let result = image.withNativeScale
            return result
        }
        guard let thumbnailImage = image.resized(withMaxDimensionPixels: maxDimensionPixels) else {
            throw OWSMediaError.failure(description: "Could not thumbnail image.")
        }
        guard nil != thumbnailImage.cgImage else {
            throw OWSMediaError.failure(description: "Missing cgImage.")
        }
        let result = thumbnailImage.withNativeScale
        return result
    }

    private class func thumbnail(forImage image: UIImage, maxDimensionPoints: CGFloat) throws -> UIImage {
        let scale = UIScreen.main.scale
        let maxDimensionPixels = maxDimensionPoints * scale
        return try thumbnail(forImage: image, maxDimensionPixels: maxDimensionPixels)
    }

    @objc
    public class func thumbnail(forImageAtPath path: String, maxDimensionPixels: CGFloat) throws -> UIImage {
        Logger.verbose("thumbnailing image: \(path)")

        guard FileManager.default.fileExists(atPath: path) else {
            throw OWSMediaError.failure(description: "Media file missing.")
        }
        guard NSData.ows_isValidImage(atPath: path) else {
            throw OWSMediaError.failure(description: "Invalid image.")
        }
        guard let originalImage = UIImage(contentsOfFile: path) else {
            throw OWSMediaError.failure(description: "Could not load original image.")
        }
        return try thumbnail(forImage: originalImage, maxDimensionPixels: maxDimensionPixels)
    }

    @objc
    public class func thumbnail(forImageAtPath path: String, maxDimensionPoints: CGFloat) throws -> UIImage {

        guard FileManager.default.fileExists(atPath: path) else {
            throw OWSMediaError.failure(description: "Media file missing.")
        }
        guard NSData.ows_isValidImage(atPath: path) else {
            throw OWSMediaError.failure(description: "Invalid image.")
        }
        guard let originalImage = UIImage(contentsOfFile: path) else {
            throw OWSMediaError.failure(description: "Could not load original image.")
        }
        return try thumbnail(forImage: originalImage, maxDimensionPoints: maxDimensionPoints)
    }

    @objc
    public class func thumbnail(forImageData imageData: Data, maxDimensionPoints: CGFloat) throws -> UIImage {
        Logger.verbose("thumbnailing image data.")

        guard imageData.ows_isValidImage else {
            throw OWSMediaError.failure(description: "Invalid image.")
        }
        guard let originalImage = UIImage(data: imageData) else {
            throw OWSMediaError.failure(description: "Could not load original image.")
        }
        return try thumbnail(forImage: originalImage, maxDimensionPoints: maxDimensionPoints)
    }

    @objc
    public class func thumbnail(forWebpAtPath path: String, maxDimensionPoints: CGFloat) throws -> UIImage {
        Logger.verbose("thumbnailing image: \(path)")

        guard FileManager.default.fileExists(atPath: path) else {
            throw OWSMediaError.failure(description: "Media file missing.")
        }
        guard NSData.ows_isValidImage(atPath: path) else {
            throw OWSMediaError.failure(description: "Invalid image.")
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path)) as NSData
        guard let stillImage = data.stillForWebpData() else {
            throw OWSMediaError.failure(description: "Could not generate still.")
        }
        return try thumbnail(forImage: stillImage, maxDimensionPoints: maxDimensionPoints)
    }

    @objc
    public class func thumbnail(forVideoAtPath path: String, maxDimensionPoints: CGFloat) throws -> UIImage {
        Logger.verbose("thumbnailing video: \(path)")

        guard isVideoOfValidContentTypeAndSize(path: path) else {
            throw OWSMediaError.failure(description: "Media file has missing or invalid length.")
        }

        let scale = UIScreen.main.scale
        let maxDimensionPixels = maxDimensionPoints * scale
        let maxSizePixels = CGSize(width: maxDimensionPixels, height: maxDimensionPixels)
        let url = URL(fileURLWithPath: path)
        let asset = AVURLAsset(url: url, options: nil)
        guard isValidVideo(asset: asset) else {
            throw OWSMediaError.failure(description: "Invalid video.")
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.maximumSize = maxSizePixels
        generator.appliesPreferredTrackTransform = true
        let time: CMTime = CMTimeMake(value: 1, timescale: 60)
        let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
        let image = UIImage(cgImage: cgImage, scale: scale, orientation: .up)
        return image
    }

    @objc
    public class func isValidVideo(path: String) -> Bool {
        guard isVideoOfValidContentTypeAndSize(path: path) else {
            Logger.error("Media file has missing or invalid length.")
            return false
        }

        let url = URL(fileURLWithPath: path)
        let asset = AVURLAsset(url: url, options: nil)
        return isValidVideo(asset: asset)
    }

    public class func isVideoOfValidContentTypeAndSize(path: String) -> Bool {
        return isVideoOfValidContentType(path: path)
            && isVideoOfValidSize(path: path)
    }

    public class func isVideoOfValidContentType(path: String) -> Bool {
        guard FileManager.default.fileExists(atPath: path) else {
            Logger.error("Media file missing.")
            return false
        }
        let fileExtension = URL(fileURLWithPath: path).pathExtension
        guard let contentType = MIMETypeUtil.mimeType(forFileExtension: fileExtension) else {
            Logger.error("Media file has unknown content type.")
            return false
        }
        guard MIMETypeUtil.isSupportedVideoMIMEType(contentType) else {
            Logger.error("Media file has invalid content type.")
            return false
        }
        return true
    }

    public class func isVideoOfValidSize(path: String) -> Bool {
        guard let fileSize = OWSFileSystem.fileSize(ofPath: path) else {
            Logger.error("Media file has unknown length.")
            return false
        }
        return fileSize.uintValue <= kMaxFileSizeVideo
    }

    public class func isValidVideo(asset: AVAsset) -> Bool {
        var maxTrackSize = CGSize.zero
        for track: AVAssetTrack in asset.tracks(withMediaType: .video) {
            let trackSize: CGSize = track.naturalSize
            maxTrackSize.width = max(maxTrackSize.width, trackSize.width)
            maxTrackSize.height = max(maxTrackSize.height, trackSize.height)
        }
        if maxTrackSize.width < 1.0 || maxTrackSize.height < 1.0 {
            Logger.error("Invalid video size: \(maxTrackSize)")
            return false
        }
        if maxTrackSize.width > kMaxVideoDimensions || maxTrackSize.height > kMaxVideoDimensions {
            Logger.error("Invalid video dimensions: \(maxTrackSize)")
            return false
        }
        return true
    }

    public class func videoResolution(url: URL) -> CGSize {
        var maxTrackSize = CGSize.zero
        let asset = AVURLAsset(url: url)
        for track: AVAssetTrack in asset.tracks(withMediaType: .video) {
            let trackSize: CGSize = track.naturalSize
            maxTrackSize.width = max(maxTrackSize.width, trackSize.width)
            maxTrackSize.height = max(maxTrackSize.height, trackSize.height)
        }
        return maxTrackSize
    }

    // MARK: Constants

    /**
     * Media Size constraints from Signal-Android
     *
     * https://github.com/signalapp/Signal-Android/blob/c4bc2162f23e0fd6bc25941af8fb7454d91a4a35/app/src/main/java/org/thoughtcrime/securesms/mms/PushMediaConstraints.java
     */
    @objc
    public static let kMaxFileSizeAnimatedImage = UInt(25 * 1024 * 1024)
    @objc
    public static let kMaxFileSizeImage = UInt(8 * 1024 * 1024)
    // Cloudflare limits uploads to 100 MB. To avoid hitting those limits,
    // we use limits that are 5% lower for the unencrypted content.
    @objc
    public static let kMaxFileSizeVideo = UInt(95 * 1000 * 1000)
    @objc
    public static let kMaxFileSizeAudio = UInt(95 * 1000 * 1000)
    @objc
    public static let kMaxFileSizeGeneric = UInt(95 * 1000 * 1000)
    @objc
    public static let kMaxAttachmentUploadSizeBytes = UInt(100 * 1000 * 1000)

    @objc
    public static let kMaxVideoDimensions: CGFloat = 4096 // 4k video width
    @objc
    public static let kMaxAnimatedImageDimensions: UInt = 1 * 1024
    @objc
    public static let kMaxStillImageDimensions: UInt = 12 * 1024
}
