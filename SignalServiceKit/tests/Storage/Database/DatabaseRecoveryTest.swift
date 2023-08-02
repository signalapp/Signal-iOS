//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import LibSignalClient
import XCTest

@testable import SignalServiceKit

final class DatabaseRecoveryTest: SSKBaseTestSwift {
    // MARK: - Setup

    override func setUp() {
        super.setUp()
        tsAccountManager.registerForTests(withLocalNumber: "+12225550101", uuid: UUID(), pni: UUID())
    }

    // MARK: - Rebuild existing database

    func testRebuildExistingDatabase() throws {
        let (databaseStorage, url) = database()
        try GRDBSchemaMigrator.migrateDatabase(databaseStorage: databaseStorage, isMainDatabase: false)
        try XCTUnwrap(databaseStorage.grdbStorage.pool.close())

        DatabaseRecovery.rebuildExistingDatabase(at: url)

        // As a smoke test, ensure that the database is still empty.
        let finishedDatabaseStorage = SDSDatabaseStorage(
            databaseFileUrl: url,
            delegate: DatabaseTestHelpers.TestSDSDatabaseStorageDelegate()
        )
        finishedDatabaseStorage.read { transaction in
            let database = transaction.unwrapGrdbRead.database
            for tableName in allNormalTableNames(transaction: transaction) {
                let sql = "SELECT EXISTS (SELECT 1 FROM \(tableName))"
                guard let anyRowExists = try? XCTUnwrap(Bool.fetchOne(database, sql: sql)) else {
                    XCTFail("Could not fetch boolean from test query")
                    return
                }
                XCTAssertFalse(anyRowExists, "\(tableName) had at least one row, unexpectedly")
            }
        }
    }

    // MARK: - Dump and restore

    func testDumpedTables() throws {
        let allTableNames = DatabaseRecovery.DumpAndRestore.allTableNames
        let allTableNamesSet = Set(allTableNames)

        let hasDuplicates = allTableNames.count != allTableNamesSet.count
        XCTAssertFalse(hasDuplicates)

        for tableName in allTableNames {
            XCTAssertFalse(tableName.starts(with: "sqlite_"))
            XCTAssertFalse(tableName.isEmpty)
            XCTAssertNotNil(tableName.range(of: validTableOrColumnNameRegex, options: .regularExpression))
        }

        let expectedTableNames: Set<String> = try {
            let (databaseStorage, _) = database()
            try GRDBSchemaMigrator.migrateDatabase(databaseStorage: databaseStorage, isMainDatabase: false)
            return databaseStorage.read { allNormalTableNames(transaction: $0) }
        }()
        XCTAssertEqual(allTableNamesSet, expectedTableNames)
    }

    func testColumnSafety() throws {
        let (databaseStorage, _) = database()
        let tableNames: Set<String> = try {
            try GRDBSchemaMigrator.migrateDatabase(databaseStorage: databaseStorage, isMainDatabase: false)
            return databaseStorage.read { allNormalTableNames(transaction: $0) }
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

    func testDumpAndRestoreOfEmptyDatabase() throws {
        let (databaseStorage, url) = database()
        try GRDBSchemaMigrator.migrateDatabase(databaseStorage: databaseStorage, isMainDatabase: false)
        try XCTUnwrap(databaseStorage.grdbStorage.pool.close())

        let dump = DatabaseRecovery.DumpAndRestore(databaseFileUrl: url)
        try XCTUnwrap(dump.run())

        let finishedDatabaseStorage = SDSDatabaseStorage(
            databaseFileUrl: url,
            delegate: DatabaseTestHelpers.TestSDSDatabaseStorageDelegate()
        )
        finishedDatabaseStorage.read { transaction in
            let database = transaction.unwrapGrdbRead.database
            for tableName in allNormalTableNames(transaction: transaction) {
                let sql = "SELECT EXISTS (SELECT 1 FROM \(tableName))"
                guard let anyRowExists = try? XCTUnwrap(Bool.fetchOne(database, sql: sql)) else {
                    XCTFail("Could not fetch boolean from test query")
                    return
                }
                XCTAssertFalse(anyRowExists, "\(tableName) had at least one row, unexpectedly")
            }
        }
    }

    func testDumpAndRestoreOnHappyDatabase() throws {
        let (databaseStorage, url) = database()
        try GRDBSchemaMigrator.migrateDatabase(databaseStorage: databaseStorage, isMainDatabase: false)

        let contactAci = Aci.randomForTesting()

        guard let localAci = tsAccountManager.localIdentifiers?.aci else {
            XCTFail("No local address. Test is not set up correctly")
            return
        }

        try! databaseStorage.write { transaction in
            // Threads
            let contactThread = insertContactThread(
                contactAddress: SignalServiceAddress(contactAci),
                transaction: transaction
            )
            guard let contactThreadId = contactThread.grdbId?.int64Value else {
                XCTFail("Thread was not inserted properly")
                return
            }

            // Message
            let messageBuilder = TSIncomingMessageBuilder.incomingMessageBuilder(
                thread: contactThread,
                messageBody: "test outgoing message"
            )
            messageBuilder.timestamp = 1234
            messageBuilder.authorAci = AciObjC(contactAci)
            let message = messageBuilder.build()
            message.anyInsert(transaction: transaction)

            // Reaction
            let reaction = OWSReaction(
                uniqueMessageId: message.uniqueId,
                emoji: "💽",
                reactor: localAci,
                sentAtTimestamp: 1234,
                receivedAtTimestamp: 1234
            )
            reaction.anyInsert(transaction: transaction)

            // Pending read receipts (not copied)
            let pendingReadReceipt = PendingReadReceiptRecord(
                threadId: contactThreadId,
                messageTimestamp: Int64(message.timestamp),
                messageUniqueId: message.uniqueId,
                authorPhoneNumber: nil,
                authorUuid: contactAci.serviceIdUppercaseString
            )
            try pendingReadReceipt.insert(transaction.unwrapGrdbWrite.database)
        }

        try XCTUnwrap(databaseStorage.grdbStorage.pool.close())

        let dump = DatabaseRecovery.DumpAndRestore(databaseFileUrl: url)
        try XCTUnwrap(dump.run())

        let finishedDatabaseStorage = SDSDatabaseStorage(
            databaseFileUrl: url,
            delegate: DatabaseTestHelpers.TestSDSDatabaseStorageDelegate()
        )
        finishedDatabaseStorage.read { transaction in
            // Thread
            let thread = TSContactThread.getWithContactAddress(
                SignalServiceAddress(contactAci),
                transaction: transaction
            )
            guard let thread = thread else {
                XCTFail("Contact thread not found in migrated database")
                return
            }

            // Message
            let threadInteractions: [TSInteraction] = {
                var result = [TSInteraction]()
                let finder = InteractionFinder(threadUniqueId: thread.uniqueId)
                try? finder.enumerateRecentInteractions(transaction: transaction) { interaction, _ in
                    result.append(interaction)
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
                return finder.allReactions(transaction: transaction.unwrapGrdbRead)
            }()
            XCTAssertEqual(reactions.count, 1)
            guard let reaction = reactions.first else {
                XCTFail("Could not get the reaction")
                return
            }
            XCTAssertEqual(reaction.emoji, "💽")

            // Pending read receipts (not copied)
            let db = transaction.unwrapGrdbRead.database
            let pendingReadReceipts: [PendingReadReceiptRecord]
            do {
                pendingReadReceipts = try PendingReadReceiptRecord.fetchAll(db)
            } catch {
                XCTFail("\(error)")
                return
            }
            XCTAssert(
                pendingReadReceipts.isEmpty,
                "Unexpectedly found \(pendingReadReceipts.count) pending read receipt(s)"
            )
        }
    }

    func testDumpAndRestoreWithInvalidEssentialTable() throws {
        let (databaseStorage, url) = database()
        try GRDBSchemaMigrator.migrateDatabase(databaseStorage: databaseStorage, isMainDatabase: false)
        databaseStorage.write { transaction in
            try! transaction.unwrapGrdbWrite.database.drop(table: SDSKeyValueStore.tableName)
        }
        try XCTUnwrap(databaseStorage.grdbStorage.pool.close())

        let dump = DatabaseRecovery.DumpAndRestore(databaseFileUrl: url)
        XCTAssertThrowsError(try dump.run()) { error in
            XCTAssertEqual(
                error as? DatabaseRecoveryError,
                DatabaseRecoveryError.unrecoverablyCorrupted
            )
        }
    }

    func testDumpAndRestoreWithInvalidNonessentialTable() throws {
        let (databaseStorage, url) = database()
        try GRDBSchemaMigrator.migrateDatabase(databaseStorage: databaseStorage, isMainDatabase: false)
        databaseStorage.write { transaction in
            try! transaction.unwrapGrdbWrite.database.drop(table: OWSReaction.databaseTableName)
        }
        try XCTUnwrap(databaseStorage.grdbStorage.pool.close())

        let dump = DatabaseRecovery.DumpAndRestore(databaseFileUrl: url)
        try XCTUnwrap(dump.run())

        let finishedDatabaseStorage = SDSDatabaseStorage(
            databaseFileUrl: url,
            delegate: DatabaseTestHelpers.TestSDSDatabaseStorageDelegate()
        )
        finishedDatabaseStorage.read { transaction in
            let sql = "SELECT EXISTS (SELECT 1 FROM \(OWSReaction.databaseTableName))"
            let database = transaction.unwrapGrdbRead.database
            guard let anyRowExists = try? XCTUnwrap(Bool.fetchOne(database, sql: sql)) else {
                XCTFail("Could not fetch boolean from test query")
                return
            }
            XCTAssertFalse(anyRowExists, "Unexpectedly found a reaction")
        }
    }

    // MARK: - Manual restoration

    func testFullTextSearchRestoration() throws {
        let (databaseStorage, url) = database()
        try GRDBSchemaMigrator.migrateDatabase(databaseStorage: databaseStorage, isMainDatabase: false)

        databaseStorage.write { transaction in
            let contactAci = Aci.randomForTesting()

            let contactThread = insertContactThread(
                contactAddress: SignalServiceAddress(contactAci),
                transaction: transaction
            )

            let messageBuilder = TSIncomingMessageBuilder.incomingMessageBuilder(
                thread: contactThread,
                messageBody: "foo bar"
            )
            messageBuilder.timestamp = 1234
            messageBuilder.authorAci = AciObjC(contactAci)
            let message = messageBuilder.build()
            message.anyInsert(transaction: transaction)
        }

        try XCTUnwrap(databaseStorage.grdbStorage.pool.close())

        let dump = DatabaseRecovery.DumpAndRestore(databaseFileUrl: url)
        try XCTUnwrap(dump.run())

        let finishedDatabaseStorage = SDSDatabaseStorage(
            databaseFileUrl: url,
            delegate: DatabaseTestHelpers.TestSDSDatabaseStorageDelegate()
        )

        let manualRecreation = DatabaseRecovery.ManualRecreation(databaseStorage: finishedDatabaseStorage)
        manualRecreation.run()

        finishedDatabaseStorage.read { transaction in
            func searchMessages(for searchText: String) -> [TSMessage] {
                var result = [TSMessage]()
                    FullTextSearchFinder.enumerateObjects(
                    searchText: searchText,
                    collections: [TSMessage.collection()],
                    maxResults: 99,
                    transaction: transaction
                ) { match, _, _ in
                    guard let match = match as? TSMessage else { return }
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

    func database() -> (databaseStorage: SDSDatabaseStorage, url: URL) {
        let url = OWSFileSystem.temporaryFileUrl()
        let databaseStorage = SDSDatabaseStorage(
            databaseFileUrl: url,
            delegate: DatabaseTestHelpers.TestSDSDatabaseStorageDelegate()
        )
        return (databaseStorage: databaseStorage, url: url)
    }

    func allNormalTableNames(transaction: SDSAnyReadTransaction) -> Set<String> {
        let db = transaction.unwrapGrdbRead.database
        let sql = "SELECT name FROM sqlite_schema WHERE type IS 'table'"
        let allTableNames = Set((try? String.fetchAll(db, sql: sql)) ?? [])
        owsAssert(!allTableNames.isEmpty, "No tables were found!")

        let tableNamesToSkip: Set<String> = ["grdb_migrations", "sqlite_sequence"]
        return allTableNames.filter { tableName in
            !tableNamesToSkip.contains(tableName) && !tableName.starts(with: "indexable_text")
        }
    }

    static func columnNames(transaction: SDSAnyReadTransaction, tableName: String) throws -> [String] {
        let db = transaction.unwrapGrdbRead.database
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
        transaction: SDSAnyWriteTransaction
    ) -> TSContactThread {
        TSContactThread.getOrCreateThread(
            withContactAddress: contactAddress,
            transaction: transaction
        )
    }
}

// MARK: - Test-only extensions

extension DatabaseRecovery.DumpAndRestore {
    fileprivate static var allTableNames: [String] {
        tablesToCopyWithBestEffort + tablesThatMustBeCopiedFlawlessly + tablesExplicitlySkipped
    }
}
