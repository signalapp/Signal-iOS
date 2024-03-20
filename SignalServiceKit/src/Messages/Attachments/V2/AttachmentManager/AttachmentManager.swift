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

    /// Given an attachment proto from its sender,
    /// returns a builder for creating the attachment locally.
    ///
    /// The attachment info needed to construct the owner object
    /// is available immediately, but the caller _must_ finalize
    /// the builder for the attachment to be created.
    ///
    /// Callers should only assume the attachment (if any) exists
    /// after finalizing.
    ///
    /// Throws an error if the provided proto is invalid.
    func createAttachmentBuilder(
        from proto: SSKProtoAttachmentPointer,
        tx: DBWriteTransaction
    ) throws -> OwnedAttachmentBuilder<Void>

    /// Given locally sourced attachmentData,
    /// returns a builder for creating the attachment locally.
    ///
    /// The attachment info needed to construct the owner object
    /// is available immediately, but the caller _must_ finalize
    /// the builder for the attachment to be created.
    ///
    /// Callers should only assume the attachment (if any) exists
    /// after finalizing.
    ///
    /// Throws an error if the provided data/mimeType is invalid.
    func createAttachmentBuilder(
        rawFileData: Data,
        mimeType: String,
        tx: DBWriteTransaction
    ) throws -> OwnedAttachmentBuilder<Void>

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

    /// Given an original message available locally, reurns a builder
    /// for creating a thumbnail attachment for quoted replies.
    ///
    /// If the original lacks an attachment, returns nil. If the original has an
    /// attachment that can't be thumbnailed, returns an appropriate
    /// info without creating a new attachment.
    ///
    /// The attachment info needed to construct the reply message
    /// is available immediately, but the caller _must_ finalize
    /// the builder to guarantee the attachment is created.
    func newQuotedReplyMessageThumbnailBuilder(
        originalMessage: TSMessage,
        tx: DBReadTransaction
    ) -> OwnedAttachmentBuilder<OWSAttachmentInfo>?

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
