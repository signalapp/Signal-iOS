//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

import libwebp
import YYImage

public protocol OWSImageSource {

    var byteLength: Int { get }

    func readData(byteOffset: Int, byteLength: Int) throws -> Data

    func cgImageSource() throws -> CGImageSource?

    /// Potentially expensive, should be avoided if possible.
    func readIntoMemory() throws -> Data
}

extension Data: OWSImageSource {

    public var byteLength: Int { count }

    public func readData(byteOffset: Int, byteLength: Int) throws -> Data {
        return self[byteOffset..<(byteOffset + byteLength)]
    }

    public func cgImageSource() throws -> CGImageSource? {
        return CGImageSourceCreateWithData(self as CFData, nil)
    }

    public func readIntoMemory() throws -> Data {
        return self
    }
}

extension OWSImageSource {
    public var ows_isValidImage: Bool {
        ows_isValidImage()
    }

    public func ows_isValidImage(mimeType: String?) -> Bool {
        ows_isValidImage(withMimeType: mimeType)
    }

    /// If mimeType is non-nil, we ensure that the magic numbers agree with the mimeType.
    public static func ows_isValidImage(at fileUrl: URL, mimeType: String?) -> Bool {
        imageMetadata(withPath: fileUrl.path, mimeType: mimeType).isValid
    }
    public static func ows_isValidImage(atPath filePath: String, mimeType: String? = nil) -> Bool {
        imageMetadata(withPath: filePath, mimeType: mimeType).isValid
    }
    public func ows_isValidImage(withMimeType mimeType: String? = nil) -> Bool {
        imageMetadata(withPath: nil, mimeType: mimeType).isValid
    }
    fileprivate func ows_isValidImage(withPath filePath: String?, mimeType: String?) -> Bool {
        imageMetadata(withPath: filePath, mimeType: mimeType).isValid
    }

    fileprivate static func ows_isValidImage(dimension imageSize: CGSize, depthBytes: CGFloat, isAnimated: Bool) -> Bool {
        if imageSize.width < 1 || imageSize.height < 1 || depthBytes < 1 {
            // Invalid metadata.
            return false
        }

        // We only support (A)RGB and (A)Grayscale, so worst case is 4.
        let worstCaseComponentsPerPixel = CGFloat(4)
        let bytesPerPixel = worstCaseComponentsPerPixel * depthBytes

        let expectedBytesPerPixel: CGFloat = 4
        let maxValidImageDimension: CGFloat = CGFloat(isAnimated ? OWSMediaUtils.kMaxAnimatedImageDimensions : OWSMediaUtils.kMaxStillImageDimensions)
        let maxBytes = maxValidImageDimension * maxValidImageDimension * expectedBytesPerPixel
        let actualBytes = imageSize.width * imageSize.height * bytesPerPixel
        if actualBytes > maxBytes {
            Logger.warn("invalid dimensions width: \(imageSize.width), height \(imageSize.height), bytesPerPixel: \(bytesPerPixel)")
            return false
        }

        return true
    }

    // Parse the GIF header to prevent the "GIF of death" issue.
    //
    // See: https://blog.flanker017.me/cve-2017-2416-gif-remote-exec/
    // See: https://www.w3.org/Graphics/GIF/spec-gif89a.txt
    //
    // TODO: Remove this check.
    // This behavior was ported over from objective-c and ends up effectively just checking for GIF headers and then that the size isn't zero.
    // It appears to be a somewhat broken attempt to workaround the above CVE which was fixed so long ago we don't ship to iOS builds with the
    // problem anymore.
    internal var ows_hasValidGifSize: Bool {
        let signatureLength = 3
        let versionLength = 3
        let widthLength = 2
        let heightLength = 2
        let prefixLength = signatureLength + versionLength
        let bufferLength = signatureLength + versionLength + widthLength + heightLength

        guard byteLength >= bufferLength else {
            return false
        }

        let gif87aPrefix = Data([0x47, 0x49, 0x46, 0x38, 0x37, 0x61])
        let gif89aPrefix = Data([0x47, 0x49, 0x46, 0x38, 0x39, 0x61])
        let prefix = try? self.readData(byteOffset: 0, byteLength: prefixLength)
        guard prefix == gif87aPrefix || prefix == gif89aPrefix else {
            return false
        }
        guard let subRange = try? self.readData(byteOffset: prefixLength, byteLength: 4) else {
            return false
        }
        return subRange != Data(count: 4)
    }

    fileprivate func ows_guessHighEfficiencyImageFormat() -> ImageFormat {
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
            return .unknown
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
            return .unknown
        }
    }

    fileprivate func ows_guessImageFormat() -> ImageFormat {
        guard byteLength >= 2 else {
            return .unknown
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

    fileprivate static func applyImageOrientation(_ orientation: CGImagePropertyOrientation, to imageSize: CGSize) -> CGSize {
        // NOTE: UIImageOrientation and CGImagePropertyOrientation values
        //       DO NOT match.
        switch orientation {
        case .up, .upMirrored, .down, .downMirrored:
            return imageSize
        case .left, .leftMirrored, .right, .rightMirrored:
            return CGSize(width: imageSize.height, height: imageSize.width)
        }
    }

    public static func hasAlpha(forValidImageFilePath filePath: String) -> Bool {
        if isWebp(filePath: filePath) {
            return true
        }

        let url = URL(fileURLWithPath: filePath)

        // With CGImageSource we avoid loading the whole image into memory.
        guard let _ = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            owsFailDebug("Could not load image: \(url)")
            return false
        }

        return imageMetadata(withPath: filePath, mimeType: nil).hasAlpha
    }

    /// Returns the image size in pixels.
    ///
    /// Returns CGSizeZero on error.
    public static func imageSize(forFilePath filePath: String, mimeType: String?) -> CGSize {
        let imageMetadata = imageMetadata(withPath: filePath, mimeType: mimeType)
        guard imageMetadata.isValid else {
            return CGSize.zero
        }
        return imageMetadata.pixelSize
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
    func isAnimatedPngData() -> NSNumber? {
        let actl = "acTL".data(using: .ascii)
        let idat = "IDAT".data(using: .ascii)

        do {
            let chunker = try PngChunker(source: self)
            while let chunk = try chunker.next() {
                if chunk.type == actl {
                    return NSNumber(value: true)
                } else if chunk.type == idat {
                    return NSNumber(value: false)
                }
            }
        } catch {
            Logger.warn("Error: \(error)")
        }

        return nil
    }

    // MARK: - Sticker Like Properties

    public static func ows_hasStickerLikeProperties(withPath filePath: String) -> Bool {
        return ows_hasStickerLikeProperties(withImageMetadata: imageMetadata(withPath: filePath, mimeType: nil))
    }

    public func ows_hasStickerLikeProperties() -> Bool {
        let imageMetadata = imageMetadata(withIsAnimated: false, imageFormat: ows_guessImageFormat())
        return Data.ows_hasStickerLikeProperties(withImageMetadata: imageMetadata)
    }

    public static func ows_hasStickerLikeProperties(withImageMetadata imageMetadata: ImageMetadata) -> Bool {
        let maxStickerHeight = CGFloat(512)
        return (imageMetadata.isValid
                && imageMetadata.pixelSize.width <= maxStickerHeight
                && imageMetadata.pixelSize.height <= maxStickerHeight
                && imageMetadata.hasAlpha)
    }

    // MARK: - Image Metadata

    public static func imageMetadata(withPath filePath: String, mimeType declaredMimeType: String?, ignoreFileSize: Bool = false) -> ImageMetadata {
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: filePath), options: .mappedIfSafe)
            // Use memory-mapped NSData instead of a URL-based
            // CGImageSource. We should usually only be reading
            // from (a small portion of) the file header,
            // depending on the file format.
            return data.imageMetadata(withPath: filePath, mimeType: declaredMimeType, ignoreFileSize: ignoreFileSize)
        } catch {
            Logger.warn("Could not read image data: \(error)")
            return .invalid()
        }
    }

    /// load image metadata about the current Data object
    ///
    /// If filePath and/or declaredMimeType is supplied, we warn
    /// if they do not match the actual file contents.  But they are
    /// both optional, we consider the actual image format (deduced
    /// using magic numbers) to be authoritative.  The file extension
    /// and declared MIME type could be wrong, but we can proceed in
    /// that case.
    ///
    /// If maxImageDimension is supplied we enforce the _smaller_ of
    /// that value and the per-format max dimension
    public func imageMetadata(withPath filePath: String?, mimeType declaredMimeType: String?, ignoreFileSize: Bool = false) -> ImageMetadata {
        let fileExtension = (filePath as? NSString)?.pathExtension.lowercased().nilIfEmpty
        let result = _imageMetadata(
            mimeTypeForValidation: declaredMimeType?.nilIfEmpty,
            fileExtensionForValidation: fileExtension,
            ignorePerTypeFileSizeLimits: ignoreFileSize
        )
        switch result {
        case .invalid:
            return .invalid()
        case .valid(let imageMetadata):
            return imageMetadata
        case .mimeTypeMismatch(let imageMetadata), .fileExtensionMismatch(let imageMetadata):
            // Do not fail in production.
            return imageMetadata
        case .genericSizeLimitExceeded:
            return .invalid()
        case .imageTypeSizeLimitExceeded:
            return .invalid()
        }
    }

    /// Load image metadata about the current Data object.
    /// Returns nil if metadata could not be determined.
    public func imageMetadata(
        mimeTypeForValidation declaredMimeType: String?,
        fileExtensionForValidation: String? = nil
    ) -> ImageMetadataResult {
        return _imageMetadata(
            mimeTypeForValidation: declaredMimeType,
            fileExtensionForValidation: fileExtensionForValidation,
            ignorePerTypeFileSizeLimits: false
        )
    }

    private func _imageMetadata(
        mimeTypeForValidation declaredMimeType: String?,
        fileExtensionForValidation: String?,
        ignorePerTypeFileSizeLimits: Bool
    ) -> ImageMetadataResult {
        guard byteLength < OWSMediaUtils.kMaxFileSizeGeneric else {
            return .genericSizeLimitExceeded
        }

        let imageFormat = ows_guessImageFormat()
        guard imageFormat.isValid(source: self) else {
            Logger.warn("Image does not have valid format.")
            return .invalid
        }

        guard let mimeType = imageFormat.mimeType else {
            Logger.warn("Image does not have MIME type.")
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
            guard let isAnimatedPng = isAnimatedPngData() else {
                Logger.warn("Could not determine if png is animated.")
                return .invalid
            }
            isAnimated = isAnimatedPng.boolValue
        default:
            isAnimated = false
        }

        guard imageFormat.isValid(source: self) else {
            Logger.warn("Image does not have valid format.")
            return .invalid
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

        guard metadata.isValid else {
            return .invalid
        }

        if let declaredMimeType, !imageFormat.isValid(mimeType: declaredMimeType) {
            Logger.info("Mimetypes do not match: \(mimeType), \(declaredMimeType)")
            return .mimeTypeMismatch(metadata)
        }

        if
            let fileExtensionForValidation,
            let mimeTypeForFileExtension = MimeTypeUtil.mimeTypeForFileExtension(fileExtensionForValidation),
            !mimeTypeForFileExtension.isEmpty,
            mimeType.rawValue.caseInsensitiveCompare(mimeTypeForFileExtension) != .orderedSame
        {
            Logger.info("fileExtension does not match: \(fileExtensionForValidation), \(mimeType), \(mimeTypeForFileExtension)")
            return .fileExtensionMismatch(metadata)
        }

        return .valid(metadata)
    }

    fileprivate func imageMetadata(withIsAnimated isAnimated: Bool, imageFormat: ImageFormat) -> ImageMetadata {
        if imageFormat == .webp {
            let imageSize = sizeForWebpData
            guard Data.ows_isValidImage(dimension: imageSize, depthBytes: 1, isAnimated: isAnimated) else {
                Logger.warn("Image does not have valid dimensions: \(imageSize)")
                return .invalid()
            }
            return .init(isValid: true, imageFormat: imageFormat, pixelSize: imageSize, hasAlpha: true, isAnimated: isAnimated)
        }

        guard let imageSource = try? self.cgImageSource() else {
            Logger.warn("Could not build imageSource.")
            return .invalid()
        }
        return Data.imageMetadata(withImageSource: imageSource, imageFormat: imageFormat, isAnimated: isAnimated)
    }

    fileprivate static func imageMetadata(withImageSource imageSource: CGImageSource, imageFormat: ImageFormat, isAnimated: Bool) -> ImageMetadata {
        let options = [kCGImageSourceShouldCache as String: false]
        guard let imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, options as CFDictionary) as? [String: AnyObject] else {
            Logger.warn("Missing imageProperties.")
            return .invalid()
        }

        guard let widthNumber = imageProperties[kCGImagePropertyPixelWidth as String] as? NSNumber else {
            Logger.warn("widthNumber was unexpectedly nil")
            return .invalid()
        }
        guard let heightNumber = imageProperties[kCGImagePropertyPixelHeight as String] as? NSNumber else {
            Logger.warn("heightNumber was unexpectedly nil")
            return .invalid()
        }

        var pixelSize = CGSize(width: widthNumber.doubleValue, height: heightNumber.doubleValue)
        if let orientationNumber = imageProperties[kCGImagePropertyOrientation as String] as? NSNumber {
            guard let orientation = CGImagePropertyOrientation(rawValue: orientationNumber.uint32Value) else {
                Logger.warn("orientation number was invalid")
                return .invalid()
            }
            pixelSize = applyImageOrientation(orientation, to: pixelSize)
        }

        let hasAlpha = imageProperties[kCGImagePropertyHasAlpha as String] as? NSNumber ?? false

        // The number of bits in each color sample of each pixel. The value of this key is a CFNumberRef.
        guard let depthNumber = imageProperties[kCGImagePropertyDepth as String] as? NSNumber else {
            Logger.warn("depthNumber was unexpectedly nil")
            return .invalid()
        }
        let depthBits = depthNumber.uintValue
        // This should usually be 1.
        let depthBytes = ceil(Double(depthBits) / 8.0)

        // The color model of the image such as "RGB", "CMYK", "Gray", or "Lab". The value of this key is CFStringRef.
        guard let colorModel = (imageProperties[kCGImagePropertyColorModel as String] as? NSString) as String? else {
            Logger.warn("colorModel was unexpectedly nil")
            return .invalid()
        }
        guard colorModel == kCGImagePropertyColorModelRGB as String || colorModel == kCGImagePropertyColorModelGray as String else {
            Logger.warn("Invalid colorModel: \(colorModel)")
            return .invalid()
        }

        guard ows_isValidImage(dimension: pixelSize, depthBytes: depthBytes, isAnimated: isAnimated) else {
            Logger.warn("Image does not have valid dimensions: \(pixelSize).")
            return .invalid()
        }

        return .init(isValid: true, imageFormat: imageFormat, pixelSize: pixelSize, hasAlpha: hasAlpha.boolValue, isAnimated: isAnimated)
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
        guard let cgImage = YYCGImageCreateWithWebPData(data as CFData, false, false, false, false) else {
            owsFailDebug("Could not generate still for webp image.")
            return nil
        }

        return UIImage(cgImage: cgImage.takeRetainedValue())
    }

    fileprivate static func isWebp(filePath: String) -> Bool {
        let fileExtension = ((filePath as NSString).lastPathComponent as NSString).pathExtension.lowercased()
        return "webp" == fileExtension
    }

    fileprivate var sizeForWebpData: CGSize {
        let webpMetadata = metadataForWebp
        guard webpMetadata.isValid else {
            return .zero
        }
        return .init(width: CGFloat(webpMetadata.canvasWidth), height: CGFloat(webpMetadata.canvasHeight))
    }

    fileprivate var metadataForWebp: WebpMetadata {
        guard let data = try? self.readIntoMemory() else {
            return WebpMetadata(isValid: false, canvasWidth: 0, canvasHeight: 0, frameCount: 0)
        }
        return data.withUnsafeBytes {
            $0.withMemoryRebound(to: UInt8.self) { buffer in
                var webPData = WebPData(bytes: buffer.baseAddress, size: buffer.count)
                guard let demuxer = WebPDemux(&webPData) else {
                    return WebpMetadata(isValid: false, canvasWidth: 0, canvasHeight: 0, frameCount: 0)
                }
                defer {
                    WebPDemuxDelete(demuxer)
                }

                let canvasWidth = WebPDemuxGetI(demuxer, WEBP_FF_CANVAS_WIDTH)
                let canvasHeight = WebPDemuxGetI(demuxer, WEBP_FF_CANVAS_HEIGHT)
                let frameCount = WebPDemuxGetI(demuxer, WEBP_FF_FRAME_COUNT)
                let result = WebpMetadata(isValid: canvasWidth > 0 && canvasHeight > 0 && frameCount > 0,
                                          canvasWidth: canvasWidth,
                                          canvasHeight: canvasHeight,
                                          frameCount: frameCount)
                return result
            }
        }
    }
}
