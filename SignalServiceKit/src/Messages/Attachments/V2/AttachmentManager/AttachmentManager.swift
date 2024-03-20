//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol AttachmentManager {

    /// Create attachment pointers from protos.
    /// Does no deduplication; once we download the contents of the attachment
    /// we may deduplicate and update the owner reference accordingly.
    /// Creates a reference from the owner to the attachment.
    func createAttachmentPointers(
        from protos: [SSKProtoAttachmentPointer],
        owner: AttachmentReference.OwnerId,
        tx: DBWriteTransaction
    )

    /// Given an attachment proto from its sender and an owner,
    /// creates a local attachment and an owner reference to it.
    ///
    /// Throws an error if the provided proto is invalid.
    func createAttachment(
        from proto: SSKProtoAttachmentPointer,
        owner: AttachmentReference.OwnerId,
        tx: DBWriteTransaction
    ) throws

    /// Given locally sourced attachmentData and an owner,
    /// creates a local attachment and an owner reference to it.
    ///
    /// Throws an error if the provided data/mimeType is invalid.
    func createAttachment(
        rawFileData: Data,
        mimeType: String,
        owner: AttachmentReference.OwnerId,
        tx: DBWriteTransaction
    ) throws

    /// Create attachment streams from the outgoing infos and their data sources,
    /// consuming those data sources.
    /// May reuse an existing attachment stream if matched by content, and discard
    /// the data source.
    /// Creates a reference from the owner to the attachment.
    func createAttachmentStreams(
        consumingDataSourcesOf unsavedAttachmentInfos: [OutgoingAttachmentInfo],
        owner: AttachmentReference.OwnerId,
        tx: DBWriteTransaction
    ) throws

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
