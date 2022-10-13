//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import CoreImage

extension UIImage {
    @objc
    public func withCornerRadius(_ cornerRadius: CGFloat) -> UIImage? {
        let rect = CGRect(origin: CGPoint(x: 0, y: 0), size: size)
        UIGraphicsBeginImageContextWithOptions(size, false, 1)
        UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius).addClip()
        draw(in: rect)
        return UIGraphicsGetImageFromCurrentImageContext()
    }

    @objc
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
        }.map(on: .sharedUserInteractive) {
            UIImage(cgImage: $0)
        }
    }

    public func cgImageWithGaussianBlurPromise(radius: CGFloat,
                                               resizeToMaxPixelDimension: CGFloat) -> Promise<CGImage> {
        return firstly(on: .sharedUserInteractive) {
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
        guard let resizedImage = self.resized(withMaxDimensionPixels: resizeToMaxPixelDimension) else {
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

    @objc
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
}
