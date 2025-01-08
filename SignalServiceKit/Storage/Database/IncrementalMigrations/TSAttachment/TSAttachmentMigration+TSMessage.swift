//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

extension TSAttachmentMigration {

    /// Migrate TSMessage TSAttachments to v2 Attachments and MessageAttachmentReferences.
    ///
    /// The migration works in 4 phases, and can be run either incrementally (while the app is running
    /// or backgrounded) or as a blocking GRDB migration.
    ///
    /// The 4 phases must be broken up into at least 3 db transactions. (Why? Filesystem changes are
    /// not part of the db transaction, so we need to first "reserve" the final file location in the db and then
    /// write the file. If the latter step fails we will just rewrite to the same file location next time we retry.)
    /// Phases 1/2 must be a separate transaction from phase 3, which must be different from phase 4.
    ///
    /// Phase 1: "prepare" TSMessages for migration, starting with the newest first.
    /// This will be enabled at the same time that we enable the FeatureFlag to use v2 attachments for
    /// _new_ messages, so the start point marks the cutoff between legacy and v2 attachments.
    /// We work backwards, newest first, to migrate the legacy attachments.
    /// We "prepare" a TSMessage by inserting a row into the TSAttachmentMigration table.
    ///
    /// Phase 2: I lied in phase 1; _some_ new messages can use legacy attachments even after the cutoff:
    /// newly inserted edits on a TSMessage with un-migrated TSAttachments on it.
    /// This is somewhat niche, and rare, and migrating oldest-first can result in some buggy behavior in the
    /// media gallery, which is why we _mostly_ go backwards (phase 1), but then do a final cleanup by
    /// going forwards from the cutoff. Since this only applies to edits made in a narrow window, we mostly
    /// expect this phase to no-op and just walk over new messages finding nothing needing migrating.
    ///
    /// Phase 3: Now that they're prepared, we walk over the TSAttachmentMigration table and migrate
    /// the TSAttachments one by one. This is the bulk of the migration. We always work in newest-first order.
    ///
    /// Phase 4: Delete all the TSAttachment folders and files on disk. Safe to do once phase 3 is complete.
    ///
    /// When run as a blocking GRDB migration, run the phases in order in back to back, but separate, migrations.
    /// This ensures they each get their own transaction, but nothing else can touch the db between them.
    ///
    /// When run iteratively, we move back and forth between phases 1, 2, and 3.
    /// We prepare batches of messages newest first (phase 1) and migrate them (phase 3) until we reach
    /// the oldest TSMessage. Then we prepare batches oldest first starting at the cutoff (phase 2) and migrate
    /// them (phase 3) until we reach the newest TSMessage. At that point we are done and run phase 4.
    public enum TSMessageMigration {

        // MARK: - Phase 1/2

        /// Phases 1 and 2 when applying as a blocking-on-launch GRDB migration.
        static func prepareBlockingTSMessageMigration(tx: GRDBWriteTransaction) {
            // If we finished phase 2, we are done.
            let finished: Bool? = Self.read(key: finishedGoingForwardsKey, tx: tx)
            if finished == true {
                return
            }

            guard
                let maxMigratedRowId: Int64 = Self.read(key: maxMigratedInteractionRowIdKey, tx: tx)
            else {
                // We've made zero progress. Migrate working backwards from the top (phase 1).
                // No need for phase 2, as this will just run top to bottom.
                _ = prepareTSMessageMigrationBatch(batchSize: nil, maxRowId: nil, minRowId: nil, tx: tx)
                return
            }

            let finishedGoingBackwards: Bool? = Self.read(key: finishedGoingBackwardsKey, tx: tx)
            if finishedGoingBackwards != true {
                // We've made partial progress in phase 1, pick up where we left off working backwards.
                let minMigratedRowId: Int64? = Self.read(key: minMigratedInteractionRowIdKey, tx: tx)
                _ = prepareTSMessageMigrationBatch(
                    batchSize: nil,
                    maxRowId: minMigratedRowId ?? maxMigratedRowId,
                    minRowId: nil,
                    tx: tx
                )
            }

            // We finished phase 1. Finish phase 2, picking up wherever we left off.
            _ = prepareTSMessageMigrationBatch(
                batchSize: nil,
                maxRowId: nil,
                minRowId: maxMigratedRowId,
                tx: tx
            )
        }

        /// Phases 1 and 2 when running as an iterative migration.
        /// - Returns
        /// True if any rows were migrated; callers should keep calling until it returns false.
        public static func prepareNextIterativeTSMessageMigrationBatch(tx: GRDBWriteTransaction) -> Bool {
            // If we finished phase 2, we are done.
            let finished: Bool? = Self.read(key: finishedGoingForwardsKey, tx: tx)
            if finished == true {
                return false
            }

            let batchSize = 5

            guard
                let maxMigratedRowId: Int64 = Self.read(key: maxMigratedInteractionRowIdKey, tx: tx)
            else {
                return Self.prepareNextIterativeBatchPhase1ColdStart(batchSize: batchSize, tx: tx)
            }

            // If phase 1 is done, proceed to phase 2.
            let finishedGoingBackwards: Bool? = Self.read(key: finishedGoingBackwardsKey, tx: tx)
            if finishedGoingBackwards == true {
                return Self.prepareNextIteraveBatchPhase2(
                    batchSize: batchSize,
                    maxMigratedRowId: maxMigratedRowId,
                    tx: tx
                )
            }

            // Otherwise continue our progress on phase 1.
            return Self.prepareNextIterativeBatchPhase1(
                batchSize: batchSize,
                maxMigratedRowId: maxMigratedRowId,
                tx: tx
            )
        }

        /// Cold start phase 1; start preparing messages newest-first from the top.
        ///
        /// - Returns
        /// True if any rows were migrated.
        private static func prepareNextIterativeBatchPhase1ColdStart(
            batchSize: Int,
            tx: GRDBWriteTransaction
        ) -> Bool {
            // We've made zero progress. Migrate working backwards from the top (phase 1).
            let maxInteractionRowId: Int64?
            do {
                maxInteractionRowId = try Int64.fetchOne(tx.database, sql: "SELECT max(id) from model_TSInteraction;")
            } catch {
                owsFail("Failed to read interaction row id")
            }
            guard let maxInteractionRowId else {
                // No interactions. Must be a new install, which is fine, it means we are instantly done.
                Self.write(true, key: finishedGoingForwardsKey, tx: tx)
                return false
            }
            // Write the cutoff point to disk.
            Self.write(maxInteractionRowId, key: maxMigratedInteractionRowIdKey, tx: tx)

            // Start going backwards from the top (phase 1).
            let lastMigratedRowId = prepareTSMessageMigrationBatch(batchSize: batchSize, maxRowId: nil, minRowId: nil, tx: tx)

            if let lastMigratedRowId {
                // Save our incremental progress.
                Self.write(lastMigratedRowId, key: minMigratedInteractionRowIdKey, tx: tx)
                return true
            } else {
                // If we got nothing back, there were no messages needing migrating. Finish phase 1;
                // next batch we try and run will proceed to phase 2.
                Self.write(true, key: finishedGoingBackwardsKey, tx: tx)
                return true
            }
        }

        /// - Returns
        /// True if any rows were migrated.
        private static func prepareNextIterativeBatchPhase1(
            batchSize: Int,
            maxMigratedRowId: Int64,
            tx: GRDBWriteTransaction
        ) -> Bool {
            // Proceed going backwards from the min id, continuing our progress on phase 1.
            let minMigratedRowId: Int64? = Self.read(key: minMigratedInteractionRowIdKey, tx: tx)
            let lastMigratedId = minMigratedRowId ?? maxMigratedRowId

            let newMinMigratedId =
                prepareTSMessageMigrationBatch(batchSize: batchSize, maxRowId: lastMigratedId, minRowId: nil, tx: tx)
            if let newMinMigratedId {
                // Save our incremental progress.
                Self.write(newMinMigratedId, key: minMigratedInteractionRowIdKey, tx: tx)
                return true
            } else {
                // If we got nothing back, there were no messages needing migrating. Finish phase 1;
                // next batch we try and run will proceed to phase 2.
                Self.write(true, key: finishedGoingBackwardsKey, tx: tx)
                return true
            }
        }

        /// - Returns
        /// True if any rows were migrated.
        private static func prepareNextIteraveBatchPhase2(
            batchSize: Int,
            maxMigratedRowId: Int64,
            tx: GRDBWriteTransaction
        ) -> Bool {
            let newMaxMigratedId =
                prepareTSMessageMigrationBatch(batchSize: batchSize, maxRowId: nil, minRowId: maxMigratedRowId, tx: tx)
            if let newMaxMigratedId {
                // Save our incremental progress.
                Self.write(newMaxMigratedId, key: maxMigratedInteractionRowIdKey, tx: tx)
                return true
            } else {
                // If we got nothing back, we are finished with phase 2.
                // The value of `maxMigratedInteractionRowIdKey` will stay stale,
                // but once we write `finishedGoingForwardsKey` it doesn't matter;
                // we are done and none of the others get read.
                Self.write(true, key: finishedGoingForwardsKey, tx: tx)
                return false
            }
        }

        // MARK: In-progress state

        private static let collectionName = "TSInteraction_TSAttachmentMigration"
        // Once true, minMigratedInteractionRowIdKey should be ignored and considered stale; phase 1 is done.
        private static let finishedGoingBackwardsKey = "finishedGoingBackwards"
        // Once set to true, all other keys are to be ignored and considered stale; phases 1 and 2 are done.
        private static let finishedGoingForwardsKey = "finishedGoingForwards"
        // Marks how far we got in phase 1, as we work our way backwards (larger to smaller row ids).
        private static let minMigratedInteractionRowIdKey = "minMigratedInteractionRowId"
        // During phase 1, marks the cutoff where we started migrating.
        // During phase 2, marks how far we got as we work our way forwards (smaller to larger row ids).
        // Once phase 2 is done (finishedGoingForwardsKey = true) the value is stale and should be ignored.
        private static let maxMigratedInteractionRowIdKey = "maxMigratedInteractionRowId"

        private static func read<T: DatabaseValueConvertible>(key: String, tx: GRDBWriteTransaction) -> T? {
            do {
                return try T.fetchOne(
                    tx.database,
                    sql: "SELECT value from keyvalue WHERE collection = ? AND key = ?",
                    arguments: [Self.collectionName, key]
                )
            } catch {
                owsFail("Unable to read key \(key)")
            }
        }

        private static func write<T: DatabaseValueConvertible>(_ t: T, key: String, tx: GRDBWriteTransaction) {
            do {
                try tx.database.execute(
                    sql: """
                        INSERT INTO keyvalue (collection,key,value) VALUES (?,?,?)
                        ON CONFLICT(key,collection) DO UPDATE SET value = ?;
                        """,
                    arguments: [Self.collectionName, key, t, t]
                )
            } catch {
                owsFail("Unable to write key \(key)")
            }
        }

        // MARK: - Phase 3

        /// Phase 3 when applying as a blocking-on-launch GRDB migration.
        static func completeBlockingTSMessageMigration(tx: GRDBWriteTransaction) {
            _ = Self.completeTSMessageMigrationBatch(batchSize: nil, errorLogger: { _ in }, tx: tx)
        }

        /// Phase 3 when running as an iterative migration.
        ///
        /// - parameter errorLogger: For logging errors. MUST NOT open a database transaction.
        ///
        /// - Returns
        /// True if any rows were migrated; callers should keep calling until it returns false.
        public static func completeNextIterativeTSMessageMigrationBatch(
            batchSize: Int = 5,
            errorLogger: (String) -> Void,
            tx: GRDBWriteTransaction
        ) -> Bool {
            let count = Self.completeTSMessageMigrationBatch(batchSize: batchSize, errorLogger: errorLogger, tx: tx)
            return count > 0
        }

        // MARK: - Phase 4

        /// Phase 4.
        /// Works the same whether its run "iteratively" or as a blocking GRDB migration.
        public static func cleanUpTSAttachmentFiles() {
            // Just try and delete the folder, don't bother checking if we've tried before.
            // If the folder is already deleted, this is super cheap.
            let rootPath = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: TSConstants.applicationGroup
            )!.path
            let attachmentsFolder = rootPath.appendingPathComponent("Attachments")
            guard OWSFileSystem.deleteFileIfExists(attachmentsFolder) == true else {
                owsFailDebug("Unable to delete folder!")
                return
            }
        }

        // MARK: - Migrating batches

        /// Does preparation for another batch, returning the last interaction row id migrated.
        ///
        /// If a batch size is provided, prepares only that many messages. Otherwise prepares them all.
        ///
        /// If maxRowId is provided, prepares messages in descending order by row id starting with the provided id (non-inclusive).
        /// If minRowId is provided, prepares messages in ascending order by row id starting with the provided id (non-inclusive).
        /// If neither is provided, prepares messages in descending order by row id starting with the latest message (inclusive).
        private static func prepareTSMessageMigrationBatch(
            batchSize: Int?,
            maxRowId: Int64?,
            minRowId: Int64?,
            tx: GRDBWriteTransaction
        ) -> Int64? {
            var sql = "SELECT * FROM model_TSInteraction"
            var arguments = StatementArguments()
            if let maxRowId {
                sql += " WHERE id < ? ORDER BY id DESC;"
                _ = arguments.append(contentsOf: [maxRowId])
            } else if let minRowId {
                sql += " WHERE id > ? ORDER BY id ASC;"
                _ = arguments.append(contentsOf: [minRowId])
            } else {
                sql += " ORDER BY id DESC"
            }
            let cursor: GRDB.RowCursor
            do {
                cursor = try Row.fetchCursor(
                    tx.database,
                    sql: sql,
                    arguments: arguments
                )
            } catch {
                owsFail("Failed to create interaction cursor")
            }
            func next() -> Row? {
                do {
                    return try cursor.next()
                } catch {
                    owsFail("Failed to iterate interaction cursor")
                }
            }
            var batchCount = 0
            var lastMessageRowId: Int64?
            while batchCount < batchSize ?? Int.max, let messageRow = next() {
                guard let messageRowId = messageRow["id"] as? Int64 else {
                    owsFail("TSInteraction row without id")
                }

                guard prepareTSMessageForMigration(
                    messageRow: messageRow,
                    messageRowId: messageRowId,
                    tx: tx
                ) else {
                    continue
                }
                batchCount += 1
                lastMessageRowId = messageRowId
            }
            return lastMessageRowId
        }

        /// Returns true if there was anything to migrate.
        fileprivate static func prepareTSMessageForMigration(
            messageRow: Row,
            messageRowId: Int64,
            tx: GRDBWriteTransaction
        ) -> Bool {
            // Check if the message has any attachments.
            let attachmentIds: [String] = (
                bodyAttachmentIds(messageRow: messageRow)
                + [
                    contactAttachmentId(messageRow: messageRow),
                    stickerAttachmentId(messageRow: messageRow),
                    linkPreviewAttachmentId(messageRow: messageRow),
                    quoteAttachmentId(messageRow: messageRow)
                ]
            ).compacted()

            guard !attachmentIds.isEmpty else {
                return false
            }

            for attachmentId in attachmentIds {
                var reservedFileIds = TSAttachmentMigration.V1AttachmentReservedFileIds(
                    tsAttachmentUniqueId: attachmentId,
                    interactionRowId: messageRowId,
                    storyMessageRowId: nil,
                    reservedV2AttachmentPrimaryFileId: UUID(),
                    reservedV2AttachmentAudioWaveformFileId: UUID(),
                    reservedV2AttachmentVideoStillFrameFileId: UUID()
                )
                do {
                    try reservedFileIds.insert(tx.database)
                } catch {
                    owsFail("Unable to insert reserved file ids")
                }
            }
            return true
        }

        private static func logAndFail(_ errorLogger: (String) -> Void, _ logMessage: String) -> Never {
            errorLogger(logMessage)
            owsFail(logMessage)
        }

        /// Completes another prepared batch, returns count of touched message rows.
        ///
        /// If a batch size is provided, prepares only that many prepared messages. Otherwise migares all prepared messages.
        private static func completeTSMessageMigrationBatch(
            batchSize: Int?,
            errorLogger: (String) -> Void,
            tx: GRDBWriteTransaction
        ) -> Int {
            let isRunningIteratively = batchSize != nil

            let reservedFileIdsCursor: RecordCursor<TSAttachmentMigration.V1AttachmentReservedFileIds>
            do {
                reservedFileIdsCursor = try TSAttachmentMigration.V1AttachmentReservedFileIds
                    .filter(Column("interactionRowId") != nil)
                    .order([Column("interactionRowId").desc])
                    .fetchCursor(tx.database)
            } catch {
                logAndFail(errorLogger, "Unable to read reserved file ids!")
            }

            func nextReservedFileIds() -> TSAttachmentMigration.V1AttachmentReservedFileIds? {
                do {
                    return try reservedFileIdsCursor.next()
                } catch {
                    logAndFail(errorLogger, "Unable to read next reserved file ids!")
                }
            }

            // row id to (true = migrated) (false = needs re-reservation for next batch)
            var migratedMessageRowIds = [Int64: Bool]()
            var deletedAttachments = [TSAttachmentMigration.V1Attachment]()
            while migratedMessageRowIds.count < batchSize ?? Int.max, let reservedFileIds = nextReservedFileIds() {
                autoreleasepool {
                    guard let messageRowId = reservedFileIds.interactionRowId else {
                        return
                    }
                    if migratedMessageRowIds[messageRowId] != nil {
                        return
                    }

                    let messageRow: GRDB.Row?
                    do {
                        messageRow = try Row.fetchOne(
                            tx.database,
                            sql: "SELECT * FROM model_TSInteraction WHERE id = ?;",
                            arguments: [messageRowId]
                        )
                    } catch {
                        logAndFail(errorLogger, "Failed to fetch interaction row")
                    }
                    guard let messageRow else {
                        // The message got deleted. Still, count this in the batch
                        // size so we don't iterate over deleted rows unbounded.
                        migratedMessageRowIds[messageRowId] = true
                        reservedFileIds.cleanUpFiles()
                        return
                    }

                    // We _have_ to migrate everything on a given TSMessage at once.
                    // Fetch all the reserved ids for the message.
                    let reservedFileIdsForMessage: [TSAttachmentMigration.V1AttachmentReservedFileIds]
                    do {
                        reservedFileIdsForMessage = try TSAttachmentMigration.V1AttachmentReservedFileIds
                            .filter(Column("interactionRowId") == messageRowId)
                            .fetchAll(tx.database)
                    } catch {
                        logAndFail(errorLogger, "Unable to read reserved file ids for message")
                    }

                    let deletedAttachmentsForMessage = Self.migrateMessageAttachments(
                        reservedFileIds: reservedFileIdsForMessage,
                        messageRow: messageRow,
                        messageRowId: messageRowId,
                        isRunningIteratively: isRunningIteratively,
                        errorLogger: errorLogger,
                        tx: tx
                    )
                    // No need to delete one by one if running non-iteratively;
                    // we nuke the whole migration table and attachment folder at the end.
                    if isRunningIteratively {
                        if let deletedAttachmentsForMessage {
                            migratedMessageRowIds[messageRowId] = true
                            deletedAttachments.append(contentsOf: deletedAttachmentsForMessage)
                        } else {
                            migratedMessageRowIds[messageRowId] = false
                        }
                    }
                }
            }

            // No need to delete one by one if running non-iteratively;
            // we nuke the whole migration table at the end.
            if isRunningIteratively {
                // Delete our reserved rows, and re-reserve for those that didn't finish.
                for migratedMessageRowId in migratedMessageRowIds {
                    let didMigrate = migratedMessageRowId.value
                    let messageRowId = migratedMessageRowId.key
                    do {
                        try TSAttachmentMigration.V1AttachmentReservedFileIds
                            .filter(Column("interactionRowId") == messageRowId)
                            .deleteAll(tx.database)
                    } catch {
                        logAndFail(errorLogger, "Unable to delete reserved file ids")
                    }

                    if
                        !didMigrate,
                        let messageRow: GRDB.Row = {
                            do {
                                return try Row.fetchOne(
                                    tx.database,
                                    sql: "SELECT * FROM model_TSInteraction WHERE id = ?;",
                                    arguments: [messageRowId]
                                )
                            } catch {
                                logAndFail(errorLogger, "Failed to fetch interaction row")
                            }
                        }()
                    {
                        // Re-reserve new rows; we will migrate in the next batch.
                        _ = Self.prepareTSMessageForMigration(
                            messageRow: messageRow,
                            messageRowId: messageRowId,
                            tx: tx
                        )
                    }
                }
                tx.addAsyncCompletion(queue: .global()) {
                    deletedAttachments.forEach { try? $0.deleteFiles() }
                }
            }

            return migratedMessageRowIds.count
        }

        // MARK: - Migrating a single TSMessage

        /// Returns the deleted TSAttachments.
        /// Empty array means nothing was migrated but the migration "succeeded" (nothing _needed_ migrating).
        /// Nil return value means new attachments were added so we need to re-reserve and migrate again
        /// later; reserved Ids should NOT be deleted.
        private static func migrateMessageAttachments(
            reservedFileIds reservedFileIdsArray: [TSAttachmentMigration.V1AttachmentReservedFileIds],
            messageRow: Row,
            messageRowId: Int64,
            isRunningIteratively: Bool,
            errorLogger: (String) -> Void,
            tx: GRDBWriteTransaction
        ) -> [TSAttachmentMigration.V1Attachment]? {
            // From attachment unique id to the reserved file ids.
            var reservedFileIdsDict = [String: TSAttachmentMigration.V1AttachmentReservedFileIds]()
            for reservedFileIds in reservedFileIdsArray {
                reservedFileIdsDict[reservedFileIds.tsAttachmentUniqueId] = reservedFileIds
            }

            var bodyTSAttachmentIds = Self.bodyAttachmentIds(messageRow: messageRow)
            var messageSticker = Self.messageSticker(messageRow: messageRow)
            var stickerTSAttachmentId = messageSticker?.attachmentId
            var linkPreview = Self.linkPreview(messageRow: messageRow)
            var linkPreviewTSAttachmentId = linkPreview?.imageAttachmentId
            var contactShare = Self.contactShare(messageRow: messageRow)
            var contactTSAttachmentId = contactShare?.avatarAttachmentId
            var quotedMessage = Self.quotedMessage(messageRow: messageRow)
            var quotedMessageTSAttachmentId = quotedMessage?.quotedAttachment?.rawAttachmentId.nilIfEmpty

            if
                bodyTSAttachmentIds.isEmpty,
                stickerTSAttachmentId == nil,
                linkPreviewTSAttachmentId == nil,
                contactTSAttachmentId == nil,
                quotedMessageTSAttachmentId == nil
            {
                // This can only happen with state that is malformed somehow, such that
                // we couldn't deserialize any of the blob columns.
                Logger.info("Attempted to migrate message without attachments.")
                // Give up; the message will be marked as migrated and we'll leave
                // state as-is. (So whatever invalid state got us here stays invalid).
                return []
            }

            var newBodyAttachmentIds: [String]?
            var newContact: TSAttachmentMigration.OWSContact?
            var newMessageSticker: TSAttachmentMigration.MessageSticker?
            var newLinkPreview: TSAttachmentMigration.OWSLinkPreview?
            var newQuotedMessage: TSAttachmentMigration.TSQuotedMessage?

            // Remove duplicates. Its unclear _how_ a message ever attained duplicate attachments,
            // but it seems it did happen at some point with a bug, so its in people's databases.
            var allAttachmentIds = Set<String>()

            // Inserts into the set as well.
            func isDuplicate(_ tsAttachmentId: String?) -> Bool {
                guard let tsAttachmentId else {
                    return false
                }
                // If we inserted, its not a duplicate.
                let didInsert = allAttachmentIds.insert(tsAttachmentId).inserted
                return !didInsert
            }

            // Note this cannot end up as an empty array. If it did, the rest of this method
            // would end up broken because we could end up with a content-less message.
            bodyTSAttachmentIds = bodyTSAttachmentIds.compactMap {
                if isDuplicate($0) {
                    Logger.warn("Found duplicate body attachment")
                    return nil
                }
                return $0
            }

            // Preference order: body > sticker > contact > linkPreview > quote
            // Insert each in that order; if its already inserted wipe the var so we pretend
            // it never existed.
            if isDuplicate(stickerTSAttachmentId) {
                Logger.warn("Found duplicate sticker attachment")
                newMessageSticker = messageSticker?.removingLegacyAttachment()
                messageSticker = nil
                stickerTSAttachmentId = nil
            }
            if isDuplicate(contactTSAttachmentId) {
                Logger.warn("Found duplicate contact avatar attachment")
                newContact = contactShare?.removingLegacyAttachment()
                contactShare = nil
                contactTSAttachmentId = nil
            }
            if isDuplicate(linkPreviewTSAttachmentId) {
                Logger.warn("Found duplicate link preview attachment")
                newLinkPreview = linkPreview?.removingLegacyAttachment()
                linkPreview = nil
                linkPreviewTSAttachmentId = nil
            }
            if isDuplicate(quotedMessageTSAttachmentId) {
                Logger.warn("Found duplicate quote attachment")
                newQuotedMessage = quotedMessage?.removingLegacyAttachment()
                quotedMessage = nil
                quotedMessageTSAttachmentId = nil
            }

            if allAttachmentIds.isEmpty {
                // Nothing to migrate! This can happen if an edit removed attachments.
                reservedFileIdsArray.forEach { $0.cleanUpFiles() }
                return []
            }

            // Ensure every attachment is represented in the reserved ids.
            let hasUnreservedAttachment = allAttachmentIds.contains(where: {
                reservedFileIdsDict[$0] == nil
            })
            if hasUnreservedAttachment {
                guard isRunningIteratively else {
                    // If we are running as a blocking GRDB migration this should be impossible.
                    logAndFail(errorLogger, "Message attachment changed between blocking migrations")
                }
                reservedFileIdsArray.forEach { $0.cleanUpFiles() }
                // Return nil to mark this message and needing another pass.
                return nil
            }

            guard let threadUniqueId = messageRow["uniqueThreadId"] as? String else {
                Logger.error("Missing thread for message")
                // Give up; the message will be marked as migrated and we'll leave
                // the broken data in the database untouched.
                return []
            }

            let threadRowId: Int64?
            do {
                threadRowId = try Int64.fetchOne(
                    tx.database,
                    sql: "SELECT id FROM model_TSThread WHERE uniqueId = ?;",
                    arguments: [threadUniqueId]
                )
            } catch {
                logAndFail(errorLogger, "Unable to read thread row id")
            }
            guard let threadRowId else {
                Logger.error("Thread doesn't exist for message")
                // Give up; the message will be marked as migrated and we'll leave
                // the broken data in the database untouched.
                return []
            }

            guard
                // Row only gives Int64, never UInt64
                let messageReceivedAtTimestampRaw = messageRow["receivedAtTimestamp"] as? Int64
            else {
                Logger.error("Missing timestamp for message")
                // Give up; the message will be marked as migrated and we'll leave
                // the broken data in the database untouched.
                return []
            }
            let messageReceivedAtTimestamp = UInt64(bitPattern: messageReceivedAtTimestampRaw)

            let isViewOnce = (messageRow["isViewOnceMessage"] as? Bool) ?? false
            let isPastEditRevision = (messageRow["editState"] as? Int) == 2

            // Edited messages can share attachments with the original.
            // Don't delete attachments if this is an edit, just migrate and leave alone.
            // We will delete when we get to the original.
            let isEditedMessage = messageRow["editState"] as? Int64 == 2

            var migratedAttachments = [TSAttachmentMigration.V1Attachment]()
            func migrateSingleMessageAttachment(
                tsAttachmentUniqueId: String,
                messageOwnerType: TSAttachmentMigration.V2MessageAttachmentOwnerType,
                orderInMessage: Int? = nil,
                stickerPackId: Data? = nil,
                stickerId: UInt32? = nil
            ) {
                guard let reservedFileIds = reservedFileIdsDict.removeValue(forKey: tsAttachmentUniqueId) else {
                    logAndFail(errorLogger, "Missing reservation for attachment")
                }
                let migratedAttachment = Self.migrateSingleMessageAttachment(
                    tsAttachmentUniqueId: tsAttachmentUniqueId,
                    reservedFileIds: reservedFileIds,
                    messageRowId: messageRowId,
                    threadRowId: threadRowId,
                    messageOwnerType: messageOwnerType,
                    messageReceivedAtTimestamp: messageReceivedAtTimestamp,
                    isEditedMessage: isEditedMessage,
                    orderInMessage: orderInMessage.map(UInt32.init(_:)),
                    stickerPackId: stickerPackId,
                    stickerId: stickerId,
                    isViewOnce: isViewOnce,
                    isPastEditRevision: isPastEditRevision,
                    errorLogger: errorLogger,
                    tx: tx
                )
                if let migratedAttachment {
                    migratedAttachments.append(migratedAttachment)
                }
            }

            for (index, bodyTSAttachmentId) in bodyTSAttachmentIds.enumerated() {
                migrateSingleMessageAttachment(
                    tsAttachmentUniqueId: bodyTSAttachmentId,
                    messageOwnerType: .bodyAttachment,
                    orderInMessage: index
                )
                newBodyAttachmentIds = []
            }

            if let messageSticker, let stickerTSAttachmentId {
                migrateSingleMessageAttachment(
                    tsAttachmentUniqueId: stickerTSAttachmentId,
                    messageOwnerType: .sticker,
                    stickerPackId: messageSticker.info.packId,
                    stickerId: messageSticker.info.stickerId
                )
                newMessageSticker = messageSticker.removingLegacyAttachment()
            }

            if let linkPreviewTSAttachmentId {
                migrateSingleMessageAttachment(
                    tsAttachmentUniqueId: linkPreviewTSAttachmentId,
                    messageOwnerType: .linkPreview
                )
                newLinkPreview = linkPreview?.removingLegacyAttachment()
            }

            if let contactTSAttachmentId {
                migrateSingleMessageAttachment(
                    tsAttachmentUniqueId: contactTSAttachmentId,
                    messageOwnerType: .contactAvatar
                )
                newContact = contactShare?.removingLegacyAttachment()
            }

            if
                let quotedMessage,
                let quotedMessageAttachment = quotedMessage.quotedAttachment,
                let quotedMessageTSAttachmentId
            {
                switch quotedMessageAttachment.attachmentType {
                case .thumbnail, .untrustedPointer:
                    // Standard case; attachment is wholly owned by this quoted reply
                    // and no thumbnail-ing is necessary.
                    migrateSingleMessageAttachment(
                        tsAttachmentUniqueId: quotedMessageTSAttachmentId,
                        messageOwnerType: .quotedReplyAttachment
                    )
                    newQuotedMessage = quotedMessage.removingLegacyAttachment()
                case .originalForSend, .original:
                    guard let reservedFileIds = reservedFileIdsDict.removeValue(forKey: quotedMessageTSAttachmentId) else {
                        logAndFail(errorLogger, "Missing reservation for attachment")
                    }
                    // These point at the attachment of the message being quoted.
                    // We need to thumbnail the message.
                    newQuotedMessage = Self.migrateQuotedMessageAttachment(
                        quotedMessage: quotedMessage,
                        originalTSAttachmentUniqueId: quotedMessageTSAttachmentId,
                        reservedFileIds: reservedFileIds,
                        messageRowId: messageRowId,
                        threadRowId: threadRowId,
                        messageReceivedAtTimestamp: messageReceivedAtTimestamp,
                        isPastEditRevision: isPastEditRevision,
                        errorLogger: errorLogger,
                        tx: tx
                    )
                case .unset, .v2:
                    // Nothing to migrate
                    break
                }
            }

            Self.updateMessageRow(
                rowId: messageRowId,
                bodyAttachmentIds: newBodyAttachmentIds,
                contact: newContact,
                messageSticker: newMessageSticker,
                linkPreview: newLinkPreview,
                quotedMessage: newQuotedMessage,
                errorLogger: errorLogger,
                tx: tx
            )

            // There are two scenarios where the attachment is the _only_ content
            // on the message, and if we didn't migrate the message has no content
            // and is therefore invalid:
            // 1) sticker messages
            // 2) body attachment(s) with no body text caption
            // All other cases (e.g. link preview) are valid even if the attachment
            // gets dropped (e.g. a link preview with no image).
            if messageSticker != nil && migratedAttachments.isEmpty {
                Logger.error("Failed to migrate sticker; left with invalid content-less message.")
            }
            if
                !bodyTSAttachmentIds.isEmpty,
                migratedAttachments.isEmpty,
                (messageRow["body"] as? String)?.nilIfEmpty == nil
            {
                Logger.error("Failed to body attachments without text; left with invalid content-less message.")
            }

            return migratedAttachments
        }

        // MARK: - Migrating a single TSAttachment

        // Returns the deleted TSAttachment.
        private static func migrateSingleMessageAttachment(
            tsAttachmentUniqueId: String,
            reservedFileIds: TSAttachmentMigration.V1AttachmentReservedFileIds,
            messageRowId: Int64,
            threadRowId: Int64,
            messageOwnerType: TSAttachmentMigration.V2MessageAttachmentOwnerType,
            messageReceivedAtTimestamp: UInt64,
            isEditedMessage: Bool,
            orderInMessage: UInt32?,
            stickerPackId: Data?,
            stickerId: UInt32?,
            isViewOnce: Bool,
            isPastEditRevision: Bool,
            errorLogger: (String) -> Void,
            tx: GRDBWriteTransaction
        ) -> TSAttachmentMigration.V1Attachment? {
            let oldAttachment: TSAttachmentMigration.V1Attachment?
            do {
                oldAttachment = try TSAttachmentMigration.V1Attachment
                    .filter(Column("uniqueId") == tsAttachmentUniqueId)
                    .fetchOne(tx.database)
            } catch {
                Logger.error("Failed to parse TSAttachment row")
                reservedFileIds.cleanUpFiles()
                return nil
            }
            guard let oldAttachment else {
                reservedFileIds.cleanUpFiles()
                return nil
            }

            let encryptionKey: Data
            if
                let oldEncryptionKey = oldAttachment.encryptionKey,
                oldEncryptionKey.count == 64
            {
                encryptionKey = oldEncryptionKey
            } else {
                if oldAttachment.encryptionKey != nil {
                    Logger.error("TSAttachment has invalid encryption key")
                }
                encryptionKey = Cryptography.randomAttachmentEncryptionKey()
            }

            let pendingAttachment: TSAttachmentMigration.PendingV2AttachmentFile?
            if let oldFilePath = oldAttachment.localFilePath, OWSFileSystem.fileExistsAndIsNotDirectory(atPath: oldFilePath) {
                let oldFileUrl = URL(fileURLWithPath: oldFilePath)
                do {
                    pendingAttachment = try TSAttachmentMigration.V2AttachmentContentValidator.validateContents(
                        unencryptedFileUrl: oldFileUrl,
                        reservedFileIds: .init(
                            primaryFile: reservedFileIds.reservedV2AttachmentPrimaryFileId,
                            audioWaveform: reservedFileIds.reservedV2AttachmentAudioWaveformFileId,
                            videoStillFrame: reservedFileIds.reservedV2AttachmentVideoStillFrameFileId
                        ),
                        encryptionKey: encryptionKey,
                        mimeType: oldAttachment.contentType,
                        renderingFlag: oldAttachment.attachmentType.asRenderingFlag,
                        sourceFilename: oldAttachment.sourceFilename
                    )
                } catch _ as TSAttachmentMigration.V2AttachmentContentValidator.AttachmentTooLargeError {
                    // If we somehow had a file that was too big, just treat it as if we had no file.
                    pendingAttachment = nil
                } catch {
                    Logger.error("Failed to validate: \(error). Attempting to copy file and retry")
                    // If we had a file I/O error (which is the only error thrown), its possible
                    // it was a transiest file reading permission error that is fixed on device
                    // restart. Try and work around this by copying the file first to a tmp file,
                    // then trying again. If this fails give up, dropping the attachment file.
                    let oldFileUrl = URL(fileURLWithPath: oldFilePath)
                    let newTmpURL = OWSFileSystem.temporaryFileUrl(
                        fileName: oldFileUrl.lastPathComponent,
                        fileExtension: oldFileUrl.pathExtension,
                        isAvailableWhileDeviceLocked: true
                    )
                    do {
                        try FileManager.default.copyItem(at: oldFileUrl, to: newTmpURL)
                        pendingAttachment = try TSAttachmentMigration.V2AttachmentContentValidator.validateContents(
                            unencryptedFileUrl: newTmpURL,
                            reservedFileIds: .init(
                                primaryFile: reservedFileIds.reservedV2AttachmentPrimaryFileId,
                                audioWaveform: reservedFileIds.reservedV2AttachmentAudioWaveformFileId,
                                videoStillFrame: reservedFileIds.reservedV2AttachmentVideoStillFrameFileId
                            ),
                            encryptionKey: encryptionKey,
                            mimeType: oldAttachment.contentType,
                            renderingFlag: oldAttachment.attachmentType.asRenderingFlag,
                            sourceFilename: oldAttachment.sourceFilename
                        )
                        Logger.info("Succesfully validated after copying file")
                    } catch {
                        Logger.error("File i/o failure of copied file: \(error)")
                        pendingAttachment = nil
                    }
                }
            } else {
                // A pointer; no validation needed.
                pendingAttachment = nil
                // Clean up files just in case.
                reservedFileIds.cleanUpFiles()
            }

            let v2AttachmentId: Int64
            if
                let pendingAttachment,
                let existingV2Attachment = {
                    do {
                        return try TSAttachmentMigration.V2Attachment
                            .filter(Column("sha256ContentHash") == pendingAttachment.sha256ContentHash)
                            .fetchOne(tx.database)
                    } catch {
                        logAndFail(errorLogger, "Failed to fetch v2 attachment")
                    }
                }()
            {
                // If we already have a v2 attachment with the same plaintext hash,
                // create new references to it and drop the pending attachment.
                v2AttachmentId = existingV2Attachment.id!
                // Delete the reserved files being used by the pending attachment.
                reservedFileIds.cleanUpFiles()
            } else {
                var v2Attachment: TSAttachmentMigration.V2Attachment
                if let pendingAttachment {
                    v2Attachment = TSAttachmentMigration.V2Attachment(
                        blurHash: pendingAttachment.blurHash,
                        sha256ContentHash: pendingAttachment.sha256ContentHash,
                        encryptedByteCount: pendingAttachment.encryptedByteCount,
                        unencryptedByteCount: pendingAttachment.unencryptedByteCount,
                        mimeType: pendingAttachment.mimeType,
                        encryptionKey: pendingAttachment.encryptionKey,
                        digestSHA256Ciphertext: pendingAttachment.digestSHA256Ciphertext,
                        contentType: UInt32(pendingAttachment.validatedContentType.rawValue),
                        transitCdnNumber: oldAttachment.cdnNumber,
                        transitCdnKey: oldAttachment.cdnKey,
                        transitUploadTimestamp: oldAttachment.uploadTimestamp,
                        transitEncryptionKey: encryptionKey,
                        transitUnencryptedByteCount: pendingAttachment.unencryptedByteCount,
                        transitDigestSHA256Ciphertext: oldAttachment.digest,
                        lastTransitDownloadAttemptTimestamp: nil,
                        localRelativeFilePath: pendingAttachment.localRelativeFilePath,
                        cachedAudioDurationSeconds: pendingAttachment.audioDurationSeconds,
                        cachedMediaHeightPixels: pendingAttachment.mediaSizePixels.map { UInt32($0.height) },
                        cachedMediaWidthPixels: pendingAttachment.mediaSizePixels.map { UInt32($0.width) },
                        cachedVideoDurationSeconds: pendingAttachment.videoDurationSeconds,
                        audioWaveformRelativeFilePath: pendingAttachment.audioWaveformRelativeFilePath,
                        videoStillFrameRelativeFilePath: pendingAttachment.videoStillFrameRelativeFilePath
                    )
                } else {
                    v2Attachment = TSAttachmentMigration.V2Attachment(
                        blurHash: oldAttachment.blurHash,
                        sha256ContentHash: nil,
                        encryptedByteCount: nil,
                        unencryptedByteCount: nil,
                        mimeType: oldAttachment.contentType,
                        encryptionKey: encryptionKey,
                        digestSHA256Ciphertext: nil,
                        contentType: nil,
                        transitCdnNumber: oldAttachment.cdnNumber,
                        transitCdnKey: oldAttachment.cdnKey,
                        transitUploadTimestamp: oldAttachment.uploadTimestamp,
                        transitEncryptionKey: encryptionKey,
                        transitUnencryptedByteCount: oldAttachment.byteCount,
                        transitDigestSHA256Ciphertext: oldAttachment.digest,
                        lastTransitDownloadAttemptTimestamp: nil,
                        localRelativeFilePath: nil,
                        cachedAudioDurationSeconds: nil,
                        cachedMediaHeightPixels: nil,
                        cachedMediaWidthPixels: nil,
                        cachedVideoDurationSeconds: nil,
                        audioWaveformRelativeFilePath: nil,
                        videoStillFrameRelativeFilePath: nil
                    )
                }

                do {
                    try v2Attachment.insert(tx.database)
                } catch {
                    logAndFail(errorLogger, "Failed to insert v2 attachment")
                }
                v2AttachmentId = v2Attachment.id!
            }

            let ownerTypeRaw: UInt32
            switch messageOwnerType {
            case .bodyAttachment:
                // Oversize text is a "body attachment" in v1, but a separate type
                // in v2. If this is the first attachment and it matches the oversize
                // text MIME type, re-map it to oversize text.
                if orderInMessage == 0, pendingAttachment?.mimeType == "text/x-signal-plain" {
                    ownerTypeRaw = UInt32(TSAttachmentMigration.V2MessageAttachmentOwnerType.oversizeText.rawValue)
                } else {
                    // Uniquely, non-oversize-text body attachments are present in the
                    // media gallery table and need to be deleted from there.
                    try? oldAttachment.deleteMediaGalleryRecord(tx: tx)
                    fallthrough
                }
            default:
                ownerTypeRaw = UInt32(messageOwnerType.rawValue)
            }

            let (sourceMediaHeightPixels, sourceMediaWidthPixels) = (try? oldAttachment.sourceMediaSizePixels()) ?? (nil, nil)

            let reference = TSAttachmentMigration.MessageAttachmentReference(
                ownerType: ownerTypeRaw,
                ownerRowId: messageRowId,
                attachmentRowId: v2AttachmentId,
                receivedAtTimestamp: messageReceivedAtTimestamp,
                contentType: pendingAttachment.map { UInt32($0.validatedContentType.rawValue) },
                renderingFlag: UInt32(oldAttachment.attachmentType.asRenderingFlag.rawValue),
                idInMessage: oldAttachment.clientUuid,
                orderInMessage: orderInMessage,
                threadRowId: threadRowId,
                caption: oldAttachment.caption,
                sourceFilename: oldAttachment.sourceFilename,
                sourceUnencryptedByteCount: oldAttachment.byteCount,
                sourceMediaHeightPixels: sourceMediaHeightPixels,
                sourceMediaWidthPixels: sourceMediaWidthPixels,
                stickerPackId: stickerPackId,
                stickerId: stickerId,
                isViewOnce: isViewOnce,
                ownerIsPastEditRevision: isPastEditRevision
            )
            do {
                try reference.insert(tx.database)
            } catch {
                logAndFail(errorLogger, "Failed to insert attachment reference")
            }

            // Edits might be reusing the original's TSAttachment.
            // DON'T delete the TSAttachment so its still available for the original.
            // Also don't return it (so we don't delete its files either).
            // If it turns out the original doesn't reuse (e.g. we edited oversize text),
            // this attachment will stick around until the migration is done, but
            // will get deleted when we bulk delete the table and folder at the end.
            if isEditedMessage {
                return nil
            }

            do {
                try oldAttachment.delete(tx.database)
            } catch {
                logAndFail(errorLogger, "Failed to insert v2 attachment")
            }

            return oldAttachment
        }

        /// Given the unique id of the _original_ message's attachment and a reply message's row id,
        /// thumbnails the attachment if possible and assigns the thumbnail to the provided message row id.
        ///
        /// Returns the new TSQuotedMessage to use on the reply TSMessage.
        /// DOES NOT delete the original attachment.
        private static func migrateQuotedMessageAttachment(
            quotedMessage: TSQuotedMessage,
            originalTSAttachmentUniqueId: String,
            reservedFileIds: TSAttachmentMigration.V1AttachmentReservedFileIds,
            messageRowId: Int64,
            threadRowId: Int64,
            messageReceivedAtTimestamp: UInt64,
            isPastEditRevision: Bool,
            errorLogger: (String) -> Void,
            tx: GRDBWriteTransaction
        ) -> TSAttachmentMigration.TSQuotedMessage {
            let oldAttachment: TSAttachmentMigration.V1Attachment?
            do {
                oldAttachment = try TSAttachmentMigration.V1Attachment
                    .filter(Column("uniqueId") == originalTSAttachmentUniqueId)
                    .fetchOne(tx.database)
            } catch {
                Logger.error("Failed to parse quote TSAttachment")
                // We can easily fall back to stub, just drop the attachment.
                reservedFileIds.cleanUpFiles()
                return quotedMessage.fallbackToStub()
            }

            guard let oldAttachment else {
                // We've got no original attachment at all.
                // This can happen if the quote came in, then the original got deleted
                // while the quote still pointed at the original's attachment.
                // Just fall back to a stub.
                reservedFileIds.cleanUpFiles()
                return quotedMessage.fallbackToStub()
            }

            let rawContentType = TSAttachmentMigration.V2AttachmentContentValidator.rawContentType(
                mimeType: oldAttachment.contentType
            )

            guard
                let oldFilePath = oldAttachment.localFilePath,
                OWSFileSystem.fileExistsAndIsNotDirectory(atPath: oldFilePath),
                rawContentType == .image || rawContentType == .video || rawContentType == .animatedImage
            else {
                // We've got no original media stream, just a pointer or non-visual media.
                // We can't easily handle this, so instead just fall back to a stub.
                reservedFileIds.cleanUpFiles()
                return quotedMessage.fallbackToStub(oldAttachment)
            }

            let pendingAttachment: TSAttachmentMigration.PendingV2AttachmentFile?
            do {
                pendingAttachment = try TSAttachmentMigration.V2AttachmentContentValidator.prepareQuotedReplyThumbnail(
                    fromOriginalAttachmentStream: oldAttachment,
                    reservedFileIds: .init(
                        primaryFile: reservedFileIds.reservedV2AttachmentPrimaryFileId,
                        audioWaveform: reservedFileIds.reservedV2AttachmentAudioWaveformFileId,
                        videoStillFrame: reservedFileIds.reservedV2AttachmentVideoStillFrameFileId
                    ),
                    renderingFlag: oldAttachment.attachmentType.asRenderingFlag,
                    sourceFilename: oldAttachment.sourceFilename
                )
            } catch {
                Logger.error("Error validating quote attachment")
                pendingAttachment = nil
            }
            guard let pendingAttachment else {
                Logger.error("Failed to validate quote attachment")
                reservedFileIds.cleanUpFiles()
                return quotedMessage.fallbackToStub(oldAttachment)
            }

            let v2AttachmentId: Int64

            let existingV2Attachment: TSAttachmentMigration.V2Attachment?
            do {
                existingV2Attachment = try TSAttachmentMigration.V2Attachment
                    .filter(Column("sha256ContentHash") == pendingAttachment.sha256ContentHash)
                    .fetchOne(tx.database)
            } catch {
                logAndFail(errorLogger, "Failed to fetch v2 attachment")
            }
            if let existingV2Attachment {
                // If we already have a v2 attachment with the same plaintext hash,
                // create new references to it and drop the pending attachment.
                v2AttachmentId = existingV2Attachment.id!
                // Delete the reserved files being used by the pending attachment.
                reservedFileIds.cleanUpFiles()
            } else {
                var v2Attachment = TSAttachmentMigration.V2Attachment(
                    blurHash: pendingAttachment.blurHash,
                    sha256ContentHash: pendingAttachment.sha256ContentHash,
                    encryptedByteCount: pendingAttachment.encryptedByteCount,
                    unencryptedByteCount: pendingAttachment.unencryptedByteCount,
                    mimeType: pendingAttachment.mimeType,
                    encryptionKey: pendingAttachment.encryptionKey,
                    digestSHA256Ciphertext: pendingAttachment.digestSHA256Ciphertext,
                    contentType: UInt32(pendingAttachment.validatedContentType.rawValue),
                    transitCdnNumber: nil,
                    transitCdnKey: nil,
                    transitUploadTimestamp: nil,
                    transitEncryptionKey: nil,
                    transitUnencryptedByteCount: nil,
                    transitDigestSHA256Ciphertext: nil,
                    lastTransitDownloadAttemptTimestamp: nil,
                    localRelativeFilePath: pendingAttachment.localRelativeFilePath,
                    cachedAudioDurationSeconds: pendingAttachment.audioDurationSeconds,
                    cachedMediaHeightPixels: pendingAttachment.mediaSizePixels.map { UInt32($0.height) },
                    cachedMediaWidthPixels: pendingAttachment.mediaSizePixels.map { UInt32($0.width) },
                    cachedVideoDurationSeconds: pendingAttachment.videoDurationSeconds,
                    audioWaveformRelativeFilePath: pendingAttachment.audioWaveformRelativeFilePath,
                    videoStillFrameRelativeFilePath: pendingAttachment.videoStillFrameRelativeFilePath
                )

                do {
                    try v2Attachment.insert(tx.database)
                } catch {
                    logAndFail(errorLogger, "Failed to insert v2 attachment")
                }
                v2AttachmentId = v2Attachment.id!
            }

            let reference = TSAttachmentMigration.MessageAttachmentReference(
                ownerType: UInt32(TSAttachmentMigration.V2MessageAttachmentOwnerType.quotedReplyAttachment.rawValue),
                ownerRowId: messageRowId,
                attachmentRowId: v2AttachmentId,
                receivedAtTimestamp: messageReceivedAtTimestamp,
                contentType: UInt32(pendingAttachment.validatedContentType.rawValue),
                renderingFlag: UInt32(pendingAttachment.renderingFlag.rawValue),
                idInMessage: nil,
                orderInMessage: nil,
                threadRowId: threadRowId,
                caption: nil,
                sourceFilename: pendingAttachment.sourceFilename,
                sourceUnencryptedByteCount: nil,
                sourceMediaHeightPixels: nil,
                sourceMediaWidthPixels: nil,
                stickerPackId: nil,
                stickerId: nil,
                // Quoted message attachments cannot be view once
                isViewOnce: false,
                ownerIsPastEditRevision: isPastEditRevision
            )
            do {
                try reference.insert(tx.database)
            } catch {
                logAndFail(errorLogger, "Failed to insert attachment reference")
            }

            // NOTE: we DO NOT delete the old attachment. It belongs to the original message.

            let newQuotedMessage = quotedMessage
            let newQuotedAttachment = newQuotedMessage.quotedAttachment
            newQuotedAttachment?.attachmentType = .v2
            newQuotedAttachment?.rawAttachmentId = ""
            newQuotedAttachment?.contentType = nil
            newQuotedAttachment?.sourceFilename = nil
            newQuotedMessage.quotedAttachment = newQuotedAttachment
            return newQuotedMessage
        }

        // MARK: - NSKeyedArchiver/Unarchiver

        private static func unarchive<T: NSCoding>(_ data: Data) throws -> T {
            let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
            unarchiver.requiresSecureCoding = false
            TSAttachmentMigration.prepareNSCodingMappings(unarchiver: unarchiver)
            let decoded = try unarchiver.decodeTopLevelObject(of: [T.self], forKey: NSKeyedArchiveRootObjectKey)
            guard let decoded = decoded as? T else {
                throw OWSAssertionError("Expected \(T.self) but decoded \(type(of: decoded))")
            }
            return decoded
        }

        private static func bodyAttachmentIds(messageRow: Row) -> [String] {
            guard let encoded = messageRow["deprecated_attachmentIds"] as? Data else {
                return []
            }
            do {
                let decoded: NSArray = try unarchive(encoded)

                var array = [String]()
                try decoded.forEach { element in
                    guard let attachmentId = element as? String else {
                        throw OWSAssertionError("Invalid attachment id")
                    }
                    array.append(attachmentId)
                }
                return array
            } catch {
                Logger.error("Failed to unarchive body attachments")
                return []
            }
        }

        private static func contactShare(messageRow: Row) -> TSAttachmentMigration.OWSContact? {
            guard let encoded = messageRow["contactShare"] as? Data else {
                return nil
            }
            do {
                return try unarchive(encoded)
            } catch {
                Logger.error("Failed to unarchive contact share")
                return nil
            }
        }

        private static func contactAttachmentId(messageRow: Row) -> String? {
            return contactShare(messageRow: messageRow)?.avatarAttachmentId
        }

        private static func messageSticker(messageRow: Row) -> TSAttachmentMigration.MessageSticker? {
            guard let encoded = messageRow["messageSticker"] as? Data else {
                return nil
            }
            do {
                return try unarchive(encoded)
            } catch {
                Logger.error("Failed to unarchive sticker")
                return nil
            }
        }

        private static func stickerAttachmentId(messageRow: Row) -> String? {
            return messageSticker(messageRow: messageRow)?.attachmentId
        }

        private static func linkPreview(messageRow: Row) -> TSAttachmentMigration.OWSLinkPreview? {
            guard let encoded = messageRow["linkPreview"] as? Data else {
                return nil
            }
            do {
                return try unarchive(encoded)
            } catch {
                Logger.error("Failed to unarchive link preview")
                return nil
            }
        }

        private static func linkPreviewAttachmentId(messageRow: Row) -> String? {
            return linkPreview(messageRow: messageRow)?.imageAttachmentId
        }

        private static func quotedMessage(messageRow: Row) -> TSAttachmentMigration.TSQuotedMessage? {
            guard let encoded = messageRow["quotedMessage"] as? Data else {
                return nil
            }
            do {
                return try unarchive(encoded)
            } catch {
                Logger.error("Failed to unarchive quoted message")
                return nil
            }
        }

        private static func quoteAttachmentId(messageRow: Row) -> String? {
            return quotedMessage(messageRow: messageRow)?.quotedAttachment?.rawAttachmentId.nilIfEmpty
        }

        private static func archive(_ value: Any) -> Data {
            let archiver = NSKeyedArchiver(requiringSecureCoding: false)
            TSAttachmentMigration.prepareNSCodingMappings(archiver: archiver)
            archiver.encode(value, forKey: NSKeyedArchiveRootObjectKey)
            return archiver.encodedData
        }

        private static func updateMessageRow(
            rowId: Int64,
            bodyAttachmentIds: [String]?,
            contact: TSAttachmentMigration.OWSContact?,
            messageSticker: TSAttachmentMigration.MessageSticker?,
            linkPreview: TSAttachmentMigration.OWSLinkPreview?,
            quotedMessage: TSAttachmentMigration.TSQuotedMessage?,
            errorLogger: (String) -> Void,
            tx: GRDBWriteTransaction
        ) {
            var sql = "UPDATE model_TSInteraction SET "
            var arguments = StatementArguments()

            var columns = [String]()
            if let bodyAttachmentIds {
                columns.append("deprecated_attachmentIds")
                _ = arguments.append(contentsOf: [archive(bodyAttachmentIds)])
            }
            if let contact {
                columns.append("contactShare")
                _ = arguments.append(contentsOf: [archive(contact)])
            }
            if let messageSticker {
                columns.append("messageSticker")
                _ = arguments.append(contentsOf: [archive(messageSticker)])
            }
            if let linkPreview {
                columns.append("linkPreview")
                _ = arguments.append(contentsOf: [archive(linkPreview)])
            }
            if let quotedMessage {
                columns.append("quotedMessage")
                _ = arguments.append(contentsOf: [archive(quotedMessage)])
            }

            sql.append(columns.map({ $0 + " = ?"}).joined(separator: ", "))
            sql.append(" WHERE id = ?;")
            _ = arguments.append(contentsOf: [rowId])
            do {
                try tx.database.execute(sql: sql, arguments: arguments)
            } catch {
                logAndFail(errorLogger, "Failed to update message columns: \(columns)")
            }
        }
    }
}

extension TSAttachmentMigration.MessageSticker {

    fileprivate func removingLegacyAttachment() -> Self {
        attachmentId = nil
        return self
    }
}

extension TSAttachmentMigration.OWSContact {

    fileprivate func removingLegacyAttachment() -> Self {
        avatarAttachmentId = nil
        return self
    }
}

extension TSAttachmentMigration.OWSLinkPreview {

    fileprivate func removingLegacyAttachment() -> Self {
        imageAttachmentId = nil
        usesV2AttachmentReferenceValue = NSNumber(value: true)
        return self
    }
}

extension TSAttachmentMigration.TSQuotedMessage {

    fileprivate func removingLegacyAttachment() -> Self {
        let newQuotedAttachment = quotedAttachment
        newQuotedAttachment?.rawAttachmentId = ""
        newQuotedAttachment?.attachmentType = .v2
        newQuotedAttachment?.contentType = nil
        newQuotedAttachment?.sourceFilename = nil
        self.quotedAttachment = newQuotedAttachment
        return self
    }

    fileprivate func fallbackToStub(
        _ oldAttachment: TSAttachmentMigration.V1Attachment? = nil
    ) -> Self {
        let newQuotedAttachment = self.quotedAttachment
        newQuotedAttachment?.attachmentType = .unset
        newQuotedAttachment?.rawAttachmentId = ""
        if let oldAttachment {
            newQuotedAttachment?.contentType = oldAttachment.contentType
            newQuotedAttachment?.sourceFilename = oldAttachment.sourceFilename
        }
        self.quotedAttachment = newQuotedAttachment
        return self
    }
}
