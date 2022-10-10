// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import AVFoundation

public enum OWSMediaError: Error {
    case failure(description: String)
}

@objc public class OWSMediaUtils: NSObject {

    @available(*, unavailable, message:"do not instantiate this class.")
    private override init() {
    }

    @objc public class func thumbnail(forImageAtPath path: String, maxDimension: CGFloat) throws -> UIImage {
        SNLog("thumbnailing image: \(path)")

        guard FileManager.default.fileExists(atPath: path) else {
            throw OWSMediaError.failure(description: "Media file missing.")
        }
        guard NSData.ows_isValidImage(atPath: path) else {
            throw OWSMediaError.failure(description: "Invalid image.")
        }
        guard let originalImage = UIImage(contentsOfFile: path) else {
            throw OWSMediaError.failure(description: "Could not load original image.")
        }
        guard let thumbnailImage = originalImage.resized(withMaxDimensionPoints: maxDimension) else {
            throw OWSMediaError.failure(description: "Could not thumbnail image.")
        }
        return thumbnailImage
    }

    @objc public class func thumbnail(forVideoAtPath path: String, maxDimension: CGFloat) throws -> UIImage {
        SNLog("thumbnailing video: \(path)")

        guard isVideoOfValidContentTypeAndSize(path: path) else {
            throw OWSMediaError.failure(description: "Media file has missing or invalid length.")
        }

        let maxSize = CGSize(width: maxDimension, height: maxDimension)
        let url = URL(fileURLWithPath: path)
        let asset = AVURLAsset(url: url, options: nil)
        guard isValidVideo(asset: asset) else {
            throw OWSMediaError.failure(description: "Invalid video.")
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.maximumSize = maxSize
        generator.appliesPreferredTrackTransform = true
        let time: CMTime = CMTimeMake(value: 1, timescale: 60)
        let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
        let image = UIImage(cgImage: cgImage)
        return image
    }

    @objc public class func isValidVideo(path: String) -> Bool {
        guard isVideoOfValidContentTypeAndSize(path: path) else {
            SNLog("Media file has missing or invalid length.")
            return false
        }

        let url = URL(fileURLWithPath: path)
        let asset = AVURLAsset(url: url, options: nil)
        return isValidVideo(asset: asset)
    }

    private class func isVideoOfValidContentTypeAndSize(path: String) -> Bool {
        guard FileManager.default.fileExists(atPath: path) else {
            SNLog("Media file missing.")
            return false
        }
        let fileExtension = URL(fileURLWithPath: path).pathExtension
        guard let contentType = MIMETypeUtil.mimeType(forFileExtension: fileExtension) else {
            SNLog("Media file has unknown content type.")
            return false
        }
        guard MIMETypeUtil.isSupportedVideoMIMEType(contentType) else {
            SNLog("Media file has invalid content type.")
            return false
        }

        guard let fileSize = OWSFileSystem.fileSize(ofPath: path) else {
            SNLog("Media file has unknown length.")
            return false
        }
        return fileSize.uintValue <= kMaxFileSizeVideo
    }

    private class func isValidVideo(asset: AVURLAsset) -> Bool {
        var maxTrackSize = CGSize.zero
        for track: AVAssetTrack in asset.tracks(withMediaType: .video) {
            let trackSize: CGSize = track.naturalSize
            maxTrackSize.width = max(maxTrackSize.width, trackSize.width)
            maxTrackSize.height = max(maxTrackSize.height, trackSize.height)
        }
        if maxTrackSize.width < 1.0 || maxTrackSize.height < 1.0 {
            SNLog("Invalid video size: \(maxTrackSize)")
            return false
        }
        if maxTrackSize.width > kMaxVideoDimensions || maxTrackSize.height > kMaxVideoDimensions {
            SNLog("Invalid video dimensions: \(maxTrackSize)")
            return false
        }
        return true
    }

    // MARK: Constants

    /**
     * Media Size constraints from Signal-Android
     *
     * https://github.com/signalapp/Signal-Android/blob/master/src/org/thoughtcrime/securesms/mms/PushMediaConstraints.java
     */
    @objc
    public static var kMaxFileSizeAnimatedImage: UInt { SNUtilitiesKitConfiguration.maxFileSize }
    @objc
    public static var kMaxFileSizeImage: UInt { SNUtilitiesKitConfiguration.maxFileSize }
    @objc
    public static var kMaxFileSizeVideo: UInt { SNUtilitiesKitConfiguration.maxFileSize }
    @objc
    public static var kMaxFileSizeAudio: UInt { SNUtilitiesKitConfiguration.maxFileSize }
    @objc
    public static var kMaxFileSizeGeneric: UInt { SNUtilitiesKitConfiguration.maxFileSize }

    @objc
    public static let kMaxVideoDimensions: CGFloat = 3 * 1024
    @objc
    public static let kMaxAnimatedImageDimensions: UInt = 1 * 1024
    @objc
    public static let kMaxStillImageDimensions: UInt = 8 * 1024
}
