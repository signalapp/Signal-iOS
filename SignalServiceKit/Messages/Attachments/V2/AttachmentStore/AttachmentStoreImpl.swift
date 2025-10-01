//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public class AttachmentStoreImpl: AttachmentStore {

    public init() {}

    typealias MessageAttachmentReferenceRecord = AttachmentReference.MessageAttachmentReferenceRecord
    typealias MessageOwnerTypeRaw = AttachmentReference.MessageOwnerTypeRaw
    typealias StoryMessageAttachmentReferenceRecord = AttachmentReference.StoryMessageAttachmentReferenceRecord
    typealias StoryMessageOwnerTypeRaw = AttachmentReference.StoryMessageOwnerTypeRaw
    typealias ThreadAttachmentReferenceRecord = AttachmentReference.ThreadAttachmentReferenceRecord

    public func fetchReferences(
        owners: [AttachmentReference.OwnerId],
        tx: DBReadTransaction
    ) -> [AttachmentReference] {
        return AttachmentReference.recordTypes.flatMap { recordType in
            return fetchReferences(
                owners: owners,
                recordType: recordType,
                tx: tx
            )
        }
    }

    public func fetchAllReferences(
        owningMessageRowId: Int64,
        tx: DBReadTransaction
    ) -> [AttachmentReference] {
        do {
            let statement = try tx.database.cachedStatement(sql: """
                SELECT *
                FROM \(MessageAttachmentReferenceRecord.databaseTableName)
                WHERE \(Column(MessageAttachmentReferenceRecord.CodingKeys.ownerRowId).name) = ?
                """)
            return try MessageAttachmentReferenceRecord
                .fetchAll(statement, arguments: [owningMessageRowId])
                .map { try AttachmentReference(record: $0) }
        } catch {
            owsFailDebug("Failed to fetch attachment references \(error)")
            return []
        }
    }

    private func fetchReferences<RecordType: FetchableAttachmentReferenceRecord>(
        owners: [AttachmentReference.OwnerId],
        recordType: RecordType.Type,
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
            let statement = try tx.database.cachedStatement(sql: sql)
            var results = try RecordType.fetchAll(statement, arguments: arguments)

            // If we have one owner and are capable of sorting, sort in ascending order.
            if owners.count == 1, let orderInOwnerKey = RecordType.orderInOwnerKey {
                results = results.sorted(by: { lhs, rhs in
                    return lhs[keyPath: orderInOwnerKey] ?? 0 <= rhs[keyPath: orderInOwnerKey] ?? 0
                })
            }
            return results.compactMap {
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

    public func fetchMaxRowId(tx: DBReadTransaction) throws -> Attachment.IDType? {
        return try Attachment.Record
            .select(
                max(Column(Attachment.Record.CodingKeys.sqliteId)),
                as: Int64.self,
            )
            .fetchOne(tx.database)
    }

    public func fetch(
        ids: [Attachment.IDType],
        tx: DBReadTransaction
    ) -> [Attachment] {
        if ids.isEmpty {
            return []
        }
        do {
            return try Attachment.Record
                .fetchAll(
                    tx.database,
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

    public func fetchAttachment(
        sha256ContentHash: Data,
        tx: DBReadTransaction
    ) -> Attachment? {
        return try? fetchAttachmentThrows(sha256ContentHash: sha256ContentHash, tx: tx)
    }

    private func fetchAttachmentThrows(
        sha256ContentHash: Data,
        tx: DBReadTransaction
    ) throws -> Attachment? {
        return try Attachment.Record
            .filter(Column(Attachment.Record.CodingKeys.sha256ContentHash) == sha256ContentHash)
            .fetchOne(tx.database)
            .map(Attachment.init(record:))
    }

    public func fetchAttachment(
        mediaName: String,
        tx: DBReadTransaction
    ) -> Attachment? {
        return try? fetchAttachmentThrows(mediaName: mediaName, tx: tx)
    }

    private func fetchAttachmentThrows(
        mediaName: String,
        tx: DBReadTransaction
    ) throws -> Attachment? {
        return try Attachment.Record
            .filter(Column(Attachment.Record.CodingKeys.mediaName) == mediaName)
            .fetchOne(tx.database)
            .map(Attachment.init(record:))
    }

    public func allQuotedReplyAttachments(
        forOriginalAttachmentId originalAttachmentId: Attachment.IDType,
        tx: DBReadTransaction
    ) throws -> [Attachment] {
        return try Attachment.Record
            .filter(Column(Attachment.Record.CodingKeys.originalAttachmentIdForQuotedReply) == originalAttachmentId)
            .fetchAll(tx.database)
            .map(Attachment.init(record:))
    }

    public func enumerateAllReferences(
        toAttachmentId attachmentId: Attachment.IDType,
        tx: DBReadTransaction,
        block: (AttachmentReference, _ stop: inout Bool) -> Void
    ) throws {
        try AttachmentReference.recordTypes.forEach { recordType in
            try enumerateReferences(
                attachmentId: attachmentId,
                recordType: recordType,
                tx: tx,
                block: block
            )
        }
    }

    public func enumerateAllAttachmentsWithMediaName(
        tx: DBReadTransaction,
        block: (Attachment) throws -> Void
    ) throws {
        try Attachment.Record
            .filter(Column(Attachment.Record.CodingKeys.mediaName) != nil)
            .fetchCursor(tx.database)
            .forEach {
                let attachment = try Attachment(record: $0)
                try block(attachment)
            }
    }

    private func enumerateReferences<RecordType: FetchableAttachmentReferenceRecord>(
        attachmentId: Attachment.IDType,
        recordType: RecordType.Type,
        tx: DBReadTransaction,
        block: (AttachmentReference, _ stop: inout Bool) -> Void
    ) throws {
        let cursor = try recordType
            .filter(recordType.attachmentRowIdColumn == attachmentId)
            .fetchCursor(tx.database)

        var stop = false
        while let record = try cursor.next() {
            let reference = try record.asReference()
            block(reference, &stop)
            if stop {
                break
            }
        }
    }

    public func oldestStickerPackReferences(
        tx: DBReadTransaction
    ) throws -> [AttachmentReference.Owner.MessageSource.StickerMetadata] {
        let ownerRowIdColumn = Column(MessageAttachmentReferenceRecord.CodingKeys.ownerRowId)
        let packIdColumn = Column(MessageAttachmentReferenceRecord.CodingKeys.stickerPackId)
        return try MessageAttachmentReferenceRecord
            .fetchAll(tx.database, sql: """
                SELECT *
                FROM \(MessageAttachmentReferenceRecord.databaseTableName)
                WHERE (\(packIdColumn.name), \(ownerRowIdColumn.name)) IN (
                    SELECT \(packIdColumn.name), MIN(\(ownerRowIdColumn.name))
                    FROM \(MessageAttachmentReferenceRecord.databaseTableName)
                    GROUP BY \(packIdColumn.name)
                );
                """
            )
            .compactMap { record in
                switch try AttachmentReference(record: record).owner {
                case .message(.sticker(let stickerMetadata)):
                    return stickerMetadata
                default:
                    return nil
                }
            }
    }

    public func allAttachmentIdsForSticker(
        _ stickerInfo: StickerInfo,
        tx: DBReadTransaction
    ) throws -> [Attachment.IDType] {
        let attachmentIdColumn = Column(MessageAttachmentReferenceRecord.CodingKeys.attachmentRowId)
        let packIdColumn = Column(MessageAttachmentReferenceRecord.CodingKeys.stickerPackId)
        let stickerIdColumn = Column(MessageAttachmentReferenceRecord.CodingKeys.stickerId)
        return try Attachment.IDType.fetchAll(
            tx.database,
            sql: """
                SELECT \(attachmentIdColumn.name)
                FROM \(MessageAttachmentReferenceRecord.databaseTableName)
                WHERE
                    \(packIdColumn.name) = ?
                    AND \(stickerIdColumn.name) = ?;
                """,
            arguments: [stickerInfo.packId, stickerInfo.stickerId]
        )
    }

    // MARK: Writes

    public func duplicateExistingMessageOwner(
        _ existingOwnerSource: AttachmentReference.Owner.MessageSource,
        with existingReference: AttachmentReference,
        newOwnerMessageRowId: Int64,
        newOwnerThreadRowId: Int64,
        newOwnerIsPastEditRevision: Bool,
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
        newRecord.ownerIsPastEditRevision = newOwnerIsPastEditRevision
        try newRecord.insert(tx.database)
    }

    public func duplicateExistingThreadOwner(
        _ existingOwnerSource: AttachmentReference.Owner.ThreadSource,
        with existingReference: AttachmentReference,
        newOwnerThreadRowId: Int64,
        tx: DBWriteTransaction
    ) throws {
        var newRecord = ThreadAttachmentReferenceRecord(
            attachmentReference: existingReference,
            threadSource: existingOwnerSource
        )
        newRecord.ownerRowId = newOwnerThreadRowId
        try newRecord.insert(tx.database)
    }

    public func update(
        _ reference: AttachmentReference,
        withReceivedAtTimestamp receivedAtTimestamp: UInt64,
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
            try tx.database.execute(
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

    public func updateAttachmentAsDownloaded(
        from source: QueuedAttachmentDownloadRecord.SourceType,
        priority: AttachmentDownloadPriority,
        id: Attachment.IDType,
        validatedMimeType: String,
        streamInfo: Attachment.StreamInfo,
        timestamp: UInt64,
        tx: DBWriteTransaction
    ) throws {
        let existingAttachment = fetch(ids: [id], tx: tx).first
        guard let existingAttachment else {
            throw OWSAssertionError("Attachment does not exist")
        }
        guard existingAttachment.asStream() == nil else {
            throw OWSAssertionError("Attachment already a stream")
        }

        // Find if there is already an attachment with the same plaintext hash.
        let existingRecord = try fetchAttachmentThrows(
            sha256ContentHash: streamInfo.sha256ContentHash,
            tx: tx
        )

        if let existingRecord, existingRecord.id != id {
            throw AttachmentInsertError.duplicatePlaintextHash(existingAttachmentId: existingRecord.id)
        }

        // Find if there is already an attachment with the same media name.
        let existingMediaNameRecord = try fetchAttachmentThrows(
            mediaName: Attachment.mediaName(
                sha256ContentHash: streamInfo.sha256ContentHash,
                encryptionKey: existingAttachment.encryptionKey
            ),
            tx: tx
        )
        if let existingMediaNameRecord, existingMediaNameRecord.id != id {
            throw AttachmentInsertError.duplicateMediaName(existingAttachmentId: existingMediaNameRecord.id)
        }

        // We count it as a "view" if the download was initiated by the user
        let lastFullscreenViewTimestamp: UInt64?
        switch priority {
        case .userInitiated:
            lastFullscreenViewTimestamp = timestamp
        case .backupRestore, .default, .localClone:
            lastFullscreenViewTimestamp = nil
        }

        var newRecord: Attachment.Record
        switch source {
        case .transitTier:
            newRecord = Attachment.Record(
                params: .forUpdatingAsDownlodedFromTransitTier(
                    attachment: existingAttachment,
                    validatedMimeType: validatedMimeType,
                    streamInfo: streamInfo,
                    sha256ContentHash: streamInfo.sha256ContentHash,
                    digestSHA256Ciphertext: streamInfo.digestSHA256Ciphertext,
                    mediaName: streamInfo.mediaName,
                    lastFullscreenViewTimestamp: lastFullscreenViewTimestamp,
                )
            )
        case .mediaTierFullsize:
            newRecord = Attachment.Record(
                params: .forUpdatingAsDownlodedFromMediaTier(
                    attachment: existingAttachment,
                    validatedMimeType: validatedMimeType,
                    streamInfo: streamInfo,
                    sha256ContentHash: streamInfo.sha256ContentHash,
                    mediaName: streamInfo.mediaName,
                    lastFullscreenViewTimestamp: lastFullscreenViewTimestamp,
                )
            )
        case .mediaTierThumbnail:
            newRecord = Attachment.Record(
                params: .forUpdatingAsDownlodedThumbnailFromMediaTier(
                    attachment: existingAttachment,
                    validatedMimeType: validatedMimeType,
                    streamInfo: streamInfo
                )
            )
        }
        newRecord.sqliteId = id
        try newRecord.checkAllUInt64FieldsFitInInt64()
        try newRecord.update(tx.database)
    }

    public func merge(
        streamInfo: Attachment.StreamInfo,
        into attachment: Attachment,
        encryptionKey: Data,
        validatedMimeType: String,
        latestTransitTierInfo: Attachment.TransitTierInfo?,
        originalTransitTierInfo: Attachment.TransitTierInfo?,
        mediaTierInfo: Attachment.MediaTierInfo?,
        thumbnailMediaTierInfo: Attachment.ThumbnailMediaTierInfo?,
        tx: DBWriteTransaction
    ) throws {
        guard attachment.asStream() == nil else {
            throw OWSAssertionError("Already a stream!")
        }

        var newRecord = Attachment.Record(params: .forMerging(
            streamInfo: streamInfo,
            into: attachment,
            encryptionKey: encryptionKey,
            mimeType: validatedMimeType,
            latestTransitTierInfo: latestTransitTierInfo,
            originalTransitTierInfo: originalTransitTierInfo,
            mediaTierInfo: mediaTierInfo,
            thumbnailMediaTierInfo: thumbnailMediaTierInfo
        ))

        newRecord.sqliteId = attachment.id
        try newRecord.checkAllUInt64FieldsFitInInt64()
        try newRecord.update(tx.database)
    }

    public func updateAttachmentAsFailedToDownload(
        from source: QueuedAttachmentDownloadRecord.SourceType,
        id: Attachment.IDType,
        timestamp: UInt64,
        tx: DBWriteTransaction
    ) throws {
        let existingAttachment = fetch(ids: [id], tx: tx).first
        guard let existingAttachment else {
            throw OWSAssertionError("Attachment does not exist")
        }
        guard existingAttachment.asStream() == nil else {
            throw OWSAssertionError("Attachment already a stream")
        }

        var newRecord: Attachment.Record
        switch source {
        case .transitTier:
            newRecord = Attachment.Record(
                params: .forUpdatingAsFailedDownlodFromTransitTier(
                    attachment: existingAttachment,
                    timestamp: timestamp
                )
            )
        case .mediaTierFullsize:
            newRecord = Attachment.Record(
                params: .forUpdatingAsFailedDownlodFromMediaTier(
                    attachment: existingAttachment,
                    timestamp: timestamp
                )
            )
        case .mediaTierThumbnail:
            newRecord = Attachment.Record(
                params: .forUpdatingAsFailedThumbnailDownlodFromMediaTier(
                    attachment: existingAttachment,
                    timestamp: timestamp
                )
            )
        }
        newRecord.sqliteId = id
        try newRecord.checkAllUInt64FieldsFitInInt64()
        try newRecord.update(tx.database)
    }

    public func removeMediaTierInfo(
        forAttachmentId id: Attachment.IDType,
        tx: DBWriteTransaction
    ) throws {
        let existingAttachment = fetch(ids: [id], tx: tx).first
        guard let existingAttachment else {
            throw OWSAssertionError("Attachment does not exist")
        }

        var newRecord = Attachment.Record(
            params: .forRemovingMediaTierInfo(attachment: existingAttachment)
        )
        newRecord.sqliteId = id
        try newRecord.checkAllUInt64FieldsFitInInt64()
        try newRecord.update(tx.database)
    }

    public func removeThumbnailMediaTierInfo(
        forAttachmentId id: Attachment.IDType,
        tx: DBWriteTransaction
    ) throws {
        let existingAttachment = fetch(ids: [id], tx: tx).first
        guard let existingAttachment else {
            throw OWSAssertionError("Attachment does not exist")
        }

        var newRecord = Attachment.Record(
            params: .forRemovingThumbnailMediaTierInfo(attachment: existingAttachment)
        )
        newRecord.sqliteId = id
        try newRecord.checkAllUInt64FieldsFitInInt64()
        try newRecord.update(tx.database)
    }

    public func updateAttachment(
        _ attachment: Attachment,
        revalidatedContentType contentType: Attachment.ContentType,
        mimeType: String,
        blurHash: String?,
        tx: DBWriteTransaction
    ) throws {
        var newRecord = Attachment.Record(
            params: .forUpdatingWithRevalidatedContentType(
                attachment: attachment,
                contentType: contentType,
                mimeType: mimeType,
                blurHash: blurHash
            )
        )
        newRecord.sqliteId = attachment.id
        try newRecord.checkAllUInt64FieldsFitInInt64()
        // NOTE: a sqlite trigger handles updating all attachment reference rows
        // with the new content type.
        try newRecord.update(tx.database)
    }

    public func addOwner(
        _ referenceParams: AttachmentReference.ConstructionParams,
        for attachmentRowId: Attachment.IDType,
        tx: DBWriteTransaction
    ) throws {
        switch referenceParams.owner {
        case .thread(.globalThreadWallpaperImage):
            // This is a special case; see comment on method.
            try insertGlobalThreadAttachmentReference(
                referenceParams: referenceParams,
                attachmentRowId: attachmentRowId,
                tx: tx
            )
        default:
            let referenceRecord = try referenceParams.buildRecord(attachmentRowId: attachmentRowId)
            try referenceRecord.checkAllUInt64FieldsFitInInt64()
            try referenceRecord.insert(tx.database)
        }
    }

    public func removeAllOwners(
        withId owner: AttachmentReference.OwnerId,
        for attachmentId: Attachment.IDType,
        tx: DBWriteTransaction
    ) throws {
        try AttachmentReference.recordTypes.forEach { recordType in
            try removeOwner(
                owner,
                idInOwner: nil,
                for: attachmentId,
                recordType: recordType,
                tx: tx
            )
        }
    }

    public func removeOwner(
        reference: AttachmentReference,
        tx: DBWriteTransaction
    ) throws {
        let idInOwner: UUID?
        switch reference.owner {
        case .message(let messageSource):
            switch messageSource {
            case .bodyAttachment(let metadata):
                idInOwner = metadata.idInOwner
            case
                    .oversizeText,
                    .linkPreview,
                    .quotedReply,
                    .sticker,
                    .contactAvatar:
                idInOwner = nil
            }
        case .storyMessage(let storyMessageSource):
            switch storyMessageSource {
            case
                    .media,
                    .textStoryLinkPreview:
                idInOwner = nil
            }
        case .thread(let threadSource):
            switch threadSource {
            case
                    .threadWallpaperImage,
                    .globalThreadWallpaperImage:
                idInOwner = nil
            }
        }
        try AttachmentReference.recordTypes.forEach { recordType in
            try removeOwner(
                reference.owner.id,
                idInOwner: idInOwner,
                for: reference.attachmentRowId,
                recordType: recordType,
                tx: tx
            )
        }
    }

    private func removeOwner<RecordType: FetchableAttachmentReferenceRecord>(
        _ owner: AttachmentReference.OwnerId,
        idInOwner: UUID?,
        for attachmentId: Attachment.IDType,
        recordType: RecordType.Type,
        tx: DBWriteTransaction
    ) throws {
        // GRDB's swift query API can't help us here because the AttachmentReference tables
        // lack a primary id column. Just use manual SQL.
        var sql = "DELETE FROM \(recordType.databaseTableName) WHERE "
        var arguments = StatementArguments()

        sql += "\(recordType.attachmentRowIdColumn.name) = ? "
        _ = arguments.append(contentsOf: [attachmentId])

        switch recordType.columnFilters(for: owner) {
        case .nonMatchingOwnerType:
            return
        case .nullOwnerRowId:
            sql += "AND \(recordType.ownerRowIdColumn.name) IS NULL"
        case .ownerRowId(let ownerRowId):
            sql += "AND \(recordType.ownerRowIdColumn.name) = ?"
            _ = arguments.append(contentsOf: [ownerRowId])
        case let .ownerTypeAndRowId(ownerRowId, ownerType, typeColumn):
            sql += "AND (\(typeColumn.name) = ? AND \(recordType.ownerRowIdColumn.name) = ?)"
            _ = arguments.append(contentsOf: [ownerType, ownerRowId])
        }

        if let idInOwner, let idInOwnerColumn = recordType.idInOwnerColumn {
            sql += " AND \(idInOwnerColumn.name) = ?"
            _ = arguments.append(contentsOf: [idInOwner.uuidString])
        }

        sql += ";"
        try tx.database.execute(
            sql: sql,
            arguments: arguments
        )
    }

    public func insert(
        _ attachmentParams: Attachment.ConstructionParams,
        reference referenceParams: AttachmentReference.ConstructionParams,
        tx: DBWriteTransaction
    ) throws -> Attachment.IDType {
        // Find if there is already an attachment with the same plaintext hash.
        let sha256ContentHash = attachmentParams.sha256ContentHash ?? attachmentParams.streamInfo?.sha256ContentHash
        let existingRecord = try sha256ContentHash.map {
            return try fetchAttachmentThrows(
                sha256ContentHash: $0,
                tx: tx
            ).map(Attachment.Record.init(attachment:))
        } ?? nil

        if let existingRecord {
            throw AttachmentInsertError.duplicatePlaintextHash(existingAttachmentId: existingRecord.sqliteId!)
        }

        // Find if there is already an attachment with the same media name.
        let existingMediaNameRecord = try attachmentParams.mediaName.map { mediaName in
            try fetchAttachmentThrows(
                mediaName: mediaName,
                tx: tx
            )
        } ?? nil
        if let existingMediaNameRecord {
            throw AttachmentInsertError.duplicateMediaName(existingAttachmentId: existingMediaNameRecord.id)
        }

        var attachmentRecord = Attachment.Record(params: attachmentParams)
        try attachmentRecord.checkAllUInt64FieldsFitInInt64()

        // Note that this will fail if we have collisions in medianame (unique constraint)
        // but thats a hash so we just ignore that possibility.
        try attachmentRecord.insert(tx.database)

        guard let attachmentRowId = attachmentRecord.sqliteId else {
            throw OWSAssertionError("No sqlite id assigned to inserted attachment")
        }

        do {
            try addOwner(
                referenceParams,
                for: attachmentRowId,
                tx: tx
            )
        } catch let ownerError {
            // We have to delete the ownerless attachment if owner creation failed.
            // Crash if the delete fails; that will certainly roll back the transaction.
            try! attachmentRecord.delete(tx.database)
            throw ownerError
        }

        return attachmentRowId
    }

    /// The "global wallpaper" reference is a special case.
    ///
    /// All other reference types have UNIQUE constraints on ownerRowId preventing duplicate owners,
    /// but UNIQUE doesn't apply to NULL values.
    /// So for this one only we overwrite the existing row if it exists.
    private func insertGlobalThreadAttachmentReference(
        referenceParams: AttachmentReference.ConstructionParams,
        attachmentRowId: Attachment.IDType,
        tx: DBWriteTransaction
    ) throws {
        let db = tx.database
        let ownerRowIdColumn = Column(ThreadAttachmentReferenceRecord.CodingKeys.ownerRowId)
        let timestampColumn = Column(ThreadAttachmentReferenceRecord.CodingKeys.creationTimestamp)
        let attachmentRowIdColumn = Column(ThreadAttachmentReferenceRecord.CodingKeys.attachmentRowId)

        let oldRecord = try AttachmentReference.ThreadAttachmentReferenceRecord
            .filter(ownerRowIdColumn == nil)
            .fetchOne(db)

        let newRecord = try referenceParams.buildRecord(attachmentRowId: attachmentRowId)
        guard let newRecord = newRecord as? ThreadAttachmentReferenceRecord else {
            throw OWSAssertionError("Non matching record type")
        }
        try newRecord.checkAllUInt64FieldsFitInInt64()

        if let oldRecord, oldRecord == newRecord {
            // They're the same, no need to do anything.
            return
        }

        // First we insert the new row and then we delete the old one, so that the deletion
        // of the old one doesn't trigger any unecessary zero-refcount attachment deletions.
        try newRecord.insert(db)

        func deleteRecord(_ record: AttachmentReference.ThreadAttachmentReferenceRecord) throws -> Int {
            return try AttachmentReference.ThreadAttachmentReferenceRecord
                .filter(ownerRowIdColumn == nil)
                .filter(timestampColumn == record.creationTimestamp)
                .filter(attachmentRowIdColumn == record.attachmentRowId)
                .deleteAll(db)
        }

        do {
            if let oldRecord {
                // Delete the old row. Match the timestamp and attachment so we are sure its the old one.
                let deleteCount = try deleteRecord(oldRecord)

                // It should have deleted only the single previous row; if this matched
                // both the equality check above should have exited early.
                owsAssertDebug(deleteCount == 1)
            }
        } catch let deleteError {
            // If we failed the subsequent delete, delete the new
            // owner reference we created (or we'll end up with two).
            // Crash if the delete fails; that will certainly roll back the transaction.
            _ = try! deleteRecord(newRecord)
            throw deleteError
        }
    }

    public func removeAllThreadOwners(tx: DBWriteTransaction) throws {
        try ThreadAttachmentReferenceRecord.deleteAll(tx.database)
    }

    public func updateMessageAttachmentThreadRowIdsForThreadMerge(
        fromThreadRowId: Int64,
        intoThreadRowId: Int64,
        tx: DBWriteTransaction
    ) throws {
        let threadRowIdColumn = GRDB.Column(AttachmentReference.MessageAttachmentReferenceRecord.CodingKeys.threadRowId)
        try AttachmentReference.MessageAttachmentReferenceRecord
            .filter(threadRowIdColumn == fromThreadRowId)
            .updateAll(tx.database, threadRowIdColumn.set(to: intoThreadRowId))
    }

    public func markViewedFullscreen(
        attachment: Attachment,
        timestamp: UInt64,
        tx: DBWriteTransaction
    ) throws {
        var newRecord = Attachment.Record(
            params: .forMarkingViewedFullscreen(
                attachment: attachment,
                viewTimestamp: timestamp
            )
        )
        newRecord.sqliteId = attachment.id
        try newRecord.checkAllUInt64FieldsFitInInt64()
        try newRecord.update(tx.database)
    }
}
