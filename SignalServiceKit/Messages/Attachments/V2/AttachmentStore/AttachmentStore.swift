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

    private typealias MessageAttachmentReferenceRecord = AttachmentReference.MessageAttachmentReferenceRecord
    private typealias StoryMessageAttachmentReferenceRecord = AttachmentReference.StoryMessageAttachmentReferenceRecord
    private typealias ThreadAttachmentReferenceRecord = AttachmentReference.ThreadAttachmentReferenceRecord

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

    /// Fetch an arbitrary reference for the provided owner.
    ///
    /// - Important
    /// Callers should be sure that they are, in fact, interested in an
    /// arbitrary reference; for example, if the passed `owner` only allows at
    /// most one reference.
    public func fetchAnyReference(
        owner: AttachmentReference.Owner.ID,
        tx: DBReadTransaction,
    ) -> AttachmentReference? {
        return fetchReferences(owner: owner, tx: tx).first
    }

    /// Fetch all references for the given owner. Results are unordered.
    public func fetchReferences(
        owner: AttachmentReference.Owner.ID,
        tx: DBReadTransaction,
    ) -> [AttachmentReference] {
        return fetchReferences(owners: [owner], tx: tx)
    }

    /// Fetch all references for the given owners. Results are unordered.
    public func fetchReferences(
        owners: [AttachmentReference.Owner.ID],
        tx: DBReadTransaction,
    ) -> [AttachmentReference] {
        return owners.flatMap { owner -> [AttachmentReference] in
            return switch owner {
            case .messageBodyAttachment(let messageRowId):
                fetchMessageAttachmentReferences(ownerType: .bodyAttachment, messageRowId: messageRowId, tx: tx)
            case .messageOversizeText(let messageRowId):
                fetchMessageAttachmentReferences(ownerType: .oversizeText, messageRowId: messageRowId, tx: tx)
            case .messageLinkPreview(let messageRowId):
                fetchMessageAttachmentReferences(ownerType: .linkPreview, messageRowId: messageRowId, tx: tx)
            case .quotedReplyAttachment(let messageRowId):
                fetchMessageAttachmentReferences(ownerType: .quotedReplyAttachment, messageRowId: messageRowId, tx: tx)
            case .messageSticker(let messageRowId):
                fetchMessageAttachmentReferences(ownerType: .sticker, messageRowId: messageRowId, tx: tx)
            case .messageContactAvatar(let messageRowId):
                fetchMessageAttachmentReferences(ownerType: .contactAvatar, messageRowId: messageRowId, tx: tx)
            case .storyMessageMedia(let storyMessageRowId):
                fetchStoryAttachmentReferences(ownerType: .media, storyMessageRowId: storyMessageRowId, tx: tx)
            case .storyMessageLinkPreview(let storyMessageRowId):
                fetchStoryAttachmentReferences(ownerType: .linkPreview, storyMessageRowId: storyMessageRowId, tx: tx)
            case .threadWallpaperImage(let threadRowId):
                fetchThreadAttachmentReferences(threadRowId: threadRowId, tx: tx)
            case .globalThreadWallpaperImage:
                fetchThreadAttachmentReferences(threadRowId: nil, tx: tx)
            }
        }
    }

    private func fetchMessageAttachmentReferences(
        ownerType: MessageAttachmentReferenceRecord.OwnerType,
        messageRowId: Int64,
        tx: DBReadTransaction,
    ) -> [AttachmentReference] {
        let query: QueryInterfaceRequest = MessageAttachmentReferenceRecord
            .filter(MessageAttachmentReferenceRecord.Columns.ownerType == ownerType.rawValue)
            .filter(MessageAttachmentReferenceRecord.Columns.ownerRowId == messageRowId)
            .order(MessageAttachmentReferenceRecord.Columns.orderInMessage.asc)

        return failIfThrows {
            return try query.fetchAll(tx.database).compactMap { record -> AttachmentReference? in
                do {
                    return try AttachmentReference(record: record)
                } catch {
                    owsFailDebug("Failed to convert message record to reference! \(error)")
                    return nil
                }
            }
        }
    }

    private func fetchStoryAttachmentReferences(
        ownerType: StoryMessageAttachmentReferenceRecord.OwnerType,
        storyMessageRowId: Int64,
        tx: DBReadTransaction,
    ) -> [AttachmentReference] {
        let query: QueryInterfaceRequest = StoryMessageAttachmentReferenceRecord
            .filter(StoryMessageAttachmentReferenceRecord.Columns.ownerType == ownerType.rawValue)
            .filter(StoryMessageAttachmentReferenceRecord.Columns.ownerRowId == storyMessageRowId)

        return failIfThrows {
            return try query.fetchAll(tx.database).compactMap { record -> AttachmentReference? in
                do {
                    return try AttachmentReference(record: record)
                } catch {
                    owsFailDebug("Failed to convert story record to reference! \(error)")
                    return nil
                }
            }
        }
    }

    private func fetchThreadAttachmentReferences(
        threadRowId: Int64?,
        tx: DBReadTransaction,
    ) -> [AttachmentReference] {
        let query: QueryInterfaceRequest = ThreadAttachmentReferenceRecord
            .filter(ThreadAttachmentReferenceRecord.Columns.ownerRowId == threadRowId)

        return failIfThrows {
            try query.fetchAll(tx.database).compactMap { record -> AttachmentReference? in
                do {
                    return try AttachmentReference(record: record)
                } catch {
                    owsFailDebug("Failed to convert thread record to reference! \(error)")
                    return nil
                }
            }
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

    /// Fetch an arbitrary referenced attachment for the provided owner.
    ///
    /// - Important
    /// Callers should be sure that they are, in fact, interested in an
    /// arbitrary attachment; for example, if the passed `owner` only allows at
    /// most one reference.
    public func fetchAnyReferencedAttachment(
        for owner: AttachmentReference.Owner.ID,
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

    public func fetchReferencedAttachments(
        for owner: AttachmentReference.Owner.ID,
        tx: DBReadTransaction,
    ) -> [ReferencedAttachment] {
        return fetchReferencedAttachments(owners: [owner], tx: tx)
    }

    public func fetchReferencedAttachments(
        owners: [AttachmentReference.Owner.ID],
        tx: DBReadTransaction,
    ) -> [ReferencedAttachment] {
        let references: [AttachmentReference] = fetchReferences(owners: owners, tx: tx)
        return fetchReferencedAttachments(references: references, tx: tx)
    }

    public func fetchReferencedAttachmentsOwnedByMessage(
        messageRowId: Int64,
        tx: DBReadTransaction,
    ) -> [ReferencedAttachment] {
        // We call this method for every interaction when doing a Backup export,
        // and we've found in practice that optimizations here matter. For
        // example, making sure it's a single query, and using a cached SQLite
        // statement.

        let sql = """
            SELECT *
            FROM \(MessageAttachmentReferenceRecord.databaseTableName)
            WHERE \(Column(MessageAttachmentReferenceRecord.CodingKeys.ownerRowId).name) = ?
        """

        let referenceRecords = failIfThrows {
            let statement = try tx.database.cachedStatement(sql: sql)
            return try MessageAttachmentReferenceRecord.fetchAll(
                statement,
                arguments: [messageRowId],
            )
        }

        let references = referenceRecords.compactMap { messageReferenceRecord in
            do {
                return try AttachmentReference(record: messageReferenceRecord)
            } catch {
                owsFailDebug("Failed to convert message record to reference! \(error)")
                return nil
            }
        }

        return fetchReferencedAttachments(references: references, tx: tx)
    }

    public func fetchReferencedAttachmentsOwnedByStory(
        storyMessageRowId: Int64,
        tx: DBReadTransaction,
    ) -> [ReferencedAttachment] {
        let allStoryOwners: [AttachmentReference.Owner.ID] = StoryMessageAttachmentReferenceRecord.OwnerType.allCases.map {
            switch $0 {
            case .media: .storyMessageMedia(storyMessageRowId: storyMessageRowId)
            case .linkPreview: .storyMessageLinkPreview(storyMessageRowId: storyMessageRowId)
            }
        }

        return fetchReferencedAttachments(owners: allStoryOwners, tx: tx)
    }

    private func fetchReferencedAttachments(
        references: [AttachmentReference],
        tx: DBReadTransaction,
    ) -> [ReferencedAttachment] {
        var attachmentsByID: [Attachment.IDType: Attachment] = [:]
        for attachmentID in Set(references.map(\.attachmentRowId)) {
            attachmentsByID[attachmentID] = fetch(id: attachmentID, tx: tx)
        }

        return references.compactMap { reference in
            guard let attachment = attachmentsByID[reference.attachmentRowId] else {
                owsFailDebug("Missing attachment \(reference.attachmentRowId) for reference!")
                return nil
            }
            return ReferencedAttachment(reference: reference, attachment: attachment)
        }
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
        var stop = false

        func enumerateReferenceRecords<Record: FetchableRecord>(
            fetchRequest: QueryInterfaceRequest<Record>,
            tx: DBReadTransaction,
            block: (Record, _ stop: inout Bool) -> Void,
        ) {
            if stop { return }

            failIfThrows {
                let cursor = try fetchRequest.fetchCursor(tx.database)
                while let record = try cursor.next() {
                    block(record, &stop)
                    if stop { break }
                }
            }
        }

        enumerateReferenceRecords(
            fetchRequest: MessageAttachmentReferenceRecord
                .filter(MessageAttachmentReferenceRecord.Columns.attachmentRowId == attachmentId),
            tx: tx,
        ) { record, stop in
            do {
                block(try AttachmentReference(record: record), &stop)
            } catch {
                owsFailDebug("Failed to convert message record to reference! \(error)")
            }
        }

        enumerateReferenceRecords(
            fetchRequest: StoryMessageAttachmentReferenceRecord
                .filter(StoryMessageAttachmentReferenceRecord.Columns.attachmentRowId == attachmentId),
            tx: tx,
        ) { record, stop in
            do {
                block(try AttachmentReference(record: record), &stop)
            } catch {
                owsFailDebug("Failed to convert story message record to reference! \(error)")
            }
        }

        enumerateReferenceRecords(
            fetchRequest: ThreadAttachmentReferenceRecord
                .filter(ThreadAttachmentReferenceRecord.Columns.attachmentRowId == attachmentId),
            tx: tx,
        ) { record, stop in
            do {
                block(try AttachmentReference(record: record), &stop)
            } catch {
                owsFailDebug("Failed to convert thread record to reference! \(error)")
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

    /// Add a attachment reference for a new past-edit revision message, cloning
    /// the existing reference with a new owner.
    public func cloneMessageOwnerForNewPastEditRevision(
        existingReference: AttachmentReference,
        existingOwnerSource: AttachmentReference.Owner.MessageSource,
        newPastRevisionRowId: Int64,
        tx: DBWriteTransaction,
    ) {
        var newRecord = MessageAttachmentReferenceRecord(
            attachmentReference: existingReference,
            messageSource: existingOwnerSource,
        )
        newRecord.ownerRowId = newPastRevisionRowId
        newRecord.ownerIsPastEditRevision = true
        failIfThrows {
            try newRecord.insert(tx.database)
        }
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
            attachmentRowId: existingReference.attachmentRowId,
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
        switch reference.owner {
        case .message(let messageSource):
            // GRDB's swift query API can't help us here because MessageAttachmentReferenceRecord
            // lacks a primary id column. Just update the single column with manual SQL.
            let receivedAtTimestampColumn = Column(MessageAttachmentReferenceRecord.CodingKeys.receivedAtTimestamp)
            let ownerTypeColumn = Column(MessageAttachmentReferenceRecord.CodingKeys.ownerTypeRaw)
            let ownerRowIdColumn = Column(MessageAttachmentReferenceRecord.CodingKeys.ownerRowId)
            try tx.database.execute(
                sql:
                "UPDATE \(MessageAttachmentReferenceRecord.databaseTableName) "
                    + "SET \(receivedAtTimestampColumn.name) = ? "
                    + "WHERE \(ownerTypeColumn.name) = ? AND \(ownerRowIdColumn.name) = ?;",
                arguments: [
                    receivedAtTimestamp,
                    messageSource.persistedOwnerType.rawValue,
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

    @discardableResult
    public func addReference(
        _ referenceParams: AttachmentReference.ConstructionParams,
        attachmentRowId: Attachment.IDType,
        tx: DBWriteTransaction,
    ) throws -> AttachmentReference {
        switch referenceParams.owner {
        case .thread(let threadSource):
            let threadReferenceRecord = ThreadAttachmentReferenceRecord(
                attachmentRowId: attachmentRowId,
                threadSource: threadSource,
            )
            switch threadSource {
            case .globalThreadWallpaperImage:
                // This is a special case; see comment on method.
                try insertGlobalThreadAttachmentReference(
                    newRecord: threadReferenceRecord,
                    tx: tx,
                )
            default:
                try threadReferenceRecord.insert(tx.database)
            }
            return try AttachmentReference(record: threadReferenceRecord)
        case .message(let messageSource):
            let messageReferenceRecord = MessageAttachmentReferenceRecord(
                attachmentRowId: attachmentRowId,
                sourceFilename: referenceParams.sourceFilename,
                sourceUnencryptedByteCount: referenceParams.sourceUnencryptedByteCount,
                sourceMediaSizePixels: referenceParams.sourceMediaSizePixels,
                messageSource: messageSource,
            )
            try messageReferenceRecord.insert(tx.database)
            return try AttachmentReference(record: messageReferenceRecord)
        case .storyMessage(let storyMessageSource):
            let storyReferenceRecord = try StoryMessageAttachmentReferenceRecord(
                attachmentRowId: attachmentRowId,
                sourceFilename: referenceParams.sourceFilename,
                sourceUnencryptedByteCount: referenceParams.sourceUnencryptedByteCount,
                sourceMediaSizePixels: referenceParams.sourceMediaSizePixels,
                storyMessageSource: storyMessageSource,
            )
            try storyReferenceRecord.insert(tx.database)
            return try AttachmentReference(record: storyReferenceRecord)
        }
    }

    /// Remove the given reference.
    ///
    /// Note that the owner of this reference may have other references to the
    /// same attachment: for example, a message containing multiple copies of
    /// the same image.
    public func removeReference(
        reference: AttachmentReference,
        tx: DBWriteTransaction,
    ) throws {
        switch reference.owner {
        case .message(let messageSource):
            try removeMessageReference(
                attachmentID: reference.attachmentRowId,
                ownerType: messageSource.persistedOwnerType,
                messageRowID: messageSource.messageRowId,
                idInMessage: messageSource.idInMessage,
                tx: tx,
            )
        case .storyMessage(let storyMessageSource):
            try removeStoryMessageReference(
                attachmentID: reference.attachmentRowId,
                ownerType: storyMessageSource.persistedOwnerType,
                storyMessageRowID: storyMessageSource.storyMessageRowId,
                tx: tx,
            )
        case .thread(let threadSource):
            try removeThreadReference(
                attachmentID: reference.attachmentRowId,
                threadRowID: threadSource.threadRowId,
                tx: tx,
            )
        }
    }

    private func removeMessageReference(
        attachmentID: Attachment.IDType,
        ownerType: MessageAttachmentReferenceRecord.OwnerType,
        messageRowID: Int64,
        idInMessage: UUID?,
        tx: DBWriteTransaction,
    ) throws {
        let query = MessageAttachmentReferenceRecord
            .filter(MessageAttachmentReferenceRecord.Columns.attachmentRowId == attachmentID)
            .filter(MessageAttachmentReferenceRecord.Columns.ownerType == ownerType.rawValue)
            .filter(MessageAttachmentReferenceRecord.Columns.ownerRowId == messageRowID)
            .filter(MessageAttachmentReferenceRecord.Columns.idInMessage == idInMessage?.uuidString)

        try query.deleteAll(tx.database)
    }

    private func removeStoryMessageReference(
        attachmentID: Attachment.IDType,
        ownerType: StoryMessageAttachmentReferenceRecord.OwnerType,
        storyMessageRowID: Int64,
        tx: DBWriteTransaction,
    ) throws {
        let query = StoryMessageAttachmentReferenceRecord
            .filter(StoryMessageAttachmentReferenceRecord.Columns.attachmentRowId == attachmentID)
            .filter(StoryMessageAttachmentReferenceRecord.Columns.ownerType == ownerType.rawValue)
            .filter(StoryMessageAttachmentReferenceRecord.Columns.ownerRowId == storyMessageRowID)

        try query.deleteAll(tx.database)
    }

    private func removeThreadReference(
        attachmentID: Attachment.IDType,
        threadRowID: Int64?,
        tx: DBWriteTransaction,
    ) throws {
        let query = ThreadAttachmentReferenceRecord
            .filter(ThreadAttachmentReferenceRecord.Columns.attachmentRowId == attachmentID)
            .filter(ThreadAttachmentReferenceRecord.Columns.ownerRowId == threadRowID)

        try query.deleteAll(tx.database)
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
            try addReference(
                referenceParams,
                attachmentRowId: attachmentRowId,
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
        newRecord: ThreadAttachmentReferenceRecord,
        tx: DBWriteTransaction,
    ) throws {
        let db = tx.database
        let ownerRowIdColumn = Column(ThreadAttachmentReferenceRecord.CodingKeys.ownerRowId)
        let timestampColumn = Column(ThreadAttachmentReferenceRecord.CodingKeys.creationTimestamp)
        let attachmentRowIdColumn = Column(ThreadAttachmentReferenceRecord.CodingKeys.attachmentRowId)

        let oldRecord = try AttachmentReference.ThreadAttachmentReferenceRecord
            .filter(ownerRowIdColumn == nil)
            .fetchOne(db)

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
