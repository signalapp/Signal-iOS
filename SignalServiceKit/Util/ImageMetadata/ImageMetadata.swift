//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum ImageFormat: CustomStringConvertible {
    case unknown
    case png
    case gif
    case tiff
    case jpeg
    case bmp
    case webp
    case heic
    case heif

    public var description: String {
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

    internal var mimeType: MimeType? {
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

    internal func isValid(source: OWSImageSource) -> Bool {
        switch self {
        case .unknown:
            return false
        case .png, .tiff, .jpeg, .bmp, .webp, .heic, .heif:
            return true
        case .gif:
            return source.ows_hasValidGifSize
        }
    }

    internal func isValid(mimeType: String?) -> Bool {
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
    public let imageFormat: ImageFormat
    @objc
    public let pixelSize: CGSize
    public let hasAlpha: Bool
    let isAnimated: Bool

    internal init(isValid: Bool, imageFormat: ImageFormat, pixelSize: CGSize, hasAlpha: Bool, isAnimated: Bool) {
        self.isValid = isValid
        self.imageFormat = imageFormat
        self.pixelSize = pixelSize
        self.hasAlpha = hasAlpha
        self.isAnimated = isAnimated
    }

    internal static func invalid() -> ImageMetadata {
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

internal struct WebpMetadata {
    let isValid: Bool
    let canvasWidth: UInt32
    let canvasHeight: UInt32
    let frameCount: UInt32
}

public enum ImageMetadataResult {
    /// Source data exceeded size limit for all attachments;
    /// as a precaution no validation was performed.
    case genericSizeLimitExceeded

    /// Exceeded the file size limit for the inferred type of image.
    /// Smaller than the generic size limit.
    case imageTypeSizeLimitExceeded

    case invalid

    case valid(ImageMetadata)

    /// A mime type was provided, and it did not match the contents.
    /// Metadata is still valid and the error can be safely ignored.
    case mimeTypeMismatch(ImageMetadata)

    /// A file extension was provided, and it did not match the contents.
    /// Metadata is still valid and the error can be safely ignored.
    case fileExtensionMismatch(ImageMetadata)
}
