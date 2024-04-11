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

public enum MimeTypeUtil {
    public static let oversizeTextAttachmentUti = "org.whispersystems.oversize-text-attachment"
    public static let oversizeTextAttachmentFileExtension = "txt"
    public static let unknownTestAttachmentUti = "org.whispersystems.unknown"
    public static let syncMessageFileExtension = "bin"
    // TODO: Remove this; it's unused.
    public static let lottieStickerFileExtension = "lottiesticker"
}
