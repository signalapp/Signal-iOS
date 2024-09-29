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
public class TSViewOnceContent {

    public typealias ContentType = ViewOnceContent.ContentType

    public let messageId: String
    public let type: ContentType

    fileprivate enum File {
        case decrypted(URL)
        case encrypted(URL, encryptionKey: Data, plaintextLength: UInt32)
    }
    /// Filepath to a copy of the file used for display purposes.
    private let file: File
    private let mimeType: String

    fileprivate init(
        messageId: String,
        type: ContentType,
        file: File,
        mimeType: String
    ) {
        self.messageId = messageId
        self.type = type
        self.file = file
        self.mimeType = mimeType
    }

    internal init(
        messageId: String,
        type: ContentType,
        unencryptedFileUrl: URL,
        mimeType: String
    ) {
        self.messageId = messageId
        self.type = type
        self.file = .decrypted(unencryptedFileUrl)
        self.mimeType = mimeType
    }

    internal init(
        messageId: String,
        type: ContentType,
        encryptedFileUrl: URL,
        encryptionKey: Data,
        plaintextLength: UInt32,
        mimeType: String
    ) {
        self.messageId = messageId
        self.type = type
        self.file = .encrypted(
            encryptedFileUrl,
            encryptionKey: encryptionKey,
            plaintextLength: plaintextLength
        )
        self.mimeType = mimeType
    }

    deinit {
        let fileUrl: URL = {
            switch file {
            case .decrypted(let url):
                return url
            case .encrypted(let url, _, _):
                return url
            }
        }()
        DispatchQueue.global().async {
            try? OWSFileSystem.deleteFile(url: fileUrl)
        }
    }

    public func loadImage() throws -> UIImage {
        switch file {
        case .decrypted(let url):
            guard let image = UIImage(contentsOfFile: url.path) else {
                throw OWSAssertionError("Couldn't load image")
            }
            return image
        case .encrypted(let url, let encryptionKey, let plaintextLength):
            return try UIImage.fromEncryptedFile(
                at: url,
                encryptionKey: encryptionKey,
                plaintextLength: plaintextLength,
                mimeType: mimeType
            )
        }
    }

    public func loadYYImage() throws -> YYImage {
        switch file {
        case .decrypted(let url):
            guard let image = YYImage(contentsOfFile: url.path) else {
                throw OWSAssertionError("Couldn't load image")
            }
            return image
        case .encrypted(let url, let encryptionKey, let plaintextLength):
            let data = try Cryptography.decryptFile(
                at: url,
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
    }

    public func loadAVAsset() throws -> AVAsset {
        switch file {
        case .decrypted(let url):
            return AVURLAsset(url: url)
        case .encrypted(let url, let encryptionKey, let plaintextLength):
            return try AVAsset.fromEncryptedFile(
                at: url,
                encryptionKey: encryptionKey,
                plaintextLength: plaintextLength,
                mimeType: mimeType
            )
        }

    }
}
