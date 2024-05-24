//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public class AttachmentStoreImpl: AttachmentStore {

    public init() {}

    public func fetchReferences(
        owners: [AttachmentReference.OwnerId],
        tx: DBReadTransaction
    ) -> [AttachmentReference] {
        fetchReferences(
            owners: owners,
            db: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead.database,
            tx: tx
        )
    }

    public func fetch(ids: [Attachment.IDType], tx: DBReadTransaction) -> [Attachment] {
        fetch(ids: ids, db: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead.database, tx: tx)
    }

    public func enumerateAllReferences(
        toAttachmentId attachmentId: Attachment.IDType,
        tx: DBReadTransaction,
        block: (AttachmentReference) -> Void
    ) {
        enumerateAllReferences(
            toAttachmentId: attachmentId,
            db: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead.database,
            tx: tx,
            block: block
        )
    }

    // MARK: - Writes

    public func addOwner(
        duplicating ownerReference: AttachmentReference,
        withNewOwner newOwner: AttachmentReference.OwnerId,
        tx: DBWriteTransaction
    ) throws{
        try addOwner(
            duplicating: ownerReference,
            withNewOwner: newOwner,
            db: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead.database,
            tx: tx
        )
    }

    public func update(
        _ reference: AttachmentReference,
        withReceivedAtTimestamp receivedAtTimestamp: UInt64,
        tx: DBWriteTransaction
    ) throws {
        try update(
            reference,
            withReceivedAtTimestamp: receivedAtTimestamp,
            db: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead.database,
            tx: tx
        )
    }

    public func removeOwner(
        _ owner: AttachmentReference.OwnerId,
        for attachmentId: Attachment.IDType,
        tx: DBWriteTransaction
    ) throws {
        try removeOwner(
            owner,
            for: attachmentId,
            db: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead.database,
            tx: tx
        )
    }

    public func insert(
        _ attachment: Attachment.ConstructionParams,
        reference: AttachmentReference.ConstructionParams,
        tx: DBWriteTransaction
    ) throws {
        try insert(
            attachment,
            reference: reference,
            db: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead.database,
            tx: tx
        )
    }

    public func removeAllThreadOwners(tx: DBWriteTransaction) throws {
        try removeAllThreadOwners(db: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead.database, tx: tx)
    }

    // MARK: - Implementation

    func fetchReferences(
        owners: [AttachmentReference.OwnerId],
        db: GRDB.Database,
        tx: DBReadTransaction
    ) -> [AttachmentReference] {
        fatalError("Unimplemented")
    }

    func fetch(
        ids: [Attachment.IDType],
        db: GRDB.Database,
        tx: DBReadTransaction
    ) -> [Attachment] {
        fatalError("Unimplemented")
    }

    func enumerateAllReferences(
        toAttachmentId: Attachment.IDType,
        db: GRDB.Database,
        tx: DBReadTransaction,
        block: (AttachmentReference) -> Void
    ) {
        fatalError("Unimplemented")
    }

    // MARK: Writes

    func addOwner(
        duplicating ownerReference: AttachmentReference,
        withNewOwner newOwner: AttachmentReference.OwnerId,
        db: GRDB.Database,
        tx: DBWriteTransaction
    ) throws{
        // New reference should have the same root type, just a different id.
        let hasMatchingType: Bool = {
            switch (ownerReference.owner.id, newOwner) {
            case
                (.messageBodyAttachment, .messageBodyAttachment),
                (.messageLinkPreview, .messageLinkPreview),
                (.messageSticker, .messageSticker),
                (.messageOversizeText, .messageOversizeText),
                (.messageContactAvatar, .messageContactAvatar),
                (.quotedReplyAttachment, .quotedReplyAttachment),
                (.storyMessageMedia, .storyMessageMedia),
                (.storyMessageLinkPreview, .storyMessageLinkPreview),
                (.threadWallpaperImage, .threadWallpaperImage),
                (.globalThreadWallpaperImage, .globalThreadWallpaperImage):
                return true
            case
                (.messageBodyAttachment, _),
                (.messageLinkPreview, _),
                (.messageSticker, _),
                (.messageOversizeText, _),
                (.messageContactAvatar, _),
                (.quotedReplyAttachment, _),
                (.storyMessageMedia, _),
                (.storyMessageLinkPreview, _),
                (.threadWallpaperImage, _),
                (.globalThreadWallpaperImage, _):
                return false
            }
        }()
        guard hasMatchingType else {
            throw OWSAssertionError("Owner reference types don't match!")
        }
        fatalError("Unimplemented")
    }

    func update(
        _ reference: AttachmentReference,
        withReceivedAtTimestamp: UInt64,
        db: GRDB.Database,
        tx: DBWriteTransaction
    ) throws {
        fatalError("Unimplemented")
    }

    func removeOwner(
        _ owner: AttachmentReference.OwnerId,
        for attachmentId: Attachment.IDType,
        db: GRDB.Database,
        tx: DBWriteTransaction
    ) throws {
        fatalError("Unimplemented")
    }

    func insert(
        _ attachment: Attachment.ConstructionParams,
        reference: AttachmentReference.ConstructionParams,
        db: GRDB.Database,
        tx: DBWriteTransaction
    ) throws {
        fatalError("Unimplemented")
    }

    func removeAllThreadOwners(db: GRDB.Database, tx: DBWriteTransaction) throws {
        fatalError("Unimplemented")
    }
}

extension AttachmentStoreImpl: AttachmentUploadStore {

    public func markUploadedToTransitTier(
        attachmentStream: AttachmentStream,
        encryptionKey: Data,
        encryptedByteLength: UInt32,
        digest: Data,
        cdnKey: String,
        cdnNumber: UInt32,
        uploadTimestamp: UInt64,
        tx: DBWriteTransaction
    ) {
        let transitTierInfo = Attachment.TransitTierInfo(
            cdnNumber: cdnNumber,
            cdnKey: cdnKey,
            uploadTimestamp: uploadTimestamp,
            encryptionKey: encryptionKey,
            encryptedByteCount: encryptedByteLength,
            digestSHA256Ciphertext: digest,
            lastDownloadAttemptTimestamp: nil
        )
        fatalError("Unimplemented")
    }
}
