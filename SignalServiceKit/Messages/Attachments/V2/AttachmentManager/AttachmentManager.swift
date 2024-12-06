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
        tx: DBWriteTransaction
    ) -> [OwnedAttachmentBackupPointerProto.CreationError]

    /// Create attachment streams from the data sources, consuming those data sources.
    /// May reuse an existing attachment stream if matched by content, and discard
    /// the data source.
    /// Creates a reference from the owner to the attachments.
    func createAttachmentStreams(
        consuming dataSources: [OwnedAttachmentDataSource],
        tx: DBWriteTransaction
    ) throws

    // MARK: - Quoted Replies

    /// Given an original message available locally, returns metadata
    /// supplied to a TSQuotedReply, which distinguishes "stubs"
    /// (attachments that cannot be thumbnail-ed) from thumbnails.
    ///
    /// If the original lacks an attachment, returns nil. If the original has an
    /// attachment that can't be thumbnailed, returns stub metadata.
    ///
    /// Callers should call ``createQuotedReplyMessageThumbnail`` to
    /// actually construct the attachment once the owning message exists.
    func quotedReplyAttachmentInfo(
        originalMessage: TSMessage,
        tx: DBReadTransaction
    ) -> QuotedAttachmentInfo?

    /// Given a quote thumbnail source, creates a builder for a thumbnail
    /// attachment (if necessary) and an owner reference to it.
    func createQuotedReplyMessageThumbnailBuilder(
        from dataSource: QuotedReplyAttachmentDataSource,
        tx: DBWriteTransaction
    ) -> OwnedAttachmentBuilder<QuotedAttachmentInfo>

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

    /// Create an attachment stream from a data source, consuming that data source.
    /// May reuse an existing attachment stream if matched by content, and discard
    /// the data source.
    /// Creates a reference from the owner to the attachment.
    public func createAttachmentStream(
        consuming dataSource: OwnedAttachmentDataSource,
        tx: DBWriteTransaction
    ) throws {
        try createAttachmentStreams(
            consuming: [dataSource],
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
                    consuming: .init(dataSource: dataSource, owner: owner),
                    tx: innerTx
                )
            }
        )
    }
}
