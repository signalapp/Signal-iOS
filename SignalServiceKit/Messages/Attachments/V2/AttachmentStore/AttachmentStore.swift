//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB

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

// MARK: -

public struct AttachmentStore {

    public init() {}

    typealias MessageAttachmentReferenceRecord = AttachmentReference.MessageAttachmentReferenceRecord
    typealias MessageOwnerTypeRaw = AttachmentReference.MessageOwnerTypeRaw
    typealias StoryMessageAttachmentReferenceRecord = AttachmentReference.StoryMessageAttachmentReferenceRecord
    typealias StoryMessageOwnerTypeRaw = AttachmentReference.StoryMessageOwnerTypeRaw
    typealias ThreadAttachmentReferenceRecord = AttachmentReference.ThreadAttachmentReferenceRecord

    // MARK: -

    public func fetchMaxRowId(tx: DBReadTransaction) throws -> Attachment.IDType? {
        return try Attachment.Record
            .select(
                max(Column(Attachment.Record.CodingKeys.sqliteId)),
                as: Int64.self,
            )
            .fetchOne(tx.database)
    }

    // MARK: -

    /// Fetch all references for the given owner. Results are unordered.
    public func fetchReferences(
        owner: AttachmentReference.OwnerId,
        tx: DBReadTransaction,
    ) -> [AttachmentReference] {
        return fetchReferences(owners: [owner], tx: tx)
    }

    /// Fetch all references for the given owners. Results are unordered.
    public func fetchReferences(
        owners: [AttachmentReference.OwnerId],
        tx: DBReadTransaction,
    ) -> [AttachmentReference] {
        return AttachmentReference.recordTypes.flatMap { recordType in
            return fetchReferences(
                owners: owners,
                recordType: recordType,
                tx: tx,
            )
        }
    }

    /// Fetch an arbitrary reference for the provided owner.
    ///
    /// - Important
    /// Callers should be sure that they are, in fact, interested in an
    /// arbitrary reference; for example, if the passed `owner` only allows at
    /// most one reference.
    public func fetchAnyReference(
        owner: AttachmentReference.OwnerId,
        tx: DBReadTransaction,
    ) -> AttachmentReference? {
        return fetchReferences(owner: owner, tx: tx).first
    }

    private func fetchReferences<RecordType: FetchableAttachmentReferenceRecord>(
        owners: [AttachmentReference.OwnerId],
        recordType: RecordType.Type,
        tx: DBReadTransaction,
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
            if owners.count == 1, let orderInMessageKey = RecordType.orderInMessageKey {
                results = results.sorted(by: { lhs, rhs in
                    return lhs[keyPath: orderInMessageKey] ?? 0 <= rhs[keyPath: orderInMessageKey] ?? 0
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

    // MARK: -

    public func fetch(
        id: Attachment.IDType,
        tx: DBReadTransaction,
    ) -> Attachment? {
        return fetch(ids: [id], tx: tx).first
    }

    public func fetch(
        ids: [Attachment.IDType],
        tx: DBReadTransaction,
    ) -> [Attachment] {
        if ids.isEmpty {
            return []
        }
        do {
            return try Attachment.Record
                .fetchAll(
                    tx.database,
                    keys: ids,
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

    /// Fetch attachment by plaintext hash. There can be only one match.
    public func fetchAttachment(
        sha256ContentHash: Data,
        tx: DBReadTransaction,
    ) -> Attachment? {
        return try? fetchAttachmentThrows(sha256ContentHash: sha256ContentHash, tx: tx)
    }

    private func fetchAttachmentThrows(
        sha256ContentHash: Data,
        tx: DBReadTransaction,
    ) throws -> Attachment? {
        return try Attachment.Record
            .filter(Column(Attachment.Record.CodingKeys.sha256ContentHash) == sha256ContentHash)
            .fetchOne(tx.database)
            .map(Attachment.init(record:))
    }

    /// Fetch attachment by media name. There can be only one match.
    public func fetchAttachment(
        mediaName: String,
        tx: DBReadTransaction,
    ) -> Attachment? {
        return try? fetchAttachmentThrows(mediaName: mediaName, tx: tx)
    }

    private func fetchAttachmentThrows(
        mediaName: String,
        tx: DBReadTransaction,
    ) throws -> Attachment? {
        return try Attachment.Record
            .filter(Column(Attachment.Record.CodingKeys.mediaName) == mediaName)
            .fetchOne(tx.database)
            .map(Attachment.init(record:))
    }

    // MARK: -

    public func fetchReferencedAttachments(
        for owner: AttachmentReference.OwnerId,
        tx: DBReadTransaction,
    ) -> [ReferencedAttachment] {
        return fetchReferencedAttachments(owners: [owner], tx: tx)
    }

    public func fetchReferencedAttachments(
        owners: [AttachmentReference.OwnerId],
        tx: DBReadTransaction,
    ) -> [ReferencedAttachment] {
        let references: [AttachmentReference] = fetchReferences(owners: owners, tx: tx)

        var attachmentsByID: [Attachment.IDType: Attachment] = [:]
        for attachmentID in Set(references.map(\.attachmentRowId)) {
            attachmentsByID[attachmentID] = fetch(id: attachmentID, tx: tx)
        }

        return references.map { reference in
            guard let attachment = attachmentsByID[reference.attachmentRowId] else {
                owsFail("Missing attachment for reference: foreign-key constraints should have prevented this!")
            }
            return ReferencedAttachment(reference: reference, attachment: attachment)
        }
    }

    public func fetchReferencedAttachmentsOwnedByMessage(
        messageRowId: Int64,
        tx: DBReadTransaction,
    ) -> [ReferencedAttachment] {
        let allMessageOwners: [AttachmentReference.OwnerId] = MessageOwnerTypeRaw.allCases.map {
            switch $0 {
            case .bodyAttachment: .messageBodyAttachment(messageRowId: messageRowId)
            case .oversizeText: .messageOversizeText(messageRowId: messageRowId)
            case .linkPreview: .messageLinkPreview(messageRowId: messageRowId)
            case .quotedReplyAttachment: .quotedReplyAttachment(messageRowId: messageRowId)
            case .sticker: .messageSticker(messageRowId: messageRowId)
            case .contactAvatar: .messageContactAvatar(messageRowId: messageRowId)
            }
        }

        return fetchReferencedAttachments(owners: allMessageOwners, tx: tx)
    }

    public func fetchReferencedAttachmentsOwnedByStory(
        storyMessageRowId: Int64,
        tx: DBReadTransaction,
    ) -> [ReferencedAttachment] {
        let allStoryOwners: [AttachmentReference.OwnerId] = StoryMessageOwnerTypeRaw.allCases.map {
            switch $0 {
            case .media: .storyMessageMedia(storyMessageRowId: storyMessageRowId)
            case .linkPreview: .storyMessageLinkPreview(storyMessageRowId: storyMessageRowId)
            }
        }

        return fetchReferencedAttachments(owners: allStoryOwners, tx: tx)
    }

    /// Fetch an arbitrary referenced attachment for the provided owner.
    ///
    /// - Important
    /// Callers should be sure that they are, in fact, interested in an
    /// arbitrary attachment; for example, if the passed `owner` only allows at
    /// most one reference.
    public func fetchAnyReferencedAttachment(
        for owner: AttachmentReference.OwnerId,
        tx: DBReadTransaction,
    ) -> ReferencedAttachment? {
        guard let reference = self.fetchAnyReference(owner: owner, tx: tx) else {
            return nil
        }
        guard let attachment = self.fetch(id: reference.attachmentRowId, tx: tx) else {
            owsFailDebug("Missing attachment!")
            return nil
        }
        return ReferencedAttachment(reference: reference, attachment: attachment)
    }

    // MARK: -

    /// Return all attachments that are themselves quoted replies
    /// of another attachment; provide the original attachment they point to.
    public func allQuotedReplyAttachments(
        forOriginalAttachmentId originalAttachmentId: Attachment.IDType,
        tx: DBReadTransaction,
    ) throws -> [Attachment] {
        return try Attachment.Record
            .filter(Column(Attachment.Record.CodingKeys.originalAttachmentIdForQuotedReply) == originalAttachmentId)
            .fetchAll(tx.database)
            .map(Attachment.init(record:))
    }

    public func quotedAttachmentReference(
        parentMessage: TSMessage,
        tx: DBReadTransaction,
    ) -> QuotedMessageAttachmentReference? {
        guard
            let messageRowId = parentMessage.sqliteRowId,
            let info = parentMessage.quotedMessage?.attachmentInfo()
        else {
            return nil
        }

        let reference = self.fetchAnyReference(
            owner: .quotedReplyAttachment(messageRowId: messageRowId),
            tx: tx,
        )

        if let reference {
            return .thumbnail(reference)
        } else if let stub = QuotedMessageAttachmentReference.Stub(info) {
            return .stub(stub)
        } else {
            return nil
        }
    }

    public func attachmentToUseInQuote(
        originalMessageRowId: Int64,
        tx: DBReadTransaction,
    ) -> AttachmentReference? {
        let orderedBodyAttachments = fetchReferences(
            owner: .messageBodyAttachment(messageRowId: originalMessageRowId),
            tx: tx,
        ).compactMap { ref -> (orderInMessage: UInt32, ref: AttachmentReference)? in
            switch ref.owner {
            case .message(.bodyAttachment(let metadata)):
                return (metadata.orderInMessage, ref)
            default:
                return nil
            }
        }.sorted { lhs, rhs in
            return lhs.orderInMessage < rhs.orderInMessage
        }.map(\.ref)

        return orderedBodyAttachments.first
            ?? self.fetchAnyReference(owner: .messageLinkPreview(messageRowId: originalMessageRowId), tx: tx)
            ?? self.fetchAnyReference(owner: .messageSticker(messageRowId: originalMessageRowId), tx: tx)
    }

    // MARK: -

    /// Enumerate all references to a given attachment id, calling the block for each one.
    /// Blocks until all references have been enumerated.
    public func enumerateAllReferences(
        toAttachmentId attachmentId: Attachment.IDType,
        tx: DBReadTransaction,
        block: (AttachmentReference, _ stop: inout Bool) -> Void,
    ) {
        AttachmentReference.recordTypes.forEach { recordType in
            enumerateReferences(
                attachmentId: attachmentId,
                recordType: recordType,
                tx: tx,
                block: block,
            )
        }
    }

    private func enumerateReferences<RecordType: FetchableAttachmentReferenceRecord>(
        attachmentId: Attachment.IDType,
        recordType: RecordType.Type,
        tx: DBReadTransaction,
        block: (AttachmentReference, _ stop: inout Bool) -> Void,
    ) {
        failIfThrows {
            let cursor = try recordType
                .filter(recordType.attachmentRowIdColumn == attachmentId)
                .fetchCursor(tx.database)

            var stop = false
            while let record = try cursor.next() {
                let reference: AttachmentReference
                do {
                    reference = try record.asReference()
                } catch {
                    owsFailDebug("Failed to create AttachmentReference! \(error)")
                    continue
                }

                block(reference, &stop)
                if stop {
                    break
                }
            }
        }
    }

    // MARK: -

    /// For each unique sticker pack id present in message sticker attachments, return
    /// the oldest message reference (by message insertion order) to that sticker attachment.
    ///
    /// Not very efficient; don't put this query on the hot path for anything.
    public func oldestStickerPackReferences(
        tx: DBReadTransaction,
    ) throws -> [AttachmentReference.Owner.MessageSource.StickerMetadata] {
        let ownerRowIdColumn = Column(MessageAttachmentReferenceRecord.CodingKeys.ownerRowId)
        let packIdColumn = Column(MessageAttachmentReferenceRecord.CodingKeys.stickerPackId)
        return try MessageAttachmentReferenceRecord
            .fetchAll(
                tx.database,
                sql: """
                SELECT *
                FROM \(MessageAttachmentReferenceRecord.databaseTableName)
                WHERE (\(packIdColumn.name), \(ownerRowIdColumn.name)) IN (
                    SELECT \(packIdColumn.name), MIN(\(ownerRowIdColumn.name))
                    FROM \(MessageAttachmentReferenceRecord.databaseTableName)
                    GROUP BY \(packIdColumn.name)
                );
                """,
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

    /// Return all attachment ids that reference the provided sticker.
    public func allAttachmentIdsForSticker(
        _ stickerInfo: StickerInfo,
        tx: DBReadTransaction,
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
            arguments: [stickerInfo.packId, stickerInfo.stickerId],
        )
    }

    // MARK: -

    /// Create a new ownership reference, copying properties of an existing reference.
    ///
    /// Copies the database row directly, only modifying the owner and isPastEditRevision columns.
    /// IMPORTANT: also copies the receivedAtTimestamp!
    ///
    /// Fails if the provided new owner isn't of the same type as the original
    /// reference; e.g. trying to duplicate a link preview as a sticker, or if the new
    /// owner is not in the same thread as the prior owner.
    /// Those operations require the explicit creation of a new owner.
    public func duplicateExistingMessageOwner(
        _ existingOwnerSource: AttachmentReference.Owner.MessageSource,
        with existingReference: AttachmentReference,
        newOwnerMessageRowId: Int64,
        newOwnerThreadRowId: Int64,
        newOwnerIsPastEditRevision: Bool,
        tx: DBWriteTransaction,
    ) throws {
        var newRecord = MessageAttachmentReferenceRecord(
            attachmentReference: existingReference,
            messageSource: existingOwnerSource,
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

    /// Create a new ownership reference, copying properties of an existing reference.
    ///
    /// Copies the database row directly, only modifying the owner column.
    /// IMPORTANT: also copies the createdTimestamp!
    public func duplicateExistingThreadOwner(
        _ existingOwnerSource: AttachmentReference.Owner.ThreadSource,
        with existingReference: AttachmentReference,
        newOwnerThreadRowId: Int64,
        tx: DBWriteTransaction,
    ) throws {
        var newRecord = ThreadAttachmentReferenceRecord(
            attachmentReference: existingReference,
            threadSource: existingOwnerSource,
        )
        newRecord.ownerRowId = newOwnerThreadRowId
        try newRecord.insert(tx.database)
    }

    /// Remove all owners of thread types (wallpaper and global wallpaper owners).
    /// Will also delete any attachments that become unowned, like any other deletion.
    public func removeAllThreadOwners(tx: DBWriteTransaction) throws {
        try ThreadAttachmentReferenceRecord.deleteAll(tx.database)
    }

    // MARK: -

    /// Update the received at timestamp on a reference.
    /// Used for edits which update the received timestamp on an existing message.
    public func update(
        _ reference: AttachmentReference,
        withReceivedAtTimestamp receivedAtTimestamp: UInt64,
        tx: DBWriteTransaction,
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
                    messageSource.messageRowId,
                ],
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
        tx: DBWriteTransaction,
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
            tx: tx,
        )

        if let existingRecord, existingRecord.id != id {
            throw AttachmentInsertError.duplicatePlaintextHash(existingAttachmentId: existingRecord.id)
        }

        // Find if there is already an attachment with the same media name.
        let existingMediaNameRecord = try fetchAttachmentThrows(
            mediaName: Attachment.mediaName(
                sha256ContentHash: streamInfo.sha256ContentHash,
                encryptionKey: existingAttachment.encryptionKey,
            ),
            tx: tx,
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
                ),
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
                ),
            )
        case .mediaTierThumbnail:
            newRecord = Attachment.Record(
                params: .forUpdatingAsDownlodedThumbnailFromMediaTier(
                    attachment: existingAttachment,
                    validatedMimeType: validatedMimeType,
                    streamInfo: streamInfo,
                ),
            )
        }
        newRecord.sqliteId = id
        try newRecord.update(tx.database)
    }

    /// Update an attachment when we have a media name or plaintext hash collision.
    /// Call this IFF the existing attachment has a media name/plaintext hash but not stream info
    /// (if it was restored from a backup), but the new copy has stream
    /// info that we should keep by merging into the existing attachment.
    public func merge(
        streamInfo: Attachment.StreamInfo,
        into attachment: Attachment,
        encryptionKey: Data,
        validatedMimeType: String,
        latestTransitTierInfo: Attachment.TransitTierInfo?,
        originalTransitTierInfo: Attachment.TransitTierInfo?,
        mediaTierInfo: Attachment.MediaTierInfo?,
        thumbnailMediaTierInfo: Attachment.ThumbnailMediaTierInfo?,
        tx: DBWriteTransaction,
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
            thumbnailMediaTierInfo: thumbnailMediaTierInfo,
        ))

        newRecord.sqliteId = attachment.id
        try newRecord.update(tx.database)
    }

    public func updateAttachmentAsFailedToDownload(
        from source: QueuedAttachmentDownloadRecord.SourceType,
        id: Attachment.IDType,
        timestamp: UInt64,
        tx: DBWriteTransaction,
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
                    timestamp: timestamp,
                ),
            )
        case .mediaTierFullsize:
            newRecord = Attachment.Record(
                params: .forUpdatingAsFailedDownlodFromMediaTier(
                    attachment: existingAttachment,
                    timestamp: timestamp,
                ),
            )
        case .mediaTierThumbnail:
            newRecord = Attachment.Record(
                params: .forUpdatingAsFailedThumbnailDownlodFromMediaTier(
                    attachment: existingAttachment,
                    timestamp: timestamp,
                ),
            )
        }
        newRecord.sqliteId = id
        try newRecord.update(tx.database)
    }

    public func removeMediaTierInfo(
        forAttachmentId id: Attachment.IDType,
        tx: DBWriteTransaction,
    ) throws {
        let existingAttachment = fetch(ids: [id], tx: tx).first
        guard let existingAttachment else {
            throw OWSAssertionError("Attachment does not exist")
        }

        var newRecord = Attachment.Record(
            params: .forRemovingMediaTierInfo(attachment: existingAttachment),
        )
        newRecord.sqliteId = id
        try newRecord.update(tx.database)
    }

    public func removeThumbnailMediaTierInfo(
        forAttachmentId id: Attachment.IDType,
        tx: DBWriteTransaction,
    ) throws {
        let existingAttachment = fetch(ids: [id], tx: tx).first
        guard let existingAttachment else {
            throw OWSAssertionError("Attachment does not exist")
        }

        var newRecord = Attachment.Record(
            params: .forRemovingThumbnailMediaTierInfo(attachment: existingAttachment),
        )
        newRecord.sqliteId = id
        try newRecord.update(tx.database)
    }

    /// Update an attachment after revalidating.
    public func updateAttachment(
        _ attachment: Attachment,
        revalidatedContentType contentType: Attachment.ContentType,
        mimeType: String,
        blurHash: String?,
        tx: DBWriteTransaction,
    ) throws {
        var newRecord = Attachment.Record(
            params: .forUpdatingWithRevalidatedContentType(
                attachment: attachment,
                contentType: contentType,
                mimeType: mimeType,
                blurHash: blurHash,
            ),
        )
        newRecord.sqliteId = attachment.id
        // NOTE: a sqlite trigger handles updating all attachment reference rows
        // with the new content type.
        try newRecord.update(tx.database)
    }

    // MARK: -

    public func addOwner(
        _ referenceParams: AttachmentReference.ConstructionParams,
        for attachmentRowId: Attachment.IDType,
        tx: DBWriteTransaction,
    ) throws {
        switch referenceParams.owner {
        case .thread(.globalThreadWallpaperImage):
            // This is a special case; see comment on method.
            try insertGlobalThreadAttachmentReference(
                referenceParams: referenceParams,
                attachmentRowId: attachmentRowId,
                tx: tx,
            )
        default:
            let referenceRecord = try referenceParams.buildRecord(attachmentRowId: attachmentRowId)
            try referenceRecord.insert(tx.database)
        }
    }

    /// Removes all owner edges to the provided attachment that
    /// have the provided owner type and id.
    /// Will delete multiple instances if the same owner has multiple
    /// edges of the given type to the given attachment (e.g. an image
    /// appears twice as a body attachment on a given message).
    public func removeAllOwners(
        withId owner: AttachmentReference.OwnerId,
        for attachmentId: Attachment.IDType,
        tx: DBWriteTransaction,
    ) throws {
        try AttachmentReference.recordTypes.forEach { recordType in
            try removeOwner(
                owner,
                idInOwner: nil,
                for: attachmentId,
                recordType: recordType,
                tx: tx,
            )
        }
    }

    /// Removes a single owner edge to the provided attachment that
    /// have the provided owner metadata.
    /// Will delete only delete the one given edge even if the same owner
    /// has multiple edges to the same attachment.
    public func removeOwner(
        reference: AttachmentReference,
        tx: DBWriteTransaction,
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
                tx: tx,
            )
        }
    }

    private func removeOwner<RecordType: FetchableAttachmentReferenceRecord>(
        _ owner: AttachmentReference.OwnerId,
        idInOwner: UUID?,
        for attachmentId: Attachment.IDType,
        recordType: RecordType.Type,
        tx: DBWriteTransaction,
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
            arguments: arguments,
        )
    }

    // MARK: -

    /// Throws ``AttachmentInsertError.duplicatePlaintextHash`` if an existing
    /// attachment is found with the same plaintext hash.
    /// May throw other errors with less strict typing if database operations fail.
    @discardableResult
    public func insert(
        _ attachmentParams: Attachment.ConstructionParams,
        reference referenceParams: AttachmentReference.ConstructionParams,
        tx: DBWriteTransaction,
    ) throws -> Attachment.IDType {
        // Find if there is already an attachment with the same plaintext hash.
        let sha256ContentHash = attachmentParams.sha256ContentHash ?? attachmentParams.streamInfo?.sha256ContentHash
        let existingRecord = try sha256ContentHash.map {
            return try fetchAttachmentThrows(
                sha256ContentHash: $0,
                tx: tx,
            ).map(Attachment.Record.init(attachment:))
        } ?? nil

        if let existingRecord {
            throw AttachmentInsertError.duplicatePlaintextHash(existingAttachmentId: existingRecord.sqliteId!)
        }

        // Find if there is already an attachment with the same media name.
        let existingMediaNameRecord = try attachmentParams.mediaName.map { mediaName in
            try fetchAttachmentThrows(
                mediaName: mediaName,
                tx: tx,
            )
        } ?? nil
        if let existingMediaNameRecord {
            throw AttachmentInsertError.duplicateMediaName(existingAttachmentId: existingMediaNameRecord.id)
        }

        var attachmentRecord = Attachment.Record(params: attachmentParams)

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
                tx: tx,
            )
        } catch let ownerError {
            // We have to delete the ownerless attachment if owner creation failed.
            // Crash if the delete fails; that will certainly roll back the transaction.
            try! attachmentRecord.delete(tx.database)
            throw ownerError
        }

        return attachmentRowId
    }

    // MARK: -

    /// The "global wallpaper" reference is a special case.
    ///
    /// All other reference types have UNIQUE constraints on ownerRowId preventing duplicate owners,
    /// but UNIQUE doesn't apply to NULL values.
    /// So for this one only we overwrite the existing row if it exists.
    private func insertGlobalThreadAttachmentReference(
        referenceParams: AttachmentReference.ConstructionParams,
        attachmentRowId: Attachment.IDType,
        tx: DBWriteTransaction,
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

    // MARK: -

    /// Call this when viewing an attachment "fullscreen", which really means "anything
    /// other than scrolling past it in a conversation".
    public func markViewedFullscreen(
        attachment: Attachment,
        timestamp: UInt64,
        tx: DBWriteTransaction,
    ) throws {
        var newRecord = Attachment.Record(
            params: .forMarkingViewedFullscreen(
                attachment: attachment,
                viewTimestamp: timestamp,
            ),
        )
        newRecord.sqliteId = attachment.id
        try newRecord.update(tx.database)
    }

    // MARK: - Thread Merging

    public func updateMessageAttachmentThreadRowIdsForThreadMerge(
        fromThreadRowId: Int64,
        intoThreadRowId: Int64,
        tx: DBWriteTransaction,
    ) throws {
        let threadRowIdColumn = GRDB.Column(AttachmentReference.MessageAttachmentReferenceRecord.CodingKeys.threadRowId)
        try AttachmentReference.MessageAttachmentReferenceRecord
            .filter(threadRowIdColumn == fromThreadRowId)
            .updateAll(tx.database, threadRowIdColumn.set(to: intoThreadRowId))
    }
}
