//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import LibSignalClient
import XCTest

@testable import SignalServiceKit

final class DatabaseRecoveryTest: SSKBaseTest {
    // MARK: - Setup

    override func setUp() {
        super.setUp()
        SSKEnvironment.shared.databaseStorageRef.write { tx in
            (DependenciesBridge.shared.registrationStateChangeManager as! RegistrationStateChangeManagerImpl).registerForTests(
                localIdentifiers: .forUnitTests,
                tx: tx,
            )
        }
    }

    private func cloneDatabaseStorage(_ databaseStorage: SDSDatabaseStorage) throws -> SDSDatabaseStorage {
        return try SDSDatabaseStorage(
            appReadiness: AppReadinessMock(),
            databaseFileUrl: databaseStorage.databaseFileUrl,
            keychainStorage: databaseStorage.keychainStorage,
        )
    }

    // MARK: - Reindex existing database

    func testReindexExistingDatabase() throws {
        let databaseStorage = try newDatabase()
        try GRDBSchemaMigrator.migrateDatabase(databaseStorage: databaseStorage)
        let oldRowCounts = try normalTableRowCounts(databaseStorage: databaseStorage)
        try XCTUnwrap(databaseStorage.grdbStorage.pool.close())

        DatabaseRecovery.reindex(databaseStorage: try cloneDatabaseStorage(databaseStorage))

        // As a smoke test, ensure that the database has the same number of rows.
        let finishedDatabaseStorage = try cloneDatabaseStorage(databaseStorage)
        let newRowCounts = try normalTableRowCounts(databaseStorage: finishedDatabaseStorage)
        XCTAssertEqual(newRowCounts, oldRowCounts)
    }

    // MARK: - Dump and restore

    func testDumpedTables() throws {
        let allTableNames = DatabaseRecovery.DumpAndRestoreOperation.allTableNames
        let allTableNamesSet = Set(allTableNames)

        let hasDuplicates = allTableNames.count != allTableNamesSet.count
        XCTAssertFalse(hasDuplicates)

        for tableName in allTableNames {
            XCTAssertFalse(tableName.starts(with: "sqlite_"))
            XCTAssertFalse(tableName.isEmpty)
            XCTAssertNotNil(tableName.range(of: validTableOrColumnNameRegex, options: .regularExpression))
        }

        let expectedTableNames: Set<String> = try {
            let databaseStorage = SSKEnvironment.shared.databaseStorageRef
            return try databaseStorage.read { try allNormalTableNames(tx: $0) }
        }()
        XCTAssertEqual(allTableNamesSet, expectedTableNames)
    }

    func testColumnSafety() throws {
        let databaseStorage = SSKEnvironment.shared.databaseStorageRef
        let tableNames: Set<String> = try {
            return try databaseStorage.read { try allNormalTableNames(tx: $0) }
        }()

        for tableName in tableNames {
            let columnNames = try databaseStorage.read { transaction in
                try Self.columnNames(transaction: transaction, tableName: tableName)
            }
            for columnName in columnNames {
                XCTAssertFalse(columnName.isEmpty)
                XCTAssertNotNil(columnName.range(of: validTableOrColumnNameRegex, options: .regularExpression))
            }
        }
    }

    private func normalTableRowCounts(databaseStorage: SDSDatabaseStorage) throws -> [String: Int] {
        return try databaseStorage.read { tx throws -> [String: Int] in
            var result = [String: Int]()
            for tableName in try allNormalTableNames(tx: tx) {
                let sql = "SELECT COUNT(*) FROM \(tableName)"
                let rowCount = try XCTUnwrap(Int.fetchOne(tx.database, sql: sql))
                result[tableName] = rowCount
            }
            return result
        }
    }

    func testDumpAndRestoreOfEmptyDatabase() throws {
        let databaseStorage = try newDatabase()
        try GRDBSchemaMigrator.migrateDatabase(databaseStorage: databaseStorage)
        let oldRowCounts = try normalTableRowCounts(databaseStorage: databaseStorage)
        try XCTUnwrap(databaseStorage.grdbStorage.pool.close())

        let dump = DatabaseRecovery.DumpAndRestoreOperation(
            appReadiness: AppReadinessMock(),
            corruptDatabaseStorage: try cloneDatabaseStorage(databaseStorage),
            keychainStorage: databaseStorage.keychainStorage,
        )
        try XCTUnwrap(dump.run())

        let finishedDatabaseStorage = try cloneDatabaseStorage(databaseStorage)
        let newRowCounts = try normalTableRowCounts(databaseStorage: finishedDatabaseStorage)
        XCTAssertEqual(newRowCounts, oldRowCounts)
    }

    func testDumpAndRestoreOnHappyDatabase() throws {
        let databaseStorage = try newDatabase()
        try GRDBSchemaMigrator.migrateDatabase(databaseStorage: databaseStorage)

        let contactAci = Aci.randomForTesting()

        guard let localAci = DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.aci else {
            XCTFail("No local address. Test is not set up correctly")
            return
        }

        try! databaseStorage.write { transaction in
            // Threads
            let contactThread = insertContactThread(
                contactAddress: SignalServiceAddress(contactAci),
                transaction: transaction,
            )
            guard let contactThreadId = contactThread.sqliteRowId else {
                XCTFail("Thread was not inserted properly")
                return
            }

            // Message
            let messageBuilder: TSIncomingMessageBuilder = .withDefaultValues(
                thread: contactThread,
                timestamp: 1234,
                authorAci: contactAci,
                messageBody: AttachmentContentValidatorMock.mockValidatedBody("test outgoing message"),
            )
            let message = messageBuilder.build()
            message.anyInsert(transaction: transaction)

            // Reaction
            let reaction = OWSReaction(
                uniqueMessageId: message.uniqueId,
                emoji: "💽",
                reactor: localAci,
                sentAtTimestamp: 1234,
                receivedAtTimestamp: 1234,
            )
            reaction.anyInsert(transaction: transaction)

            // Pending read receipts (not copied)
            let pendingReadReceipt = PendingReadReceiptRecord(
                threadId: contactThreadId,
                messageTimestamp: Int64(message.timestamp),
                messageUniqueId: message.uniqueId,
                authorPhoneNumber: nil,
                authorAci: contactAci,
            )
            try pendingReadReceipt.insert(transaction.database)
        }

        try XCTUnwrap(databaseStorage.grdbStorage.pool.close())

        let dump = DatabaseRecovery.DumpAndRestoreOperation(
            appReadiness: AppReadinessMock(),
            corruptDatabaseStorage: try cloneDatabaseStorage(databaseStorage),
            keychainStorage: databaseStorage.keychainStorage,
        )
        try XCTUnwrap(dump.run())

        let finishedDatabaseStorage = try SDSDatabaseStorage(
            appReadiness: AppReadinessMock(),
            databaseFileUrl: databaseStorage.databaseFileUrl,
            keychainStorage: databaseStorage.keychainStorage,
        )
        finishedDatabaseStorage.read { transaction in
            // Thread
            let thread = TSContactThread.getWithContactAddress(
                SignalServiceAddress(contactAci),
                transaction: transaction,
            )
            guard let thread else {
                XCTFail("Contact thread not found in migrated database")
                return
            }

            // Message
            let threadInteractions: [TSInteraction] = {
                var result = [TSInteraction]()
                let finder = InteractionFinder(threadUniqueId: thread.uniqueId)
                try? finder.enumerateInteractionsForConversationView(
                    rowIdFilter: .newest,
                    tx: transaction,
                ) { interaction -> Bool in
                    result.append(interaction)
                    return true
                }
                return result
            }()
            XCTAssertEqual(threadInteractions.count, 1)
            guard let interaction = threadInteractions.first as? TSIncomingMessage else {
                XCTFail("Interaction is not an outgoing message")
                return
            }
            XCTAssertEqual(interaction.body, "test outgoing message")

            // Reaction
            let reactions: [OWSReaction] = {
                let finder = ReactionFinder(uniqueMessageId: interaction.uniqueId)
                return finder.allReactions(transaction: transaction)
            }()
            XCTAssertEqual(reactions.count, 1)
            guard let reaction = reactions.first else {
                XCTFail("Could not get the reaction")
                return
            }
            XCTAssertEqual(reaction.emoji, "💽")

            // Pending read receipts (not copied)
            let db = transaction.database
            let pendingReadReceipts: [PendingReadReceiptRecord]
            do {
                pendingReadReceipts = try PendingReadReceiptRecord.fetchAll(db)
            } catch {
                XCTFail("\(error)")
                return
            }
            XCTAssert(
                pendingReadReceipts.isEmpty,
                "Unexpectedly found \(pendingReadReceipts.count) pending read receipt(s)",
            )
        }
    }

    func testDumpAndRestoreWithInvalidEssentialTable() throws {
        let databaseStorage = try newDatabase()
        try GRDBSchemaMigrator.migrateDatabase(databaseStorage: databaseStorage)
        databaseStorage.write { transaction in
            try! transaction.database.drop(table: KeyValueStore.tableName)
        }
        try XCTUnwrap(databaseStorage.grdbStorage.pool.close())

        let dump = DatabaseRecovery.DumpAndRestoreOperation(
            appReadiness: AppReadinessMock(),
            corruptDatabaseStorage: try cloneDatabaseStorage(databaseStorage),
            keychainStorage: databaseStorage.keychainStorage,
        )
        XCTAssertThrowsError(try dump.run()) { error in
            XCTAssertEqual(
                error as? DatabaseRecoveryError,
                DatabaseRecoveryError.unrecoverablyCorrupted,
            )
        }
    }

    func testDumpAndRestoreWithInvalidNonessentialTable() throws {
        let databaseStorage = try newDatabase()
        try GRDBSchemaMigrator.migrateDatabase(databaseStorage: databaseStorage)
        databaseStorage.write { transaction in
            try! transaction.database.drop(table: OWSReaction.databaseTableName)
        }
        try XCTUnwrap(databaseStorage.grdbStorage.pool.close())

        let dump = DatabaseRecovery.DumpAndRestoreOperation(
            appReadiness: AppReadinessMock(),
            corruptDatabaseStorage: try cloneDatabaseStorage(databaseStorage),
            keychainStorage: databaseStorage.keychainStorage,
        )
        try XCTUnwrap(dump.run())

        let finishedDatabaseStorage = try SDSDatabaseStorage(
            appReadiness: AppReadinessMock(),
            databaseFileUrl: databaseStorage.databaseFileUrl,
            keychainStorage: databaseStorage.keychainStorage,
        )
        finishedDatabaseStorage.read { transaction in
            let sql = "SELECT EXISTS (SELECT 1 FROM \(OWSReaction.databaseTableName))"
            let database = transaction.database
            guard let anyRowExists = try? XCTUnwrap(Bool.fetchOne(database, sql: sql)) else {
                XCTFail("Could not fetch boolean from test query")
                return
            }
            XCTAssertFalse(anyRowExists, "Unexpectedly found a reaction")
        }
    }

    // MARK: - Manual restoration

    func testFullTextSearchRestoration() throws {
        let databaseStorage = try newDatabase()
        try GRDBSchemaMigrator.migrateDatabase(databaseStorage: databaseStorage)

        databaseStorage.write { transaction in
            let contactAci = Aci.randomForTesting()

            let contactThread = insertContactThread(
                contactAddress: SignalServiceAddress(contactAci),
                transaction: transaction,
            )

            let messageBuilder: TSIncomingMessageBuilder = .withDefaultValues(
                thread: contactThread,
                timestamp: 1234,
                authorAci: contactAci,
                messageBody: AttachmentContentValidatorMock.mockValidatedBody("foo bar"),
            )
            let message = messageBuilder.build()
            message.anyInsert(transaction: transaction)
        }

        try XCTUnwrap(databaseStorage.grdbStorage.pool.close())

        let dump = DatabaseRecovery.DumpAndRestoreOperation(
            appReadiness: AppReadinessMock(),
            corruptDatabaseStorage: try cloneDatabaseStorage(databaseStorage),
            keychainStorage: databaseStorage.keychainStorage,
        )
        try XCTUnwrap(dump.run())

        let finishedDatabaseStorage = try SDSDatabaseStorage(
            appReadiness: AppReadinessMock(),
            databaseFileUrl: databaseStorage.databaseFileUrl,
            keychainStorage: databaseStorage.keychainStorage,
        )

        let recreateFTSIndex = DatabaseRecovery.RecreateFTSIndexOperation(databaseStorage: finishedDatabaseStorage)
        recreateFTSIndex.run()

        finishedDatabaseStorage.read { transaction in
            func searchMessages(for searchText: String) -> [TSMessage] {
                var result = [TSMessage]()
                FullTextSearchIndexer.search(
                    for: searchText,
                    maxResults: 99,
                    tx: transaction,
                ) { match, _, _ in
                    result.append(match)
                }
                return result
            }

            XCTAssertEqual(searchMessages(for: "foo").count, 1)
            XCTAssertTrue(searchMessages(for: "garbage").isEmpty)
        }
    }

    // MARK: - Test helpers

    let validTableOrColumnNameRegex = "^[a-zA-Z][a-zA-Z0-9_]+$"

    func newDatabase() throws -> SDSDatabaseStorage {
        return try SDSDatabaseStorage(
            appReadiness: AppReadinessMock(),
            databaseFileUrl: OWSFileSystem.temporaryFileUrl(),
            keychainStorage: MockKeychainStorage(),
        )
    }

    func allNormalTableNames(tx: DBReadTransaction) throws -> Set<String> {
        let db = tx.database
        let sql = "SELECT name FROM sqlite_schema WHERE type IS 'table'"
        let allTableNames = Set(try String.fetchAll(db, sql: sql))
        owsPrecondition(!allTableNames.isEmpty, "No tables were found!")

        let tableNamesToSkip: Set<String> = ["grdb_migrations", "sqlite_sequence"]
        return allTableNames.filter { tableName in
            return
                !tableNamesToSkip.contains(tableName)
                    && !tableName.starts(with: "indexable_text")
                    && !tableName.starts(with: SearchableNameIndexerImpl.Constants.databaseTableName)

        }
    }

    static func columnNames(transaction: DBReadTransaction, tableName: String) throws -> [String] {
        let db = transaction.database
        var result = [String]()
        let cursor = try Row.fetchCursor(db, sql: "PRAGMA table_info(\(tableName))")
        try cursor.forEach { row in
            guard let columnName = row["name"] as? String else {
                throw OWSGenericError("Column name could not be read. Test is not working correctly")
            }
            result.append(columnName)
        }
        return result
    }

    func insertContactThread(
        contactAddress: SignalServiceAddress,
        transaction: DBWriteTransaction,
    ) -> TSContactThread {
        TSContactThread.getOrCreateThread(
            withContactAddress: contactAddress,
            transaction: transaction,
        )
    }
}

// MARK: - Test-only extensions

private extension DatabaseRecovery.DumpAndRestoreOperation {
    static var allTableNames: [String] {
        tablesToCopyWithBestEffort + tablesThatMustBeCopiedFlawlessly + tablesExplicitlySkipped
    }
}
