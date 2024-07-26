//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

import libwebp
import YYImage

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
    public static func ows_hasStickerLikeProperties(metadata: ImageMetadata) -> Bool {
        Data.ows_hasStickerLikeProperties(withImageMetadata: metadata)
    }

    @objc
    @available(swift, obsoleted: 1)
    public static func ows_hasStickerLikeProperties(withPath filePath: String) -> Bool {
        Data.ows_hasStickerLikeProperties(withPath: filePath)
    }
}
