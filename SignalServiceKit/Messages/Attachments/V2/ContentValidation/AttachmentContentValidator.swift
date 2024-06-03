//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol PendingAttachment {
    var blurHash: String? { get }
    var sha256ContentHash: Data { get }
    var encryptedByteCount: UInt32 { get }
    var unencryptedByteCount: UInt32 { get }
    var mimeType: String { get }
    var encryptionKey: Data { get }
    var digestSHA256Ciphertext: Data { get }
    var localRelativeFilePath: String { get }
    var sourceFilename: String? { get }
    var validatedContentType: Attachment.ContentType { get }
}

public protocol AttachmentContentValidator {

    /// Validate and prepare a DataSource's contents, based on the provided mimetype.
    /// Returns a PendingAttachment with validated contents, ready to be inserted.
    /// Note the content type may be `invalid`; we can still create an Attachment from these.
    /// Errors are thrown if data reading/parsing fails.
    func validateContents(
        dataSource: DataSource,
        mimeType: String,
        sourceFilename: String?
    ) async throws -> PendingAttachment

    /// Validate and prepare an encrypted attachment file's contents, based on the provided mimetype.
    /// Returns a PendingAttachment with validated contents, ready to be inserted.
    /// Note the content type may be `invalid`; we can still create an Attachment from these.
    /// Errors are thrown if data reading/parsing/decryption fails.
    func validateContents(
        ofEncryptedFileAt fileUrl: URL,
        encryptionKey: Data,
        plaintextLength: UInt32,
        digestSHA256Ciphertext: Data,
        mimeType: String,
        sourceFilename: String?
    ) async throws -> PendingAttachment
}
