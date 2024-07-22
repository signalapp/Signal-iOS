//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
public enum StickerType: UInt {
    case webp
    case apng
    case gif

    public static func stickerType(forContentType contentType: String?) -> StickerType {
        if let contentType = contentType {
            switch contentType {
            case MimeType.imageWebp.rawValue:
                return .webp
            case MimeType.imagePng.rawValue:
                return .apng
            case MimeType.imageGif.rawValue:
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

    public var mimeType: String {
        switch self {
        case .webp:
            return MimeType.imageWebp.rawValue
        case .apng:
            return MimeType.imagePng.rawValue
        case .gif:
            return MimeType.imageGif.rawValue
        }
    }

    public var fileExtension: String {
        switch self {
        case .webp:
            return "webp"
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
public protocol StickerMetadata: Hashable {
    var stickerInfo: StickerInfo { get }
    var stickerType: StickerType { get }
    // May contain multiple emoji.
    var emojiString: String? { get }

    /// Check if the sticker's data is valid, if applicable.
    func isValidImage() -> Bool

    /// Read the sticker data off disk into memory, typically for display or sending.
    func readStickerData() throws -> Data
}

extension StickerMetadata {
    public var packId: Data {
        stickerInfo.packId
    }

    public var packKey: Data {
        stickerInfo.packKey
    }

    public var packInfo: StickerPackInfo {
        StickerPackInfo(packId: packId, packKey: packKey)
    }

    public var stickerId: UInt32 {
        stickerInfo.stickerId
    }

    public var firstEmoji: String? {
        StickerManager.firstEmoji(in: emojiString ?? "")
    }

    public var mimeType: String {
        stickerType.mimeType
    }
}

public class DecryptedStickerMetadata: StickerMetadata {

    public let stickerInfo: StickerInfo
    public let stickerType: StickerType
    public let stickerDataUrl: URL
    public let emojiString: String?

    public init(
        stickerInfo: StickerInfo,
        stickerType: StickerType,
        stickerDataUrl: URL,
        emojiString: String?
    ) {
        self.stickerInfo = stickerInfo
        self.stickerType = stickerType
        self.stickerDataUrl = stickerDataUrl
        self.emojiString = emojiString
    }

    public func isValidImage() -> Bool {
        return Data.ows_isValidImage(at: stickerDataUrl, mimeType: mimeType)
    }

    public func readStickerData() throws -> Data {
        return try Data(contentsOf: stickerDataUrl)
    }

    public static func == (lhs: DecryptedStickerMetadata, rhs: DecryptedStickerMetadata) -> Bool {
        return lhs.stickerInfo.asKey() == rhs.stickerInfo.asKey()
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(stickerInfo.asKey().hashValue)
    }
}

public class EncryptedStickerMetadata: StickerMetadata {

    public let stickerInfo: StickerInfo
    public let stickerType: StickerType
    public let emojiString: String?

    public let encryptedStickerDataUrl: URL
    public let encryptionKey: Data
    public let plaintextLength: UInt32

    public init(
        stickerInfo: StickerInfo,
        stickerType: StickerType,
        emojiString: String?,
        encryptedStickerDataUrl: URL,
        encryptionKey: Data,
        plaintextLength: UInt32
    ) {
        self.stickerInfo = stickerInfo
        self.stickerType = stickerType
        self.emojiString = emojiString
        self.encryptedStickerDataUrl = encryptedStickerDataUrl
        self.encryptionKey = encryptionKey
        self.plaintextLength = plaintextLength
    }

    public func isValidImage() -> Bool {
        /// We validate data prior to encryption; no need to re-validate at read time.
        return true
    }

    public func readStickerData() throws -> Data {
        return try Cryptography.decryptFile(
            at: encryptedStickerDataUrl,
            metadata: .init(
                key: encryptionKey,
                plaintextLength: Int(plaintextLength)
            )
        )
    }

    public static func == (lhs: EncryptedStickerMetadata, rhs: EncryptedStickerMetadata) -> Bool {
        return lhs.stickerInfo.asKey() == rhs.stickerInfo.asKey()
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(stickerInfo.asKey().hashValue)
    }
}

extension EncryptedStickerMetadata {

    public static func from(
        attachment: AttachmentStream,
        stickerInfo: StickerInfo,
        stickerType: StickerType,
        emojiString: String?
    ) -> EncryptedStickerMetadata {
        return .init(
            stickerInfo: stickerInfo,
            stickerType: stickerType,
            emojiString: emojiString,
            encryptedStickerDataUrl: attachment.fileURL,
            encryptionKey: attachment.attachment.encryptionKey,
            plaintextLength: attachment.info.unencryptedByteCount
        )
    }
}
