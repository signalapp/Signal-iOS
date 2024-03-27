//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
public enum StickerType: UInt {
    case webp
    case signalLottie
    case apng
    case gif

    public static func stickerType(forContentType contentType: String?) -> StickerType {
        if let contentType = contentType {
            switch contentType {
            case OWSMimeTypeImageWebp:
                return .webp
            case OWSMimeTypeLottieSticker:
                return .signalLottie
            case OWSMimeTypeImagePng:
                return .apng
            case OWSMimeTypeImageGif:
                return .gif
            default:
                owsFailDebug("Unknown content type: \(contentType)")
                return .webp
            }
        } else {
            // Unknown contentType, assume webp.
            return .webp
        }
    }

    public var contentType: String {
        switch self {
        case .webp:
            return OWSMimeTypeImageWebp
        case .signalLottie:
            return OWSMimeTypeLottieSticker
        case .apng:
            return OWSMimeTypeImagePng
        case .gif:
            return OWSMimeTypeImageGif
        }
    }

    public var fileExtension: String {
        switch self {
        case .webp:
            return "webp"
        case .signalLottie:
            return kLottieStickerFileExtension
        case .apng:
            return "png"
        case .gif:
            return "gif"
        }
    }
}

// MARK: - StickerMetadata

// The state needed to render or send a sticker.
// Should only ever be instantiated for a sticker which is available locally.
// This might represent an "installed" sticker, a "transient" sticker (used
// to render sticker pack views for uninstalled packs) or a sticker received
// in a message.
@objc
public class StickerMetadata: NSObject {
    @objc
    public let stickerInfo: StickerInfo

    @objc
    public var packId: Data {
        stickerInfo.packId
    }

    @objc
    public var packKey: Data {
        stickerInfo.packKey
    }

    @objc
    public var packInfo: StickerPackInfo {
        StickerPackInfo(packId: packId, packKey: packKey)
    }

    @objc
    public var stickerId: UInt32 {
        stickerInfo.stickerId
    }

    @objc
    public let stickerType: StickerType

    @objc
    public let stickerDataUrl: URL

    // May contain multiple emoji.
    @objc
    public let emojiString: String?

    @objc
    public required init(stickerInfo: StickerInfo,
                         stickerType: StickerType,
                         stickerDataUrl: URL,
                         emojiString: String?) {
        self.stickerInfo = stickerInfo
        self.stickerType = stickerType
        self.stickerDataUrl = stickerDataUrl
        self.emojiString = emojiString
    }

    @objc
    public var firstEmoji: String? {
        StickerManager.firstEmoji(inEmojiString: emojiString)
    }

    @objc
    public var contentType: String {
        stickerType.contentType
    }

    @objc
    public override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? StickerMetadata else {
            return false
        }
        return stickerInfo.asKey() == other.stickerInfo.asKey()
    }

    @objc
    public override var hash: Int {
        stickerInfo.asKey().hashValue
    }
}
