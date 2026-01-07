//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol AttachmentManager {

    // MARK: - Creating Attachments from source

    /// Create attachment pointers from protos.
    /// Does no deduplication; once we download the contents of the attachment
    /// we may deduplicate and update the owner reference accordingly.
    /// Creates a reference from the owner to the attachment.
    ///
    /// Throws an error if any of the provided protos are invalid.
    func createAttachmentPointer(
        from ownedProto: OwnedAttachmentPointerProto,
        tx: DBWriteTransaction,
    ) throws

    /// Create attachment pointers from backup protos.
    /// Does no deduplication; once we download the contents of the attachment
    /// we may deduplicate and update the owner reference accordingly.
    /// Creates a reference from the owner to the attachment.
    ///
    /// - parameter uploadEra: see ``Attachment/uploadEra(backupSubscriptionId:)``.
    ///     Defines the valid lifetime of the backup upload. Derived from the subscription id.
    ///
    /// - returns errors for any of the provided protos that are invalid. Callers _must_ cancel
    /// the transaction if any error is returned; not doing so could result in writing partial invalid state.
    /// Returns an empty array on success.
    func createAttachmentPointer(
        from ownedBackupProto: OwnedAttachmentBackupPointerProto,
        uploadEra: String,
        attachmentByteCounter: BackupArchiveAttachmentByteCounter,
        tx: DBWriteTransaction,
    ) -> OwnedAttachmentBackupPointerProto.CreationError?

    /// Create attachment streams from the given data sources.
    ///
    /// May save new attachment streams, or reuse existing attachment streams if
    /// matched by content.
    ///
    /// Creates a reference from the owner to the attachments.
    func createAttachmentStream(
        from ownedDataSource: OwnedAttachmentDataSource,
        tx: DBWriteTransaction,
    ) throws

    /// Update an existing placeholder attachment with the full oversized text attachment file
    /// we restored from a backup.
    /// May reuse an existing attachment stream if matched by content, which will delete
    /// both the provided pending files and the placeholder attachment whose id was provided,
    /// pointing all its references to the existing duplicate.
    func updateAttachmentWithOversizeTextFromBackup(
        attachmentId: Attachment.IDType,
        pendingAttachment: PendingAttachment,
        tx: DBWriteTransaction,
    ) throws

    // MARK: - Quoted Replies

    func createQuotedReplyMessageThumbnail(
        from quotedReplyAttachmentDataSource: QuotedReplyAttachmentDataSource,
        owningMessageAttachmentBuilder: AttachmentReference.OwnerBuilder.MessageAttachmentBuilder,
        tx: DBWriteTransaction,
    ) throws
}
