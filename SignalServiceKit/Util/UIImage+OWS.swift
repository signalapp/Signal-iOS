//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import CoreImage

extension UIImage {
    public static func image(color: UIColor, size: CGSize = CGSize(width: 1, height: 1)) -> UIImage {
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

    public func normalized() -> UIImage {
        guard imageOrientation != .up else {
            return self
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            self.draw(in: CGRect(origin: CGPoint.zero, size: size))
        }
    }

    public func withCornerRadius(_ cornerRadius: CGFloat) -> UIImage? {
        let rect = CGRect(origin: CGPoint(x: 0, y: 0), size: size)
        UIGraphicsBeginImageContextWithOptions(size, false, 1)
        UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius).addClip()
        draw(in: rect)
        return UIGraphicsGetImageFromCurrentImageContext()
    }

    public func withTitle(
        _ title: String,
        font: UIFont,
        color: UIColor,
        maxTitleWidth: CGFloat,
        minimumScaleFactor: CGFloat,
        spacing: CGFloat
    ) -> UIImage? {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = font
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = minimumScaleFactor
        titleLabel.textAlignment = .center
        titleLabel.textColor = color
        titleLabel.numberOfLines = title.components(separatedBy: " ").count > 1 ? 2 : 1
        titleLabel.lineBreakMode = .byTruncatingTail

        let titleSize = titleLabel.textRect(forBounds: CGRect(
            origin: .zero,
            size: CGSize(width: maxTitleWidth, height: .greatestFiniteMagnitude
        )), limitedToNumberOfLines: titleLabel.numberOfLines).size
        let additionalWidth = size.width >= titleSize.width ? 0 : titleSize.width - size.width

        var newSize = size
        newSize.height += spacing + titleSize.height
        newSize.width = max(titleSize.width, size.width)

        UIGraphicsBeginImageContextWithOptions(newSize, false, max(scale, UIScreen.main.scale))

        // Draw the image into the new image
        draw(in: CGRect(origin: CGPoint(x: additionalWidth / 2, y: 0), size: size))

        // Draw the title label into the new image
        titleLabel.drawText(in: CGRect(origin: CGPoint(
            x: size.width > titleSize.width ? (size.width - titleSize.width) / 2 : 0,
            y: size.height + spacing
        ), size: titleSize))

        let newImage = UIGraphicsGetImageFromCurrentImageContext()

        UIGraphicsEndImageContext()

        return newImage
    }

    public func withGaussianBlurPromise(radius: CGFloat, resizeToMaxPixelDimension: CGFloat) -> Promise<UIImage> {
        return firstly {
            cgImageWithGaussianBlurPromise(radius: radius, resizeToMaxPixelDimension: resizeToMaxPixelDimension)
        }.map(on: DispatchQueue.sharedUserInteractive) {
            UIImage(cgImage: $0)
        }
    }

    public func cgImageWithGaussianBlurPromise(radius: CGFloat,
                                               resizeToMaxPixelDimension: CGFloat) -> Promise<CGImage> {
        return firstly(on: DispatchQueue.sharedUserInteractive) {
            try self.cgImageWithGaussianBlur(radius: radius,
                                             resizeToMaxPixelDimension: resizeToMaxPixelDimension)
        }
    }

    public func withGaussianBlur(radius: CGFloat, resizeToMaxPixelDimension: CGFloat) throws -> UIImage {
        UIImage(cgImage: try cgImageWithGaussianBlur(radius: radius,
                                                     resizeToMaxPixelDimension: resizeToMaxPixelDimension))
    }

    public func cgImageWithGaussianBlur(radius: CGFloat,
                                        resizeToMaxPixelDimension: CGFloat) throws -> CGImage {
        guard let resizedImage = self.resized(maxDimensionPixels: resizeToMaxPixelDimension) else {
            throw OWSAssertionError("Failed to downsize image for blur")
        }
        return try resizedImage.cgImageWithGaussianBlur(radius: radius)
    }

    public func withGaussianBlur(radius: CGFloat, tintColor: UIColor? = nil) throws -> UIImage {
        UIImage(cgImage: try cgImageWithGaussianBlur(radius: radius, tintColor: tintColor))
    }

    public func cgImageWithGaussianBlur(radius: CGFloat, tintColor: UIColor? = nil) throws -> CGImage {
        guard let clampFilter = CIFilter(name: "CIAffineClamp") else {
            throw OWSAssertionError("Failed to create blur filter")
        }

        guard let blurFilter = CIFilter(name: "CIGaussianBlur",
                                        parameters: [kCIInputRadiusKey: radius]) else {
            throw OWSAssertionError("Failed to create blur filter")
        }
        guard let cgImage = self.cgImage else {
            throw OWSAssertionError("Missing cgImage.")
        }

        // In order to get a nice edge-to-edge blur, we must apply a clamp filter and *then* the blur filter.
        let inputImage = CIImage(cgImage: cgImage)
        clampFilter.setDefaults()
        clampFilter.setValue(inputImage, forKey: kCIInputImageKey)

        guard let clampOutput = clampFilter.outputImage else {
            throw OWSAssertionError("Failed to clamp image")
        }

        blurFilter.setValue(clampOutput, forKey: kCIInputImageKey)

        guard let blurredOutput = blurFilter.value(forKey: kCIOutputImageKey) as? CIImage else {
            throw OWSAssertionError("Failed to blur clamped image")
        }

        var outputImage: CIImage = blurredOutput
        if let tintColor = tintColor {
            guard let tintFilter = CIFilter(name: "CIConstantColorGenerator",
                                            parameters: [
                                                kCIInputColorKey: CIColor(color: tintColor)
                                            ]) else {
                throw OWSAssertionError("Could not create tintFilter.")
            }
            guard let tintImage = tintFilter.outputImage else {
                throw OWSAssertionError("Could not create tintImage.")
            }

            guard let tintOverlayFilter = CIFilter(name: "CISourceOverCompositing",
                                                   parameters: [
                                                    kCIInputBackgroundImageKey: outputImage,
                                                    kCIInputImageKey: tintImage
                                                   ]) else {
                throw OWSAssertionError("Could not create tintOverlayFilter.")
            }
            guard let tintOverlayImage = tintOverlayFilter.outputImage else {
                throw OWSAssertionError("Could not create tintOverlayImage.")
            }
            outputImage = tintOverlayImage
        }

        let context = CIContext(options: nil)
        guard let blurredImage = context.createCGImage(outputImage, from: inputImage.extent) else {
            throw OWSAssertionError("Failed to create CGImage from blurred output")
        }

        return blurredImage
    }

    public func preloadForRendering() -> UIImage {
        guard let inputCGImage = self.cgImage else {
            owsFailDebug("Unexpected ciImage.")
            return self
        }
        let hasAlpha: Bool = {
            switch inputCGImage.alphaInfo {
            case .none,
                 .noneSkipLast,
                 .noneSkipFirst:
                return false
            case .premultipliedLast,
                 .premultipliedFirst,
             .last,
             .first,
             .alphaOnly:
                return true
            @unknown default:
                owsFailDebug("Unknown CGImageAlphaInfo value.")
                return true
            }
        }()
        let width = inputCGImage.width
        let height = inputCGImage.height
        let colourSpace = CGColorSpaceCreateDeviceRGB()
        let alphaInfo: CGImageAlphaInfo = hasAlpha ? .premultipliedFirst : .noneSkipFirst
        let bitmapInfo: UInt32 = alphaInfo.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let imageContext = CGContext(data: nil,
                                           width: width,
                                           height: height,
                                           bitsPerComponent: 8,
                                           bytesPerRow: width * 4,
                                           space: colourSpace,
                                           bitmapInfo: bitmapInfo) else {
            owsFailDebug("Could not create context.")
            return self
        }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        imageContext.draw(inputCGImage, in: rect)
        guard let outputCGImage = imageContext.makeImage() else {
            owsFailDebug("Could not make image.")
            return self
        }
        return UIImage(cgImage: outputCGImage)
    }

    var withNativeScale: UIImage {
        let scale = UIScreen.main.scale
        if self.scale == scale {
            return self
        } else {
            guard let cgImage = cgImage else {
                owsFailDebug("Missing cgImage.")
                return self
            }
            return UIImage(cgImage: cgImage, scale: scale, orientation: self.imageOrientation)
        }
    }

    @objc
    public var pixelWidth: Int {
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
    public var pixelHeight: Int {
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
    public var pixelSize: CGSize {
        CGSize(width: pixelWidth, height: pixelHeight)
    }

    public static func validJpegData(fromAvatarData avatarData: Data) -> Data? {
        let imageMetadata = avatarData.imageMetadata(withPath: nil, mimeType: nil)
        guard imageMetadata.isValid else {
            return nil
        }

        // TODO: We might want to raise this value if we ever want to render large contact avatars
        // on linked devices (e.g. in a call view).  If so, we should also modify `avatarDataForCNContact`
        // to _not_ use `thumbnailImageData`.  This would make contact syncs much more expensive, however.
        let maxAvatarDimensionPixels = 600
        if imageMetadata.imageFormat == .jpeg
            && imageMetadata.pixelSize.width <= CGFloat(maxAvatarDimensionPixels)
            && imageMetadata.pixelSize.height <= CGFloat(maxAvatarDimensionPixels) {

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

    // Source: https://github.com/AliSoftware/UIImage-Resize
    public func resizedImage(to dstSize: CGSize) -> UIImage? {
        var dstSize = dstSize
        guard let imgRef = cgImage else {
            return nil
        }
        // the below values are regardless of orientation : for UIImages from Camera, width>height (landscape)
        let srcSize = CGSize(width: imgRef.width, height: imgRef.height)
        // not equivalent to self.size (which is dependent on the imageOrientation)!

        // Don't resize if we already meet the required destination size.
        if srcSize == dstSize {
            return self
        }

        let scaleRatio = dstSize.width / srcSize.width
        let orient = imageOrientation
        var transform: CGAffineTransform = .identity
        switch orient {
        case .up:
            transform = .identity
        case .upMirrored:
            transform = .init(translationX: srcSize.width, y: 0)
            transform = transform.scaledBy(x: -1, y: 1)
        case .down:
            transform = .init(translationX: srcSize.width, y: srcSize.height)
            transform = transform.rotated(by: CGFloat.pi)
        case .downMirrored:
            transform = .init(translationX: 0, y: srcSize.height)
            transform = transform.scaledBy(x: 1, y: -1)
        case .leftMirrored:
            dstSize = CGSize(width: dstSize.height, height: dstSize.width)
            transform = .init(translationX: srcSize.height, y: srcSize.width)
            transform = transform.scaledBy(x: -1, y: 1)
            transform = transform.rotated(by: 3 * CGFloat.halfPi)
        case .left:
            dstSize = CGSize(width: dstSize.height, height: dstSize.width)
            transform = .init(translationX: 0, y: srcSize.width)
            transform = transform.rotated(by: 3 * CGFloat.halfPi)
        case .rightMirrored:
            dstSize = CGSize(width: dstSize.height, height: dstSize.width)
            transform = .init(scaleX: -1, y: 1)
            transform = transform.rotated(by: .halfPi)
        case .right:
            dstSize = CGSize(width: dstSize.height, height: dstSize.width)
            transform = .init(translationX: srcSize.height, y: 0)
            transform = transform.rotated(by: .halfPi)
        @unknown default:
            owsFailDebug("Invalid image orientation")
            return nil
        }

        // The actual resize: draw the image on a new context, applying a transform matrix
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: dstSize, format: format)
        return renderer.image { context in
            context.cgContext.interpolationQuality = .high

            if orient == .right || orient == .left {
                context.cgContext.scaleBy(x: -scaleRatio, y: scaleRatio)
                context.cgContext.translateBy(x: -srcSize.height, y: 0)
            } else {
                context.cgContext.scaleBy(x: scaleRatio, y: -scaleRatio)
                context.cgContext.translateBy(x: 0, y: -srcSize.height)
            }

            context.cgContext.concatenate(transform)

            // we use srcSize (and not dstSize) as the size to specify is in user space (and we use the CTM to apply a scaleRatio)
            context.cgContext.draw(imgRef, in: CGRect(origin: .zero, size: srcSize))
        }
    }

    @objc
    public func resizedImage(toFillPixelSize dstSize: CGSize) -> UIImage {
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

    public func resized(maxDimensionPoints: CGFloat) -> UIImage? {
        resized(originalSize: size, maxDimension: maxDimensionPoints, isPixels: false)
    }

    public func resized(maxDimensionPixels: CGFloat) -> UIImage? {
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
            draw(in: renderRect)
        }
    }
}
