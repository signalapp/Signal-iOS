//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum MimeType: String {
    case applicationJson = "application/json"
    case applicationOctetStream = "application/octet-stream"
    case applicationPdf = "application/pdf"
    case applicationXProtobuf = "application/x-protobuf"
    case applicationZip = "application/zip"
    case imageApng = "image/apng"
    case imageBmp = "image/bmp"
    case imageGif = "image/gif"
    case imageHeic = "image/heic"
    case imageHeif = "image/heif"
    case imageJpeg = "image/jpeg"
    case imagePng = "image/png"
    case imageTiff = "image/tiff"
    case imageVndMozillaApng = "image/vnd.mozilla.apng"
    case imageWebp = "image/webp"
    case imageXTiff = "image/x-tiff"
    case imageXWindowsBmp = "image/x-windows-bmp"
    /// oversized text message
    case textXSignalPlain = "text/x-signal-plain"
    // TODO: Remove this; it's unused.
    case textXSignalStickerLottie = "text/x-signal-sticker-lottie"
    /// unknown for tests
    case unknownMimetype = "unknown/mimetype"
}

@objc
public class MimeTypeUtil: NSObject {
    override private init() {}

    public static let oversizeTextAttachmentUti = "org.whispersystems.oversize-text-attachment"
    public static let oversizeTextAttachmentFileExtension = "txt"
    public static let unknownTestAttachmentUti = "org.whispersystems.unknown"
    public static let syncMessageFileExtension = "bin"
    // TODO: Remove this; it's unused.
    public static let lottieStickerFileExtension = "lottiesticker"

    @objc
    public static let supportedVideoMimeTypesToExtensionTypes: [String: String] = [
        "video/3gpp": "3gp",
        "video/3gpp2": "3g2",
        "video/mp4": "mp4",
        "video/quicktime": "mov",
        "video/x-m4v": "m4v",
        "video/mpeg": "mpg",
    ]
    @objc
    public static let supportedAudioMimeTypesToExtensionTypes: [String: String] = [
        "audio/aac": "m4a",
        "audio/x-m4p": "m4p",
        "audio/x-m4b": "m4b",
        "audio/x-m4a": "m4a",
        "audio/wav": "wav",
        "audio/x-wav": "wav",
        "audio/x-mpeg": "mp3",
        "audio/mpeg": "mp3",
        "audio/mp4": "mp4",
        "audio/mp3": "mp3",
        "audio/mpeg3": "mp3",
        "audio/x-mp3": "mp3",
        "audio/x-mpeg3": "mp3",
        "audio/aiff": "aiff",
        "audio/x-aiff": "aiff",
        "audio/3gpp2": "3g2",
        "audio/3gpp": "3gp",
    ]
    @objc
    public static let supportedImageMimeTypesToExtensionTypes: [String: String] = [
        MimeType.imageJpeg.rawValue: "jpeg",
        "image/pjpeg": "jpeg",
        MimeType.imagePng.rawValue: "png",
        MimeType.imageTiff.rawValue: "tif",
        MimeType.imageXTiff.rawValue: "tif",
        MimeType.imageBmp.rawValue: "bmp",
        MimeType.imageXWindowsBmp.rawValue: "bmp",
        MimeType.imageHeic.rawValue: "heic",
        MimeType.imageHeif.rawValue: "heif",
        MimeType.imageWebp.rawValue: "webp",
    ]
    @objc
    public static let supportedDefinitelyAnimatedMimeTypesToExtensionTypes: [String: String] = {
        var result = [
            MimeType.imageGif.rawValue: "gif",
            MimeType.imageApng.rawValue: "png",
            MimeType.imageVndMozillaApng.rawValue: "png",
        ]
        if FeatureFlags.supportAnimatedStickers_Lottie {
            result[MimeType.textXSignalStickerLottie.rawValue] = lottieStickerFileExtension
        }
        return result
    }()
    @objc
    public static let supportedMaybeAnimatedMimeTypesToExtensionTypes: [String: String] = {
        var result = supportedDefinitelyAnimatedMimeTypesToExtensionTypes;
        result[MimeType.imageWebp.rawValue] = "webp"
        result[MimeType.imagePng.rawValue] = "png"
        return result
    }()
    @objc
    public static let supportedBinaryDataMimeTypesToExtensionTypes: [String: String] = [
        MimeType.applicationOctetStream.rawValue: "dat",
    ]
}
