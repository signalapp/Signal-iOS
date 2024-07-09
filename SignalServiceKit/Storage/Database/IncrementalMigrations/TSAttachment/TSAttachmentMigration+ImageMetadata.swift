//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension TSAttachmentMigration {
    enum ImageFormat {
        case unknown
        case png
        case gif
        case tiff
        case jpeg
        case bmp
        case webp
        case heic
        case heif

        var mimeType: String? {
            switch self {
            case .png:
                return "image/png"
            case .gif:
                return "image/gif"
            case .tiff:
                return "image/tiff"
            case .jpeg:
                return "image/jpeg"
            case .bmp:
                return "image/bmp"
            case .webp:
                return "image/webp"
            case .heic:
                return "image/heic"
            case .heif:
                return "image/heif"
            case .unknown:
                return nil
            }
        }

        func isValid(source: TSAttachmentMigration.OWSImageSource) -> Bool {
            switch self {
            case .unknown:
                return false
            case .png, .tiff, .jpeg, .bmp, .webp, .heic, .heif:
                return true
            case .gif:
                return source.ows_hasValidGifSize
            }
        }

        func isValid(mimeType: String?) -> Bool {
            owsAssertDebug(!(mimeType?.isEmpty ?? true))

            switch self {
            case .unknown:
                return false
            case .png:
                guard let mimeType else { return true }
                return (mimeType.caseInsensitiveCompare("image/png") == .orderedSame ||
                        mimeType.caseInsensitiveCompare("image/apng") == .orderedSame ||
                        mimeType.caseInsensitiveCompare("image/vnd.mozilla.apng") == .orderedSame)
            case .gif:
                guard let mimeType else { return true }
                return mimeType.caseInsensitiveCompare("image/gif") == .orderedSame
            case .tiff:
                guard let mimeType else { return true }
                return (mimeType.caseInsensitiveCompare("image/tiff") == .orderedSame ||
                        mimeType.caseInsensitiveCompare("image/x-tiff") == .orderedSame)
            case .jpeg:
                guard let mimeType else { return true }
                return mimeType.caseInsensitiveCompare("image/jpeg") == .orderedSame
            case .bmp:
                guard let mimeType else { return true }
                return (mimeType.caseInsensitiveCompare("image/bmp") == .orderedSame ||
                        mimeType.caseInsensitiveCompare("image/x-windows-bmp") == .orderedSame)
            case .webp:
                guard let mimeType else { return true }
                return mimeType.caseInsensitiveCompare("image/webp") == .orderedSame
            case .heic:
                guard let mimeType else { return true }
                return mimeType.caseInsensitiveCompare("image/heic") == .orderedSame
            case .heif:
                guard let mimeType else { return true }
                return mimeType.caseInsensitiveCompare("image/heif") == .orderedSame
            }
        }
    }

    struct ImageMetadata {
        let isValid: Bool
        let imageFormat: ImageFormat
        let pixelSize: CGSize
        let hasAlpha: Bool
        let isAnimated: Bool

        static func invalid() -> Self {
            .init(isValid: false, imageFormat: .unknown, pixelSize: .zero, hasAlpha: false, isAnimated: false)
        }

        var mimeType: String? {
            imageFormat.mimeType
        }

        var fileExtension: String? {
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
}
