//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol AttachmentStore {

    /// Fetch all references for the provided owners.
    /// Results are unordered.
    func fetchReferences(
        owners: [AttachmentReference.OwnerId],
        tx: DBReadTransaction
    ) -> [AttachmentReference]

    /// Fetch attachments by id.
    func fetch(
        ids: [Attachment.IDType],
        tx: DBReadTransaction
    ) -> [Attachment]

    /// Enumerate all references to a given attachment id, calling the block for each one.
    /// Blocks until all references have been enumerated.
    func enumerateAllReferences(
        toAttachmentId: Attachment.IDType,
        tx: DBReadTransaction,
        block: (AttachmentReference) -> Void
    )

    // MARK: - Writes

    /// Create a new ownership reference, copying properties of an existing reference.
    ///
    /// Copies the database row directly, only modifying the owner column.
    ///
    /// Fails if the provided new owner isn't of the same type as the original
    /// reference; e.g. trying to duplicate a story owner on a message, or
    /// a message link preview as a message sticker. Those operations require
    /// the explicit creation of a new owner.
    func addOwner(
        duplicating ownerReference: AttachmentReference,
        withNewOwner: AttachmentReference.OwnerId,
        tx: DBWriteTransaction
    ) throws

    /// Update the received at timestamp on a reference.
    /// Used for edits which update the received timestamp on an existing message.
    func update(
        _ reference: AttachmentReference,
        withReceivedAtTimestamp: UInt64,
        tx: DBWriteTransaction
    ) throws

    func removeOwner(
        _ owner: AttachmentReference.OwnerId,
        for attachmentId: Attachment.IDType,
        tx: DBWriteTransaction
    ) throws

    func insert(
        _ attachment: Attachment.ConstructionParams,
        reference: AttachmentReference.ConstructionParams,
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
}
