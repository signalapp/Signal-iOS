//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// When validating a downloaded attachment, we might either have a plaintext
/// hash or encrypted blob hash (digest) to validate against, either of which ensure
/// the file we download is the same as the one the sender intended (or ourselves,
/// if we are the sender).
public enum AttachmentIntegrityCheck: Equatable {
    case digestSHA256Ciphertext(Data)
    case sha256ContentHash(Data)

    var isEmpty: Bool {
        switch self {
        case .digestSHA256Ciphertext(let data):
            return data.isEmpty
        case .sha256ContentHash(let data):
            return data.isEmpty
        }
    }
}

public protocol PendingAttachment {
    var blurHash: String? { get }
    var sha256ContentHash: Data { get }
    var encryptedByteCount: UInt32 { get }
    var unencryptedByteCount: UInt32 { get }
    var mimeType: String { get }
    var encryptionKey: Data { get }
    var digestSHA256Ciphertext: Data { get }
    var localRelativeFilePath: String { get }
    var renderingFlag: AttachmentReference.RenderingFlag { get }
    var sourceFilename: String? { get }
    var validatedContentType: Attachment.ContentType { get }
    var orphanRecordId: OrphanedAttachmentRecord.IDType { get }

    mutating func removeBorderlessRenderingFlagIfPresent()
}

public protocol RevalidatedAttachment {
    var validatedContentType: Attachment.ContentType { get }
    /// Revalidation might _change_ the mimeType we report.
    var mimeType: String { get }
    var blurHash: String? { get }
    /// Orphan record for any created ancillary files, such as the audio waveform.
    var orphanRecordId: OrphanedAttachmentRecord.IDType { get }
}

public enum ValidatedMessageBody {
    /// The original body was small enough to send as-is.
    case inline(MessageBody)
    /// The original body was too large; we truncated and created an attachment with the untruncated text.
    case oversize(truncated: MessageBody, fullsize: PendingAttachment)
}

public protocol AttachmentContentValidator {

    /// Validate and prepare a DataSource's contents, based on the provided mimetype.
    /// Returns a PendingAttachment with validated contents, ready to be inserted.
    /// Note the content type may be `invalid`; we can still create an Attachment from these.
    /// Errors are thrown if data reading/parsing fails.
    ///
    /// - Parameter  shouldConsume: If true, the source file will be deleted and the DataSource
    /// consumed after validation is complete; otherwise the source file will be left as-is.
    func validateContents(
        dataSource: DataSource,
        shouldConsume: Bool,
        mimeType: String,
        renderingFlag: AttachmentReference.RenderingFlag,
        sourceFilename: String?
    ) throws -> PendingAttachment

    /// Validate and prepare a Data's contents, based on the provided mimetype.
    /// Returns a PendingAttachment with validated contents, ready to be inserted.
    /// Note the content type may be `invalid`; we can still create an Attachment from these.
    /// Errors are thrown if data parsing fails.
    func validateContents(
        data: Data,
        mimeType: String,
        renderingFlag: AttachmentReference.RenderingFlag,
        sourceFilename: String?
    ) throws -> PendingAttachment

    /// Validate and prepare an encrypted attachment file's contents, based on the provided mimetype.
    /// Returns a PendingAttachment with validated contents, ready to be inserted.
    /// Note the content type may be `invalid`; we can still create an Attachment from these.
    /// Errors are thrown if data reading/parsing/decryption fails.
    ///
    /// - Parameter plaintextLength: If provided, the decrypted file will be truncated
    /// after this length. If nil, it is assumed the encrypted file has no custom padding (anything besides PKCS7)
    /// and will not be truncated after decrypting.
    func validateDownloadedContents(
        ofEncryptedFileAt fileUrl: URL,
        encryptionKey: Data,
        plaintextLength: UInt32?,
        integrityCheck: AttachmentIntegrityCheck,
        mimeType: String,
        renderingFlag: AttachmentReference.RenderingFlag,
        sourceFilename: String?
    ) throws -> PendingAttachment

    /// Just validate an encrypted attachment file's contents, based on the provided mimetype.
    /// Returns the validated content type;  does no integrityCheck validation or primary file copy preparation.
    /// Errors are thrown if data reading/parsing/decryption fails.
    func reValidateContents(
        ofEncryptedFileAt fileUrl: URL,
        encryptionKey: Data,
        plaintextLength: UInt32,
        mimeType: String
    ) throws -> RevalidatedAttachment

    /// Validate and prepare a backup media file's contents, based on the provided mimetype.
    /// Returns a PendingAttachment with validated contents, ready to be inserted.
    /// Note the content type may be `invalid`; we can still create an Attachment from these.
    /// Errors are thrown if data reading/parsing/decryption fails.
    ///
    /// Unlike attachments from the live service, integrityCheck is not required; we can guarantee
    /// correctness for backup media files since they come from the local user.
    /// 
    /// Unlike transit tier attachments, backup attachments are encrypted twice: once when uploaded
    /// to the transit tier, and again when copied to the media tier.  This means validating media tier
    /// attachments required decrypting the file twice to allow validating the actual contents of the attachment.
    ///
    /// Strictly speaking we don't usually need content type validation either, but the set of valid
    /// contents can change over time so it is best to re-validate.
    ///
    /// - Parameter outerDecryptionData: The media tier decryption metadata use as the outer layer of encryption.
    /// - Parameter innerDecryptionData: The transit tier decryption metadata.
    /// - Parameter finalEncryptionKey: The encryption key used to encrypt the file in it's final destination.  If the finalEncryptionKey
    /// matches the encryption key in `innerEncryptionData`, this re-encryption will be skipped.
    func validateContents(
        ofBackupMediaFileAt fileUrl: URL,
        outerDecryptionData: DecryptionMetadata,
        innerDecryptionData: DecryptionMetadata,
        finalEncryptionKey: Data,
        mimeType: String,
        renderingFlag: AttachmentReference.RenderingFlag,
        sourceFilename: String?
    ) throws -> PendingAttachment

    /// If the provided message body is large enough to require an oversize text
    /// attachment, creates a pending one, alongside the truncated message body.
    /// If not, just returns the message body as is.
    func prepareOversizeTextsIfNeeded<Key: Hashable>(
        from texts: [Key: MessageBody]
    ) throws -> [Key: ValidatedMessageBody]

    /// Build a `QuotedReplyAttachmentDataSource` for a reply to a message with the provided attachment.
    /// Throws an error if the provided attachment is non-visual, or if data reading/writing fails.
    func prepareQuotedReplyThumbnail(
        fromOriginalAttachment: AttachmentStream,
        originalReference: AttachmentReference
    ) throws -> QuotedReplyAttachmentDataSource

    /// Build a `PendingAttachment` for a reply to a message with the provided attachment stream.
    /// Throws an error if the provided attachment is non-visual, or if data reading/writing fails.
    func prepareQuotedReplyThumbnail(
        fromOriginalAttachmentStream: AttachmentStream
    ) throws -> PendingAttachment
}

extension AttachmentContentValidator {

    public func validateContents(
        dataSource: DataSource,
        shouldConsume: Bool,
        mimeType: String,
        renderingFlag: AttachmentReference.RenderingFlag,
        sourceFilename: String?
    ) throws -> AttachmentDataSource {
        return .from(pendingAttachment: try self.validateContents(
            dataSource: dataSource,
            shouldConsume: shouldConsume,
            mimeType: mimeType,
            renderingFlag: renderingFlag,
            sourceFilename: sourceFilename
        ))
    }

    public func validateContents(
        data: Data,
        mimeType: String,
        renderingFlag: AttachmentReference.RenderingFlag,
        sourceFilename: String?
    ) throws -> AttachmentDataSource {
        return .from(pendingAttachment: try self.validateContents(
            data: data,
            mimeType: mimeType,
            renderingFlag: renderingFlag,
            sourceFilename: sourceFilename
        ))
    }
}
