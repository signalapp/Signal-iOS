//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import AVFoundation
import Foundation
public import YYImage

/// When presenting a view-once message, we:
/// 1. copy the displayable attachment contents to a tmp file
/// 2. delete the original attachment
/// 3. display the copied contents
///
/// This object represents the result of (1); the copied contents.
public class ViewOnceContent {

    public enum ContentType {
        case stillImage, animatedImage, video, loopingVideo
    }

    public let messageId: String
    public let type: ContentType

    /// File URL to a copy of the encrypted file used for display purposes.
    fileprivate let fileUrl: URL
    fileprivate let encryptionKey: Data
    fileprivate let plaintextLength: UInt32
    fileprivate let mimeType: String

    init(
        messageId: String,
        type: ContentType,
        fileUrl: URL,
        encryptionKey: Data,
        plaintextLength: UInt32,
        mimeType: String
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
            encryptionKey: encryptionKey,
            plaintextLength: plaintextLength,
            mimeType: mimeType
        )
    }

    public func loadYYImage() throws -> YYImage {
        // hmac and digest are validated at download time; no need to revalidate every read.
        let data = try Cryptography.decryptFileWithoutValidating(
            at: fileUrl,
            metadata: .init(
                key: encryptionKey,
                plaintextLength: Int(plaintextLength)
            )
        )
        guard let image = YYImage(data: data) else {
            throw OWSAssertionError("Couldn't load image")
        }
        return image
    }

    public func loadAVAsset() throws -> AVAsset {
        return try AVAsset.fromEncryptedFile(
            at: fileUrl,
            encryptionKey: encryptionKey,
            plaintextLength: plaintextLength,
            mimeType: mimeType
        )
    }
}
