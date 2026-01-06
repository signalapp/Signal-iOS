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

public struct PendingAttachment {
    let blurHash: String?
    let sha256ContentHash: Data
    let encryptedByteCount: UInt32
    let unencryptedByteCount: UInt32
    let mimeType: String
    let encryptionKey: Data
    let digestSHA256Ciphertext: Data
    let localRelativeFilePath: String
    private(set) var renderingFlag: AttachmentReference.RenderingFlag
    let sourceFilename: String?
    let validatedContentType: Attachment.ContentType
    let orphanRecordId: OrphanedAttachmentRecord.RowId

    mutating func removeBorderlessRenderingFlagIfPresent() {
        switch renderingFlag {
        case .borderless:
            renderingFlag = .default
        default:
            return
        }
    }
}

public struct RevalidatedAttachment {
    let validatedContentType: Attachment.ContentType
    /// Revalidation might _change_ the mimeType we report.
    let mimeType: String
    let blurHash: String?
    /// Orphan record for any created ancillary files, such as the audio waveform.
    let orphanRecordId: OrphanedAttachmentRecord.RowId
}

public protocol ValidatedInlineMessageBody {
    /// The (possibly truncated) body to inline in the message.
    var inlinedBody: MessageBody { get }
}

public protocol ValidatedMessageBody: ValidatedInlineMessageBody {
    /// If the original text didn't fit inline, the pending attachment that
    /// should be used to create the oversize text Attachment.
    var oversizeText: PendingAttachment? { get }
}

public protocol AttachmentContentValidator {

    /// Validate and prepare a DataSource's contents, based on the provided mimetype.
    /// Returns a PendingAttachment with validated contents, ready to be inserted.
    /// Note the content type may be `invalid`; we can still create an Attachment from these.
    /// Errors are thrown if data reading/parsing fails.
    func validateDataSourceContents(
        _ dataSource: DataSourcePath,
        mimeType: String,
        renderingFlag: AttachmentReference.RenderingFlag,
        sourceFilename: String?,
    ) async throws -> PendingAttachment

    /// Validate and prepare a Data's contents, based on the provided mimetype.
    /// Returns a PendingAttachment with validated contents, ready to be inserted.
    /// Note the content type may be `invalid`; we can still create an Attachment from these.
    /// Errors are thrown if data parsing fails.
    func validateDataContents(
        _ data: Data,
        mimeType: String,
        renderingFlag: AttachmentReference.RenderingFlag,
        sourceFilename: String?,
    ) async throws -> PendingAttachment

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
        attachmentKey: AttachmentKey,
        plaintextLength: UInt32?,
        integrityCheck: AttachmentIntegrityCheck,
        mimeType: String,
        renderingFlag: AttachmentReference.RenderingFlag,
        sourceFilename: String?,
    ) async throws -> PendingAttachment

    /// Just validate an encrypted attachment file's contents, based on the provided mimetype.
    /// Returns the validated content type;  does no integrityCheck validation or primary file copy preparation.
    /// Errors are thrown if data reading/parsing/decryption fails.
    func reValidateContents(
        ofEncryptedFileAt fileUrl: URL,
        attachmentKey: AttachmentKey,
        plaintextLength: UInt32,
        mimeType: String,
    ) async throws -> RevalidatedAttachment

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
    func validateBackupMediaFileContents(
        fileUrl: URL,
        outerDecryptionData: DecryptionMetadata,
        innerDecryptionData: DecryptionMetadata,
        finalAttachmentKey: AttachmentKey,
        mimeType: String,
        renderingFlag: AttachmentReference.RenderingFlag,
        sourceFilename: String?,
    ) async throws -> PendingAttachment

    /// Truncates the provided message body if necessary for inlining in a message,
    /// dropping any remaining text even if it might otherwise fit in an oversized text
    /// attachment.
    /// It is much preferred to use ``prepareOversizeTextsIfNeeded(from:)``;
    /// this method only exists as a temporary solution for callsites that process bodies
    /// from within inescapable write transactions and therefore cannot do the
    /// double-commit necessary to prepare an oversize text Attachment.
    /// (This method takes a transaction, despite not using it, to nudge callers.
    /// If you're not already in a write tx, you should use prepareOversizeTextsIfNeeded).
    func truncatedMessageBodyForInlining(
        _ body: MessageBody,
        tx: DBWriteTransaction,
    ) -> ValidatedInlineMessageBody

    /// If the provided message body is large enough to require an oversize text
    /// attachment, creates a pending one, alongside the truncated message body.
    /// If not, just returns the message body as is.
    ///
    /// - parameter encryptionKeys: The encryption key to use for the pending attachment
    /// file to create for oversize text, if any. If there is no provided encryption key for a given MessageBody
    /// input, a random key will be used.
    func prepareOversizeTextsIfNeeded<Key: Hashable>(
        from texts: [Key: MessageBody],
        attachmentKeys: [Key: AttachmentKey],
    ) async throws -> [Key: ValidatedMessageBody]

    /// Build a `QuotedReplyAttachmentDataSource` for a reply to a message with the provided attachment.
    /// Throws an error if the provided attachment is non-visual, or if data reading/writing fails.
    func prepareQuotedReplyThumbnail(
        fromOriginalAttachment: AttachmentStream,
        originalReference: AttachmentReference,
    ) async throws -> QuotedReplyAttachmentDataSource

    /// Build a `PendingAttachment` for a reply to a message with the provided attachment stream.
    /// Throws an error if the provided attachment is non-visual, or if data reading/writing fails.
    func prepareQuotedReplyThumbnail(
        fromOriginalAttachmentStream: AttachmentStream,
    ) async throws -> PendingAttachment
}

extension AttachmentContentValidator {

    public func prepareOversizeTextIfNeeded(
        _ body: MessageBody,
    ) async throws -> ValidatedMessageBody {
        return try await prepareOversizeTextsIfNeeded(
            from: ["": body],
            attachmentKeys: [:],
        ).values.first!
    }
}
