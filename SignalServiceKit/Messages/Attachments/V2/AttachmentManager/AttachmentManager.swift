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
        from protos: [SSKProtoAttachmentPointer],
        owner: AttachmentReference.OwnerBuilder,
        tx: DBWriteTransaction
    ) throws

    /// Create attachment streams from the data sources, consuming those data sources.
    /// May reuse an existing attachment stream if matched by content, and discard
    /// the data source.
    /// Creates a reference from the owner to the attachments.
    func createAttachmentStreams(
        consuming dataSources: [AttachmentDataSource],
        owner: AttachmentReference.OwnerBuilder,
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
    ) -> OWSAttachmentInfo?

    /// Given an original message available locally and a new message
    /// quoting that original, creates a thumbnail attachment and an owner
    /// reference to it.
    ///
    /// If the original lacks an attachment, does nothing.
    /// If the original has an attachment that can't be thumbnailed, does nothing.
    ///
    /// Only throws if a thumbnail _should_ have been created but failed.
    func createQuotedReplyMessageThumbnail(
        originalMessage: TSMessage,
        quotedReplyMessageId: Int64,
        tx: DBWriteTransaction
    ) throws

    // MARK: - Removing Attachments

    /// Remove an attachment from an owner.
    /// Will only delete the attachment if this is the last owner.
    /// Typically because the owner has been deleted.
    func removeAttachment(
        _ attachment: TSResource,
        from owner: AttachmentReference.OwnerId,
        tx: DBWriteTransaction
    )

    /// Removed all attachments of the provided types from the provided owners.
    /// Will only delete attachments if they are left without any owners.
    func removeAllAttachments(
        from owners: [AttachmentReference.OwnerId],
        tx: DBWriteTransaction
    )
}

// MARK: - Array<->Single object convenience methods

extension AttachmentManager {

    /// Given an attachment proto from its sender and an owner,
    /// creates a local attachment and an owner reference to it.
    ///
    /// Throws an error if the provided proto is invalid.
    public func createAttachmentPointer(
        from proto: SSKProtoAttachmentPointer,
        owner: AttachmentReference.OwnerBuilder,
        tx: DBWriteTransaction
    ) throws {
        try createAttachmentPointers(
            from: [proto],
            owner: owner,
            tx: tx
        )
    }

    /// Create an attachment stream from a data source, consuming that data source.
    /// May reuse an existing attachment stream if matched by content, and discard
    /// the data source.
    /// Creates a reference from the owner to the attachment.
    public func createAttachmentStream(
        consuming dataSource: AttachmentDataSource,
        owner: AttachmentReference.OwnerBuilder,
        tx: DBWriteTransaction
    ) throws {
        try createAttachmentStreams(
            consuming: [dataSource],
            owner: owner,
            tx: tx
        )
    }
}
