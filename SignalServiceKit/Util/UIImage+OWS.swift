//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CoreImage
import Foundation
public import UIKit

public extension UIImage {

    static func image(color: UIColor, size: CGSize = CGSize(width: 1, height: 1)) -> UIImage {
        let rect = CGRect(origin: CGPoint.zero, size: size)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            color.setFill()
            context.fill(rect)
        }
    }

    var withNativeScale: UIImage {
        let scale = UIScreen.main.scale
        if self.scale == scale {
            return self
        } else {
            guard let cgImage else {
                owsFailDebug("Missing cgImage.")
                return self
            }
            return UIImage(cgImage: cgImage, scale: scale, orientation: self.imageOrientation)
        }
    }

    @objc
    var pixelWidth: Int {
        switch imageOrientation {
        case .up, .down, .upMirrored, .downMirrored:
            return cgImage?.width ?? 0
        case .left, .right, .leftMirrored, .rightMirrored:
            return cgImage?.height ?? 0
        @unknown default:
            owsFailDebug("unhandled image orientation: \(imageOrientation)")
            return 0
        }
    }

    @objc
    var pixelHeight: Int {
        switch imageOrientation {
        case .up, .down, .upMirrored, .downMirrored:
            return cgImage?.height ?? 0
        case .left, .right, .leftMirrored, .rightMirrored:
            return cgImage?.width ?? 0
        @unknown default:
            owsFailDebug("unhandled image orientation: \(imageOrientation)")
            return 0
        }
    }

    @objc
    var pixelSize: CGSize {
        CGSize(width: pixelWidth, height: pixelHeight)
    }

    static func validJpegData(fromAvatarData avatarData: Data) -> Data? {
        let imageMetadata = DataImageSource(avatarData).imageMetadata()
        guard let imageMetadata else {
            return nil
        }

        // TODO: We might want to raise this value if we ever want to render large contact avatars
        // on linked devices (e.g. in a call view).  If so, we should also modify `avatarDataForCNContact`
        // to _not_ use `thumbnailImageData`.  This would make contact syncs much more expensive, however.
        let maxAvatarDimensionPixels = 600
        if
            imageMetadata.imageFormat == .jpeg
            && imageMetadata.pixelSize.width <= CGFloat(maxAvatarDimensionPixels)
            && imageMetadata.pixelSize.height <= CGFloat(maxAvatarDimensionPixels)
        {

            return avatarData
        }

        guard var avatarImage = UIImage(data: avatarData) else {
            owsFailDebug("Could not load avatar.")
            return nil
        }

        if avatarImage.pixelWidth > maxAvatarDimensionPixels || avatarImage.pixelHeight > maxAvatarDimensionPixels {
            if let newAvatarImage = avatarImage.resized(maxDimensionPixels: CGFloat(maxAvatarDimensionPixels)) {
                avatarImage = newAvatarImage
            } else {
                owsFailDebug("Could not resize avatar.")
                return nil
            }
        }

        return avatarImage.jpegData(compressionQuality: 0.9)
    }

    func resizedImage(toFillPixelSize dstSize: CGSize) -> UIImage {
        owsAssertDebug(dstSize.width > 0)
        owsAssertDebug(dstSize.height > 0)

        // Get the size in pixels, not points.
        let srcSize = pixelSize
        owsAssertDebug(srcSize.width > 0)
        owsAssertDebug(srcSize.height > 0)

        let widthRatio = srcSize.width / dstSize.width
        let heightRatio = srcSize.height / dstSize.height
        var drawRect: CGRect
        if widthRatio > heightRatio {
            let width = dstSize.height * srcSize.width / srcSize.height
            drawRect = CGRect(x: (width - dstSize.width) * -0.5, y: 0, width: width, height: dstSize.height)
        } else {
            let height = dstSize.width * srcSize.height / srcSize.width
            drawRect = CGRect(x: 0, y: (height - dstSize.height) * -0.5, width: dstSize.width, height: height)
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: dstSize, format: format)
        return renderer.image { context in
            context.cgContext.interpolationQuality = .high
            draw(in: drawRect)
        }
    }

    func resized(maxDimensionPoints: CGFloat) -> UIImage? {
        resized(originalSize: size, maxDimension: maxDimensionPoints, isPixels: false)
    }

    func resized(maxDimensionPixels: CGFloat) -> UIImage? {
        resized(originalSize: pixelSize, maxDimension: maxDimensionPixels, isPixels: true)
    }

    /// Original size and maxDimension should both be in the same units, either points or pixels.
    private func resized(originalSize: CGSize, maxDimension: CGFloat, isPixels: Bool) -> UIImage? {
        if originalSize.width < 1 || originalSize.height < 1 {
            Logger.error("Invalid original size: \(originalSize)")
            return nil
        }

        let maxOriginalDimension = max(originalSize.width, originalSize.height)
        if maxOriginalDimension < maxDimension {
            // Don't bother scaling an image that is already smaller than the max dimension.
            return self
        }

        var unroundedThumbnailSize: CGSize
        if originalSize.width > originalSize.height {
            unroundedThumbnailSize = CGSize(width: maxDimension, height: maxDimension * originalSize.height / originalSize.width)
        } else {
            unroundedThumbnailSize = CGSize(width: maxDimension * originalSize.width / originalSize.height, height: maxDimension)
        }

        var renderRect = CGRect(
            origin: .zero,
            size: CGSize(
                width: round(unroundedThumbnailSize.width),
                height: round(unroundedThumbnailSize.height),
            ),
        )
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

        let thumbnailSize = CGSize(
            width: round(unroundedThumbnailSize.width),
            height: round(unroundedThumbnailSize.height),
        )

        let format = UIGraphicsImageRendererFormat()
        if isPixels {
            format.scale = 1
        }
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: thumbnailSize, format: format)
        return renderer.image { context in
            context.cgContext.interpolationQuality = .high
            draw(in: renderRect)
        }
    }
}
