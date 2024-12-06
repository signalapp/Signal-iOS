//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum AttachmentInsertError: Error {
    /// An existing attachment was found with the same plaintext hash, making the new
    /// attachment a duplicate. Callers should instead create a new owner reference to
    /// the same existing attachment.
    case duplicatePlaintextHash(existingAttachmentId: Attachment.IDType)
    /// An existing attachment was found with the same media name, making the new
    /// attachment a duplicate. Callers should instead create a new owner reference to
    /// the same existing attachment and possibly update it with any stream info.
    case duplicateMediaName(existingAttachmentId: Attachment.IDType)
}

public protocol AttachmentStore {

    /// Fetch all references for the provided owners.
    /// Results are unordered.
    func fetchReferences(
        owners: [AttachmentReference.OwnerId],
        tx: DBReadTransaction
    ) -> [AttachmentReference]

    /// Fetch all references for the provider message owner row id.
    /// Results are unordered.
    func fetchAllReferences(
        owningMessageRowId: Int64,
        tx: DBReadTransaction
    ) -> [AttachmentReference]

    /// Fetch attachments by id.
    func fetch(
        ids: [Attachment.IDType],
        tx: DBReadTransaction
    ) -> [Attachment]

    /// Fetch attachment by plaintext hash. There can be only one match.
    func fetchAttachment(
        sha256ContentHash: Data,
        tx: DBReadTransaction
    ) -> Attachment?

    /// Fetch attachment by media name. There can be only one match.
    func fetchAttachment(
        mediaName: String,
        tx: DBReadTransaction
    ) -> Attachment?

    /// Enumerate all references to a given attachment id, calling the block for each one.
    /// Blocks until all references have been enumerated.
    func enumerateAllReferences(
        toAttachmentId: Attachment.IDType,
        tx: DBReadTransaction,
        block: (AttachmentReference) -> Void
    ) throws

    /// Enumerate all attachments with non-nil media names, calling the block for each one.
    /// Blocks until all attachments have been enumerated.
    func enumerateAllAttachmentsWithMediaName(
        tx: DBReadTransaction,
        block: (Attachment) throws -> Void
    ) throws

    /// Return all attachments that are themselves quoted replies
    /// of another attachment; provide the original attachment they point to.
    func allQuotedReplyAttachments(
        forOriginalAttachmentId: Attachment.IDType,
        tx: DBReadTransaction
    ) throws -> [Attachment]

    /// For each unique sticker pack id present in message sticker attachments, return
    /// the oldest message reference (by message insertion order) to that sticker attachment.
    ///
    /// Not very efficient; don't put this query on the hot path for anything.
    func oldestStickerPackReferences(
        tx: DBReadTransaction
    ) throws -> [AttachmentReference.Owner.MessageSource.StickerMetadata]

    // MARK: - Writes

    /// Create a new ownership reference, copying properties of an existing reference.
    ///
    /// Copies the database row directly, only modifying the owner and isPastEditRevision columns.
    /// IMPORTANT: also copies the receivedAtTimestamp!
    ///
    /// Fails if the provided new owner isn't of the same type as the original
    /// reference; e.g. trying to duplicate a link preview as a sticker, or if the new
    /// owner is not in the same thread as the prior owner.
    /// Those operations require the explicit creation of a new owner.
    func duplicateExistingMessageOwner(
        _ existingOwnerSource: AttachmentReference.Owner.MessageSource,
        with reference: AttachmentReference,
        newOwnerMessageRowId: Int64,
        newOwnerThreadRowId: Int64,
        newOwnerIsPastEditRevision: Bool,
        tx: DBWriteTransaction
    ) throws

    /// Create a new ownership reference, copying properties of an existing reference.
    ///
    /// Copies the database row directly, only modifying the owner column.
    /// IMPORTANT: also copies the createdTimestamp!
    func duplicateExistingThreadOwner(
        _ existingOwnerSource: AttachmentReference.Owner.ThreadSource,
        with reference: AttachmentReference,
        newOwnerThreadRowId: Int64,
        tx: DBWriteTransaction
    ) throws

    /// Update the received at timestamp on a reference.
    /// Used for edits which update the received timestamp on an existing message.
    func update(
        _ reference: AttachmentReference,
        withReceivedAtTimestamp: UInt64,
        tx: DBWriteTransaction
    ) throws

    func updateAttachmentAsDownloaded(
        from source: QueuedAttachmentDownloadRecord.SourceType,
        id: Attachment.IDType,
        validatedMimeType: String,
        streamInfo: Attachment.StreamInfo,
        tx: DBWriteTransaction
    ) throws

    func updateAttachmentAsFailedToDownload(
        from source: QueuedAttachmentDownloadRecord.SourceType,
        id: Attachment.IDType,
        timestamp: UInt64,
        tx: DBWriteTransaction
    ) throws

    /// Update an attachment after revalidating.
    func updateAttachment(
        _ attachment: Attachment,
        revalidatedContentType contentType: Attachment.ContentType,
        mimeType: String,
        blurHash: String?,
        tx: DBWriteTransaction
    ) throws

    /// Update an attachment when we have a media name collision.
    /// Call this IFF the existing attachment has a media name but not stream info
    /// (if it was restored from a backup), but the new copy has stream
    /// info that we should keep by merging into the existing attachment.
    func merge(
        streamInfo: Attachment.StreamInfo,
        into attachment: Attachment,
        validatedMimeType: String,
        tx: DBWriteTransaction
    ) throws

    func addOwner(
        _ reference: AttachmentReference.ConstructionParams,
        for attachmentId: Attachment.IDType,
        tx: DBWriteTransaction
    ) throws

    /// Removes all owner edges to the provided attachment that
    /// have the provided owner type and id.
    /// Will delete multiple instances if the same owner has multiple
    /// edges of the given type to the given attachment (e.g. an image
    /// appears twice as a body attachment on a given message).
    func removeAllOwners(
        withId owner: AttachmentReference.OwnerId,
        for attachmentId: Attachment.IDType,
        tx: DBWriteTransaction
    ) throws

    /// Removes a single owner edge to the provided attachment that
    /// have the provided owner metadata.
    /// Will delete only delete the one given edge even if the same owner
    /// has multiple edges to the same attachment.
    func removeOwner(
        reference: AttachmentReference,
        tx: DBWriteTransaction
    ) throws

    /// Throws ``AttachmentInsertError.duplicatePlaintextHash`` if an existing
    /// attachment is found with the same plaintext hash.
    /// May throw other errors with less strict typing if database operations fail.
    func insert(
        _ attachment: Attachment.ConstructionParams,
        reference: AttachmentReference.ConstructionParams,
        tx: DBWriteTransaction
    ) throws

    /// Remove all owners of thread types (wallpaper and global wallpaper owners).
    /// Will also delete any attachments that become unowned, like any other deletion.
    func removeAllThreadOwners(tx: DBWriteTransaction) throws

    // MARK: - Thread Merging

    func updateMessageAttachmentThreadRowIdsForThreadMerge(
        fromThreadRowId: Int64,
        intoThreadRowId: Int64,
        tx: DBWriteTransaction
    ) throws
}

// MARK: - Convenience

extension AttachmentStore {

    /// Fetch all references for the provided owner.
    /// Results are unordered.
    public func fetchReferences(
        owner: AttachmentReference.OwnerId,
        tx: DBReadTransaction
    ) -> [AttachmentReference] {
        return fetchReferences(owners: [owner], tx: tx)
    }

    /// Fetch the first reference for the provided owner.
    ///
    /// Ordering is not guaranteed; selection of "first" is arbitrary,
    /// so in general this method is for when the owner type
    /// allows only one (or no) reference.
    public func fetchFirstReference(
        owner: AttachmentReference.OwnerId,
        tx: DBReadTransaction
    ) -> AttachmentReference? {
        return fetchReferences(owner: owner, tx: tx).first
    }

    /// Fetch an attachment by id.
    public func fetch(
        id: Attachment.IDType,
        tx: DBReadTransaction
    ) -> Attachment? {
        return fetch(ids: [id], tx: tx).first
    }

    /// Convenience method to perform the two-step fetch
    /// owner -> AttachmentReference(s) -> Attachment(s).
    public func fetch(
        owner: AttachmentReference.OwnerId,
        tx: DBReadTransaction
    ) -> [Attachment] {
        let refs = fetchReferences(owner: owner, tx: tx)
        return fetch(for: refs, tx: tx)
    }

    /// Convenience method to perform the two-step fetch
    /// owner -> AttachmentReference -> Attachment.
    ///
    /// Ordering is not guaranteed; selection of "first" is arbitrary,
    /// so in general this method is for when the owner type
    /// allows only one (or no) attachment.
    public func fetchFirst(
        owner: AttachmentReference.OwnerId,
        tx: DBReadTransaction
    ) -> Attachment? {
        guard let ref = fetchFirstReference(owner: owner, tx: tx) else {
            return nil
        }
        return fetch(for: ref, tx: tx)
    }

    public func fetch(
        for reference: AttachmentReference,
        tx: DBReadTransaction
    ) -> Attachment? {
        return fetch(id: reference.attachmentRowId, tx: tx)
    }

    public func fetch(
        for references: [AttachmentReference],
        tx: DBReadTransaction
    ) -> [Attachment] {
        return fetch(ids: references.map(\.attachmentRowId), tx: tx)
    }

    public func orderedBodyAttachments(
        for message: TSMessage,
        tx: DBReadTransaction
    ) -> [AttachmentReference] {
        guard let messageRowId = message.sqliteRowId else {
            owsFailDebug("Fetching attachments for un-inserted message")
            return []
        }
        return self.orderedBodyAttachments(forMessageRowId: messageRowId, tx: tx)
    }

    public func orderedBodyAttachments(
        forMessageRowId messageRowId: Int64,
        tx: DBReadTransaction
    ) -> [AttachmentReference] {
        return self
            .fetchReferences(owner: .messageBodyAttachment(messageRowId: messageRowId), tx: tx)
            .lazy
            .compactMap { (ref: AttachmentReference) -> (UInt32, AttachmentReference)? in
                switch ref.owner {
                case .message(.bodyAttachment(let metadata)):
                    return (metadata.orderInOwner, ref)
                default:
                    return nil
                }
            }
            .sorted(by: { $0.0 < $1.0 })
            .map(\.1)
    }

    // MARK: - Referenced Attachments

    public func fetchReferencedAttachments(
        owners: [AttachmentReference.OwnerId],
        tx: DBReadTransaction
    ) -> [ReferencedAttachment] {
        let references = self.fetchReferences(owners: owners, tx: tx)
        let attachments = Dictionary(
            grouping: self.fetch(ids: references.map(\.attachmentRowId), tx: tx),
            by: \.id
        )
        return references.compactMap { reference -> ReferencedAttachment? in
            guard let attachment = attachments[reference.attachmentRowId]?.first else {
                owsFailDebug("Missing attachment!")
                return nil
            }
            return ReferencedAttachment(reference: reference, attachment: attachment)
        }
    }

    public func fetchReferencedAttachments(
        for owner: AttachmentReference.OwnerId,
        tx: DBReadTransaction
    ) -> [ReferencedAttachment] {
        return fetchReferencedAttachments(owners: [owner], tx: tx)
    }

    public func fetchAllReferencedAttachments(
        owningMessageRowId: Int64,
        tx: DBReadTransaction
    ) -> [ReferencedAttachment] {
        let references = self.fetchAllReferences(owningMessageRowId: owningMessageRowId, tx: tx)
        let attachments = Dictionary(
            grouping: self.fetch(ids: references.map(\.attachmentRowId), tx: tx),
            by: \.id
        )
        return references.compactMap { reference -> ReferencedAttachment? in
            guard let attachment = attachments[reference.attachmentRowId]?.first else {
                owsFailDebug("Missing attachment!")
                return nil
            }
            return ReferencedAttachment(reference: reference, attachment: attachment)
        }
    }

    public func fetchFirstReferencedAttachment(
        for owner: AttachmentReference.OwnerId,
        tx: DBReadTransaction
    ) -> ReferencedAttachment? {
        guard let reference = self.fetchFirstReference(owner: owner, tx: tx) else {
            return nil
        }
        guard let attachment = self.fetch(id: reference.attachmentRowId, tx: tx) else {
            owsFailDebug("Missing attachment!")
            return nil
        }
        return ReferencedAttachment(reference: reference, attachment: attachment)
    }

    public func orderedReferencedBodyAttachments(
        for message: TSMessage,
        tx: DBReadTransaction
    ) -> [ReferencedAttachment] {
        let references = self.orderedBodyAttachments(for: message, tx: tx)
        let attachments = Dictionary(
            grouping: self.fetch(ids: references.map(\.attachmentRowId), tx: tx),
            by: \.id
        )
        return references.compactMap { reference -> ReferencedAttachment? in
            guard let attachment = attachments[reference.attachmentRowId]?.first else {
                owsFailDebug("Missing attachment!")
                return nil
            }
            return ReferencedAttachment(reference: reference, attachment: attachment)
        }
    }

    public func allAttachments(
        forMessageWithRowId messageRowId: Int64,
        tx: DBReadTransaction
    ) -> [AttachmentReference] {
        return fetchReferences(
            owners: AttachmentReference.MessageOwnerTypeRaw.allCases.map {
                $0.with(messageRowId: messageRowId)
            },
            tx: tx
        )
    }
}
