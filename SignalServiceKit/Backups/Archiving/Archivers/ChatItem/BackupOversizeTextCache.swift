//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import GRDB

/// This table is used exclusively by backups to import/export inlined "oversize" text.
///
/// For Context: "oversize" text is when a message's body exceeds ``OWSMediaUtils.kOversizeTextMessageSizeThresholdBytes``;
/// the full text (including the first ``OWSMediaUtils.kOversizeTextMessageSizeThresholdBytes`` bytes) is represented as an Attachment
/// for purposes of message sending/receiving.
/// Backups have a separate, larger threshold (``BackupOversizeTextCache/maxTextLengthBytes``). All oversize
/// text attachments are truncated to this length and inlined in the backup proto (bytes past this length are simply dropped).
///
/// Because the _rest of the app_ represents oversize text as an attachment file on disk, but backups prefers not to do file i/o\*,
/// we instead write all inlined oversize text to this table to be used by import/export.
///
/// For export, we populate this table as part of backups, before opening the write tx. Population is incremental; we don't
/// wipe the table so we only need to populate any new oversize text atachments that got created since the last backup.
///
/// For import, we populate the table with inlined text from the backup, and block backup restore completion on then translating
/// all the inlined text into Attachment stream files after the backup write tx commits.
///
/// \* Two reasons to avoid file i/o
///   1. performance
///   2. during restore if we cancel/terminate the whole backup write transaction is rolled back but any file i/o we did
///     at the same time is not rolled back; we'd need a mechanism to clean up the files.
public struct BackupOversizeTextCache: Codable, FetchableRecord, MutablePersistableRecord {

    /// Every row in this table is limited to this many bytes (not characters) of text, in both
    /// the Swift model object and at the SQLite level.
    public static let maxTextLengthBytes = OWSMediaUtils.kMaxOversizeTextMessageReceiveSizeBytes

    public typealias IDType = Int64

    public private(set) var id: IDType?
    public let attachmentRowId: Attachment.IDType
    public let text: String

    fileprivate init(id: IDType?, attachmentRowId: Attachment.IDType, text: String) {
        self.id = id
        self.attachmentRowId = attachmentRowId
        self.text = text
    }

    // MARK: FetchableRecord

    public static var databaseTableName: String { "BackupOversizeTextCache" }

    // MARK: MutablePersistableRecord

    public mutating func didInsert(with rowID: Int64, for column: String?) {
        self.id = rowID
    }

    // MARK: Codable

    public enum CodingKeys: String, CodingKey {
        case id
        case attachmentRowId
        case text
    }
}

extension BackupArchive {
    struct ArchivedMessageBody {
        let inlinedText: String
        let oversizedTextPointer: BackupProto_FilePointer?
    }
}

class BackupArchiveInlinedOversizeTextArchiver {

    private let attachmentsArchiver: BackupArchiveMessageAttachmentArchiver
    private let attachmentContentValidator: AttachmentContentValidator
    private let attachmentManager: AttachmentManager
    private let attachmentStore: AttachmentStore
    private let db: DB
    private let logger: PrefixedLogger

    private static let lastRestoredRowIdKey = "lastRestoredRowIdKey"
    private let kvStore = KeyValueStore(collection: "BackupOversizeTextCacheStore")

    // MARK: - Public API

    init(
        attachmentsArchiver: BackupArchiveMessageAttachmentArchiver,
        attachmentContentValidator: AttachmentContentValidator,
        attachmentManager: AttachmentManager,
        attachmentStore: AttachmentStore,
        db: DB,
    ) {
        self.attachmentsArchiver = attachmentsArchiver
        self.attachmentContentValidator = attachmentContentValidator
        self.attachmentManager = attachmentManager
        self.attachmentStore = attachmentStore
        self.db = db
        self.logger = PrefixedLogger(prefix: "[Backups]")
    }

    // MARK: - Archive

    /// Populate the BackupOversizeTextCache table with any oversize text attachment streams that weren't
    /// already present. After calling this method, BackupOversizeTextCache can be read for backup export.
    /// Message processing (and sending) should be suspended while this runs, so that new attachments are not created,
    func populateTableIncrementally(progress: OWSProgressSink?) async throws {
        // We can get away with fetching attachment ids in one read then processing in separate
        // writes because no new attachments should be created while backups is running.
        // Worst case, we miss an attachment and the oversized text ends up truncated
        // or as a pointer in the backup.
        var attachmentIdIndex = 0
        let attachmentIds: [Attachment.IDType] = try db.read { tx in
            try self.attachmentRowIdsForTablePopulation(tx: tx)
        }

        let progressSource: OWSProgressSource?
        if let progress {
            progressSource = await progress.addSource(
                withLabel: "BackupOversizeTextCache",
                unitCount: UInt64(attachmentIds.count),
            )
        } else {
            progressSource = nil
        }

        if attachmentIds.isEmpty {
            return
        }

        try await TimeGatedBatch.processAll(db: db) { tx in
            let batchIds = attachmentIds.dropFirst(attachmentIdIndex).prefix(Self.batchCount)
            attachmentIdIndex += Self.batchCount
            try self.populateTableIncrementallyBatch(
                attachmentIds: batchIds,
                progress: progressSource,
                tx: tx,
            )
            return batchIds.isEmpty ? .done(()) : .more
        }
    }

    typealias ArchivedMessageBody = BackupArchive.ArchivedMessageBody

    func archiveMessageBody(
        text: String,
        messageRowId: Int64,
        messageId: BackupArchive.InteractionUniqueId,
        context: BackupArchive.ArchivingContext,
    ) -> BackupArchive.ArchiveInteractionResult<ArchivedMessageBody> {
        var text = text
        // It was possible, in the past, to end up with inlined text
        // longer than OWSMediaUtils.kOversizeTextMessageSizeThresholdBytes; inline
        // this now at the oversize text limit.
        if text.lengthOfBytes(using: .utf8) > BackupOversizeTextCache.maxTextLengthBytes {
            text = text.trimToUtf8ByteCount(BackupOversizeTextCache.maxTextLengthBytes)
        }

        let oversizedTextReference = attachmentStore.fetchAnyReference(
            owner: .messageOversizeText(messageRowId: messageRowId),
            tx: context.tx,
        )
        guard
            let oversizedTextReference
        else {
            // No oversized text if there's no corresponding attachment!
            return .success(ArchivedMessageBody(
                inlinedText: text,
                oversizedTextPointer: nil,
            ))
        }

        let oversizedText: String?
        do {
            oversizedText = try self.fetchInlineableOversizedText(
                attachmentId: oversizedTextReference.attachmentRowId,
                tx: context.tx,
            )
        } catch {
            return .completeFailure(.fatalArchiveError(.oversizedTextCacheFetchError(error)))
        }

        if let oversizedText {
            // If we had downloaded the attachment, we'd have an oversized text to inline.
            // If we inline, no need to include a pointer (in fact, doing so is disallowed).
            return .success(ArchivedMessageBody(
                inlinedText: oversizedText,
                oversizedTextPointer: nil,
            ))
        } else {
            // Otherwise the best we can do is return a pointer.
            guard let attachment = attachmentStore.fetch(id: oversizedTextReference.attachmentRowId, tx: context.tx) else {
                return .success(ArchivedMessageBody(
                    inlinedText: text,
                    oversizedTextPointer: nil,
                ))
            }
            var partialErrors = [BackupArchive.ArchiveFrameError<BackupArchive.InteractionUniqueId>]()
            let pointerResult = attachmentsArchiver.archiveOversizeTextAttachment(
                ReferencedAttachment(reference: oversizedTextReference, attachment: attachment),
                context: context,
            )
            switch pointerResult.bubbleUp(ArchivedMessageBody.self, partialErrors: &partialErrors) {
            case .bubbleUpError(let error):
                return error
            case .continue(let oversizedTextPointer):
                let body = ArchivedMessageBody(
                    inlinedText: text.trimToUtf8ByteCount(OWSMediaUtils.kOversizeTextMessageSizeThresholdBytes),
                    oversizedTextPointer: oversizedTextPointer,
                )
                if partialErrors.isEmpty {
                    return .success(body)
                } else {
                    return .partialFailure(body, partialErrors)
                }
            }
        }
    }

    // MARK: Restore

    typealias RestoredMessageBody = BackupArchive.RestoredMessageContents.Text.RestoredMessageBody

    func restoreMessageBody(
        _ text: String,
        bodyRanges: MessageBodyRanges,
        oversizeTextAttachment: BackupProto_FilePointer?,
        chatItemId: BackupArchive.ChatItemId,
    ) -> BackupArchive.RestoreInteractionResult<RestoredMessageBody?> {
        var partialErrors = [BackupArchive.RestoreFrameError<BackupArchive.ChatItemId>]()

        var text = text
        let inlinedTextLength = text.lengthOfBytes(using: .utf8)
        if inlinedTextLength > BackupOversizeTextCache.maxTextLengthBytes {
            // It is never allowed to have text beyond this limit inlined,
            // truncate and drop any excess.
            partialErrors.append(.restoreFrameError(
                .invalidProtoData(.standardMessageWayTooOversizedBody),
                chatItemId,
            ))
            text = text.trimToUtf8ByteCount(BackupOversizeTextCache.maxTextLengthBytes)
        }
        let inlinedBody: MessageBody
        if inlinedTextLength > OWSMediaUtils.kOversizeTextMessageSizeThresholdBytes {
            inlinedBody = MessageBody(
                text: text.trimToUtf8ByteCount(OWSMediaUtils.kOversizeTextMessageSizeThresholdBytes),
                ranges: bodyRanges,
            )
        } else {
            inlinedBody = MessageBody(text: text, ranges: bodyRanges)
        }

        let oversizeText: RestoredMessageBody.OversizeText?
        if let oversizeTextAttachment {
            if text.isEmpty {
                return .messageFailure([.restoreFrameError(
                    .invalidProtoData(.longTextStandardMessageMissingBody),
                    chatItemId,
                )])
            } else if inlinedTextLength > OWSMediaUtils.kOversizeTextMessageSizeThresholdBytes {
                // If we have an oversize text attachment, we are not allowed to _also_
                // have inlined oversize text (that exceeds the standard body length limit).
                partialErrors.append(.restoreFrameError(
                    .invalidProtoData(.longTextStandardMessageWithOversizeBody),
                    chatItemId,
                ))
                // Drop the pointer; treat the text as inlined.
                oversizeText = .inlined(text)
            } else {
                oversizeText = .attachmentPointer(oversizeTextAttachment)
            }
        } else if inlinedTextLength > OWSMediaUtils.kOversizeTextMessageSizeThresholdBytes {
            oversizeText = .inlined(text)
        } else {
            oversizeText = nil
        }

        let restoredBody = RestoredMessageBody(
            inlinedBody: inlinedBody,
            oversizeText: oversizeText,
        )

        if partialErrors.isEmpty {
            return .success(restoredBody)
        } else {
            // We still get text, albeit potentially truncated, if
            // we have these failures. So count as a partial restore, not
            // complete failure.
            return .partialRestore(restoredBody, partialErrors)
        }
    }

    /// Restore oversized text from a backup, preparing it to be fully restored later
    /// (after this tx commits) by `finishRestoringAll()`.
    func restoreOversizeText(
        _ oversizedText: RestoredMessageBody.OversizeText,
        messageRowId: Int64,
        message: TSMessage,
        thread: BackupArchive.ChatThread,
        chatItemId: BackupArchive.ChatItemId,
        context: BackupArchive.ChatItemRestoringContext,
    ) -> BackupArchive.RestoreInteractionResult<Void> {
        let text: String
        switch oversizedText {
        case .attachmentPointer(let attachmentPointer):
            return attachmentsArchiver.restoreOversizeTextAttachment(
                attachmentPointer,
                chatItemId: chatItemId,
                messageRowId: messageRowId,
                message: message,
                thread: thread,
                context: context,
            )
        case .inlined(let _text):
            text = _text
        }

        // Construct an undownloadable FilePointer proto so that we can use it
        // to construct a placeholder, undownloadable attachment that we will
        // later populate with the oversized text in `finishRestoringAll`
        var fakeProto = BackupProto_FilePointer()
        fakeProto.locatorInfo = BackupProto_FilePointer.LocatorInfo()
        fakeProto.contentType = MimeType.textXSignalPlain.rawValue

        let ownedAttachment = OwnedAttachmentBackupPointerProto(
            proto: fakeProto,
            renderingFlag: .default,
            clientUUID: nil,
            owner: .messageOversizeText(.init(
                messageRowId: messageRowId,
                receivedAtTimestamp: message.receivedAtTimestamp,
                threadRowId: thread.threadRowId,
                isPastEditRevision: message.isPastEditRevision(),
            )),
        )

        // Whether we're free or paid this should be set when we restored the account data frame.
        guard let uploadEra = context.uploadEra else {
            return .messageFailure([.restoreFrameError(.invalidProtoData(.accountDataNotFound), chatItemId)])
        }

        let error = attachmentManager.createAttachmentPointer(
            from: ownedAttachment,
            uploadEra: uploadEra,
            attachmentByteCounter: context.attachmentByteCounter,
            tx: context.tx,
        )
        if error != nil {
            return .messageFailure([.restoreFrameError(
                .failedToCreateAttachment,
                chatItemId,
            )])
        }

        // Fetch the attachment reference we just created.
        let reference = attachmentStore.fetchAnyReference(
            owner: .messageOversizeText(messageRowId: messageRowId),
            tx: context.tx,
        )

        guard let reference else {
            return .messageFailure([.restoreFrameError(
                .failedToCreateAttachment,
                chatItemId,
            )])
        }

        do {
            try self.insert(attachmentId: reference.attachmentRowId, text: text, tx: context.tx)
        } catch {
            return .messageFailure([.restoreFrameError(
                .failedToCreateAttachment,
                chatItemId,
            )])
        }

        return .success(())
    }

    func finishRestoringOversizedTextAttachments(
        progress: OWSProgressSink?,
    ) async throws {
        let progressSource: OWSProgressSource?
        if let progress {
            let unitCount = try db.read { tx in
                let minId = kvStore.getInt64(Self.lastRestoredRowIdKey, defaultValue: 0, transaction: tx)
                return try BackupOversizeTextCache
                    .filter(Column(BackupOversizeTextCache.CodingKeys.id) > minId)
                    .fetchCount(tx.database)
            }
            progressSource = await progress.addSource(withLabel: "OversizedTexts", unitCount: UInt64(max(1, unitCount)))
        } else {
            progressSource = nil
        }

        var finished = false
        while !finished {
            finished = try await self.finishRestoringOversizedTextAttachmentBatch()
            if let progressSource {
                let remainingUnitCount = progressSource.totalUnitCount - progressSource.completedUnitCount
                if remainingUnitCount > 0 {
                    progressSource.incrementCompletedUnitCount(by: min(remainingUnitCount, UInt64(Self.batchCount)))
                }
            }
        }
    }

    // MARK: - Helpers

    private func fetchInlineableOversizedText(attachmentId: Attachment.IDType, tx: DBReadTransaction) throws -> String? {
        return try BackupOversizeTextCache
            .filter(Column(BackupOversizeTextCache.CodingKeys.attachmentRowId) == attachmentId)
            .fetchOne(tx.database)?
            .text
    }

    @discardableResult
    private func insert(attachmentId: Attachment.IDType, text: String, tx: DBWriteTransaction) throws -> BackupOversizeTextCache.IDType {
        var text = text
        if text.lengthOfBytes(using: .utf8) > BackupOversizeTextCache.maxTextLengthBytes {
            logger.error("Oversized backup text too long! Truncating...")
            text = text.trimToUtf8ByteCount(BackupOversizeTextCache.maxTextLengthBytes)
        }
        var record = BackupOversizeTextCache(id: nil, attachmentRowId: attachmentId, text: text)
        try record.insert(tx.database)
        return record.id!
    }

    // Work in batches of 50 so we can make (and commit) incremental progress.
    static let batchCount = 50

    private func attachmentRowIdsForTablePopulation(tx: DBReadTransaction) throws -> [Attachment.IDType] {
        return try Attachment.Record
            .filter(Column(Attachment.Record.CodingKeys.contentType) == Attachment.ContentTypeRaw.file.rawValue)
            .filter(Column(Attachment.Record.CodingKeys.mimeType) == MimeType.textXSignalPlain.rawValue)
            .filter(Column(Attachment.Record.CodingKeys.localRelativeFilePath) != nil)
            // Only rows not already represented in the oversize text cache table
            .filter(
                !BackupOversizeTextCache
                    .select(Column(BackupOversizeTextCache.CodingKeys.attachmentRowId))
                    .filter(
                        SQL(stringLiteral: "\(Attachment.Record.databaseTableName).\(Attachment.Record.CodingKeys.sqliteId.rawValue)")
                            == Column(BackupOversizeTextCache.CodingKeys.attachmentRowId))
                    .exists(),
            )
            .select(Column(Attachment.Record.CodingKeys.sqliteId))
            .fetchAll(tx.database)
    }

    // Returns number of rows processed. Returns 0 if finished.
    private func populateTableIncrementallyBatch(
        attachmentIds: ArraySlice<Attachment.IDType>,
        progress: OWSProgressSource?,
        tx: DBWriteTransaction,
    ) throws {
        var maxRecordId: BackupOversizeTextCache.IDType = 0
        for attachmentId in attachmentIds {
            guard let stream = attachmentStore.fetch(id: attachmentId, tx: tx)?.asStream() else {
                continue
            }
            owsAssertDebug(stream.contentType.raw == .file)
            owsAssertDebug(stream.mimeType == MimeType.textXSignalPlain.rawValue)
            let text = try stream.decryptedLongText()
            let recordId = try self.insert(attachmentId: stream.id, text: text, tx: tx)
            maxRecordId = max(maxRecordId, recordId)
            if let progress {
                progress.incrementCompletedUnitCount(by: 1)
            }
        }
        // Treat these rows as "restored" (since we already have a corresponding attachment stream).
        // We'll never do a restore after doing an archive, but its still best practice to set.
        kvStore.setInt64(maxRecordId, key: Self.lastRestoredRowIdKey, transaction: tx)
    }

    // Returns true if done (no more rows to restore)
    private func finishRestoringOversizedTextAttachmentBatch() async throws -> Bool {
        let records = try db.read { tx in
            let minId = kvStore.getInt64(Self.lastRestoredRowIdKey, defaultValue: 0, transaction: tx)
            return try BackupOversizeTextCache
                .filter(Column(BackupOversizeTextCache.CodingKeys.id) > minId)
                .order(Column(BackupOversizeTextCache.CodingKeys.id).asc)
                .limit(Self.batchCount)
                .fetchAll(tx.database)
        }
        if records.isEmpty {
            return true
        }
        var cacheIdToAttachmentId = [BackupOversizeTextCache.IDType: Attachment.IDType]()
        var attachmentIdToCacheIds = [Attachment.IDType: [BackupOversizeTextCache.IDType]]()
        var messageBodies = [BackupOversizeTextCache.IDType: MessageBody]()
        for record in records {
            cacheIdToAttachmentId[record.id!] = record.attachmentRowId
            var cacheIds = attachmentIdToCacheIds[record.attachmentRowId] ?? []
            cacheIds.append(record.id!)
            attachmentIdToCacheIds[record.attachmentRowId] = cacheIds
            messageBodies[record.id!] = MessageBody(text: record.text, ranges: .empty)
        }

        var attachmentKeys = [BackupOversizeTextCache.IDType: AttachmentKey]()
        try db.read { tx in
            for attachment in attachmentStore.fetch(ids: Array(attachmentIdToCacheIds.keys), tx: tx) {
                for recordId in attachmentIdToCacheIds[attachment.id] ?? [] {
                    attachmentKeys[recordId] = try AttachmentKey(combinedKey: attachment.encryptionKey)
                }
            }
        }

        do {
            let pendingAttachments = try await attachmentContentValidator.prepareOversizeTextsIfNeeded(
                from: messageBodies,
                attachmentKeys: attachmentKeys,
            )

            try await db.awaitableWriteWithRollbackIfThrows { tx in
                var maxRecordId: BackupOversizeTextCache.IDType = 0
                defer {
                    // Mark progress by writing the max record id.
                    kvStore.setInt64(maxRecordId, key: Self.lastRestoredRowIdKey, transaction: tx)
                }
                for (recordId, validatedMessageBody) in pendingAttachments {
                    maxRecordId = max(maxRecordId, recordId)
                    guard let pendingAttachment = validatedMessageBody.oversizeText else {
                        owsFailDebug("Got oversize text thats fits a normal message?")
                        continue
                    }
                    guard let attachmentId = cacheIdToAttachmentId[recordId] else {
                        owsFailDebug("Missing attachment id")
                        continue
                    }
                    try attachmentManager.updateAttachmentWithOversizeTextFromBackup(
                        attachmentId: attachmentId,
                        pendingAttachment: pendingAttachment,
                        tx: tx,
                    )
                }
            }
        } catch let error {
            owsFailDebug("Unable to process batch \(error.grdbErrorForLogging)")
            // Skip this batch; the backup already committed and theres no going back,
            // so all we can do is drop this long text to avoid bricking the app entirely.
            let maxRecordId: BackupOversizeTextCache.IDType = records.lazy.compactMap(\.id).max() ?? 0
            await db.awaitableWriteWithRollbackIfThrows { tx in
                kvStore.setInt64(maxRecordId, key: Self.lastRestoredRowIdKey, transaction: tx)
            }
        }
        return false
    }
}
