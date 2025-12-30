//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public enum DatabaseRecoveryError: Error {
    case ranOutOfDiskSpace
    case unrecoverablyCorrupted
}

/// Tries to recover corrupted databases.
///
/// Database recovery is split into three parts:
///
/// 1. Rebuild existing database. If we're lucky, we might be able to rebuild the existing database
///    in-place. This just runs `REINDEX` for now. We might be able to do other things in the future
///    like rebuilding the FTS index. If this succeeds, we probably don't need to do the rest.
/// 2. "Dump and restore". Before most of the app is set up (i.e., before database connections are
///    established), we copy some data into a new database and then make that new database the
///    primary database, clobbering the old one.
/// 3. "Manual recreation". After the app is mostly set up, we attempt to recover some additional
///    data, such as full-text search indexes, which can be recomputed.
///
/// Why have this split?
///
/// - If the process stops after we've clobbered the old database, we can still continue. For
///   example, imagine that the app crashes after the first step completes, or the user gets
///   impatient and closes the app.
/// - As of this writing, the code makes it challenging to do some data restoration, such as
///   restoring full-text search indexes, without the app being mostly set up.
///
/// It's up to the caller to coordinate these steps, and decide which are necessary.
public enum DatabaseRecovery {

    private static let logger = PrefixedLogger(prefix: "[DatabaseRecovery]")

    // MARK: - Reindex

    public static func reindex(databaseStorage: SDSDatabaseStorage) {
        logger.info("Attempting to reindex the database...")
        do {
            // We use the `performWrite` method directly instead of the usual
            // `write` methods because we explicitly do NOT want to owsFail if
            // opening the write throws an error (probably a corruption error).
            try databaseStorage.performWriteWithTxCompletion(
                file: #file,
                function: #function,
                line: #line,
            ) { tx in
                do {
                    try SqliteUtil.reindex(db: tx.database)
                    logger.info("Reindexed database")
                    return .commit
                } catch {
                    logger.warn("Failed to reindex database")
                    return .rollback
                }
            }
        } catch {
            logger.warn("Failed to write to database")
        }
    }

    // MARK: - Dump and restore

    /// Dump and restore tables.
    ///
    /// Remember: this isn't everything you need to do to recover a database! See earlier docs.
    public class DumpAndRestoreOperation {
        private let appReadiness: AppReadiness
        private let corruptDatabaseStorage: SDSDatabaseStorage
        private let keychainStorage: any KeychainStorage

        private let unitCountForCheckpoint: Int64 = 1
        private let unitCountForOldDatabaseMigration: Int64 = 1
        private let unitCountForNewDatabaseCreation: Int64 = 1
        private let unitCountForBestEffortCopy = Int64(DumpAndRestoreOperation.tablesToCopyWithBestEffort.count)
        private let unitCountForFlawlessCopy = Int64(DumpAndRestoreOperation.tablesThatMustBeCopiedFlawlessly.count)
        private let unitCountForMigrationIds: Int64 = 1
        private let unitCountForNewDatabasePromotion: Int64 = 3

        public let progress: Progress

        public init(appReadiness: AppReadiness, corruptDatabaseStorage: SDSDatabaseStorage, keychainStorage: any KeychainStorage) {
            self.appReadiness = appReadiness
            self.corruptDatabaseStorage = corruptDatabaseStorage
            self.keychainStorage = keychainStorage
            let totalUnitCount = Int64(
                unitCountForCheckpoint +
                    unitCountForOldDatabaseMigration +
                    unitCountForNewDatabaseCreation +
                    unitCountForBestEffortCopy +
                    unitCountForFlawlessCopy +
                    unitCountForMigrationIds +
                    unitCountForNewDatabasePromotion,
            )
            self.progress = Progress(totalUnitCount: totalUnitCount)
        }

        /// Run the dump and restore process.
        ///
        /// Remember: this isn't everything you need to do to recover a database! See earlier docs.
        ///
        /// If this completes successfully, you probably want to mark the database as dumped
        /// and restored.
        public func run() throws {
            guard progress.completedUnitCount == 0 else {
                owsFailDebug("Dump and restore should not be run more than once")
                return
            }

            guard Self.allTableNamesAreSafe() else {
                owsFail("An unsafe table name was found, which could lead to SQL injection. Stopping")
            }

            Self.logTablesExplicitlySkipped()

            logger.info("Attempting database dump and restore")

            let oldDatabaseStorage = self.corruptDatabaseStorage

            progress.performAsCurrent(withPendingUnitCount: unitCountForCheckpoint) {
                Self.attemptToCheckpoint(oldDatabaseStorage: oldDatabaseStorage)
            }

            progress.performAsCurrent(withPendingUnitCount: unitCountForOldDatabaseMigration) {
                do {
                    logger.info("Running migrations on old database...")
                    try Self.runMigrationsOn(databaseStorage: oldDatabaseStorage)
                } catch {
                    Logger.warn("Couldn't migrate existing database. Repair will probably fail because of an incompatible schema")
                }
            }

            let newTemporaryDatabaseFileUrl = Self.temporaryDatabaseFileUrl()
            defer {
                Self.deleteTemporaryDatabase(databaseFileUrl: newTemporaryDatabaseFileUrl)
            }

            let newDatabaseStorage = try progress.performAsCurrent(
                withPendingUnitCount: unitCountForNewDatabaseCreation,
            ) {
                let newDatabaseStorage: SDSDatabaseStorage
                do {
                    newDatabaseStorage = try SDSDatabaseStorage(
                        appReadiness: self.appReadiness,
                        databaseFileUrl: newTemporaryDatabaseFileUrl,
                        keychainStorage: self.keychainStorage,
                    )
                    logger.info("Running migrations on new database...")
                    try Self.runMigrationsOn(databaseStorage: newDatabaseStorage)
                    try Self.deleteEverythingFrom(databaseStorage: newDatabaseStorage)
                } catch {
                    throw DatabaseRecoveryError.unrecoverablyCorrupted
                }
                return newDatabaseStorage
            }

            let copyTablesWithBestEffort = Self.prepareToCopyTablesWithBestEffort(
                oldDatabaseStorage: oldDatabaseStorage,
                newDatabaseStorage: newDatabaseStorage,
            )
            progress.addChild(
                copyTablesWithBestEffort.progress,
                withPendingUnitCount: unitCountForBestEffortCopy,
            )
            try copyTablesWithBestEffort.run()

            let copyTablesThatMustBeCopiedFlawlessly = Self.prepareToCopyTablesThatMustBeCopiedFlawlessly(
                oldDatabaseStorage: oldDatabaseStorage,
                newDatabaseStorage: newDatabaseStorage,
            )
            progress.addChild(
                copyTablesThatMustBeCopiedFlawlessly.progress,
                withPendingUnitCount: unitCountForFlawlessCopy,
            )
            try copyTablesThatMustBeCopiedFlawlessly.run()

            progress.performAsCurrent(withPendingUnitCount: unitCountForMigrationIds) {
                do {
                    try Self.copyMigrationIds(oldDatabaseStorage: oldDatabaseStorage, newDatabaseStorage: newDatabaseStorage)
                } catch {
                    Logger.warn("Continuing despite MigrationId copy error: \(error.grdbErrorForLogging)")
                }
            }

            try progress.performAsCurrent(withPendingUnitCount: unitCountForNewDatabasePromotion) {
                try Self.promoteNewDatabase(
                    oldDatabaseStorage: oldDatabaseStorage,
                    newDatabaseStorage: newDatabaseStorage,
                )
            }

            logger.info("Dump and restore complete")
        }

        // MARK: Checkpoint old database to clear its WAL/SHM files

        private static func attemptToCheckpoint(oldDatabaseStorage: SDSDatabaseStorage) {
            logger.info("Attempting to checkpoint the old database...")
            do {
                try checkpoint(databaseStorage: oldDatabaseStorage)
                logger.info("Checkpointed old database.")
            } catch {
                logger.warn("Failed to checkpoint old database with error: \(error). Continuing on")
            }
        }

        // MARK: Creating new database

        private static func temporaryDatabaseFileUrl() -> URL {
            logger.info("Creating temporary database file...")
            let result = OWSFileSystem.temporaryFileUrl()
            logger.info("Created at \(result)")
            return result
        }

        private static func deleteTemporaryDatabase(databaseFileUrl: URL) {
            logger.info("Attempting to delete temporary database files...")
            let urls: [URL] = [
                databaseFileUrl,
                GRDBDatabaseStorageAdapter.walFileUrl(for: databaseFileUrl),
                GRDBDatabaseStorageAdapter.shmFileUrl(for: databaseFileUrl),
            ]
            for url in urls {
                do {
                    try OWSFileSystem.deleteFileIfExists(url: url)
                    logger.info("Deleted temporary database file")
                } catch {
                    logger.warn("Failed to delete temporary database file")
                }
            }
        }

        // MARK: Running schema migrations

        private static func runMigrationsOn(databaseStorage: SDSDatabaseStorage) throws {
            do {
                _ = try GRDBSchemaMigrator.migrateDatabase(
                    databaseStorage: databaseStorage,
                    // We assume data migrations don't affect the schema of the tables, and
                    // we'll run them on the repaired database if everything else succeeds.
                    runDataMigrations: false,
                )
                logger.info("Ran migrations")
            } catch {
                logger.warn("Failed to run migrations: \(error.grdbErrorForLogging)")
                throw error
            }
        }

        /// Runs DELETE FROM on every non-sqlite, non-grdb, non-fts table.
        private static func deleteEverythingFrom(databaseStorage: SDSDatabaseStorage) throws {
            try databaseStorage.write { tx in
                let tableNames = try String.fetchAll(tx.database, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")
                for tableName in tableNames {
                    let shouldSkip = (
                        Database.isSQLiteInternalTable(tableName)
                            || Database.isGRDBInternalTable(tableName),
                    )
                    if shouldSkip {
                        continue
                    }
                    if
                        let ftsTableName = ftsTableName(forTableName: tableName),
                        tableNames.contains(ftsTableName)
                    {
                        continue
                    }
                    owsPrecondition(SqliteUtil.isSafe(sqlName: tableName))
                    logger.info("Deleting everything from \(tableName)")
                    try tx.database.execute(sql: "DELETE FROM \"\(tableName)\"")
                }
            }
        }

        private static func ftsTableName(forTableName tableName: String) -> String? {
            for suffix in ["_config", "_data", "_docsize", "_idx"] {
                if let matchingRange = tableName.range(of: suffix, options: [.anchored, .backwards]) {
                    return String(tableName[..<matchingRange.lowerBound])
                }
            }
            return nil
        }

        // MARK: Copy tables with best effort

        static let tablesToCopyWithBestEffort: [String] = [
            // We should try to copy thread data.
            OWSReaction.databaseTableName,
            OWSRecipientIdentity.databaseTableName,
            OWSUserProfile.databaseTableName,
            SignalAccount.databaseTableName,
            SignalRecipient.databaseTableName,
            StoryMessage.databaseTableName,
            TSInteraction.table.tableName,
            TSGroupMember.databaseTableName,
            TSMention.databaseTableName,
            TSPaymentModel.table.tableName,
            TSThread.table.tableName,
            ThreadAssociatedData.databaseTableName,
            // We'd like to get receipts back, but it's okay if we don't get them all.
            DonationReceipt.databaseTableName,
            // We'd like to lookups for our contacts' usernames. However, we
            // don't want to block recovery on them.
            UsernameLookupRecord.databaseTableName,
            // This table should be recovered with the same effort as the
            // TSInteraction table. It doesn't hold any value without that data.
            EditRecord.databaseTableName,
            TSPaymentsActivationRequestModel.databaseTableName,
            // Okay to best-effort recover calls.
            CallLinkRecord.databaseTableName,
            CallRecord.databaseTableName,
            DeletedCallRecord.databaseTableName,
            NicknameRecord.databaseTableName,
            Attachment.Record.databaseTableName,
            AttachmentReference.MessageAttachmentReferenceRecord.databaseTableName,
            AttachmentReference.StoryMessageAttachmentReferenceRecord.databaseTableName,
            AttachmentReference.ThreadAttachmentReferenceRecord.databaseTableName,
            OrphanedAttachmentRecord.databaseTableName,
            QueuedAttachmentDownloadRecord.databaseTableName,
            ArchivedPayment.databaseTableName,
            QueuedBackupAttachmentDownload.databaseTableName,
            AttachmentUploadRecord.databaseTableName,
            "AttachmentValidationBackfillQueue",
            QueuedBackupAttachmentUpload.databaseTableName,
            QueuedBackupStickerPackDownload.databaseTableName,
            OrphanedBackupAttachment.databaseTableName,
            "MessageBackupAvatarFetchQueue",
            "AvatarDefaultColor",
            GroupMessageProcessorJob.databaseTableName,
            "ListedBackupMediaObject",
            "BackupOversizeTextCache",
            "Poll",
            "PollOption",
            "PollVote",
            "PinnedMessage",
        ]

        private static func prepareToCopyTablesWithBestEffort(
            oldDatabaseStorage: SDSDatabaseStorage,
            newDatabaseStorage: SDSDatabaseStorage,
        ) -> PreparedOperation {
            .init(totalUnitCount: Int64(tablesToCopyWithBestEffort.count)) { progress in
                for tableName in self.tablesToCopyWithBestEffort {
                    try progress.performAsCurrent(withPendingUnitCount: 1) {
                        try self.copyWithBestEffort(
                            tableName: tableName,
                            oldDatabaseStorage: oldDatabaseStorage,
                            newDatabaseStorage: newDatabaseStorage,
                        )
                    }
                }
            }
        }

        private static func copyWithBestEffort(
            tableName: String,
            oldDatabaseStorage: SDSDatabaseStorage,
            newDatabaseStorage: SDSDatabaseStorage,
        ) throws {
            logger.info("Attempting to copy \(tableName) (best effort)...")
            let result = copyTable(
                tableName: tableName,
                from: oldDatabaseStorage,
                to: newDatabaseStorage,
            )
            switch result {
            case let .totalFailure(error):
                logger.warn("Completely unable to copy \(tableName)")
                if error.isSqliteFullError {
                    throw DatabaseRecoveryError.ranOutOfDiskSpace
                }
            case let .copiedSomeButHadTrouble(error, rowsCopied):
                logger.warn("Finished copying \(tableName). Copied \(rowsCopied) row(s), but there was an error")
                if error.isSqliteFullError {
                    throw DatabaseRecoveryError.ranOutOfDiskSpace
                }
            case let .wentFlawlessly(rowsCopied):
                logger.info("Finished copying \(tableName). Copied \(rowsCopied) row(s)")
            }
        }

        // MARK: Copy essential tables

        static let tablesThatMustBeCopiedFlawlessly: [String] = [
            // The app will be too unpredictable with strange key-value stores.
            KeyValueStore.tableName,
            // If we get a disappearing timer wrong, users might send messages incorrectly.
            DisappearingMessagesConfigurationRecord.databaseTableName,
            // We don't want to get our linked devices wrong.
            // We *could* fetch these from the server. Could be a good followup change.
            OWSDevice.databaseTableName,
            // We must get these 3 right to keep everyone blocked.
            BlockedRecipient.databaseTableName,
            BlockedGroup.databaseTableName,
            StoryRecipient.databaseTableName,
            PreKey.databaseTableName,
            KyberPreKeyUseRecord.databaseTableName,
            SignalServiceKit.SessionRecord.databaseTableName,
        ]

        /// Copy tables that must be copied flawlessly. Operation throws if any tables fail.
        private static func prepareToCopyTablesThatMustBeCopiedFlawlessly(
            oldDatabaseStorage: SDSDatabaseStorage,
            newDatabaseStorage: SDSDatabaseStorage,
        ) -> PreparedOperation {
            .init(totalUnitCount: Int64(tablesThatMustBeCopiedFlawlessly.count)) { progress in
                for tableName in self.tablesThatMustBeCopiedFlawlessly {
                    let result = progress.performAsCurrent(withPendingUnitCount: 1) {
                        self.copyTableThatMustBeCopiedFlawlessly(
                            tableName: tableName,
                            oldDatabaseStorage: oldDatabaseStorage,
                            newDatabaseStorage: newDatabaseStorage,
                        )
                    }
                    switch result {
                    case let .totalFailure(error), let .copiedSomeButHadTrouble(error, _):
                        Logger.warn("Couldn't copy tables flawlessly: \(error.grdbErrorForLogging)")
                        let toThrow: DatabaseRecoveryError = error.isSqliteFullError ? .ranOutOfDiskSpace : .unrecoverablyCorrupted
                        throw toThrow
                    case .wentFlawlessly:
                        break
                    }
                }
            }
        }

        private static func copyTableThatMustBeCopiedFlawlessly(
            tableName: String,
            oldDatabaseStorage: SDSDatabaseStorage,
            newDatabaseStorage: SDSDatabaseStorage,
        ) -> TableCopyResult {
            logger.info("Attempting to copy \(tableName) (with no mistakes)...")
            let result = copyTable(
                tableName: tableName,
                from: oldDatabaseStorage,
                to: newDatabaseStorage,
            )
            switch result {
            case .totalFailure:
                logger.warn("Completely unable to copy \(tableName)")
            case let .copiedSomeButHadTrouble(_, rowsCopied):
                logger.warn("Failed copying \(tableName) flawlessly. Copied \(rowsCopied) row(s)")
            case let .wentFlawlessly(rowsCopied: rowsCopied):
                logger.info("Finished copying \(tableName). Copied \(rowsCopied) row(s)")
            }
            return result
        }

        // MARK: Copy migrations

        /// Copies migrationIds (esp. data migrations) that were already performed.
        ///
        /// After repairing, we want to skip data migrations we've already run, but
        /// we want to execute the ones that haven't yet run.
        private static func copyMigrationIds(
            oldDatabaseStorage: SDSDatabaseStorage,
            newDatabaseStorage: SDSDatabaseStorage,
        ) throws {
            let migrationIds = try oldDatabaseStorage.read { tx in
                return try String.fetchAll(tx.database, sql: "SELECT identifier FROM grdb_migrations")
            }
            try newDatabaseStorage.write { tx in
                for migrationId in migrationIds {
                    try tx.database.execute(
                        sql: "INSERT OR IGNORE INTO grdb_migrations (identifier) VALUES (?)",
                        arguments: [migrationId],
                    )
                }
            }
        }

        // MARK: Promote the old database

        /// "Promotes" the new database and clobbers the old one.
        ///
        /// Neither database instance should be used after this.
        private static func promoteNewDatabase(
            oldDatabaseStorage: SDSDatabaseStorage,
            newDatabaseStorage: SDSDatabaseStorage,
        ) throws {
            try checkpointAndClose(databaseStorage: oldDatabaseStorage, logLabel: "old")
            try checkpointAndClose(databaseStorage: newDatabaseStorage, logLabel: "new")

            logger.info("Replacing old database with the new one...")

            _ = try FileManager.default.replaceItemAt(
                oldDatabaseStorage.databaseFileUrl,
                withItemAt: newDatabaseStorage.databaseFileUrl,
            )

            logger.info("Out with the old database, in with the new!")
        }

        private static func checkpointAndClose(
            databaseStorage: SDSDatabaseStorage,
            logLabel: String,
        ) throws {
            logger.info("Checkpointing \(logLabel) database...")
            try checkpoint(databaseStorage: databaseStorage)

            logger.info("Checkpointed \(logLabel) database. Closing...")
            try databaseStorage.grdbStorage.pool.close()

            logger.info("Cleaning up WAL and SHM files...")
            OWSFileSystem.deleteFileIfExists(databaseStorage.grdbStorage.databaseWALFilePath)
            OWSFileSystem.deleteFileIfExists(databaseStorage.grdbStorage.databaseSHMFilePath)

            logger.info("\(logLabel.capitalized) database closed.")
        }

        // MARK: Tables that are explicitly skipped

        static let tablesExplicitlySkipped: [String] = [
            // We only need these for resend requests. We'd rather not send garbage.
            MessageSendLog.Message.databaseTableName,
            MessageSendLog.Payload.databaseTableName,
            MessageSendLog.Recipient.databaseTableName,
            // We'd rather not try to resurrect jobs, as they may result in unintended behavior (e.g., a bad message send).
            JobRecord.databaseTableName,
            PendingReadReceiptRecord.databaseTableName,
            PendingViewedReceiptRecord.databaseTableName,
            // Can be recovered in other ways, after recovery is done.
            ProfileBadge.databaseTableName,
            StickerPack.table.tableName,
            HiddenRecipient.databaseTableName,
            // Not essential.
            StoryContextAssociatedData.databaseTableName,
            ExperienceUpgrade.databaseTableName,
            InstalledSticker.table.tableName,
            CancelledGroupRing.databaseTableName,
            CdsPreviousE164.databaseTableName,
            SpamReportingTokenRecord.databaseTableName,
            // Can be easily re-created.
            CombinedGroupSendEndorsementRecord.databaseTableName,
            IndividualGroupSendEndorsementRecord.databaseTableName,
        ]

        /// Log the tables we're explicitly skipping.
        ///
        /// This is a little weird, but helps us be clear: we don't copy all tables.
        private static func logTablesExplicitlySkipped() {
            logger.info("Explicitly skipping tables: \(tablesExplicitlySkipped.joined(separator: ", "))")
        }

        // MARK: Checkpointing tables

        private static func checkpoint(databaseStorage: SDSDatabaseStorage) throws {
            try databaseStorage.grdbStorage.pool.writeWithoutTransaction { database -> Void in
                // It's important that we do a truncating checkpoint so we empty out the WAL.
                // Alternatively, we could copy it over.
                try database.checkpoint(.truncate)
            }
        }

        // MARK: Copying tables

        enum TableCopyResult {
            case totalFailure(error: Error)
            case copiedSomeButHadTrouble(error: Error, rowsCopied: UInt)
            case wentFlawlessly(rowsCopied: UInt)
        }

        private static func copyTable(
            tableName: String,
            from: SDSDatabaseStorage,
            to: SDSDatabaseStorage,
        ) -> TableCopyResult {
            owsPrecondition(SqliteUtil.isSafe(sqlName: tableName))

            do {
                return try from.readThrows(
                    file: #file,
                    function: #function,
                    line: #line,
                ) { fromTransaction -> TableCopyResult in
                    let fromDb = fromTransaction.database

                    let columnNames: [String]
                    let cursor: RowCursor
                    do {
                        columnNames = try getColumnNames(db: fromDb, tableName: tableName)
                        cursor = try Row.fetchCursor(fromDb, sql: "SELECT * FROM \(tableName)")
                    } catch {
                        logger.warn("Could not create cursor for table \(tableName) with error: \(error)")
                        return .totalFailure(error: error)
                    }

                    let insertSql = insertSql(tableName: tableName, columnNames: columnNames)

                    return to.write { toTransaction in
                        let toDb = toTransaction.database

                        let insertStatement: Statement
                        do {
                            insertStatement = try toDb.makeStatement(sql: insertSql)
                        } catch {
                            logger.warn("Could not create prepared insert statement. \(error)")
                            return .totalFailure(error: error)
                        }

                        var rowsCopied: UInt = 0
                        var latestError: Error?

                        do {
                            try cursor.forEach { row in
                                let statementArguments = StatementArguments(row.asDictionary)
                                do {
                                    try insertStatement.execute(arguments: statementArguments)
                                    rowsCopied += 1
                                } catch {
                                    latestError = error
                                }
                            }
                        } catch {
                            logger.warn("Error while iterating: \(error)")
                            latestError = error
                        }

                        if let latestError {
                            return .copiedSomeButHadTrouble(error: latestError, rowsCopied: rowsCopied)
                        } else {
                            return .wentFlawlessly(rowsCopied: rowsCopied)
                        }
                    }
                }
            } catch {
                logger.warn("Error when reading: \(error)")
                return .totalFailure(error: error)
            }
        }

        // MARK: Utilities

        /// Determine whether a table name *could* lead to SQL injection.
        ///
        /// This is unlikely to happen, and should always return `true`.
        /// See documentation for ``SqliteUtil.isSafe`` for more.
        private static func allTableNamesAreSafe() -> Bool {
            (tablesToCopyWithBestEffort + tablesThatMustBeCopiedFlawlessly).allSatisfy {
                SqliteUtil.isSafe(sqlName: $0)
            }
        }

        private static func getColumnNames(db: Database, tableName: String) throws -> [String] {
            owsPrecondition(SqliteUtil.isSafe(sqlName: tableName))

            var result = [String]()
            let cursor = try Row.fetchCursor(db, sql: "PRAGMA table_info(\(tableName))")
            try cursor.forEach { row in
                guard let columnName = row["name"] as? String else {
                    throw DatabaseRecoveryError.unrecoverablyCorrupted
                }
                result.append(columnName)
            }
            return result
        }

        private static func insertSql(tableName: String, columnNames: [String]) -> String {
            owsPrecondition(SqliteUtil.isSafe(sqlName: tableName))
            for columnName in columnNames {
                owsPrecondition(SqliteUtil.isSafe(sqlName: columnName))
            }

            let columnNamesSql = columnNames.map({ "'\($0)'" }).joined(separator: ", ")
            let valuesSql = columnNames.map({ ":\($0)" }).joined(separator: ", ")
            return "INSERT INTO \(tableName) (\(columnNamesSql)) VALUES (\(valuesSql))"
        }
    }

    // MARK: - Manual recreation

    /// Manually recreate various tables, such as the full-text search indexes.
    public class RecreateFTSIndexOperation {
        private let databaseStorage: SDSDatabaseStorage

        private let unitCountForFullTextSearch: Int64 = 2
        public let progress: Progress

        public init(databaseStorage: SDSDatabaseStorage) {
            self.databaseStorage = databaseStorage
            self.progress = Progress(totalUnitCount: unitCountForFullTextSearch)
        }

        public func run() {
            guard progress.completedUnitCount == 0 else {
                owsFailDebug("Manual recreation should not be run more than once")
                return
            }

            progress.performAsCurrent(withPendingUnitCount: unitCountForFullTextSearch) {
                attemptToRecreateFullTextSearch()
            }
        }

        private func attemptToRecreateFullTextSearch() {
            logger.info("Starting to re-index full text search...")

            databaseStorage.write { tx in
                let searchableNameIndexer = DependenciesBridge.shared.searchableNameIndexer
                searchableNameIndexer.indexEverything(tx: tx)
            }

            databaseStorage.write { tx in
                TSInteraction.anyEnumerate(transaction: tx) { interaction, _ in
                    guard let message = interaction as? TSMessage else {
                        return
                    }
                    FullTextSearchIndexer.insert(message, tx: tx)
                }
            }

            logger.info("Finished re-indexing full text search")
        }
    }

    // MARK: - Utilities

    private struct PreparedOperation {
        let progress: Progress
        private let fn: (Progress) throws -> Void

        init(totalUnitCount: Int64, fn: @escaping (Progress) throws -> Void) {
            self.progress = Progress(totalUnitCount: totalUnitCount)
            self.fn = fn
        }

        func run() throws {
            try fn(progress)
        }
    }

    public static func integrityCheck(databaseStorage: SDSDatabaseStorage) -> SqliteUtil.IntegrityCheckResult {
        logger.info("Running integrity check on database...")
        let result = GRDBDatabaseStorageAdapter.checkIntegrity(databaseStorage: databaseStorage)
        switch result {
        case .ok: logger.info("Integrity check succeeded!")
        case .notOk: logger.warn("Integrity check failed")
        }
        return result
    }
}

// MARK: -

private extension Error {
    var isSqliteFullError: Bool {
        guard let self = self as? DatabaseError else { return false }
        return self.resultCode == .SQLITE_FULL
    }
}

// MARK: -

private extension Row {
    var asDictionary: [String: DatabaseValue] {
        var result = [String: DatabaseValue]()
        for rowIndex in stride(from: startIndex, to: endIndex, by: 1) {
            let (columnName, databaseValue) = self[rowIndex]
            result[columnName] = databaseValue
        }
        return result
    }
}
