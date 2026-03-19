//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import ImageIO

import SDWebImage

public protocol OWSImageSource {

    var byteLength: Int { get }

    func readData(byteOffset: Int, byteLength: Int) throws -> Data

    func cgImageSource() throws -> CGImageSource?
}

public struct DataImageSource: OWSImageSource {
    public let rawValue: Data

    public init(_ rawValue: Data) {
        self.rawValue = rawValue
    }

    public static func forPath(_ filePath: String) throws -> Self {
        do {
            // Use memory-mapped Data instead of a URL-based CGImageSource because we
            // may only need to read from a small portion of the file header.
            return Self(try Data(contentsOf: URL(fileURLWithPath: filePath), options: .mappedIfSafe))
        } catch {
            Logger.warn("Could not read image data: \(error)")
            throw error
        }
    }

    public var byteLength: Int { self.rawValue.count }

    public func readData(byteOffset: Int, byteLength: Int) throws -> Data {
        return self.rawValue.dropFirst(byteOffset).prefix(byteLength)
    }

    public func cgImageSource() throws -> CGImageSource? {
        return CGImageSourceCreateWithData(self.rawValue as CFData, nil)
    }
}

extension OWSImageSource {
    public var ows_isValidImage: Bool {
        return imageMetadata() != nil
    }

    private func ows_guessHighEfficiencyImageFormat() -> ImageFormat? {
        // A HEIF image file has the first 16 bytes like
        // 0000 0018 6674 7970 6865 6963 0000 0000
        // so in this case the 5th to 12th bytes shall make a string of "ftypheic"
        let heifHeaderStartsAt = 4
        let heifBrandStartsAt = 8
        // We support "heic", "mif1" or "msf1". Other brands are invalid for us for now.
        // The length is 4 + 1 because the brand must be terminated with a null.
        // Include the null in the comparison to prevent a bogus brand like "heicfake"
        // from being considered valid.
        let heifSupportedBrandLength = 5
        let totalHeaderLength = heifBrandStartsAt - heifHeaderStartsAt + heifSupportedBrandLength
        guard byteLength >= heifBrandStartsAt + heifSupportedBrandLength else {
            return nil
        }

        // These are the brands of HEIF formatted files that are renderable by CoreGraphics
        let heifBrandHeaderHeic = Data("ftypheic\0".utf8)
        let heifBrandHeaderHeif = Data("ftypmif1\0".utf8)
        let heifBrandHeaderHeifStream = Data("ftypmsf1\0".utf8)

        // Pull the string from the header and compare it with the supported formats
        let header = try? readData(byteOffset: heifHeaderStartsAt, byteLength: totalHeaderLength)

        if header == heifBrandHeaderHeic {
            return .heic
        } else if header == heifBrandHeaderHeif || header == heifBrandHeaderHeifStream {
            return .heif
        } else {
            return nil
        }
    }

    private func ows_guessImageFormat() -> ImageFormat? {
        guard byteLength >= 2 else {
            return nil
        }

        switch try? readData(byteOffset: 0, byteLength: 2) {
        case Data([0x47, 0x49]):
            return .gif
        case Data([0x89, 0x50]):
            return .png
        case Data([0xff, 0xd8]):
            return .jpeg
        case Data([0x42, 0x4d]):
            return .bmp
        case Data([0x4d, 0x4d]), // Motorola byte order TIFF
             Data([0x49, 0x49]): // Intel byte order TIFF
            return .tiff
        case Data([0x52, 0x49]):
            // First two letters of RIFF tag.
            return .webp
        default:
            return ows_guessHighEfficiencyImageFormat()
        }
    }

    // MARK: - Image Metadata

    /// load image metadata about the current object
    public func imageMetadata() -> ImageMetadata? {
        // The largest image we should be able to handle in most places. This must
        // be larger than the largest animated image (so that we can check if it's
        // animated); it must also be larger than the largest image we support in
        // the image editor. We can handle images larger than this by resizing them
        // to fit within the dimensions for the highest quality.
        let byteLimit = 72_000_000
        assert(byteLimit >= OWSMediaUtils.kMaxFileSizeAnimatedImage)
        assert(byteLimit >= 4 * Int(ImageQualityTier.seven.maxEdgeSize) ^ 2 + 50_000)
        guard byteLength < byteLimit else {
            return nil
        }
        let imageFormat = ows_guessImageFormat()
        guard let imageFormat else {
            Logger.warn("Image does not have valid format.")
            return nil
        }
        guard let imageSource = try? self.cgImageSource() else {
            Logger.warn("Could not build imageSource.")
            return nil
        }
        return imageMetadataWithImageSource(
            imageSource,
            imageFormat: imageFormat,
        )
    }
}

private func applyImageOrientation(_ orientation: CGImagePropertyOrientation, to imageSize: CGSize) -> CGSize {
    // NOTE: UIImageOrientation and CGImagePropertyOrientation values
    //       DO NOT match.
    switch orientation {
    case .up, .upMirrored, .down, .downMirrored:
        return imageSize
    case .left, .leftMirrored, .right, .rightMirrored:
        return CGSize(width: imageSize.height, height: imageSize.width)
    }
}

private func isImageSizeValid(_ imageSize: CGSize, depthBytes: CGFloat) -> Bool {
    if imageSize.width < 1 || imageSize.height < 1 || depthBytes < 1 {
        // Invalid metadata.
        return false
    }

    // We only support (A)RGB and (A)Grayscale, so worst case is 4.
    let worstCaseComponentsPerPixel = CGFloat(4)
    let bytesPerPixel = worstCaseComponentsPerPixel * depthBytes
    let actualBytes = imageSize.width * imageSize.height * bytesPerPixel

    let expectedBytesPerPixel: CGFloat = 4
    let maxValidImageDimension = OWSMediaUtils.kMaxImageDimensions
    let maxBytes = maxValidImageDimension * maxValidImageDimension * expectedBytesPerPixel

    if actualBytes > maxBytes {
        Logger.warn("invalid dimensions width: \(imageSize.width), height \(imageSize.height), bytesPerPixel: \(bytesPerPixel)")
        return false
    }

    return true
}

private func imageMetadataWithImageSource(_ imageSource: CGImageSource, imageFormat: ImageFormat) -> ImageMetadata? {
    let options = [kCGImageSourceShouldCache as String: false]
    guard let imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, options as CFDictionary) as? [String: AnyObject] else {
        Logger.warn("Missing imageProperties.")
        return nil
    }

    guard let widthNumber = imageProperties[kCGImagePropertyPixelWidth as String] as? NSNumber else {
        Logger.warn("widthNumber was unexpectedly nil")
        return nil
    }
    guard let heightNumber = imageProperties[kCGImagePropertyPixelHeight as String] as? NSNumber else {
        Logger.warn("heightNumber was unexpectedly nil")
        return nil
    }

    var pixelSize = CGSize(width: widthNumber.doubleValue, height: heightNumber.doubleValue)
    if let orientationNumber = imageProperties[kCGImagePropertyOrientation as String] as? NSNumber {
        guard let orientation = CGImagePropertyOrientation(rawValue: orientationNumber.uint32Value) else {
            Logger.warn("orientation number was invalid")
            return nil
        }
        pixelSize = applyImageOrientation(orientation, to: pixelSize)
    }

    let hasAlpha = imageProperties[kCGImagePropertyHasAlpha as String] as? NSNumber ?? false

    // The number of bits in each color sample of each pixel. The value of this key is a CFNumberRef.
    guard let depthNumber = imageProperties[kCGImagePropertyDepth as String] as? NSNumber else {
        Logger.warn("depthNumber was unexpectedly nil")
        return nil
    }
    let depthBits = depthNumber.uintValue
    // This should usually be 1.
    let depthBytes = ceil(Double(depthBits) / 8.0)

    // The color model of the image such as "RGB", "CMYK", "Gray", or "Lab". The value of this key is CFStringRef.
    guard let colorModel = (imageProperties[kCGImagePropertyColorModel as String] as? NSString) as String? else {
        Logger.warn("colorModel was unexpectedly nil")
        return nil
    }
    guard colorModel == kCGImagePropertyColorModelRGB as String || colorModel == kCGImagePropertyColorModelGray as String else {
        Logger.warn("Invalid colorModel: \(colorModel)")
        return nil
    }

    guard isImageSizeValid(pixelSize, depthBytes: depthBytes) else {
        Logger.warn("Image does not have valid dimensions: \(pixelSize).")
        return nil
    }

    let frameCount = CGImageSourceGetCount(imageSource)
    let isAnimated = frameCount > 1

    return .init(imageFormat: imageFormat, pixelSize: pixelSize, hasAlpha: hasAlpha.boolValue, isAnimated: isAnimated)
}

private struct WebpMetadata {
    let canvasWidth: Int
    let canvasHeight: Int
    let frameCount: UInt

    init?(canvasWidth: Int, canvasHeight: Int, frameCount: UInt) {
        guard canvasWidth > 0, canvasHeight > 0, frameCount > 0 else {
            return nil
        }
        self.canvasWidth = canvasWidth
        self.canvasHeight = canvasHeight
        self.frameCount = frameCount
    }
}
