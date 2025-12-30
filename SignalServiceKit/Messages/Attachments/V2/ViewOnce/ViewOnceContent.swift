//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import AVFoundation
import Foundation
public import SDWebImage

/// When presenting a view-once message, we:
/// 1. copy the displayable attachment contents to a tmp file
/// 2. delete the original attachment
/// 3. display the copied contents
///
/// This object represents the result of (1); the copied contents.
public class ViewOnceContent {

    public enum ContentType {
        case stillImage
        case animatedImage
        case video
        case loopingVideo
    }

    public let messageId: String
    public let type: ContentType

    /// File URL to a copy of the encrypted file used for display purposes.
    private let fileUrl: URL
    private let encryptionKey: Data
    private let plaintextLength: UInt32
    private let mimeType: String

    init(
        messageId: String,
        type: ContentType,
        fileUrl: URL,
        encryptionKey: Data,
        plaintextLength: UInt32,
        mimeType: String,
    ) {
        self.messageId = messageId
        self.type = type
        self.fileUrl = fileUrl
        self.encryptionKey = encryptionKey
        self.plaintextLength = plaintextLength
        self.mimeType = mimeType
    }

    deinit {
        let fileUrl = self.fileUrl
        DispatchQueue.global().async {
            try? OWSFileSystem.deleteFile(url: fileUrl)
        }
    }

    public func loadImage() throws -> UIImage {
        return try UIImage.fromEncryptedFile(
            at: fileUrl,
            attachmentKey: AttachmentKey(combinedKey: encryptionKey),
            plaintextLength: plaintextLength,
            mimeType: mimeType,
        )
    }

    public func loadYYImage() throws -> SDAnimatedImage {
        // hmac and digest are validated at download time; no need to revalidate every read.
        let data = try Cryptography.decryptFileWithoutValidating(
            at: fileUrl,
            metadata: DecryptionMetadata(
                key: AttachmentKey(combinedKey: encryptionKey),
                plaintextLength: UInt64(safeCast: plaintextLength),
            ),
        )
        guard let image = SDAnimatedImage(data: data) else {
            throw OWSAssertionError("Couldn't load image")
        }
        return image
    }

    public func loadAVAsset() throws -> AVAsset {
        return try AVAsset.fromEncryptedFile(
            at: fileUrl,
            attachmentKey: AttachmentKey(combinedKey: encryptionKey),
            plaintextLength: plaintextLength,
            mimeType: mimeType,
        )
    }
}
