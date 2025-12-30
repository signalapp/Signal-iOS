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

    /// Potentially expensive, should be avoided if possible.
    func readIntoMemory() throws -> Data
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

    public func readIntoMemory() throws -> Data {
        return self.rawValue
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

    /// Determine whether something is an animated PNG.
    ///
    /// Does this by checking that the `acTL` chunk appears before any `IDAT` chunk.
    /// See [the APNG spec][0] for more.
    ///
    /// [0]: https://wiki.mozilla.org/APNG_Specification
    ///
    /// - Returns:
    ///   `true` if the contents appear to be an APNG.
    ///   `false` if the contents are a still PNG.
    ///   `nil` if the contents are invalid.
    func isAnimatedPng() -> Bool? {
        let actl = "acTL".data(using: .ascii)
        let idat = "IDAT".data(using: .ascii)

        do {
            let chunker = try PngChunker(source: self)
            while let chunk = try chunker.next() {
                if chunk.type == actl {
                    return true
                } else if chunk.type == idat {
                    return false
                }
            }
        } catch {
            Logger.warn("Error: \(error)")
        }

        return nil
    }

    // MARK: - Image Metadata

    /// load image metadata about the current object
    public func imageMetadata(ignorePerTypeFileSizeLimits: Bool = false) -> ImageMetadata? {
        let result = _imageMetadataResult(ignorePerTypeFileSizeLimits: ignorePerTypeFileSizeLimits)
        switch result {
        case .invalid:
            return nil
        case .valid(let imageMetadata):
            return imageMetadata
        case .genericSizeLimitExceeded:
            return nil
        case .imageTypeSizeLimitExceeded:
            return nil
        }
    }

    /// Load image metadata about the current Data object.
    /// Returns nil if metadata could not be determined.
    public func imageMetadataResult() -> ImageMetadataResult {
        return _imageMetadataResult(ignorePerTypeFileSizeLimits: false)
    }

    private func _imageMetadataResult(ignorePerTypeFileSizeLimits: Bool) -> ImageMetadataResult {
        guard byteLength < OWSMediaUtils.kMaxFileSizeGeneric else {
            return .genericSizeLimitExceeded
        }

        let imageFormat = ows_guessImageFormat()
        guard let imageFormat else {
            Logger.warn("Image does not have valid format.")
            return .invalid
        }

        let isAnimated: Bool
        switch imageFormat {
        case .gif:
            // TODO: We currently treat all GIFs as animated. We could reflect the actual image content.
            isAnimated = true
        case .webp:
            let webpMetadata = metadataForWebp
            guard webpMetadata.isValid else {
                Logger.warn("Image does not have valid webpMetadata.")
                return .invalid
            }
            isAnimated = webpMetadata.frameCount > 1
        case .png:
            guard let isAnimatedPng = isAnimatedPng() else {
                Logger.warn("Could not determine if png is animated.")
                return .invalid
            }
            isAnimated = isAnimatedPng
        default:
            isAnimated = false
        }

        if !ignorePerTypeFileSizeLimits {
            if isAnimated, byteLength > OWSMediaUtils.kMaxFileSizeAnimatedImage {
                Logger.warn("Oversize image.")
                return .imageTypeSizeLimitExceeded
            } else if !isAnimated, byteLength > OWSMediaUtils.kMaxFileSizeImage {
                Logger.warn("Oversize image.")
                return .imageTypeSizeLimitExceeded
            }
        }

        let metadata = imageMetadata(withIsAnimated: isAnimated, imageFormat: imageFormat)

        guard let metadata else {
            return .invalid
        }

        return .valid(metadata)
    }

    private func imageMetadata(withIsAnimated isAnimated: Bool, imageFormat: ImageFormat) -> ImageMetadata? {
        if imageFormat == .webp {
            let imageSize = sizeForWebpData
            guard isImageSizeValid(imageSize, depthBytes: 1, isAnimated: isAnimated) else {
                Logger.warn("Image does not have valid dimensions: \(imageSize)")
                return nil
            }
            return .init(imageFormat: imageFormat, pixelSize: imageSize, hasAlpha: true, isAnimated: isAnimated)
        }

        guard let imageSource = try? self.cgImageSource() else {
            Logger.warn("Could not build imageSource.")
            return nil
        }
        return imageMetadataWithImageSource(imageSource, imageFormat: imageFormat, isAnimated: isAnimated)
    }

    // MARK: - WEBP

    public func stillForWebpData() -> UIImage? {
        guard ows_guessImageFormat() == .webp else {
            owsFailDebug("Invalid webp image.")
            return nil
        }

        guard let data = try? self.readIntoMemory() else {
            return nil
        }

        return UIImage.sd_image(with: data)
    }

    private var sizeForWebpData: CGSize {
        let webpMetadata = metadataForWebp
        guard webpMetadata.isValid else {
            return .zero
        }
        return .init(width: CGFloat(webpMetadata.canvasWidth), height: CGFloat(webpMetadata.canvasHeight))
    }

    private var metadataForWebp: WebpMetadata {
        guard let data = try? self.readIntoMemory() else {
            return WebpMetadata(isValid: false, canvasWidth: 0, canvasHeight: 0, frameCount: 0)
        }
        guard let image = SDAnimatedImage(data: data) else {
            return WebpMetadata(isValid: false, canvasWidth: 0, canvasHeight: 0, frameCount: 0)
        }

        let count = image.sd_imageFrameCount
        let height = image.pixelHeight
        let width = image.pixelWidth
        return WebpMetadata(
            isValid: width > 0 && height > 0 && count > 0,
            canvasWidth: UInt32(width),
            canvasHeight: UInt32(height),
            frameCount: UInt32(count),
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

private func isImageSizeValid(_ imageSize: CGSize, depthBytes: CGFloat, isAnimated: Bool) -> Bool {
    if imageSize.width < 1 || imageSize.height < 1 || depthBytes < 1 {
        // Invalid metadata.
        return false
    }

    // We only support (A)RGB and (A)Grayscale, so worst case is 4.
    let worstCaseComponentsPerPixel = CGFloat(4)
    let bytesPerPixel = worstCaseComponentsPerPixel * depthBytes
    let actualBytes = imageSize.width * imageSize.height * bytesPerPixel

    let expectedBytesPerPixel: CGFloat = 4
    let maxValidImageDimension = CGFloat(isAnimated ? OWSMediaUtils.kMaxAnimatedImageDimensions : OWSMediaUtils.kMaxStillImageDimensions)
    let maxBytes = maxValidImageDimension * maxValidImageDimension * expectedBytesPerPixel

    if actualBytes > maxBytes {
        Logger.warn("invalid dimensions width: \(imageSize.width), height \(imageSize.height), bytesPerPixel: \(bytesPerPixel)")
        return false
    }

    return true
}

private func imageMetadataWithImageSource(_ imageSource: CGImageSource, imageFormat: ImageFormat, isAnimated: Bool) -> ImageMetadata? {
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

    guard isImageSizeValid(pixelSize, depthBytes: depthBytes, isAnimated: isAnimated) else {
        Logger.warn("Image does not have valid dimensions: \(pixelSize).")
        return nil
    }

    return .init(imageFormat: imageFormat, pixelSize: pixelSize, hasAlpha: hasAlpha.boolValue, isAnimated: isAnimated)
}
