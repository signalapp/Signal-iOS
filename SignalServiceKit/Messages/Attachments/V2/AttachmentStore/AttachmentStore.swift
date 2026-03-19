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

    public func fetchMaxRowId(tx: DBReadTransaction) -> Attachment.IDType? {
        return failIfThrows {
            try Attachment.Record
                .select(
                    max(Column(Attachment.Record.CodingKeys.sqliteId)),
                    as: Int64.self,
                )
                .fetchOne(tx.database)
        }
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

    /// Fetch an existing Attachment record with the given plaintext hash. There
    /// will be at most one.
    public func fetchAttachmentRecord(
        sha256ContentHash: Data,
        tx: DBReadTransaction,
    ) -> Attachment.Record? {
        let query = Attachment.Record
            .filter(Column(Attachment.Record.CodingKeys.sha256ContentHash) == sha256ContentHash)

        return failIfThrows {
            try query.fetchOne(tx.database)
        }
    }

    /// Fetch an existing Attachment record with the given mediaName. There will
    /// be at most one.
    public func fetchAttachmentRecord(
        mediaName: String,
        tx: DBReadTransaction,
    ) -> Attachment.Record? {
        let query = Attachment.Record
            .filter(Column(Attachment.Record.CodingKeys.mediaName) == mediaName)

        return failIfThrows {
            try query.fetchOne(tx.database)
        }
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
    ) -> [Attachment] {
        let query = Attachment.Record
            .filter(Column(Attachment.Record.CodingKeys.originalAttachmentIdForQuotedReply) == originalAttachmentId)

        return failIfThrows {
            try query.fetchAll(tx.database)
                .compactMap { try? Attachment(record: $0) }
        }
    }

    public func quotedAttachmentReference(
        owningMessage: TSMessage,
        tx: DBReadTransaction,
    ) -> QuotedMessageAttachmentReference? {
        guard
            let messageRowId = owningMessage.sqliteRowId,
            let info = owningMessage.quotedMessage?.attachmentInfo()
        else {
            return nil
        }

        let referencedAttachment = self.fetchAnyReferencedAttachment(
            for: .quotedReplyAttachment(messageRowId: messageRowId),
            tx: tx,
        )

        if let referencedAttachment {
            return .thumbnail(referencedAttachment)
        } else if
            info.originalAttachmentMimeType != nil
            || info.originalAttachmentSourceFilename != nil
        {
            return .stub(QuotedMessageAttachmentReference.Stub(
                mimeType: info.originalAttachmentMimeType,
                sourceFilename: info.originalAttachmentSourceFilename,
                renderingFlag: info.originalAttachmentRenderingFlag,
            ))
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
    ) -> [AttachmentReference.Owner.MessageSource.StickerMetadata] {
        let ownerRowIdColumn = Column(MessageAttachmentReferenceRecord.CodingKeys.ownerRowId)
        let packIdColumn = Column(MessageAttachmentReferenceRecord.CodingKeys.stickerPackId)

        let records = failIfThrows {
            let sql = """
                SELECT *
                FROM \(MessageAttachmentReferenceRecord.databaseTableName)
                WHERE (\(packIdColumn.name), \(ownerRowIdColumn.name)) IN (
                    SELECT \(packIdColumn.name), MIN(\(ownerRowIdColumn.name))
                    FROM \(MessageAttachmentReferenceRecord.databaseTableName)
                    GROUP BY \(packIdColumn.name)
                )
            """
            return try MessageAttachmentReferenceRecord.fetchAll(
                tx.database,
                sql: sql,
            )
        }

        return records
            .compactMap { record in
                switch try? AttachmentReference(record: record).owner {
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
    ) -> [Attachment.IDType] {
        let attachmentIdColumn = Column(MessageAttachmentReferenceRecord.CodingKeys.attachmentRowId)
        let packIdColumn = Column(MessageAttachmentReferenceRecord.CodingKeys.stickerPackId)
        let stickerIdColumn = Column(MessageAttachmentReferenceRecord.CodingKeys.stickerId)
        let sql = """
            SELECT \(attachmentIdColumn.name)
            FROM \(MessageAttachmentReferenceRecord.databaseTableName)
            WHERE
                \(packIdColumn.name) = ?
                AND \(stickerIdColumn.name) = ?;
        """

        return failIfThrows {
            return try Attachment.IDType.fetchAll(
                tx.database,
                sql: sql,
                arguments: [stickerInfo.packId, stickerInfo.stickerId],
            )
        }
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

    // MARK: -

    /// Add an attachment reference for a thread, cloning the existing reference
    /// with a new owner.
    public func cloneThreadOwner(
        existingReference: AttachmentReference,
        existingOwnerSource: AttachmentReference.Owner.ThreadSource,
        newThreadRowId: Int64,
        tx: DBWriteTransaction,
    ) {
        var newRecord = ThreadAttachmentReferenceRecord(
            attachmentRowId: existingReference.attachmentRowId,
            threadSource: existingOwnerSource,
        )
        newRecord.ownerRowId = newThreadRowId
        failIfThrows {
            try newRecord.insert(tx.database)
        }
    }

    /// Remove all owners of thread types (wallpaper and global wallpaper owners).
    /// Will also delete any attachments that become unowned, like any other deletion.
    public func removeAllThreadOwners(tx: DBWriteTransaction) {
        failIfThrows {
            try ThreadAttachmentReferenceRecord.deleteAll(tx.database)
        }
    }

    // MARK: -

    /// Update a message-owner attachment reference's received-at timestamp.
    public func updateReceivedAtTimestamp(
        owningMessageSource messageSource: AttachmentReference.Owner.MessageSource,
        newReceivedAtTimestamp receivedAtTimestamp: UInt64,
        tx: DBWriteTransaction,
    ) {
        let receivedAtTimestampColumn = Column(MessageAttachmentReferenceRecord.CodingKeys.receivedAtTimestamp)
        let ownerTypeColumn = Column(MessageAttachmentReferenceRecord.CodingKeys.ownerTypeRaw)
        let ownerRowIdColumn = Column(MessageAttachmentReferenceRecord.CodingKeys.ownerRowId)
        let sql = """
            UPDATE \(MessageAttachmentReferenceRecord.databaseTableName)
            SET \(receivedAtTimestampColumn.name) = ?
            WHERE \(ownerTypeColumn.name) = ? AND \(ownerRowIdColumn.name) = ?
        """

        failIfThrows {
            try tx.database.execute(
                sql: sql,
                arguments: [
                    receivedAtTimestamp,
                    messageSource.persistedOwnerType.rawValue,
                    messageSource.messageRowId,
                ],
            )
        }
    }

    public func updateAttachmentAsDownloaded(
        attachment: Attachment,
        from source: QueuedAttachmentDownloadRecord.SourceType,
        priority: AttachmentDownloadPriority,
        validatedMimeType: String,
        streamInfo: Attachment.StreamInfo,
        timestamp: UInt64,
        tx: DBWriteTransaction,
    ) throws(AttachmentInsertError) {
        // Find if there is already an attachment with the same plaintext hash.
        if
            let existingAttachmentId = fetchAttachmentRecord(
                sha256ContentHash: streamInfo.sha256ContentHash,
                tx: tx,
            )?.sqliteId,
            existingAttachmentId != attachment.id
        {
            throw AttachmentInsertError.duplicatePlaintextHash(existingAttachmentId: existingAttachmentId)
        }

        // Find if there is already an attachment with the same media name.
        if
            let existingAttachmentId = fetchAttachmentRecord(
                mediaName: Attachment.mediaName(
                    sha256ContentHash: streamInfo.sha256ContentHash,
                    encryptionKey: attachment.encryptionKey,
                ),
                tx: tx,
            )?.sqliteId,
            existingAttachmentId != attachment.id
        {
            throw AttachmentInsertError.duplicateMediaName(existingAttachmentId: existingAttachmentId)
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
                    attachment: attachment,
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
                    attachment: attachment,
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
                    attachment: attachment,
                    validatedMimeType: validatedMimeType,
                    streamInfo: streamInfo,
                ),
            )
        }
        newRecord.sqliteId = attachment.id
        failIfThrows {
            try newRecord.update(tx.database)
        }
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
    ) {
        owsPrecondition(
            attachment.asStream() == nil,
            "Merging stream info into an attachment that is already a stream!",
        )

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
        failIfThrows {
            try newRecord.update(tx.database)
        }
    }

    public func updateAttachmentAsFailedToDownload(
        attachment existingAttachment: Attachment,
        source: QueuedAttachmentDownloadRecord.SourceType,
        timestamp: UInt64,
        tx: DBWriteTransaction,
    ) {
        guard existingAttachment.asStream() == nil else {
            Logger.warn("Attachment already a stream!")
            return
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
        newRecord.sqliteId = existingAttachment.id
        failIfThrows {
            try newRecord.update(tx.database)
        }
    }

    public func removeMediaTierInfo(
        attachment: Attachment,
        tx: DBWriteTransaction,
    ) {
        var newRecord = Attachment.Record(
            params: .forRemovingMediaTierInfo(attachment: attachment),
        )
        newRecord.sqliteId = attachment.id
        failIfThrows {
            try newRecord.update(tx.database)
        }
    }

    public func removeThumbnailMediaTierInfo(
        attachment: Attachment,
        tx: DBWriteTransaction,
    ) {
        var newRecord = Attachment.Record(
            params: .forRemovingThumbnailMediaTierInfo(attachment: attachment),
        )
        newRecord.sqliteId = attachment.id
        failIfThrows {
            try newRecord.update(tx.database)
        }
    }

    // MARK: -

    /// Update an attachment after revalidating.
    public func updateAttachment(
        _ attachment: Attachment,
        revalidatedContentType contentType: Attachment.ContentType,
        mimeType: String,
        blurHash: String?,
        tx: DBWriteTransaction,
    ) {
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
        failIfThrows {
            try newRecord.update(tx.database)
        }
    }

    // MARK: -

    @discardableResult
    public func addReference(
        _ referenceParams: AttachmentReference.ConstructionParams,
        attachmentRowId: Attachment.IDType,
        tx: DBWriteTransaction,
    ) -> AttachmentReference {
        switch referenceParams.owner {
        case .thread(let threadSource):
            let threadReferenceRecord = ThreadAttachmentReferenceRecord(
                attachmentRowId: attachmentRowId,
                threadSource: threadSource,
            )
            switch threadSource {
            case .globalThreadWallpaperImage:
                // This is a special case; see comment on method.
                return insertGlobalThreadAttachmentReference(
                    newRecord: threadReferenceRecord,
                    tx: tx,
                )
            case .threadWallpaperImage:
                return failIfThrows {
                    try threadReferenceRecord.insert(tx.database)
                    return try AttachmentReference(record: threadReferenceRecord)
                }
            }
        case .message(let messageSource):
            let messageReferenceRecord = MessageAttachmentReferenceRecord(
                attachmentRowId: attachmentRowId,
                sourceFilename: referenceParams.sourceFilename,
                sourceUnencryptedByteCount: referenceParams.sourceUnencryptedByteCount,
                sourceMediaSizePixels: referenceParams.sourceMediaSizePixels,
                messageSource: messageSource,
            )
            return failIfThrows {
                try messageReferenceRecord.insert(tx.database)
                return try AttachmentReference(record: messageReferenceRecord)
            }
        case .storyMessage(let storyMessageSource):
            let storyReferenceRecord = StoryMessageAttachmentReferenceRecord(
                attachmentRowId: attachmentRowId,
                sourceFilename: referenceParams.sourceFilename,
                sourceUnencryptedByteCount: referenceParams.sourceUnencryptedByteCount,
                sourceMediaSizePixels: referenceParams.sourceMediaSizePixels,
                storyMessageSource: storyMessageSource,
            )
            return failIfThrows {
                try storyReferenceRecord.insert(tx.database)
                return try AttachmentReference(record: storyReferenceRecord)
            }
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
    ) {
        switch reference.owner {
        case .message(let messageSource):
            removeMessageReference(
                attachmentID: reference.attachmentRowId,
                ownerType: messageSource.persistedOwnerType,
                messageRowID: messageSource.messageRowId,
                idInMessage: messageSource.idInMessage,
                tx: tx,
            )
        case .storyMessage(let storyMessageSource):
            removeStoryMessageReference(
                attachmentID: reference.attachmentRowId,
                ownerType: storyMessageSource.persistedOwnerType,
                storyMessageRowID: storyMessageSource.storyMessageRowId,
                tx: tx,
            )
        case .thread(let threadSource):
            removeThreadReference(
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
    ) {
        let query = MessageAttachmentReferenceRecord
            .filter(MessageAttachmentReferenceRecord.Columns.attachmentRowId == attachmentID)
            .filter(MessageAttachmentReferenceRecord.Columns.ownerType == ownerType.rawValue)
            .filter(MessageAttachmentReferenceRecord.Columns.ownerRowId == messageRowID)
            .filter(MessageAttachmentReferenceRecord.Columns.idInMessage == idInMessage?.uuidString)

        failIfThrows {
            try query.deleteAll(tx.database)
        }
    }

    private func removeStoryMessageReference(
        attachmentID: Attachment.IDType,
        ownerType: StoryMessageAttachmentReferenceRecord.OwnerType,
        storyMessageRowID: Int64,
        tx: DBWriteTransaction,
    ) {
        let query = StoryMessageAttachmentReferenceRecord
            .filter(StoryMessageAttachmentReferenceRecord.Columns.attachmentRowId == attachmentID)
            .filter(StoryMessageAttachmentReferenceRecord.Columns.ownerType == ownerType.rawValue)
            .filter(StoryMessageAttachmentReferenceRecord.Columns.ownerRowId == storyMessageRowID)

        failIfThrows {
            try query.deleteAll(tx.database)
        }
    }

    private func removeThreadReference(
        attachmentID: Attachment.IDType,
        threadRowID: Int64?,
        tx: DBWriteTransaction,
    ) {
        let query = ThreadAttachmentReferenceRecord
            .filter(ThreadAttachmentReferenceRecord.Columns.attachmentRowId == attachmentID)
            .filter(ThreadAttachmentReferenceRecord.Columns.ownerRowId == threadRowID)

        failIfThrows {
            try query.deleteAll(tx.database)
        }
    }

    // MARK: -

    @discardableResult
    public func insert(
        _ attachmentParams: Attachment.ConstructionParams,
        reference referenceParams: AttachmentReference.ConstructionParams,
        tx: DBWriteTransaction,
    ) throws(AttachmentInsertError) -> Attachment {
        // Find if there is already an attachment with the same plaintext hash.
        if
            let sha256ContentHash = attachmentParams.sha256ContentHash ?? attachmentParams.streamInfo?.sha256ContentHash,
            let existingAttachmentId = fetchAttachmentRecord(
                sha256ContentHash: sha256ContentHash,
                tx: tx,
            )?.sqliteId
        {
            throw AttachmentInsertError.duplicatePlaintextHash(existingAttachmentId: existingAttachmentId)
        }

        // Find if there is already an attachment with the same media name.
        if
            let mediaName = attachmentParams.mediaName,
            let existingAttachmentId = fetchAttachmentRecord(
                mediaName: mediaName,
                tx: tx,
            )?.sqliteId
        {
            throw AttachmentInsertError.duplicateMediaName(existingAttachmentId: existingAttachmentId)
        }

        let attachment = failIfThrows {
            // Note that there are UNIQUE constraints on this table (e.g.,
            // plaintext hash and mediaName). Importantly, those are checked
            // above manually.
            var attachmentRecord = Attachment.Record(params: attachmentParams)
            try attachmentRecord.insert(tx.database)
            return try Attachment(record: attachmentRecord)
        }

        addReference(
            referenceParams,
            attachmentRowId: attachment.id,
            tx: tx,
        )

        return attachment
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
    ) -> AttachmentReference {
        let db = tx.database
        let ownerRowIdColumn = Column(ThreadAttachmentReferenceRecord.CodingKeys.ownerRowId)
        let timestampColumn = Column(ThreadAttachmentReferenceRecord.CodingKeys.creationTimestamp)
        let attachmentRowIdColumn = Column(ThreadAttachmentReferenceRecord.CodingKeys.attachmentRowId)

        let oldRecord = failIfThrows {
            try AttachmentReference.ThreadAttachmentReferenceRecord
                .filter(ownerRowIdColumn == nil)
                .fetchOne(db)
        }

        // First we insert the new row and then we delete the old one, so that the deletion
        // of the old one doesn't trigger any unecessary zero-refcount attachment deletions.
        let newReference = failIfThrows {
            try newRecord.insert(db)
            return try AttachmentReference(record: newRecord)
        }

        if let record = oldRecord {
            let query = AttachmentReference.ThreadAttachmentReferenceRecord
                .filter(ownerRowIdColumn == nil)
                .filter(timestampColumn == record.creationTimestamp)
                .filter(attachmentRowIdColumn == record.attachmentRowId)

            failIfThrows {
                let deleteCount = try query.deleteAll(db)
                // It should have deleted only the single previous row; if this matched
                // both the equality check above should have exited early.
                owsAssertDebug(deleteCount == 1)
            }
        }

        return newReference
    }

    // MARK: -

    /// Call this when viewing an attachment "fullscreen", which really means "anything
    /// other than scrolling past it in a conversation".
    public func markViewedFullscreen(
        attachment: Attachment,
        timestamp: UInt64,
        tx: DBWriteTransaction,
    ) {
        var newRecord = Attachment.Record(
            params: .forMarkingViewedFullscreen(
                attachment: attachment,
                viewTimestamp: timestamp,
            ),
        )
        newRecord.sqliteId = attachment.id
        failIfThrows {
            try newRecord.update(tx.database)
        }
    }

    // MARK: - Thread Merging

    public func updateMessageAttachmentThreadRowIdsForThreadMerge(
        fromThreadRowId: Int64,
        intoThreadRowId: Int64,
        tx: DBWriteTransaction,
    ) {
        let threadRowIdColumn = GRDB.Column(AttachmentReference.MessageAttachmentReferenceRecord.CodingKeys.threadRowId)
        let query = AttachmentReference.MessageAttachmentReferenceRecord
            .filter(threadRowIdColumn == fromThreadRowId)

        failIfThrows {
            try query.updateAll(tx.database, threadRowIdColumn.set(to: intoThreadRowId))
        }
    }
}
