//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum ImageFormat: CustomStringConvertible {
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

    public var mimeType: MimeType {
        return self.mimeTypes.preferredMimeType
    }

    private var mimeTypes: (preferredMimeType: MimeType, alternativeMimeTypes: [MimeType]) {
        switch self {
        case .png: (.imagePng, [.imageApng, .imageVndMozillaApng])
        case .gif: (.imageGif, [])
        case .tiff: (.imageTiff, [.imageXTiff])
        case .jpeg: (.imageJpeg, [])
        case .bmp: (.imageBmp, [.imageXWindowsBmp])
        case .webp: (.imageWebp, [])
        case .heic: (.imageHeic, [])
        case .heif: (.imageHeif, [])
        }
    }

    public var fileExtension: String {
        // All known ImageFormats must have a corresponding extension.
        return MimeTypeUtil.fileExtensionForMimeType(mimeType.rawValue)!
    }

    internal func isValid(mimeType: String) -> Bool {
        owsAssertDebug(!mimeType.isEmpty)
        let mimeTypes = self.mimeTypes
        return ([mimeTypes.preferredMimeType] + mimeTypes.alternativeMimeTypes).contains(where: {
            return mimeType.caseInsensitiveCompare($0.rawValue) == .orderedSame
        })
    }
}

public struct ImageMetadata {
    public let imageFormat: ImageFormat
    public let pixelSize: CGSize
    public let hasAlpha: Bool
    public let isAnimated: Bool

    internal init(imageFormat: ImageFormat, pixelSize: CGSize, hasAlpha: Bool, isAnimated: Bool) {
        self.imageFormat = imageFormat
        self.pixelSize = pixelSize
        self.hasAlpha = hasAlpha
        self.isAnimated = isAnimated
    }

    public var hasStickerLikeProperties: Bool {
        let maxStickerHeight = CGFloat(512)
        return (
            pixelSize.width <= maxStickerHeight
            && pixelSize.height <= maxStickerHeight
            && pixelSize != CGSize(width: 1, height: 1)
            && hasAlpha
        )
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
}
