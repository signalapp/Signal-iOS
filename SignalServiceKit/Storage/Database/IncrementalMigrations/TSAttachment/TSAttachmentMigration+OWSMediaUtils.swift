//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AVKit
import Foundation

extension TSAttachmentMigration {

    static let kMaxAnimatedImageDimensions: UInt = 12 * 1024
    static let kMaxStillImageDimensions: UInt = 12 * 1024
    static let kMaxFileSizeAnimatedImage = UInt(25 * 1024 * 1024)
    static let kMaxFileSizeImage = UInt(8 * 1024 * 1024)
    static let kMaxFileSizeGeneric = UInt(95 * 1000 * 1000)

    enum OWSMediaUtils {
        // This size is large enough to render full screen.
        static func thumbnailDimensionPointsLarge() -> CGFloat {
            let screenSizePoints = UIScreen.main.bounds.size
            return max(screenSizePoints.width, screenSizePoints.height)
        }

        static func isValidVideo(asset: AVAsset) -> Bool {
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
            if maxTrackSize.width > 4096 || maxTrackSize.height > 4096 {
                Logger.error("Invalid video dimensions: \(maxTrackSize)")
                return false
            }
            return true
        }

        static func thumbnail(forImage image: UIImage, maxDimensionPixels: CGFloat) throws -> UIImage {
            if image.pixelSize.width <= maxDimensionPixels,
               image.pixelSize.height <= maxDimensionPixels {
                let result = image.withNativeScale
                return result
            }
            guard let thumbnailImage = Self.resize(image: image, maxDimensionPixels: maxDimensionPixels) else {
                throw OWSAssertionError("Could not thumbnail image.")
            }
            guard nil != thumbnailImage.cgImage else {
                throw OWSAssertionError("Missing cgImage.")
            }
            let result = thumbnailImage.withNativeScale
            return result
        }

        static func thumbnail(forVideo asset: AVAsset, maxSizePixels: CGSize) throws -> UIImage {
            let generator = AVAssetImageGenerator(asset: asset)
            generator.maximumSize = maxSizePixels
            generator.appliesPreferredTrackTransform = true
            let time: CMTime = CMTimeMake(value: 1, timescale: 60)
            let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
            let image = UIImage(cgImage: cgImage, scale: UIScreen.main.scale, orientation: .up)
            return image
        }

        static func resize(image: UIImage, maxDimensionPoints: CGFloat) -> UIImage? {
            resize(image: image, originalSize: image.size, maxDimension: maxDimensionPoints, isPixels: false)
        }

        static func resize(image: UIImage, maxDimensionPixels: CGFloat) -> UIImage? {
            resize(image: image, originalSize: image.pixelSize, maxDimension: maxDimensionPixels, isPixels: true)
        }

        /// Original size and maxDimension should both be in the same units, either points or pixels.
        private static func resize(image: UIImage, originalSize: CGSize, maxDimension: CGFloat, isPixels: Bool) -> UIImage? {
            if originalSize.width < 1 || originalSize.height < 1 {
                Logger.error("Invalid original size: \(originalSize)")
                return nil
            }

            let maxOriginalDimension = max(originalSize.width, originalSize.height)
            if maxOriginalDimension < maxDimension {
                // Don't bother scaling an image that is already smaller than the max dimension.
                return image
            }

            var unroundedThumbnailSize: CGSize
            if originalSize.width > originalSize.height {
                unroundedThumbnailSize = CGSize(width: maxDimension, height: maxDimension * originalSize.height / originalSize.width)
            } else {
                unroundedThumbnailSize = CGSize(width: maxDimension * originalSize.width / originalSize.height, height: maxDimension)
            }

            var renderRect = CGRect(origin: .zero,
                                    size: CGSize.init(width: round(unroundedThumbnailSize.width),
                                                      height: round(unroundedThumbnailSize.height)))
            if unroundedThumbnailSize.width < 1 {
                // crop instead of resizing.
                let newWidth = min(maxDimension, originalSize.width)
                let newHeight = originalSize.height * (newWidth / originalSize.width)
                renderRect.origin.y = round((maxDimension - newHeight) / 2)
                renderRect.size.width = round(newWidth)
                renderRect.size.height = round(newHeight)
                unroundedThumbnailSize.height = maxDimension
                unroundedThumbnailSize.width = newWidth
            }
            if unroundedThumbnailSize.height < 1 {
                // crop instead of resizing.
                let newHeight = min(maxDimension, originalSize.height)
                let newWidth = originalSize.width * (newHeight / originalSize.height)
                renderRect.origin.x = round((maxDimension - newWidth) / 2)
                renderRect.size.width = round(newWidth)
                renderRect.size.height = round(newHeight)
                unroundedThumbnailSize.height = newHeight
                unroundedThumbnailSize.width = maxDimension
            }

            let thumbnailSize = CGSize(width: round(unroundedThumbnailSize.width),
                                       height: round(unroundedThumbnailSize.height))

            let format = UIGraphicsImageRendererFormat()
            if isPixels {
                format.scale = 1
            }
            format.opaque = false
            let renderer = UIGraphicsImageRenderer(size: thumbnailSize, format: format)
            return renderer.image { context in
                context.cgContext.interpolationQuality = .high
                image.draw(in: renderRect)
            }
        }
    }

    enum BlurHash {
        static func computeBlurHashSync(for image: UIImage) throws -> String {
            // Use a small thumbnail size; quality doesn't matter. This is important for perf.
            var thumbnail: UIImage
            let maxDimensionPixels: CGFloat = 200
            if image.pixelSize.width > maxDimensionPixels || image.pixelSize.height > maxDimensionPixels {
                thumbnail = try OWSMediaUtils.thumbnail(forImage: image, maxDimensionPixels: maxDimensionPixels)
            } else {
                thumbnail = image
            }
            guard let normalized = Self.normalize(image: thumbnail, backgroundColor: .white) else {
                throw OWSAssertionError("Could not normalize thumbnail.")
            }
            // blurHash uses a DCT transform, so these are AC and DC components.
            // We use 4x3.
            //
            // https://github.com/woltapp/blurhash/blob/master/Algorithm.md
            guard let blurHash = normalized.blurHash(numberOfComponents: (4, 3)) else {
                throw OWSAssertionError("Could not generate blurHash.")
            }
            guard self.isValidBlurHash(blurHash) else {
                throw OWSAssertionError("Generated invalid blurHash.")
            }
            return blurHash
        }

        // BlurHashEncode only works with images in a very specific
        // pixel format: RGBA8888.
        static func normalize(image: UIImage, backgroundColor: UIColor) -> UIImage? {
            guard let cgImage = image.cgImage else {
                return nil
            }

            // As long as we're normalizing the image, reduce the size.
            // The blurHash algorithm doesn't need more data.
            // This also places an upper bound on blurHash perf cost.
            let srcSize = image.pixelSize
            guard srcSize.width > 0, srcSize.height > 0 else {
                return nil
            }
            let srcMinDimension: CGFloat = min(srcSize.width, srcSize.height)
            // Make sure the short dimension is N.
            let scale: CGFloat = min(1.0, 16 / srcMinDimension)
            let dstWidth: Int = Int(round(srcSize.width * scale))
            let dstHeight: Int = Int(round(srcSize.height * scale))
            let dstSize = CGSize(width: dstWidth, height: dstHeight)
            let dstRect = CGRect(origin: .zero, size: dstSize)
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            // RGBA8888 pixel format
            let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
            guard let context = CGContext(
                data: nil,
                width: dstWidth,
                height: dstHeight,
                bitsPerComponent: 8,
                bytesPerRow: dstWidth * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else {
                return nil
            }
            context.setFillColor(backgroundColor.cgColor)
            context.fill(dstRect)
            context.draw(cgImage, in: dstRect)
            return (context.makeImage().flatMap { UIImage(cgImage: $0) })
        }

        static func isValidBlurHash(_ blurHash: String?) -> Bool {
            guard let blurHash = blurHash else {
                return false
            }
            guard blurHash.count >= 6 && blurHash.count < 100 else {
                return false
            }
            return blurHash.unicodeScalars.allSatisfy {
                CharacterSet(
                    charactersIn: "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz#$%*+,-.:;=?@[]^_{|}~"
                ).contains($0)
            }
        }
    }
}
