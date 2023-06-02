//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import XCTest

@testable import SignalServiceKit

class GRDBSchemaMigratorTest: XCTestCase {
    func testMigrateFromScratch() throws {
        let databaseStorage = SDSDatabaseStorage(
            databaseFileUrl: OWSFileSystem.temporaryFileUrl(),
            delegate: DatabaseTestHelpers.TestSDSDatabaseStorageDelegate()
        )

        try GRDBSchemaMigrator.migrateDatabase(
            databaseStorage: databaseStorage,
            isMainDatabase: false
        )

        databaseStorage.read { transaction in
            let db = transaction.unwrapGrdbRead.database
            let sql = "SELECT name FROM sqlite_schema WHERE type IS 'table'"
            let allTableNames = (try? String.fetchAll(db, sql: sql)) ?? []

            XCTAssert(allTableNames.contains(TSThread.table.tableName))
        }
    }

    private func keyedArchiverData(rootObject: Any) -> Data {
        try! NSKeyedArchiver.archivedData(withRootObject: rootObject, requiringSecureCoding: true)
    }

    func testMigrateVoiceMessageDrafts() throws {
        let collection = "DraftVoiceMessage"

        let baseUrl = URL(fileURLWithPath: "/not/a/real/path", isDirectory: true)
        let initialEntries: [(String, String, Data)] = [
            (collection, "00000000-0000-4000-8000-000000000001", keyedArchiverData(rootObject: NSNumber(true))),
            (collection, "00000000-0000-4000-8000-000000000002", keyedArchiverData(rootObject: NSNumber(true))),
            (collection, "00000000-0000-4000-8000-000000000003", keyedArchiverData(rootObject: NSNumber(false))),
            (collection, "00000000-0000-4000-8000-000000000004", keyedArchiverData(rootObject: [6, 7, 8, 9, 10])),
            (collection, "abc1+/==", keyedArchiverData(rootObject: NSNumber(true))),
            ("UnrelatedCollection", "SomeKey", Data(count: 3))
        ]

        // Set up the database with sample data that may have existed.
        let databaseQueue = DatabaseQueue()
        try databaseQueue.write { db in
            // A snapshot of the key value store as it existed when this migration was
            // added. If the key value store's schema is updated in the future, don't
            // update this call site. It must remain as a snapshot.
            try db.execute(
                sql: "CREATE TABLE keyvalue (key TEXT NOT NULL, collection TEXT NOT NULL, value BLOB NOT NULL, PRIMARY KEY (key, collection))"
            )
            for (collection, key, value) in initialEntries {
                try db.execute(
                    sql: "INSERT INTO keyvalue (collection, key, value) VALUES (?, ?, ?)",
                    arguments: [collection, key, value]
                )
            }
        }

        // Run the test.
        var copyResults: [Result<Void, Error>] = [.success(()), .failure(CocoaError(.fileNoSuchFile)), .success(())]
        var copyRequests = [(URL, URL)]()
        let copyItem = { (src: URL, dst: URL) throws in
            copyRequests.append((src, dst))
            return try copyResults.removeFirst().get()
        }
        try databaseQueue.write { db in
            let transaction = GRDBWriteTransaction(database: db)
            defer { transaction.finalizeTransaction() }
            try GRDBSchemaMigrator.migrateVoiceMessageDrafts(
                transaction: transaction,
                appSharedDataUrl: baseUrl,
                copyItem: copyItem
            )
        }

        // Validate the ending state.
        let rows = try databaseQueue.read {
            try Row.fetchAll($0, sql: "SELECT collection, key, value FROM keyvalue ORDER BY collection, key")
        }
        let migratedFilenames = Dictionary(uniqueKeysWithValues: copyRequests.map { ($0.0.lastPathComponent, $0.1.lastPathComponent) })

        XCTAssertEqual(rows.count, 3)

        XCTAssertEqual(rows[0]["collection"], collection)
        XCTAssertEqual(rows[0]["key"], "00000000-0000-4000-8000-000000000001")
        XCTAssertEqual(
            rows[0]["value"],
            keyedArchiverData(rootObject: migratedFilenames["00000000%2D0000%2D4000%2D8000%2D000000000001"]!)
        )

        XCTAssertEqual(rows[1]["collection"], collection)
        XCTAssertEqual(rows[1]["key"], "abc1+/==")
        XCTAssertEqual(
            rows[1]["value"],
            keyedArchiverData(rootObject: migratedFilenames["abc1%2B%2F%3D%3D"]!)
        )

        XCTAssertEqual(rows[2]["collection"], "UnrelatedCollection")
        XCTAssertEqual(rows[2]["key"], "SomeKey")
        XCTAssertEqual(rows[2]["value"], Data(count: 3))
    }

    func testMigrateThreadReplyInfos() throws {
        let collection = "TSThreadReplyInfo"

        let initialEntries: [(String, String, String)] = [
            (collection, "00000000-0000-4000-8000-000000000001", #"{"author":{"backingUuid":"00000000-0000-4000-8000-00000000000A","backingPhoneNumber":null},"timestamp":1683201600000}"#),
            (collection, "00000000-0000-4000-8000-000000000002", #"{"author":{"backingUuid":null,"backingPhoneNumber":"+16505550100"},"timestamp":1683201600000}"#),
            (collection, "00000000-0000-4000-8000-000000000003", "ABC123"),
            ("UnrelatedCollection", "00000000-0000-4000-8000-000000000001", #"{"author":{"backingUuid":"00000000-0000-4000-8000-00000000000A","backingPhoneNumber":null},"timestamp":1683201600000}"#)
        ]

        // Set up the database with sample data that may have existed.
        let databaseQueue = DatabaseQueue()
        try databaseQueue.write { db in
            // A snapshot of the key value store as it existed when this migration was
            // added. If the key value store's schema is updated in the future, don't
            // update this call site. It must remain as a snapshot.
            try db.execute(
                sql: "CREATE TABLE keyvalue (key TEXT NOT NULL, collection TEXT NOT NULL, value BLOB NOT NULL, PRIMARY KEY (key, collection))"
            )
            for (collection, key, value) in initialEntries {
                try db.execute(
                    sql: "INSERT INTO keyvalue (collection, key, value) VALUES (?, ?, ?)",
                    arguments: [collection, key, try XCTUnwrap(value.data(using: .utf8))]
                )
            }
        }

        // Run the test.
        try databaseQueue.write { db in
            let transaction = GRDBWriteTransaction(database: db)
            defer { transaction.finalizeTransaction() }
            try GRDBSchemaMigrator.migrateThreadReplyInfos(transaction: transaction)
        }

        // Validate the ending state.
        let rows = try databaseQueue.read {
            try Row.fetchAll($0, sql: "SELECT collection, key, value FROM keyvalue ORDER BY collection, key")
        }

        XCTAssertEqual(rows.count, 3)

        XCTAssertEqual(rows[0]["collection"], collection)
        XCTAssertEqual(rows[0]["key"], "00000000-0000-4000-8000-000000000001")
        XCTAssertEqual(rows[0]["value"], #"{"author":"00000000-0000-4000-8000-00000000000A","timestamp":1683201600000}"#)

        XCTAssertEqual(rows[1]["collection"], collection)
        XCTAssertEqual(rows[1]["key"], "00000000-0000-4000-8000-000000000003")
        XCTAssertEqual(rows[1]["value"], "ABC123")

        XCTAssertEqual(rows[2]["collection"], "UnrelatedCollection")
        XCTAssertEqual(rows[2]["key"], "00000000-0000-4000-8000-000000000001")
        XCTAssertEqual(rows[2]["value"], #"{"author":{"backingUuid":"00000000-0000-4000-8000-00000000000A","backingPhoneNumber":null},"timestamp":1683201600000}"#)
    }

    func testMigrateEditRecords() throws {
        let tableName = EditRecord.databaseTableName
        let tempTableName = "\(EditRecord.databaseTableName)_temp"
        let databaseQueue = DatabaseQueue()
        let initialValues: [(Int64, Int64, Int64)] = [
            (0, 0, 1),
            (1, 0, 2),
            (2, 3, 4),
            (3, 4, 5),
            (4, 6, 7),
            (5, 6, 8)
        ]
        try setupEditRecordMigrationTables(
            databaseQueue: databaseQueue,
            initialRecords: initialValues,
            initialInteractionIds: Array(0...8)
        )

        try databaseQueue.write { db in
            let tx = GRDBWriteTransaction(database: db)
            defer { tx.finalizeTransaction() }
            try GRDBSchemaMigrator.migrateEditRecordTable(tx: tx)
        }
        let exists = checkTableExists(tableName: tableName, databaseQueue: databaseQueue)
        let tempExists = checkTableExists(tableName: tempTableName, databaseQueue: databaseQueue)
        let count = try databaseQueue.read({ db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(tableName)")
        })

        XCTAssertTrue(exists)
        XCTAssertFalse(tempExists)
        XCTAssertEqual(count, initialValues.count)
    }

    func testMigrateEditRecordsEmptyExisting() throws {
        let tableName = EditRecord.databaseTableName
        let tempTableName = "\(EditRecord.databaseTableName)_temp"
        let databaseQueue = DatabaseQueue()
        try setupEditRecordMigrationTables(
            databaseQueue: databaseQueue,
            initialRecords: [],
            initialInteractionIds: Array(0...8)
        )

        try databaseQueue.write { db in
            let tx = GRDBWriteTransaction(database: db)
            defer { tx.finalizeTransaction() }
            try GRDBSchemaMigrator.migrateEditRecordTable(tx: tx)
        }
        let exists = checkTableExists(tableName: tableName, databaseQueue: databaseQueue)
        let tempExists = checkTableExists(tableName: tempTableName, databaseQueue: databaseQueue)

        XCTAssertTrue(exists)
        XCTAssertFalse(tempExists)
    }
}

extension GRDBSchemaMigratorTest {
    fileprivate func checkTableExists(tableName: String, databaseQueue: DatabaseQueue) -> Bool {
        do {
            try databaseQueue.read({ db in
                try db.execute(sql: "SELECT EXISTS (SELECT 1 FROM \(tableName));")
            })
            return true
        } catch {
            return false
        }

    }

    fileprivate func setupEditRecordMigrationTables(
        databaseQueue: DatabaseQueue,
        initialRecords: [(Int64, Int64, Int64)],
        initialInteractionIds: [Int64]
    ) throws {
        try databaseQueue.write { db in
            try db.execute(
                sql: """
                    CREATE TABLE model_TSInteraction (
                        id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
                    );
                """
            )

            for x in initialInteractionIds {
                try db.execute(
                    sql: "INSERT INTO model_TSInteraction (id) VALUES (?)",
                    arguments: [x]
                )
            }

            let tx = GRDBWriteTransaction(database: db)
            try GRDBSchemaMigrator.createEditRecordTable(tx: tx)
            tx.finalizeTransaction()

            for (id, latest, past) in initialRecords {
                try db.execute(
                    sql: "INSERT INTO EditRecord (id, latestRevisionId, pastRevisionId) VALUES (?, ?, ?)",
                    arguments: [id, latest, past]
                )
            }
        }
    }
}
