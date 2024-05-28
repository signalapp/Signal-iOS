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

    typealias MessageAttachmentReferenceRecord = AttachmentReference.MessageAttachmentReferenceRecord
    typealias MessageOwnerTypeRaw = AttachmentReference.MessageOwnerTypeRaw
    typealias StoryMessageAttachmentReferenceRecord = AttachmentReference.StoryMessageAttachmentReferenceRecord
    typealias StoryMessageOwnerTypeRaw = AttachmentReference.StoryMessageOwnerTypeRaw
    typealias ThreadAttachmentReferenceRecord = AttachmentReference.ThreadAttachmentReferenceRecord

    func fetchReferences(
        owners: [AttachmentReference.OwnerId],
        db: GRDB.Database,
        tx: DBReadTransaction
    ) -> [AttachmentReference] {
        let messageReferences = fetchReferences(
            owners: owners,
            recordType: MessageAttachmentReferenceRecord.self,
            db: db,
            tx: tx
        )

        let storyMessageReferences = fetchReferences(
            owners: owners,
            recordType: StoryMessageAttachmentReferenceRecord.self,
            db: db,
            tx: tx
        )

        let threadReferences = fetchReferences(
            owners: owners,
            recordType: ThreadAttachmentReferenceRecord.self,
            db: db,
            tx: tx
        )

        return messageReferences + storyMessageReferences + threadReferences
    }

    private func fetchReferences<RecordType: FetchableAttachmentReferenceRecord>(
        owners: [AttachmentReference.OwnerId],
        recordType: RecordType.Type,
        db: GRDB.Database,
        tx: DBReadTransaction
    ) -> [AttachmentReference] {
        var filterClauses = [String]()
        var arguments = StatementArguments()
        var numMatchingOwners = 0
        for owner in owners {
            switch recordType.columnFilters(for: owner) {
            case .nonMatchingOwnerType:
                continue
            case .nullOwnerRowId:
                filterClauses.append("\(recordType.ownerRowIdColumn.name) IS NULL")
            case .ownerRowId(let ownerRowId):
                filterClauses.append("\(recordType.ownerRowIdColumn.name) = ?")
                _ = arguments.append(contentsOf: [ownerRowId])
            case let .ownerTypeAndRowId(ownerRowId, ownerType, ownerTypeColumn):
                filterClauses.append("(\(ownerTypeColumn.name) = ? AND \(recordType.ownerRowIdColumn.name) = ?)")
                _ = arguments.append(contentsOf: [ownerType, ownerRowId])
            }
            numMatchingOwners += 1
        }
        guard numMatchingOwners > 0 else {
            return []
        }
        let sql = "SELECT * FROM \(recordType.databaseTableName) WHERE \(filterClauses.joined(separator: " OR "));"
        do {
            return try RecordType
                .fetchAll(db, sql: sql, arguments: arguments)
                .compactMap {
                    do {
                        return try $0.asReference()
                    } catch {
                        // Fail the individual row, not all of them.
                        owsFailDebug("Failed to parse attachment reference: \(error)")
                        return nil
                    }
                }
        } catch {
            owsFailDebug("Failed to fetch attachment references \(error)")
            return []
        }
    }

    func fetch(
        ids: [Attachment.IDType],
        db: GRDB.Database,
        tx: DBReadTransaction
    ) -> [Attachment] {
        do {
            return try Attachment.Record
                .fetchAll(
                    db,
                    keys: ids
                )
                .compactMap { record in
                    // Errors will be logged by the initializer.
                    // Drop only _this_ attachment by returning nil,
                    // instead of throwing and failing all of them.
                    return try? Attachment(record: record)
                }
        } catch {
            owsFailDebug("Failed to read attachment records from disk \(error)")
            return []
        }
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
        _ attachmentParams: Attachment.ConstructionParams,
        reference referenceParams: AttachmentReference.ConstructionParams,
        db: GRDB.Database,
        tx: DBWriteTransaction
    ) throws {
        // If there is already an attachment with the same plaintext hash, reuse it.
        let existingRecord = try attachmentParams.streamInfo.map { streamInfo in
            return try Attachment.Record
                .filter(Column(Attachment.Record.CodingKeys.sha256ContentHash) == streamInfo.sha256ContentHash)
                .fetchOne(db)
        } ?? nil

        let attachmentRowId: Attachment.IDType?
        if let existingRecord {
            attachmentRowId = existingRecord.sqliteId
        } else {
            var attachmentRecord = Attachment.Record(params: attachmentParams)

            // Note that this will fail if we have collisions in medianame (unique constraint)
            // but thats a hash so we just ignore that possibility.
            try attachmentRecord.insert(db)
            attachmentRowId = attachmentRecord.sqliteId
        }

        guard let attachmentRowId else {
            throw OWSAssertionError("No sqlite id assigned to inserted attachment")
        }

        try referenceParams.buildRecord(attachmentRowId: attachmentRowId).insert(db)
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
