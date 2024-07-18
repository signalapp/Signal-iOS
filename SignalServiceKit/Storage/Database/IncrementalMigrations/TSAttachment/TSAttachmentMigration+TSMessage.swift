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
    enum TSMessageMigration {

        // MARK: - Phase 1/2

        /// Phases 1 and 2 when applying as a blocking-on-launch GRDB migration.
        static func prepareBlockingTSMessageMigration(tx: GRDBWriteTransaction) throws {
            // If we finished phase 2, we are done.
            let finished: Bool? = try Self.read(key: finishedGoingForwardsKey, tx: tx)
            if finished == true {
                return
            }

            guard
                let maxMigratedRowId: Int64 = try Self.read(key: maxMigratedInteractionRowIdKey, tx: tx)
            else {
                // We've made zero progress. Migrate working backwards from the top (phase 1).
                // No need for phase 2, as this will just run top to bottom.
                _ = try prepareTSMessageMigrationBatch(batchSize: nil, maxRowId: nil, minRowId: nil, tx: tx)
                return
            }

            let finishedGoingBackwards: Bool? = try Self.read(key: finishedGoingBackwardsKey, tx: tx)
            if finishedGoingBackwards != true {
                // We've made partial progress in phase 1, pick up where we left off working backwards.
                let minMigratedRowId: Int64? = try Self.read(key: minMigratedInteractionRowIdKey, tx: tx)
                _ = try prepareTSMessageMigrationBatch(
                    batchSize: nil,
                    maxRowId: minMigratedRowId ?? maxMigratedRowId,
                    minRowId: nil,
                    tx: tx
                )
            }

            // We finished phase 1. Finish phase 2, picking up wherever we left off.
            _ = try prepareTSMessageMigrationBatch(
                batchSize: nil,
                maxRowId: nil,
                minRowId: maxMigratedRowId,
                tx: tx
            )
        }

        /// Phases 1 and 2 when running as an iterative migration.
        /// - Returns
        /// True if any rows were migrated; callers should keep calling until it returns false.
        static func prepareNextIterativeTSMessageMigrationBatch(tx: GRDBWriteTransaction) throws -> Bool {
            // If we finished phase 2, we are done.
            let finished: Bool? = try Self.read(key: finishedGoingForwardsKey, tx: tx)
            if finished == true {
                return false
            }

            let batchSize = 5

            guard
                let maxMigratedRowId: Int64 = try Self.read(key: maxMigratedInteractionRowIdKey, tx: tx)
            else {
                return try Self.prepareNextIterativeBatchPhase1ColdStart(batchSize: batchSize, tx: tx)
            }

            // If phase 1 is done, proceed to phase 2.
            let finishedGoingBackwards: Bool? = try Self.read(key: finishedGoingBackwardsKey, tx: tx)
            if finishedGoingBackwards == true {
                return try Self.prepareNextIteraveBatchPhase2(
                    batchSize: batchSize,
                    maxMigratedRowId: maxMigratedRowId,
                    tx: tx
                )
            }

            // Otherwise continue our progress on phase 1.
            return try Self.prepareNextIterativeBatchPhase1(
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
        ) throws -> Bool {
            // We've made zero progress. Migrate working backwards from the top (phase 1).
            guard
                let maxInteractionRowId = try Int64.fetchOne(tx.database, sql: "SELECT max(id) from model_TSInteraction;")
            else {
                // No interactions. Must be a new install, which is fine, it means we are instantly done.
                try Self.write(true, key: finishedGoingForwardsKey, tx: tx)
                return false
            }
            // Write the cutoff point to disk.
            try Self.write(maxInteractionRowId, key: maxMigratedInteractionRowIdKey, tx: tx)

            // Start going backwards from the top (phase 1).
            let lastMigratedRowId = try prepareTSMessageMigrationBatch(batchSize: batchSize, maxRowId: nil, minRowId: nil, tx: tx)

            if let lastMigratedRowId {
                // Save our incremental progress.
                try Self.write(lastMigratedRowId, key: minMigratedInteractionRowIdKey, tx: tx)
                return true
            } else {
                // If we got nothing back, there were no messages needing migrating. Finish phase 1;
                // next batch we try and run will proceed to phase 2.
                try Self.write(true, key: finishedGoingBackwardsKey, tx: tx)
                return true
            }
        }

        /// - Returns
        /// True if any rows were migrated.
        private static func prepareNextIterativeBatchPhase1(
            batchSize: Int,
            maxMigratedRowId: Int64,
            tx: GRDBWriteTransaction
        ) throws -> Bool {
            // Proceed going backwards from the min id, continuing our progress on phase 1.
            let minMigratedRowId: Int64? = try Self.read(key: minMigratedInteractionRowIdKey, tx: tx)
            let lastMigratedId = minMigratedRowId ?? maxMigratedRowId

            let newMinMigratedId =
                try prepareTSMessageMigrationBatch(batchSize: batchSize, maxRowId: lastMigratedId, minRowId: nil, tx: tx)
            if let newMinMigratedId {
                // Save our incremental progress.
                try Self.write(newMinMigratedId, key: minMigratedInteractionRowIdKey, tx: tx)
                return true
            } else {
                // If we got nothing back, there were no messages needing migrating. Finish phase 1;
                // next batch we try and run will proceed to phase 2.
                try Self.write(true, key: finishedGoingBackwardsKey, tx: tx)
                return true
            }
        }

        /// - Returns
        /// True if any rows were migrated.
        private static func prepareNextIteraveBatchPhase2(
            batchSize: Int,
            maxMigratedRowId: Int64,
            tx: GRDBWriteTransaction
        ) throws -> Bool {
            let newMaxMigratedId =
                try prepareTSMessageMigrationBatch(batchSize: batchSize, maxRowId: nil, minRowId: maxMigratedRowId, tx: tx)
            if let newMaxMigratedId {
                // Save our incremental progress.
                try Self.write(newMaxMigratedId, key: maxMigratedInteractionRowIdKey, tx: tx)
                return true
            } else {
                // If we got nothing back, we are finished with phase 2.
                // The value of `maxMigratedInteractionRowIdKey` will stay stale,
                // but once we write `finishedGoingForwardsKey` it doesn't matter;
                // we are done and none of the others get read.
                try Self.write(true, key: finishedGoingForwardsKey, tx: tx)
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

        private static func read<T: DatabaseValueConvertible>(key: String, tx: GRDBWriteTransaction) throws -> T? {
            return try T.fetchOne(
                tx.database,
                sql: "SELECT value from keyvalue WHERE collection = ? AND key = ?",
                arguments: [Self.collectionName, key]
            )
        }

        private static func write<T: DatabaseValueConvertible>(_ t: T, key: String, tx: GRDBWriteTransaction) throws {
            try tx.database.execute(
                sql: """
                    INSERT INTO keyvalue (collection,key,value) VALUES (?,?,?)
                    ON CONFLICT(key,collection) DO UPDATE SET value = ?;
                    """,
                arguments: [Self.collectionName, key, t, t]
            )
        }

        // MARK: - Phase 3

        /// Phase 3 when applying as a blocking-on-launch GRDB migration.
        static func completeBlockingTSMessageMigration(tx: GRDBWriteTransaction) throws {
            _ = try Self.completeTSMessageMigrationBatch(batchSize: nil, tx: tx)
        }

        /// Phase 3 when running as an iterative migration.
        /// - Returns
        /// True if any rows were migrated; callers should keep calling until it returns false.
        static func completeNextIterativeTSMessageMigrationBatch(tx: GRDBWriteTransaction) throws -> Bool {
            let batchSize = 5
            let count = try Self.completeTSMessageMigrationBatch(batchSize: batchSize, tx: tx)
            return count > 0
        }

        // MARK: - Phase 4

        /// Phase 4.
        /// Works the same whether its run "iteratively" or as a blocking GRDB migration.
        static func cleanUpTSAttachmentFiles() throws {
            // Just try and delete the folder, don't bother checking if we've tried before.
            // If the folder is already deleted, this is super cheap.
            let rootPath = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: TSConstants.applicationGroup
            )!.path
            let attachmentsFolder = rootPath.appendingPathComponent("Attachments")
            guard OWSFileSystem.deleteFileIfExists(attachmentsFolder) == true else {
                throw OWSAssertionError("Unable to delete folder!")
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
        ) throws -> Int64? {
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
            let cursor = try Row.fetchCursor(
                tx.database,
                sql: sql,
                arguments: arguments
            )
            var batchCount = 0
            var lastMessageRowId: Int64?
            while batchCount < batchSize ?? Int.max, let messageRow = try cursor.next() {
                guard let messageRowId = messageRow["id"] as? Int64 else {
                    throw OWSAssertionError("TSInteraction row without id")
                }

                guard try prepareTSMessageForMigration(
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
        ) throws -> Bool {
            // Check if the message has any attachments.
            let attachmentIds: [String] = (
                try bodyAttachmentIds(messageRow: messageRow)
                + [
                    try contactAttachmentId(messageRow: messageRow),
                    try stickerAttachmentId(messageRow: messageRow),
                    try linkPreviewAttachmentId(messageRow: messageRow),
                    try quoteAttachmentId(messageRow: messageRow)
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
                try reservedFileIds.insert(tx.database)
            }
            return true
        }

        /// Completes another prepared batch, returns count of touched message rows.
        ///
        /// If a batch size is provided, prepares only that many prepared messages. Otherwise migares all prepared messages.
        private static func completeTSMessageMigrationBatch(
            batchSize: Int?,
            tx: GRDBWriteTransaction
        ) throws -> Int {
            let isRunningIteratively = batchSize != nil

            let reservedFileIdsCursor = try TSAttachmentMigration.V1AttachmentReservedFileIds
                .filter(Column("interactionRowId") != nil)
                .order([Column("interactionRowId").desc])
                .fetchCursor(tx.database)

            // row id to (true = migrated) (false = needs re-reservation for next batch)
            var migratedMessageRowIds = [Int64: Bool]()
            var deletedAttachments = [TSAttachmentMigration.V1Attachment]()
            while migratedMessageRowIds.count < batchSize ?? Int.max, let reservedFileIds = try reservedFileIdsCursor.next() {
                guard let messageRowId = reservedFileIds.interactionRowId else {
                    continue
                }
                if migratedMessageRowIds[messageRowId] != nil {
                    continue
                }

                let messageRow = try Row.fetchOne(
                    tx.database,
                    sql: "SELECT * FROM model_TSInteraction WHERE id = ?;",
                    arguments: [messageRowId]
                )
                guard let messageRow else {
                    // The message got deleted. Still, count this in the batch
                    // size so we don't iterate over deleted rows unbounded.
                    migratedMessageRowIds[messageRowId] = true
                    try reservedFileIds.cleanUpFiles()
                    continue
                }

                // We _have_ to migrate everything on a given TSMessage at once.
                // Fetch all the reserved ids for the message.
                let reservedFileIdsForMessage = try TSAttachmentMigration.V1AttachmentReservedFileIds
                    .filter(Column("interactionRowId") == messageRowId)
                    .fetchAll(tx.database)

                let deletedAttachmentsForMessage = try Self.migrateMessageAttachments(
                    reservedFileIds: reservedFileIdsForMessage,
                    messageRow: messageRow,
                    messageRowId: messageRowId,
                    isRunningIteratively: isRunningIteratively,
                    tx: tx
                )
                if let deletedAttachmentsForMessage {
                    migratedMessageRowIds[messageRowId] = true
                    deletedAttachments.append(contentsOf: deletedAttachmentsForMessage)
                } else {
                    migratedMessageRowIds[messageRowId] = false
                }
            }

            // Delete our reserved rows, and re-reserve for those that didn't finish.
            for migratedMessageRowId in migratedMessageRowIds {
                let didMigrate = migratedMessageRowId.value
                let messageRowId = migratedMessageRowId.key
                try TSAttachmentMigration.V1AttachmentReservedFileIds
                    .filter(Column("interactionRowId") == messageRowId)
                    .deleteAll(tx.database)

                if
                    isRunningIteratively,
                    !didMigrate,
                    let messageRow = try Row.fetchOne(
                        tx.database,
                        sql: "SELECT * FROM model_TSInteraction WHERE id = ?;",
                        arguments: [messageRowId]
                    )
                {
                    // Re-reserve new rows; we will migrate in the next batch.
                    _ = try Self.prepareTSMessageForMigration(
                        messageRow: messageRow,
                        messageRowId: messageRowId,
                        tx: tx
                    )
                }
            }

            tx.addAsyncCompletion(queue: .global()) {
                deletedAttachments.forEach { try? $0.deleteFiles() }
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
            tx: GRDBWriteTransaction
        ) throws -> [TSAttachmentMigration.V1Attachment]? {
            // From attachment unique id to the reserved file ids.
            var reservedFileIdsDict = [String: TSAttachmentMigration.V1AttachmentReservedFileIds]()
            for reservedFileIds in reservedFileIdsArray {
                reservedFileIdsDict[reservedFileIds.tsAttachmentUniqueId] = reservedFileIds
            }

            let bodyTSAttachmentIds = try Self.bodyAttachmentIds(messageRow: messageRow)
            let messageSticker = try Self.messageSticker(messageRow: messageRow)
            let stickerTSAttachmentId = messageSticker?.attachmentId
            let linkPreview = try Self.linkPreview(messageRow: messageRow)
            let linkPreviewTSAttachmentId = linkPreview?.imageAttachmentId
            let contactShare = try Self.contactShare(messageRow: messageRow)
            let contactTSAttachmentId = contactShare?.avatarAttachmentId
            let quotedMessage = try Self.quotedMessage(messageRow: messageRow)
            let quotedMessageTSAttachmentId = quotedMessage?.quotedAttachment?.rawAttachmentId.nilIfEmpty

            // Check if the message has any attachments.
            let allAttachmentIds: [String] = (
                bodyTSAttachmentIds
                + [
                    stickerTSAttachmentId,
                    linkPreviewTSAttachmentId,
                    contactTSAttachmentId,
                    quotedMessageTSAttachmentId
                ]
            ).compacted()

            if allAttachmentIds.isEmpty {
                // Nothing to migrate! This can happen if an edit removed attachments.
                try reservedFileIdsArray.forEach { try $0.cleanUpFiles() }
                return []
            }

            // Ensure every attachment is represented in the reserved ids.
            let hasUnreservedAttachment = allAttachmentIds.contains(where: {
                reservedFileIdsDict[$0] == nil
            })
            if hasUnreservedAttachment {
                guard isRunningIteratively else {
                    // If we are running as a blocking GRDB migration this should be impossible.
                    throw OWSAssertionError("Message attachment changed between blocking migrations")
                }
                try reservedFileIdsArray.forEach { try $0.cleanUpFiles() }
                // Return nil to mark this message and needing another pass.
                return nil
            }

            guard let threadUniqueId = messageRow["uniqueThreadId"] as? String else {
                throw OWSAssertionError("Missing thread for message")
            }

            let threadRowId = try Int64.fetchOne(
                tx.database,
                sql: "SELECT id FROM model_TSThread WHERE uniqueId = ?;",
                arguments: [threadUniqueId]
            )
            guard let threadRowId else {
                throw OWSAssertionError("Thread doesn't exist for message")
            }

            guard
                // Row only gives Int64, never UInt64
                let messageReceivedAtTimestampRaw = messageRow["receivedAtTimestamp"] as? Int64
            else {
                throw OWSAssertionError("Missing timestamp for message")
            }
            let messageReceivedAtTimestamp = UInt64(bitPattern: messageReceivedAtTimestampRaw)

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
            ) throws {
                guard let reservedFileIds = reservedFileIdsDict.removeValue(forKey: tsAttachmentUniqueId) else {
                    throw OWSAssertionError("Missing reservation for attachment")
                }
                let migratedAttachment = try Self.migrateSingleMessageAttachment(
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
                    tx: tx
                )
                if let migratedAttachment {
                    migratedAttachments.append(migratedAttachment)
                }
            }

            var newBodyAttachmentIds: [String]?
            var newContact: TSAttachmentMigration.OWSContact?
            var newMessageSticker: TSAttachmentMigration.MessageSticker?
            var newLinkPreview: TSAttachmentMigration.OWSLinkPreview?
            var newQuotedMessage: TSAttachmentMigration.TSQuotedMessage?

            for (index, bodyTSAttachmentId) in bodyTSAttachmentIds.enumerated() {
                try migrateSingleMessageAttachment(
                    tsAttachmentUniqueId: bodyTSAttachmentId,
                    messageOwnerType: .bodyAttachment,
                    orderInMessage: index
                )
                newBodyAttachmentIds = []
            }

            if let messageSticker, let stickerTSAttachmentId {
                try migrateSingleMessageAttachment(
                    tsAttachmentUniqueId: stickerTSAttachmentId,
                    messageOwnerType: .sticker,
                    stickerPackId: messageSticker.info.packId,
                    stickerId: messageSticker.info.stickerId
                )
                newMessageSticker = messageSticker
                newMessageSticker?.attachmentId = nil
            }

            if let linkPreviewTSAttachmentId {
                try migrateSingleMessageAttachment(
                    tsAttachmentUniqueId: linkPreviewTSAttachmentId,
                    messageOwnerType: .linkPreview
                )
                newLinkPreview = linkPreview
                newLinkPreview?.imageAttachmentId = nil
                newLinkPreview?.usesV2AttachmentReferenceValue = NSNumber(value: true)
            }

            if let contactTSAttachmentId {
                try migrateSingleMessageAttachment(
                    tsAttachmentUniqueId: contactTSAttachmentId,
                    messageOwnerType: .contactAvatar
                )
                newContact = contactShare
                newContact?.avatarAttachmentId = nil
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
                    try migrateSingleMessageAttachment(
                        tsAttachmentUniqueId: quotedMessageTSAttachmentId,
                        messageOwnerType: .quotedReplyAttachment
                    )
                    newQuotedMessage = quotedMessage
                    var newQuotedAttachment = newQuotedMessage?.quotedAttachment
                    newQuotedAttachment?.rawAttachmentId = ""
                    newQuotedAttachment?.attachmentType = .v2
                    newQuotedAttachment?.contentType = nil
                    newQuotedAttachment?.sourceFilename = nil
                    newQuotedMessage?.quotedAttachment = newQuotedAttachment
                case .originalForSend, .original:
                    guard let reservedFileIds = reservedFileIdsDict.removeValue(forKey: quotedMessageTSAttachmentId) else {
                        throw OWSAssertionError("Missing reservation for attachment")
                    }
                    // These point at the attachment of the message being quoted.
                    // We need to thumbnail the message.
                    newQuotedMessage = try Self.migrateQuotedMessageAttachment(
                        quotedMessage: quotedMessage,
                        originalTSAttachmentUniqueId: quotedMessageTSAttachmentId,
                        reservedFileIds: reservedFileIds,
                        messageRowId: messageRowId,
                        threadRowId: threadRowId,
                        messageReceivedAtTimestamp: messageReceivedAtTimestamp,
                        tx: tx
                    )
                case .unset, .v2:
                    // Nothing to migrate
                    break
                }
            }

            try Self.updateMessageRow(
                rowId: messageRowId,
                bodyAttachmentIds: newBodyAttachmentIds,
                contact: newContact,
                messageSticker: newMessageSticker,
                linkPreview: newLinkPreview,
                quotedMessage: newQuotedMessage,
                tx: tx
            )

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
            tx: GRDBWriteTransaction
        ) throws -> TSAttachmentMigration.V1Attachment? {
            let oldAttachment = try TSAttachmentMigration.V1Attachment
                .filter(Column("uniqueId") == tsAttachmentUniqueId)
                .fetchOne(tx.database)
            guard let oldAttachment else {
                try reservedFileIds.cleanUpFiles()
                return nil
            }

            let pendingAttachment: TSAttachmentMigration.PendingV2AttachmentFile?
            if let oldFilePath = oldAttachment.localFilePath, OWSFileSystem.fileOrFolderExists(atPath: oldFilePath) {
                pendingAttachment = try TSAttachmentMigration.V2AttachmentContentValidator.validateContents(
                    unencryptedFileUrl: URL(fileURLWithPath: oldFilePath),
                    reservedFileIds: .init(
                        primaryFile: reservedFileIds.reservedV2AttachmentPrimaryFileId,
                        audioWaveform: reservedFileIds.reservedV2AttachmentAudioWaveformFileId,
                        videoStillFrame: reservedFileIds.reservedV2AttachmentVideoStillFrameFileId
                    ),
                    encryptionKey: oldAttachment.encryptionKey,
                    mimeType: oldAttachment.contentType,
                    renderingFlag: oldAttachment.attachmentType.asRenderingFlag,
                    sourceFilename: oldAttachment.sourceFilename
                )
            } else {
                // A pointer; no validation needed.
                pendingAttachment = nil
                // Clean up files just in case.
                try reservedFileIds.cleanUpFiles()
            }

            let v2AttachmentId: Int64
            if
                let pendingAttachment,
                let existingV2Attachment = try TSAttachmentMigration.V2Attachment
                    .filter(Column("sha256ContentHash") == pendingAttachment.sha256ContentHash)
                    .fetchOne(tx.database)
            {
                // If we already have a v2 attachment with the same plaintext hash,
                // create new references to it and drop the pending attachment.
                v2AttachmentId = existingV2Attachment.id!
                // Delete the reserved files being used by the pending attachment.
                try reservedFileIds.cleanUpFiles()
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
                        transitEncryptionKey: oldAttachment.encryptionKey,
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
                        encryptionKey: oldAttachment.encryptionKey ?? Cryptography.randomAttachmentEncryptionKey(),
                        digestSHA256Ciphertext: nil,
                        contentType: nil,
                        transitCdnNumber: oldAttachment.cdnNumber,
                        transitCdnKey: oldAttachment.cdnKey,
                        transitUploadTimestamp: oldAttachment.uploadTimestamp,
                        transitEncryptionKey: oldAttachment.encryptionKey,
                        transitUnencryptedByteCount: oldAttachment.byteCount,
                        transitDigestSHA256Ciphertext: oldAttachment.digest,
                        lastTransitDownloadAttemptTimestamp: nil,
                        localRelativeFilePath: pendingAttachment?.localRelativeFilePath,
                        cachedAudioDurationSeconds: nil,
                        cachedMediaHeightPixels: nil,
                        cachedMediaWidthPixels: nil,
                        cachedVideoDurationSeconds: nil,
                        audioWaveformRelativeFilePath: nil,
                        videoStillFrameRelativeFilePath: nil
                    )
                }

                try v2Attachment.insert(tx.database)
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
                    try oldAttachment.deleteMediaGalleryRecord(tx: tx)
                    fallthrough
                }
            default:
                ownerTypeRaw = UInt32(messageOwnerType.rawValue)
            }

            let (sourceMediaHeightPixels, sourceMediaWidthPixels) = try oldAttachment.sourceMediaSizePixels() ?? (nil, nil)

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
                stickerId: stickerId
            )
            try reference.insert(tx.database)

            // Edits might be reusing the original's TSAttachment.
            // DON'T delete the TSAttachment so its still available for the original.
            // Also don't return it (so we don't delete its files either).
            // If it turns out the original doesn't reuse (e.g. we edited oversize text),
            // this attachment will stick around until the migration is done, but
            // will get deleted when we bulk delete the table and folder at the end.
            if isEditedMessage {
                return nil
            }

            try oldAttachment.delete(tx.database)

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
            tx: GRDBWriteTransaction
        ) throws -> TSAttachmentMigration.TSQuotedMessage? {
            let oldAttachment = try TSAttachmentMigration.V1Attachment
                .filter(Column("uniqueId") == originalTSAttachmentUniqueId)
                .fetchOne(tx.database)
            guard let oldAttachment else {
                try reservedFileIds.cleanUpFiles()
                return nil
            }

            let rawContentType = TSAttachmentMigration.V2AttachmentContentValidator.rawContentType(
                mimeType: oldAttachment.contentType
            )

            guard
                let oldFilePath = oldAttachment.localFilePath,
                OWSFileSystem.fileOrFolderExists(atPath: oldFilePath),
                rawContentType == .image || rawContentType == .video || rawContentType == .animatedImage
            else {
                // We've got no original media stream, just a pointer or non-visual media.
                // We can't easily handle this, so instead just fall back to a stub.
                var newQuotedMessage = quotedMessage
                var newQuotedAttachment = newQuotedMessage.quotedAttachment
                newQuotedAttachment?.attachmentType = .unset
                newQuotedAttachment?.rawAttachmentId = ""
                newQuotedAttachment?.contentType = oldAttachment.contentType
                newQuotedAttachment?.sourceFilename = oldAttachment.sourceFilename
                newQuotedMessage.quotedAttachment = newQuotedAttachment

                try reservedFileIds.cleanUpFiles()
                return newQuotedMessage
            }

            let pendingAttachment = try TSAttachmentMigration.V2AttachmentContentValidator.prepareQuotedReplyThumbnail(
                fromOriginalAttachmentStream: oldAttachment,
                reservedFileIds: .init(
                    primaryFile: reservedFileIds.reservedV2AttachmentPrimaryFileId,
                    audioWaveform: reservedFileIds.reservedV2AttachmentAudioWaveformFileId,
                    videoStillFrame: reservedFileIds.reservedV2AttachmentVideoStillFrameFileId
                ),
                renderingFlag: oldAttachment.attachmentType.asRenderingFlag,
                sourceFilename: oldAttachment.sourceFilename
            )

            let v2AttachmentId: Int64

            let existingV2Attachment = try TSAttachmentMigration.V2Attachment
                .filter(Column("sha256ContentHash") == pendingAttachment.sha256ContentHash)
                .fetchOne(tx.database)
            if let existingV2Attachment {
                // If we already have a v2 attachment with the same plaintext hash,
                // create new references to it and drop the pending attachment.
                v2AttachmentId = existingV2Attachment.id!
                // Delete the reserved files being used by the pending attachment.
                try reservedFileIds.cleanUpFiles()
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

                try v2Attachment.insert(tx.database)
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
                stickerId: nil
            )
            try reference.insert(tx.database)

            // NOTE: we DO NOT delete the old attachment. It belongs to the original message.

            var newQuotedMessage = quotedMessage
            var newQuotedAttachment = newQuotedMessage.quotedAttachment
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
                throw OWSAssertionError("Unexpected type when decoding")
            }
            return decoded
        }

        private static func bodyAttachmentIds(messageRow: Row) throws -> [String] {
            guard let encoded = messageRow["attachmentIds"] as? Data else {
                return []
            }
            let decoded: NSArray = try unarchive(encoded)

            var array = [String]()
            try decoded.forEach { element in
                guard let attachmentId = element as? String else {
                    throw OWSAssertionError("Invalid attachment id")
                }
                array.append(attachmentId)
            }
            return array
        }

        private static func contactShare(messageRow: Row) throws -> TSAttachmentMigration.OWSContact? {
            guard let encoded = messageRow["contactShare"] as? Data else {
                return nil
            }
            return try unarchive(encoded)
        }

        private static func contactAttachmentId(messageRow: Row) throws -> String? {
            return try contactShare(messageRow: messageRow)?.avatarAttachmentId
        }

        private static func messageSticker(messageRow: Row) throws -> TSAttachmentMigration.MessageSticker? {
            guard let encoded = messageRow["messageSticker"] as? Data else {
                return nil
            }
            return try unarchive(encoded)
        }

        private static func stickerAttachmentId(messageRow: Row) throws -> String? {
            return try messageSticker(messageRow: messageRow)?.attachmentId
        }

        private static func linkPreview(messageRow: Row) throws -> TSAttachmentMigration.OWSLinkPreview? {
            guard let encoded = messageRow["linkPreview"] as? Data else {
                return nil
            }
            return try unarchive(encoded)
        }

        private static func linkPreviewAttachmentId(messageRow: Row) throws -> String? {
            return try linkPreview(messageRow: messageRow)?.imageAttachmentId
        }

        private static func quotedMessage(messageRow: Row) throws -> TSAttachmentMigration.TSQuotedMessage? {
            guard let encoded = messageRow["quotedMessage"] as? Data else {
                return nil
            }
            return try unarchive(encoded)
        }

        private static func quoteAttachmentId(messageRow: Row) throws -> String? {
            return try quotedMessage(messageRow: messageRow)?.quotedAttachment?.rawAttachmentId.nilIfEmpty
        }

        private static func archive(_ value: Any) throws -> Data {
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
            tx: GRDBWriteTransaction
        ) throws {
            var sql = "UPDATE model_TSInteraction SET "
            var arguments = StatementArguments()

            var columns = [String]()
            if let bodyAttachmentIds {
                columns.append("attachmentIds")
                _ = arguments.append(contentsOf: [try archive(bodyAttachmentIds)])
            }
            if let contact {
                columns.append("contactShare")
                _ = arguments.append(contentsOf: [try archive(contact)])
            }
            if let messageSticker {
                columns.append("messageSticker")
                _ = arguments.append(contentsOf: [try archive(messageSticker)])
            }
            if let linkPreview {
                columns.append("linkPreview")
                _ = arguments.append(contentsOf: [try archive(linkPreview)])
            }
            if let quotedMessage {
                columns.append("quotedMessage")
                _ = arguments.append(contentsOf: [try archive(quotedMessage)])
            }

            sql.append(columns.map({ $0 + " = ?"}).joined(separator: ", "))
            sql.append(" WHERE id = ?;")
            _ = arguments.append(contentsOf: [rowId])
            tx.execute(sql: sql, arguments: arguments)
        }
    }
}
