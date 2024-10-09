//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import XCTest

@testable import SignalServiceKit

class GRDBSchemaMigratorTest: XCTestCase {
    func testMigrateFromScratch() throws {
        let databaseStorage = try SDSDatabaseStorage(
            appReadiness: AppReadinessMock(),
            databaseFileUrl: OWSFileSystem.temporaryFileUrl(),
            keychainStorage: MockKeychainStorage()
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

    func testMigrateRemovePhoneNumbers() throws {
        // Set up the database with sample data that may have existed.
        let databaseQueue = DatabaseQueue()
        try databaseQueue.write { db in
            try db.execute(sql: """
            CREATE TABLE "model_SignalRecipient" (
                "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                "recipientPhoneNumber" TEXT,
                "recipientUUID" TEXT
            );
            CREATE UNIQUE INDEX "RecipientAciIndex" ON "model_SignalRecipient" ("recipientUUID");
            CREATE UNIQUE INDEX "RecipientPhoneNumberIndex" ON "model_SignalRecipient" ("recipientPhoneNumber");

            INSERT INTO "model_SignalRecipient" (
                "recipientPhoneNumber", "recipientUUID"
            ) VALUES
                ('+17635550100', '00000000-0000-4000-A000-000000000000'),
                ('+17635550101', NULL),
                ('kLocalProfileUniqueId', '00000000-0000-4000-A000-000000000FFF');

            CREATE TABLE "SampleTable" (
                "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                "phoneNumber" TEXT,
                "serviceIdString" TEXT
            );
            CREATE INDEX "ProfileServiceIdIndex" ON "SampleTable" ("serviceIdString");
            CREATE INDEX "ProfilePhoneNumberIndex" ON "SampleTable" ("phoneNumber");

            INSERT INTO "SampleTable" (
                "phoneNumber", "serviceIdString"
            ) VALUES
                (NULL, '00000000-0000-4000-A000-000000000000'),
                (NULL, '00000000-0000-4000-B000-000000000000'),
                ('+17635550100', '00000000-0000-4000-A000-000000000000'),
                ('+17635550100', 'PNI:00000000-0000-4000-A000-000000000000'),
                ('+17635550100', NULL),
                ('+17635550101', NULL),
                ('+17635550102', NULL),
                ('kLocalProfileUniqueId', NULL),
                ('kLocalProfileUniqueId', '00000000-0000-4000-A000-000000000EEE');
            """)
            try GRDBSchemaMigrator.removeLocalProfileSignalRecipient(in: db)
            try GRDBSchemaMigrator.removeRedundantPhoneNumbers(
                in: db,
                tableName: "SampleTable",
                serviceIdColumn: "serviceIdString",
                phoneNumberColumn: "phoneNumber"
            )
            let cursor = try Row.fetchCursor(db, sql: "SELECT * FROM SampleTable")
            var row: Row
            row = try cursor.next()!
            XCTAssertEqual(row[1] as String?, nil)
            XCTAssertEqual(row[2] as String?, "00000000-0000-4000-A000-000000000000")
            row = try cursor.next()!
            XCTAssertEqual(row[1] as String?, nil)
            XCTAssertEqual(row[2] as String?, "00000000-0000-4000-B000-000000000000")
            row = try cursor.next()!
            XCTAssertEqual(row[1] as String?, nil)
            XCTAssertEqual(row[2] as String?, "00000000-0000-4000-A000-000000000000")
            row = try cursor.next()!
            XCTAssertEqual(row[1] as String?, "+17635550100")
            XCTAssertEqual(row[2] as String?, "PNI:00000000-0000-4000-A000-000000000000")
            row = try cursor.next()!
            XCTAssertEqual(row[1] as String?, nil)
            XCTAssertEqual(row[2] as String?, "00000000-0000-4000-A000-000000000000")
            row = try cursor.next()!
            XCTAssertEqual(row[1] as String?, "+17635550101")
            XCTAssertEqual(row[2] as String?, nil)
            row = try cursor.next()!
            XCTAssertEqual(row[1] as String?, "+17635550102")
            XCTAssertEqual(row[2] as String?, nil)
            row = try cursor.next()!
            XCTAssertEqual(row[1] as String?, "kLocalProfileUniqueId")
            XCTAssertEqual(row[2] as String?, nil)
            row = try cursor.next()!
            XCTAssertEqual(row[1] as String?, "kLocalProfileUniqueId")
            XCTAssertEqual(row[2] as String?, nil)
            XCTAssertNil(try cursor.next())
        }
    }

    func testMigrateBlockedRecipients() throws {
        // Set up the database with sample data that may have existed.
        let blockedAciStrings = [
            "00000000-0000-4000-A000-000000000001",
            "00000000-0000-4000-A000-000000000008",
            "",
        ]
        let blockedPhoneNumbers = [
            "+17635550102",
            "+17635550103",
            "+17635550104",
            "+17635550105",
            "+17635550107",
            "+17635550109",
            "",
        ]

        let blockedAciData = keyedArchiverData(rootObject: blockedAciStrings)
        let blockedPhoneNumberData = keyedArchiverData(rootObject: blockedPhoneNumbers)

        let databaseQueue = DatabaseQueue()
        try databaseQueue.write { db in
            try db.execute(sql: """
            CREATE TABLE keyvalue (
                "collection" TEXT NOT NULL,
                "key" TEXT NOT NULL,
                "value" BLOB NOT NULL,
                PRIMARY KEY ("collection", "key")
            );

            CREATE TABLE "model_SignalRecipient" (
                "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                "recordType" INTEGER NOT NULL,
                "uniqueId" TEXT NOT NULL UNIQUE ON CONFLICT FAIL,
                "devices" BLOB NOT NULL,
                "recipientPhoneNumber" TEXT UNIQUE,
                "recipientUUID" TEXT UNIQUE
            );

            INSERT INTO "model_SignalRecipient" (
                "recordType", "uniqueId", "devices", "recipientPhoneNumber", "recipientUUID"
            ) VALUES
                (31, '00000000-0000-4000-B000-00000000000F', X'', '+17635550101', '00000000-0000-4000-A000-000000000001'),
                (31, '00000000-0000-4000-B000-00000000000E', X'', '+17635550102', '00000000-0000-4000-A000-000000000002'),
                (31, '00000000-0000-4000-B000-00000000000D', X'', '+17635550103', '00000000-0000-4000-A000-000000000003'),
                (31, '00000000-0000-4000-B000-00000000000C', X'', '+17635550104', '00000000-0000-4000-A000-000000000004'),
                (31, '00000000-0000-4000-B000-00000000000B', X'', '+17635550105', NULL),
                (31, '00000000-0000-4000-B000-00000000000A', X'', NULL, '00000000-0000-4000-A000-000000000006'),
                (31, '00000000-0000-4000-B000-000000000009', X'', '+17635550107', '00000000-0000-4000-A000-000000000007');

            CREATE TABLE "model_OWSUserProfile" (
                "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                "recipientUUID" TEXT UNIQUE,
                "profileName" TEXT,
                "isPhoneNumberShared" BOOLEAN
            );

            INSERT INTO "model_OWSUserProfile" ("recipientUUID", "profileName", "isPhoneNumberShared") VALUES
                ('00000000-0000-4000-A000-000000000002', NULL, TRUE),
                ('00000000-0000-4000-A000-000000000004', NULL, FALSE),
                ('00000000-0000-4000-A000-000000000007', NULL, FALSE);

            CREATE TABLE "model_SignalAccount" (
                "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                "recipientPhoneNumber" TEXT UNIQUE
            );

            INSERT INTO "model_SignalAccount" ("recipientPhoneNumber") VALUES
                ('+17635550103');
            """)

            try db.execute(
                sql: """
                INSERT INTO "keyvalue" ("collection", "key", "value") VALUES (?, ?, ?)
                """,
                arguments: ["kOWSBlockingManager_BlockedPhoneNumbersCollection", "kOWSBlockingManager_BlockedUUIDsKey", blockedAciData]
            )
            try db.execute(
                sql: """
                INSERT INTO "keyvalue" ("collection", "key", "value") VALUES (?, ?, ?)
                """,
                arguments: ["kOWSBlockingManager_BlockedPhoneNumbersCollection", "kOWSBlockingManager_BlockedPhoneNumbersKey", blockedPhoneNumberData]
            )
            try db.execute(
                sql: """
                INSERT INTO "keyvalue" ("collection", "key", "value") VALUES (?, ?, ?)
                """,
                arguments: ["kOWSStorageServiceOperation_IdentifierMap", "state", #"{"accountIdChangeMap":{"00000000-0000-4000-B000-000000000009": 0, "00000000-0000-4000-B000-000000000123": 0}}"#]
            )

            do {
                let tx = GRDBWriteTransaction(database: db)
                defer { tx.finalizeTransaction() }
                try GRDBSchemaMigrator.migrateBlockedRecipients(tx: tx)
            }

            let blockedRecipientIds = try Int64.fetchAll(db, sql: "SELECT * FROM BlockedRecipient")
            XCTAssertEqual(blockedRecipientIds, [1, 2, 3, 5, 8, 9])

            let encodedState = try Data.fetchOne(db, sql: "SELECT value FROM keyvalue WHERE collection = ? AND key = ?", arguments: ["kOWSStorageServiceOperation_IdentifierMap", "state"])
            let decodedState = try encodedState.map { try JSONDecoder().decode([String: [String: Int]].self, from: $0) } ?? [:]
            XCTAssertEqual(decodedState["accountIdChangeMap"], [
                "00000000-0000-4000-B000-000000000009": 1,
                "00000000-0000-4000-B000-000000000123": 0,
                "00000000-0000-4000-B000-00000000000C": 1,
            ])
        }
    }

    func testMigrateCallRecords() throws {
        let databaseQueue = DatabaseQueue()
        try databaseQueue.write { db in
            try db.execute(sql: """
            CREATE TABLE "model_TSInteraction"("id" INTEGER PRIMARY KEY);
            INSERT INTO "model_TSInteraction" VALUES (2), (3);

            CREATE TABLE "model_TSThread"("id" INTEGER PRIMARY KEY);
            INSERT INTO "model_TSThread" VALUES (4), (5);

            CREATE TABLE IF NOT EXISTS "CallRecord" (
                "id" INTEGER PRIMARY KEY NOT NULL
                ,"callId" TEXT NOT NULL
                ,"interactionRowId" INTEGER NOT NULL UNIQUE REFERENCES "model_TSInteraction"("id") ON DELETE CASCADE
                ,"threadRowId" INTEGER NOT NULL REFERENCES "model_TSThread"("id") ON DELETE RESTRICT
                ,"type" INTEGER NOT NULL
                ,"direction" INTEGER NOT NULL
                ,"status" INTEGER NOT NULL
                ,"timestamp" INTEGER NOT NULL
                ,"groupCallRingerAci" BLOB
                ,"unreadStatus" INTEGER NOT NULL DEFAULT 0
                ,"callEndedTimestamp" INTEGER NOT NULL DEFAULT 0
            );
            INSERT INTO "CallRecord" VALUES
                (1, '18446744073709551615', 2, 4, 1, 1, 1, 1727730000000, NULL, 0, 1727740000000),
                (2, '18446744073709551614', 3, 5, 0, 0, 3, 1727750000000, NULL, 1, 1727760000000);

            CREATE UNIQUE INDEX "index_call_record_on_callId_and_threadId" ON "CallRecord"("callId", "threadRowId");
            CREATE INDEX "index_call_record_on_timestamp" ON "CallRecord"("timestamp");
            CREATE INDEX "index_call_record_on_status_and_timestamp" ON "CallRecord"("status", "timestamp");
            CREATE INDEX "index_call_record_on_threadRowId_and_timestamp" ON "CallRecord"("threadRowId", "timestamp");
            CREATE INDEX "index_call_record_on_threadRowId_and_status_and_timestamp" ON "CallRecord"("threadRowId", "status", "timestamp");
            CREATE INDEX "index_call_record_on_callStatus_and_unreadStatus_and_timestamp" ON "CallRecord"("status", "unreadStatus", "timestamp");
            CREATE INDEX "index_call_record_on_threadRowId_and_callStatus_and_unreadStatus_and_timestamp" ON "CallRecord"("threadRowId", "status", "unreadStatus", "timestamp");

            CREATE TABLE IF NOT EXISTS "DeletedCallRecord" (
                "id" INTEGER PRIMARY KEY NOT NULL
                ,"callId" TEXT NOT NULL
                ,"threadRowId" INTEGER NOT NULL REFERENCES "model_TSThread"("id") ON DELETE RESTRICT
                ,"deletedAtTimestamp" INTEGER NOT NULL
            );
            INSERT INTO "DeletedCallRecord" VALUES
                (1, '18446744073709551613', 4, 1727770000),
                (2, '18446744073709551612', 5, 1727780000);

            CREATE UNIQUE INDEX "index_deleted_call_record_on_threadRowId_and_callId" ON "DeletedCallRecord"("threadRowId", "callId");
            CREATE INDEX "index_deleted_call_record_on_deletedAtTimestamp" ON "DeletedCallRecord"("deletedAtTimestamp");
            """)

            do {
                let tx = GRDBWriteTransaction(database: db)
                defer { tx.finalizeTransaction() }
                try GRDBSchemaMigrator.addCallLinkTable(tx: tx)
            }

            let tableNames = try Row.fetchAll(db, sql: "pragma table_list").map { $0["name"] as String }
            XCTAssert(tableNames.contains("CallLink"))
            XCTAssert(tableNames.contains("CallRecord"))
            XCTAssert(!tableNames.contains("new_CallRecord"))
            XCTAssert(tableNames.contains("DeletedCallRecord"))
            XCTAssert(!tableNames.contains("new_DeletedCallRecord"))

            let callRecords = try Row.fetchAll(db, sql: "SELECT * FROM CallRecord")
            XCTAssertEqual(callRecords[0]["id"], 1)
            XCTAssertEqual(callRecords[0]["callId"], "18446744073709551615")
            XCTAssertEqual(callRecords[1]["id"], 2)
            XCTAssertEqual(callRecords[1]["callId"], "18446744073709551614")

            let deletedCallRecords = try Row.fetchAll(db, sql: "SELECT * FROM DeletedCallRecord")
            XCTAssertEqual(deletedCallRecords[0]["id"], 1)
            XCTAssertEqual(deletedCallRecords[0]["callId"], "18446744073709551613")
            XCTAssertEqual(deletedCallRecords[1]["id"], 2)
            XCTAssertEqual(deletedCallRecords[1]["callId"], "18446744073709551612")
        }
    }
}
