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
            fatalError("TODO")
        }

        /// Completes another prepared batch, returns count of touched message rows.
        ///
        /// If a batch size is provided, prepares only that many prepared messages. Otherwise migares all prepared messages.
        private static func completeTSMessageMigrationBatch(
            batchSize: Int?,
            tx: GRDBWriteTransaction
        ) throws -> Int {
            fatalError("TODO")
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
