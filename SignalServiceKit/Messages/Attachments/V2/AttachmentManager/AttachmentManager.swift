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
    func createAttachmentPointers(
        from protos: [OwnedAttachmentPointerProto],
        tx: DBWriteTransaction
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
    func createAttachmentPointers(
        from backupProtos: [OwnedAttachmentBackupPointerProto],
        uploadEra: String,
        attachmentByteCounter: BackupArchiveAttachmentByteCounter,
        tx: DBWriteTransaction
    ) -> [OwnedAttachmentBackupPointerProto.CreationError]

    /// Create attachment streams from the given data sources.
    ///
    /// May save new attachment streams, or reuse existing attachment streams if
    /// matched by content.
    ///
    /// Creates a reference from the owner to the attachments.
    func createAttachmentStreams(
        from dataSources: [OwnedAttachmentDataSource],
        tx: DBWriteTransaction
    ) throws

    /// Update an existing placeholder attachment with the full oversized text attachment file
    /// we restored from a backup.
    /// May reuse an existing attachment stream if matched by content, which will delete
    /// both the provided pending files and the placeholder attachment whose id was provided,
    /// pointing all its references to the existing duplicate.
    func updateAttachmentWithOversizeTextFromBackup(
        attachmentId: Attachment.IDType,
        pendingAttachment: PendingAttachment,
        tx: DBWriteTransaction
    ) throws

    // MARK: - Quoted Replies

    func createQuotedReplyMessageThumbnail(
        from quotedReplyAttachmentDataSource: QuotedReplyAttachmentDataSource,
        owningMessageAttachmentBuilder: AttachmentReference.OwnerBuilder.MessageAttachmentBuilder,
        tx: DBWriteTransaction,
    ) throws

    // MARK: - Removing Attachments

    /// Remove an attachment from an owner.
    /// Will only delete the attachment if this is the last owner.
    /// Typically because the owner has been deleted.
    func removeAttachment(
        reference: AttachmentReference,
        tx: DBWriteTransaction
    ) throws

    /// Removed all attachments of the provided types from the provided owners.
    /// Will only delete attachments if they are left without any owners.
    func removeAllAttachments(
        from owners: [AttachmentReference.OwnerId],
        tx: DBWriteTransaction
    ) throws
}

// MARK: - Array<->Single object convenience methods

extension AttachmentManager {

    /// Given an attachment proto from its sender and an owner,
    /// creates a local attachment and an owner reference to it.
    ///
    /// Throws an error if the provided proto is invalid.
    public func createAttachmentPointer(
        from proto: OwnedAttachmentPointerProto,
        tx: DBWriteTransaction
    ) throws {
        try createAttachmentPointers(
            from: [proto],
            tx: tx
        )
    }

    /// Create attachment streams from the given data sources.
    ///
    /// May save new attachment streams, or reuse existing attachment streams if
    /// matched by content.
    ///
    /// Creates a reference from the owner to the attachment.
    public func createAttachmentStream(
        from dataSource: OwnedAttachmentDataSource,
        tx: DBWriteTransaction
    ) throws {
        try createAttachmentStreams(
            from: [dataSource],
            tx: tx
        )
    }
}

// MARK: - OwnedAttachmentBuilder convenience

extension AttachmentManager {

    public func createAttachmentPointerBuilder(
        from proto: SSKProtoAttachmentPointer,
        tx: DBWriteTransaction
    ) throws -> OwnedAttachmentBuilder<Void> {
        return OwnedAttachmentBuilder<Void>(
            finalize: { [self] owner, innerTx in
                return try self.createAttachmentPointer(
                    from: .init(proto: proto, owner: owner),
                    tx: innerTx
                )
            }
        )
    }

    public func createAttachmentStreamBuilder(
        from dataSource: AttachmentDataSource,
        tx: DBWriteTransaction
    ) throws -> OwnedAttachmentBuilder<Void> {
        return OwnedAttachmentBuilder<Void>(
            finalize: { [self] owner, innerTx in
                return try self.createAttachmentStream(
                    from: OwnedAttachmentDataSource(dataSource: dataSource, owner: owner),
                    tx: innerTx
                )
            }
        )
    }
}
