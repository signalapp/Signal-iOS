//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

import libwebp
import YYImage

enum ImageFormat: CustomStringConvertible {
    case unknown
    case png
    case gif
    case tiff
    case jpeg
    case bmp
    case webp
    case heic
    case heif

    var description: String {
        switch self {
        case .unknown:
            "ImageFormat_Unknown"
        case .png:
            "ImageFormat_Png"
        case .gif:
            "ImageFormat_Gif"
        case .tiff:
            "ImageFormat_Tiff"
        case .jpeg:
            "ImageFormat_Jpeg"
        case .bmp:
            "ImageFormat_Bmp"
        case .webp:
            "ImageFormat_Webp"
        case .heic:
            "ImageFormat_Heic"
        case .heif:
            "ImageFormat_Heif"
        }
    }

    fileprivate var mimeType: MimeType? {
        switch self {
        case .png:
            return MimeType.imagePng
        case .gif:
            return MimeType.imageGif
        case .tiff:
            return MimeType.imageTiff
        case .jpeg:
            return MimeType.imageJpeg
        case .bmp:
            return MimeType.imageBmp
        case .webp:
            return MimeType.imageWebp
        case .heic:
            return MimeType.imageHeic
        case .heif:
            return MimeType.imageHeif
        case .unknown:
            return nil
        }
    }

    fileprivate func isValid(data: Data) -> Bool {
        switch self {
        case .unknown:
            return false
        case .png, .tiff, .jpeg, .bmp, .webp, .heic, .heif:
            return true
        case .gif:
            return data.ows_hasValidGifSize
        }
    }

    fileprivate func isValid(mimeType: String?) -> Bool {
        owsAssertDebug(!(mimeType?.isEmpty ?? true))

        switch self {
        case .unknown:
            return false
        case .png:
            guard let mimeType else { return true }
            return (mimeType.caseInsensitiveCompare(MimeType.imagePng.rawValue) == .orderedSame ||
                    mimeType.caseInsensitiveCompare(MimeType.imageApng.rawValue) == .orderedSame ||
                    mimeType.caseInsensitiveCompare(MimeType.imageVndMozillaApng.rawValue) == .orderedSame)
        case .gif:
            guard let mimeType else { return true }
            return mimeType.caseInsensitiveCompare(MimeType.imageGif.rawValue) == .orderedSame
        case .tiff:
            guard let mimeType else { return true }
            return (mimeType.caseInsensitiveCompare(MimeType.imageTiff.rawValue) == .orderedSame ||
                    mimeType.caseInsensitiveCompare(MimeType.imageXTiff.rawValue) == .orderedSame)
        case .jpeg:
            guard let mimeType else { return true }
            return mimeType.caseInsensitiveCompare(MimeType.imageJpeg.rawValue) == .orderedSame
        case .bmp:
            guard let mimeType else { return true }
            return (mimeType.caseInsensitiveCompare(MimeType.imageBmp.rawValue) == .orderedSame ||
                    mimeType.caseInsensitiveCompare(MimeType.imageXWindowsBmp.rawValue) == .orderedSame)
        case .webp:
            guard let mimeType else { return true }
            return mimeType.caseInsensitiveCompare(MimeType.imageWebp.rawValue) == .orderedSame
        case .heic:
            guard let mimeType else { return true }
            return mimeType.caseInsensitiveCompare(MimeType.imageHeic.rawValue) == .orderedSame
        case .heif:
            guard let mimeType else { return true }
            return mimeType.caseInsensitiveCompare(MimeType.imageHeif.rawValue) == .orderedSame
        }
    }
}

// TODO: Convert to struct once all users of this type are swift.
@objc
public class ImageMetadata: NSObject {
    @objc
    public let isValid: Bool
    let imageFormat: ImageFormat
    @objc
    public let pixelSize: CGSize
    let hasAlpha: Bool
    let isAnimated: Bool

    fileprivate init(isValid: Bool, imageFormat: ImageFormat, pixelSize: CGSize, hasAlpha: Bool, isAnimated: Bool) {
        self.isValid = isValid
        self.imageFormat = imageFormat
        self.pixelSize = pixelSize
        self.hasAlpha = hasAlpha
        self.isAnimated = isAnimated
    }

    fileprivate static func invalid() -> ImageMetadata {
        .init(isValid: false, imageFormat: .unknown, pixelSize: .zero, hasAlpha: false, isAnimated: false)
    }

    public var mimeType: String? {
        imageFormat.mimeType?.rawValue
    }
    public var fileExtension: String? {
        guard let mimeType else {
            return nil
        }
        return MimeTypeUtil.fileExtensionForMimeType(mimeType)
    }
}

extension NSData {
    @objc
    @available(swift, obsoleted: 1)
    public static func imageSize(forFilePath filePath: String, mimeType: String?) -> CGSize {
        Data.imageSize(forFilePath: filePath, mimeType: mimeType)
    }

    @objc
    @available(swift, obsoleted: 1)
    public func imageMetadata(withPath filePath: String?, mimeType: String?) -> ImageMetadata {
        (self as Data).imageMetadata(withPath: filePath, mimeType: mimeType)
    }

    @objc
    @available(swift, obsoleted: 1)
    public func imageMetadata(withPath filePath: String?, mimeType: String?, ignoreFileSize: Bool) -> ImageMetadata {
        (self as Data).imageMetadata(withPath: filePath, mimeType: mimeType, ignoreFileSize: ignoreFileSize)
    }

    @objc
    @available(swift, obsoleted: 1)
    public static func imageMetadata(withPath filePath: String, mimeType: String?, ignoreFileSize: Bool) -> ImageMetadata {
        Data.imageMetadata(withPath: filePath, mimeType: mimeType, ignoreFileSize: ignoreFileSize)
    }

    @objc
    @available(swift, obsoleted: 1)
    public var ows_isValidImage: Bool {
        (self as Data).ows_isValidImage
    }

    @objc(ows_isValidImageAtUrl:mimeType:)
    @available(swift, obsoleted: 1)
    public static func ows_isValidImage(at fileUrl: URL, mimeType: String?) -> Bool {
        Data.ows_isValidImage(at: fileUrl, mimeType: mimeType)
    }

    @objc
    @available(swift, obsoleted: 1)
    public static func ows_isValidImage(atPath filePath: String, mimeType: String?) -> Bool {
        Data.ows_isValidImage(atPath: filePath, mimeType: mimeType)
    }

    @objc
    @available(swift, obsoleted: 1)
    public var ows_hasStickerLikeProperties: Bool {
        (self as Data).ows_hasStickerLikeProperties()
    }

    @objc
    @available(swift, obsoleted: 1)
    public static func ows_hasStickerLikeProperties(withPath filePath: String) -> Bool {
        Data.ows_hasStickerLikeProperties(withPath: filePath)
    }
}

 // MARK: -

extension Data {
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
    fileprivate var ows_hasValidGifSize: Bool {
        let signatureLength = 3
        let versionLength = 3
        let widthLength = 2
        let heightLength = 2
        let prefixLength = signatureLength + versionLength
        let bufferLength = signatureLength + versionLength + widthLength + heightLength

        guard count >= bufferLength else {
            return false
        }

        let gif87aPrefix = Data([0x47, 0x49, 0x46, 0x38, 0x37, 0x61])
        let gif89aPrefix = Data([0x47, 0x49, 0x46, 0x38, 0x39, 0x61])
        guard prefix(prefixLength) == gif87aPrefix || prefix(prefixLength) == gif89aPrefix else {
            return false
        }
        return dropFirst(prefixLength).prefix(4) != Data(count: 4)
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
        guard count >= heifBrandStartsAt + heifSupportedBrandLength else {
            return .unknown
        }

        // These are the brands of HEIF formatted files that are renderable by CoreGraphics
        let heifBrandHeaderHeic = Data("ftypheic\0".utf8)
        let heifBrandHeaderHeif = Data("ftypmif1\0".utf8)
        let heifBrandHeaderHeifStream = Data("ftypmsf1\0".utf8)

        // Pull the string from the header and compare it with the supported formats
        let header = dropFirst(heifHeaderStartsAt).prefix(totalHeaderLength)

        if header == heifBrandHeaderHeic {
            return .heic
        } else if header == heifBrandHeaderHeif || header == heifBrandHeaderHeifStream {
            return .heif
        } else {
            return .unknown
        }
    }

    fileprivate func ows_guessImageFormat() -> ImageFormat {
        guard count >= 2 else {
            return .unknown
        }

        switch prefix(2) {
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
            let chunker = try PngChunker(data: self as Data)
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

    fileprivate static func ows_hasStickerLikeProperties(withImageMetadata imageMetadata: ImageMetadata) -> Bool {
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
        let imageFormat = ows_guessImageFormat()
        guard imageFormat.isValid(data: self) else {
            Logger.warn("Image does not have valid format.")
            return .invalid()
        }

        guard let mimeType = imageFormat.mimeType else {
            Logger.warn("Image does not have MIME type.")
            return .invalid()
        }

        if let declaredMimeType, !declaredMimeType.isEmpty, !imageFormat.isValid(mimeType: declaredMimeType) {
            Logger.info("Mimetypes do not match: \(mimeType), \(declaredMimeType)")
            // Do not fail in production.
        }

        if let filePath, !filePath.isEmpty {
            let fileExtension = (filePath as NSString).pathExtension.lowercased()
            if !fileExtension.isEmpty {
                let mimeTypeForFileExtension = MimeTypeUtil.mimeTypeForFileExtension(fileExtension)
                if let mimeTypeForFileExtension, !mimeTypeForFileExtension.isEmpty,
                   mimeType.rawValue.caseInsensitiveCompare(mimeTypeForFileExtension) != .orderedSame {
                    Logger.info("fileExtension does not match: \(fileExtension), \(mimeType), \(mimeTypeForFileExtension)")
                    // Do not fail in production.
                }
            }
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
                return .invalid()
            }
            isAnimated = webpMetadata.frameCount > 1
        case .png:
            guard let isAnimatedPng = isAnimatedPngData() else {
                Logger.warn("Could not determine if png is animated.")
                return .invalid()
            }
            isAnimated = isAnimatedPng.boolValue
        default:
            isAnimated = false
        }

        guard imageFormat.isValid(data: self) else {
            Logger.warn("Image does not have valid format.")
            return .invalid()
        }

        let targetFileSize = if ignoreFileSize {
            OWSMediaUtils.kMaxFileSizeGeneric
        } else if isAnimated {
            OWSMediaUtils.kMaxFileSizeAnimatedImage
        } else {
            OWSMediaUtils.kMaxFileSizeImage
        }
        let fileSize = count
        if fileSize > targetFileSize {
            Logger.warn("Oversize image.")
            return .invalid()
        }

        return imageMetadata(withIsAnimated: isAnimated, imageFormat: imageFormat)
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

        guard let imageSource = CGImageSourceCreateWithData(self as CFData, nil) else {
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

        guard let cgImage = YYCGImageCreateWithWebPData(self as CFData, false, false, false, false) else {
            owsFailDebug("Could not generate still for webp image.")
            return nil
        }

        return UIImage(cgImage: cgImage.takeRetainedValue())
    }

    fileprivate static func isWebp(filePath: String) -> Bool {
        let fileExtension = ((filePath as NSString).lastPathComponent as NSString).pathExtension.lowercased()
        return "webp" == fileExtension
    }

    fileprivate struct WebpMetadata {
        let isValid: Bool
        let canvasWidth: UInt32
        let canvasHeight: UInt32
        let frameCount: UInt32
    }

    fileprivate var sizeForWebpData: CGSize {
        let webpMetadata = metadataForWebp
        guard webpMetadata.isValid else {
            return .zero
        }
        return .init(width: CGFloat(webpMetadata.canvasWidth), height: CGFloat(webpMetadata.canvasHeight))
    }

    fileprivate var metadataForWebp: WebpMetadata {
        withUnsafeBytes {
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
