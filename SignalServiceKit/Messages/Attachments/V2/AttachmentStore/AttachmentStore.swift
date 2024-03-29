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
}

// MARK: - Convenience

extension AttachmentStore {

    /// Fetch all references for the provided owner.
    /// Results are unordered.
    func fetchReferences(
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
    func fetchFirstReference(
        owner: AttachmentReference.OwnerId,
        tx: DBReadTransaction
    ) -> AttachmentReference? {
        return fetchReferences(owner: owner, tx: tx).first
    }

    /// Fetch an attachment by id.
    func fetch(
        id: Attachment.IDType,
        tx: DBReadTransaction
    ) -> Attachment? {
        return fetch(ids: [id], tx: tx).first
    }

    /// Convenience method to perform the two-step fetch
    /// owner -> AttachmentReference(s) -> Attachment(s).
    func fetch(
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
    func fetchFirst(
        owner: AttachmentReference.OwnerId,
        tx: DBReadTransaction
    ) -> Attachment? {
        guard let ref = fetchFirstReference(owner: owner, tx: tx) else {
            return nil
        }
        return fetch(for: ref, tx: tx)
    }

    func fetch(
        for reference: AttachmentReference,
        tx: DBReadTransaction
    ) -> Attachment? {
        return fetch(id: reference.attachmentRowId, tx: tx)
    }

    func fetch(
        for references: [AttachmentReference],
        tx: DBReadTransaction
    ) -> [Attachment] {
        return fetch(ids: references.map(\.attachmentRowId), tx: tx)
    }

    func orderedBodyAttachments(
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
                    return (metadata.index, ref)
                default:
                    return nil
                }
            }
            .sorted(by: { $0.0 < $1.0 })
            .map(\.1)
    }
}
