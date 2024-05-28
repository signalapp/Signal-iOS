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

    public func duplicateExistingMessageOwner(
        _ existingOwnerSource: AttachmentReference.Owner.MessageSource,
        with reference: AttachmentReference,
        newOwnerMessageRowId: Int64,
        newOwnerThreadRowId: Int64,
        tx: DBWriteTransaction
    ) throws {
        try duplicateExistingMessageOwner(
            existingOwnerSource,
            with: reference,
            newOwnerMessageRowId: newOwnerMessageRowId,
            newOwnerThreadRowId: newOwnerThreadRowId,
            db: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead.database,
            tx: tx
        )
    }

    public func duplicateExistingThreadOwner(
        _ existingOwnerSource: AttachmentReference.Owner.ThreadSource,
        with reference: AttachmentReference,
        newOwnerThreadRowId: Int64,
        tx: DBWriteTransaction
    ) throws {
        try duplicateExistingThreadOwner(
            existingOwnerSource,
            with: reference,
            newOwnerThreadRowId: newOwnerThreadRowId,
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
        return AttachmentReference.recordTypes.flatMap { recordType in
            return fetchReferences(
                owners: owners,
                recordType: recordType,
                db: db,
                tx: tx
            )
        }
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
        toAttachmentId attachmentId: Attachment.IDType,
        db: GRDB.Database,
        tx: DBReadTransaction,
        block: (AttachmentReference) -> Void
    ) {
        AttachmentReference.recordTypes.forEach { recordType in
            enumerateReferences(
                attachmentId: attachmentId,
                recordType: recordType,
                db: db,
                tx: tx,
                block: block
            )
        }
    }

    private func enumerateReferences<RecordType: FetchableAttachmentReferenceRecord>(
        attachmentId: Attachment.IDType,
        recordType: RecordType.Type,
        db: GRDB.Database,
        tx: DBReadTransaction,
        block: (AttachmentReference) -> Void
    ) {
        do {
            let cursor = try recordType
                .filter(recordType.attachmentRowIdColumn == attachmentId)
                .fetchCursor(db)

            while let record = try cursor.next() {
                do {
                    let reference = try record.asReference()
                    block(reference)
                } catch {
                    // Fail the individual row, not all of them.
                    owsFailDebug("Failed to parse attachment reference: \(error)")
                    continue
                }
            }
        } catch {
            owsFailDebug("Failed to enumerate attachment references \(error)")
            return
        }
    }

    // MARK: Writes

    func duplicateExistingMessageOwner(
        _ existingOwnerSource: AttachmentReference.Owner.MessageSource,
        with existingReference: AttachmentReference,
        newOwnerMessageRowId: Int64,
        newOwnerThreadRowId: Int64,
        db: GRDB.Database,
        tx: DBWriteTransaction
    ) throws {
        var newRecord = MessageAttachmentReferenceRecord(
            attachmentReference: existingReference,
            messageSource: existingOwnerSource
        )
        // Check that the thread id on the record we just duplicated
        // (the thread id of the original owner) matches the new thread id.
        guard newRecord.threadRowId == newOwnerThreadRowId else {
            // We could easily update the thread id to the new one, but this is
            // a canary to tell us when this method is being used not as intended.
            throw OWSAssertionError("Copying reference to a message on another thread!")
        }
        newRecord.ownerRowId = newOwnerMessageRowId
        try newRecord.insert(db)
    }

    func duplicateExistingThreadOwner(
        _ existingOwnerSource: AttachmentReference.Owner.ThreadSource,
        with existingReference: AttachmentReference,
        newOwnerThreadRowId: Int64,
        db: GRDB.Database,
        tx: DBWriteTransaction
    ) throws {
        var newRecord = ThreadAttachmentReferenceRecord(
            attachmentReference: existingReference,
            threadSource: existingOwnerSource
        )
        newRecord.ownerRowId = newOwnerThreadRowId
        try newRecord.insert(db)
    }

    func update(
        _ reference: AttachmentReference,
        withReceivedAtTimestamp receivedAtTimestamp: UInt64,
        db: GRDB.Database,
        tx: DBWriteTransaction
    ) throws {
        guard SDS.fitsInInt64(receivedAtTimestamp) else {
            throw OWSAssertionError("UInt64 doesn't fit in Int64")
        }

        switch reference.owner {
        case .message(let messageSource):
            // GRDB's swift query API can't help us here because MessageAttachmentReferenceRecord
            // lacks a primary id column. Just update the single column with manual SQL.
            let receivedAtTimestampColumn = Column(MessageAttachmentReferenceRecord.CodingKeys.receivedAtTimestamp)
            let ownerTypeColumn = Column(MessageAttachmentReferenceRecord.CodingKeys.ownerType)
            let ownerRowIdColumn = Column(MessageAttachmentReferenceRecord.CodingKeys.ownerRowId)
            try db.execute(
                sql:
                    "UPDATE \(MessageAttachmentReferenceRecord.databaseTableName) "
                    + "SET \(receivedAtTimestampColumn.name) = ? "
                    + "WHERE \(ownerTypeColumn.name) = ? AND \(ownerRowIdColumn.name) = ?;",
                arguments: [
                    receivedAtTimestamp,
                    messageSource.rawMessageOwnerType.rawValue,
                    messageSource.messageRowId
                ]
            )
        case .storyMessage:
            throw OWSAssertionError("Cannot update timestamp on story attachment reference")
        case .thread:
            throw OWSAssertionError("Cannot update timestamp on thread attachment reference")
        }
    }

    func removeOwner(
        _ owner: AttachmentReference.OwnerId,
        for attachmentId: Attachment.IDType,
        db: GRDB.Database,
        tx: DBWriteTransaction
    ) throws {
        try AttachmentReference.recordTypes.forEach { recordType in
            try removeOwner(
                owner,
                for: attachmentId,
                recordType: recordType,
                db: db,
                tx: tx
            )
        }
    }

    private func removeOwner<RecordType: FetchableAttachmentReferenceRecord>(
        _ owner: AttachmentReference.OwnerId,
        for attachmentId: Attachment.IDType,
        recordType: RecordType.Type,
        db: GRDB.Database,
        tx: DBWriteTransaction
    ) throws {
        // GRDB's swift query API can't help us here because the AttachmentReference tables
        // lack a primary id column. Just use manual SQL.
        var sql = "DELETE FROM \(recordType.databaseTableName) WHERE "
        var arguments = StatementArguments()
        switch recordType.columnFilters(for: owner) {
        case .nonMatchingOwnerType:
            return
        case .nullOwnerRowId:
            sql += "\(recordType.ownerRowIdColumn.name) IS NULL"
        case .ownerRowId(let ownerRowId):
            sql += "\(recordType.ownerRowIdColumn.name) = ?"
            _ = arguments.append(contentsOf: [ownerRowId])
        case let .ownerTypeAndRowId(ownerRowId, ownerType, typeColumn):
            sql += "(\(typeColumn.name) = ? AND \(recordType.ownerRowIdColumn.name) = ?)"
            _ = arguments.append(contentsOf: [ownerType, ownerRowId])
        }
        sql += ";"
        try db.execute(
            sql: sql,
            arguments: arguments
        )
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
            try attachmentRecord.checkAllUInt64FieldsFitInInt64()

            // Note that this will fail if we have collisions in medianame (unique constraint)
            // but thats a hash so we just ignore that possibility.
            try attachmentRecord.insert(db)
            attachmentRowId = attachmentRecord.sqliteId
        }

        guard let attachmentRowId else {
            throw OWSAssertionError("No sqlite id assigned to inserted attachment")
        }

        switch referenceParams.owner {
        case .thread(.globalThreadWallpaperImage):
            // This is a special case; see comment on method.
            try insertGlobalThreadAttachmentReference(
                referenceParams: referenceParams,
                attachmentRowId: attachmentRowId,
                db: db,
                tx: tx
            )
        default:
            let referenceRecord = try referenceParams.buildRecord(attachmentRowId: attachmentRowId)
            try referenceRecord.checkAllUInt64FieldsFitInInt64()
            try referenceRecord.insert(db)
        }
    }

    /// The "global wallpaper" reference is a special case.
    ///
    /// All other reference types have UNIQUE constraints on ownerRowId preventing duplicate owners,
    /// but UNIQUE doesn't apply to NULL values.
    /// So for this one only we overwrite the existing row if it exists.
    private func insertGlobalThreadAttachmentReference(
        referenceParams: AttachmentReference.ConstructionParams,
        attachmentRowId: Attachment.IDType,
        db: GRDB.Database,
        tx: DBWriteTransaction
    ) throws {

        let ownerRowIdColumn = Column(ThreadAttachmentReferenceRecord.CodingKeys.ownerRowId)
        let timestampColumn = Column(ThreadAttachmentReferenceRecord.CodingKeys.creationTimestamp)
        let attachmentRowIdColumn = Column(ThreadAttachmentReferenceRecord.CodingKeys.attachmentRowId)

        let oldRecord = try AttachmentReference.ThreadAttachmentReferenceRecord
            .filter(ownerRowIdColumn == nil)
            .fetchOne(db)

        let newRecord = try referenceParams.buildRecord(attachmentRowId: attachmentRowId)
        try newRecord.checkAllUInt64FieldsFitInInt64()

        if let oldRecord, oldRecord == (newRecord as? ThreadAttachmentReferenceRecord) {
            // They're the same, no need to do anything.
            return
        }

        // First we insert the new row and then we delete the old one, so that the deletion
        // of the old one doesn't trigger any unecessary zero-refcount attachment deletions.
        try newRecord.insert(db)
        if let oldRecord {
            // Delete the old row. Match the timestamp and attachment so we are sure its the old one.
            let deleteCount = try AttachmentReference.ThreadAttachmentReferenceRecord
                .filter(ownerRowIdColumn == nil)
                .filter(timestampColumn == oldRecord.creationTimestamp)
                .filter(attachmentRowIdColumn == oldRecord.attachmentRowId)
                .deleteAll(db)

            // It should have deleted only the single previous row; if this matched
            // both the equality check above should have exited early.
            owsAssertDebug(deleteCount == 1)
        }
    }

    func removeAllThreadOwners(db: GRDB.Database, tx: DBWriteTransaction) throws {
        try ThreadAttachmentReferenceRecord.deleteAll(db)
    }
}

extension AttachmentStoreImpl: AttachmentUploadStore {

    public func markUploadedToTransitTier(
        attachmentStream: AttachmentStream,
        info transitTierInfo: Attachment.TransitTierInfo,
        tx: DBWriteTransaction
    ) {
        fatalError("Unimplemented")
    }
}
