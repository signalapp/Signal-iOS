//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import LibSignalClient
import XCTest

@testable import SignalServiceKit

class GRDBSchemaMigratorTest: XCTestCase {
    func testSchemaMigrations() throws {
        // TODO: Reuse initializeSampleDatabase when it doesn't need globals.
        let databaseStorage = try SDSDatabaseStorage(
            appReadiness: AppReadinessMock(),
            databaseFileUrl: OWSFileSystem.temporaryFileUrl(),
            keychainStorage: MockKeychainStorage(),
        )
        // Run all schema migrations. This should succeed without globals!
        try GRDBSchemaMigrator.migrateDatabase(
            databaseStorage: databaseStorage,
            runDataMigrations: false,
        )
        try extractSchema(databaseStorage: databaseStorage)
    }

    /// Extracts the current database schema for documentation.
    private func extractSchema(databaseStorage: SDSDatabaseStorage) throws {
        struct SchemaEntry: Encodable {
            var name: String
            var sql: String
        }
        let schemaEntries = try databaseStorage.read { tx in
            let rows = try Row.fetchAll(tx.database, sql: "SELECT * FROM sqlite_master")
            return rows.compactMap { row -> SchemaEntry? in
                let name: String = row["name"]
                let sql: String? = row["sql"]
                guard let sql else {
                    return nil
                }
                return SchemaEntry(name: name, sql: sql)
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let encodedSchema = try encoder.encode(schemaEntries)
        let schemaDumpPath = ProcessInfo.processInfo.environment["SCHEMA_DUMP_PATH"]
        if let schemaDumpPath {
            try encodedSchema.write(to: URL(fileURLWithPath: schemaDumpPath))
            Logger.verbose("wrote schema to \(schemaDumpPath)")
        }
    }

    private func keyedArchiverData(rootObject: Any) -> Data {
        try! NSKeyedArchiver.archivedData(withRootObject: rootObject, requiringSecureCoding: true)
    }

    private func encodeGroupIdInGroupModel(groupId: Data) -> Data {
        @objc(TSGroupModelWithOnlyGroupId)
        class TSGroupModelWithOnlyGroupId: NSObject, NSSecureCoding {
            static var supportsSecureCoding: Bool { true }
            let groupId: NSData
            init(groupId: Data) { self.groupId = groupId as NSData }
            required init?(coder: NSCoder) { owsFail("Don't decode these!") }
            func encode(with coder: NSCoder) {
                coder.encode(groupId, forKey: "groupId")
            }
        }
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        coder.setClassName("SignalServiceKit.TSGroupModelV2", for: TSGroupModelWithOnlyGroupId.self)
        coder.encode(TSGroupModelWithOnlyGroupId(groupId: groupId), forKey: NSKeyedArchiveRootObjectKey)
        return coder.encodedData
    }

    func testPopulateStoryContextAssociatedData() throws {
        let nowMs = Date().ows_millisecondsSince1970
        let databaseQueue = DatabaseQueue()
        try databaseQueue.write { db in
            try db.execute(sql: """
            CREATE TABLE "thread_associated_data" (hideStory BOOLEAN NOT NULL, threadUniqueId TEXT NOT NULL);
            CREATE TABLE "model_TSThread" (uniqueId TEXT NOT NULL, lastReceivedStoryTimestamp INTEGER, lastViewedStoryTimestamp INTEGER, groupModel BLOB, contactUUID TEXT);

            INSERT INTO "thread_associated_data" (hideStory, threadUniqueId) VALUES (TRUE, 'A'), (FALSE, 'B');
            """)
            try db.execute(
                sql: """
                INSERT INTO "model_TSThread" (uniqueId, lastReceivedStoryTimestamp, lastViewedStoryTimestamp, contactUUID) VALUES (?, ?, ?, ?)
                """,
                arguments: ["A", nowMs - 20_002, nowMs - 20_001, "00000000-0000-4000-8000-00000000000A"],
            )
            try db.execute(
                sql: """
                INSERT INTO "model_TSThread" (uniqueId, lastReceivedStoryTimestamp, lastViewedStoryTimestamp, groupModel) VALUES (?, ?, ?, ?)
                """,
                arguments: ["B", nowMs - 86400_002, nowMs - 86400_001, encodeGroupIdInGroupModel(groupId: Data(repeating: 9, count: 32))],
            )
            let tx = DBWriteTransaction(database: db)
            defer { tx.finalizeTransaction() }
            try GRDBSchemaMigrator.createStoryContextAssociatedData(tx: tx)
            try GRDBSchemaMigrator.populateStoryContextAssociatedData(tx: tx)
            try GRDBSchemaMigrator.dropColumnsMigratedToStoryContextAssociatedData(tx: tx)
        }
        let rows = try databaseQueue.read { db in
            return try Row.fetchAll(db, sql: "SELECT * FROM model_StoryContextAssociatedData")
        }
        XCTAssertEqual(rows.count, 2)

        XCTAssertEqual(rows[0]["contactUuid"] as String?, "00000000-0000-4000-8000-00000000000A")
        XCTAssertEqual(rows[0]["groupId"] as Data?, nil)
        XCTAssertEqual(rows[0]["isHidden"] as Bool, true)
        XCTAssertEqual(rows[0]["latestUnexpiredTimestamp"] as UInt64?, nowMs - 20_002)
        XCTAssertEqual(rows[0]["lastReceivedTimestamp"] as UInt64?, nowMs - 20_002)
        XCTAssertEqual(rows[0]["lastViewedTimestamp"] as UInt64?, nowMs - 20_001)

        XCTAssertEqual(rows[1]["contactUuid"] as String?, nil)
        XCTAssertEqual(rows[1]["groupId"] as Data?, Data(repeating: 9, count: 32))
        XCTAssertEqual(rows[1]["isHidden"] as Bool, false)
        XCTAssertEqual(rows[1]["latestUnexpiredTimestamp"] as UInt64?, nil)
        XCTAssertEqual(rows[1]["lastReceivedTimestamp"] as UInt64?, nowMs - 86400_002)
        XCTAssertEqual(rows[1]["lastViewedTimestamp"] as UInt64?, nowMs - 86400_001)
    }

    func testPopulateStoryMessageReplyCount() throws {
        let databaseQueue = DatabaseQueue()
        try databaseQueue.write { db in
            try db.execute(sql: """
            CREATE TABLE "model_TSInteraction" (
                storyTimestamp INTEGER,
                storyAuthorUuidString TEXT,
                isGroupStoryReply BOOLEAN
            );
            CREATE TABLE "model_StoryMessage" (
                id INTEGER PRIMARY KEY,
                timestamp INTEGER NOT NULL,
                authorUuid TEXT NOT NULL,
                groupId BLOB,
                replyCount INTEGER NOT NULL DEFAULT 0
            );
            INSERT INTO "model_TSInteraction" (storyTimestamp, storyAuthorUuidString, isGroupStoryReply) VALUES (1234, '00000000-0000-4000-8000-00000000000A', TRUE);
            INSERT INTO "model_StoryMessage" (timestamp, authorUuid, groupId) VALUES (1234, '00000000-0000-4000-8000-00000000000A', X'00000000000000000000000000001234');
            """)
            let tx = DBWriteTransaction(database: db)
            defer { tx.finalizeTransaction() }
            try GRDBSchemaMigrator.populateStoryMessageReplyCount(tx: tx)
        }
        let replyCount = try databaseQueue.read { db in
            return try Int.fetchOne(db, sql: "SELECT replyCount FROM model_StoryMessage")
        }
        XCTAssertEqual(replyCount, 1)
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
            ("UnrelatedCollection", "SomeKey", Data(count: 3)),
        ]

        // Set up the database with sample data that may have existed.
        let databaseQueue = DatabaseQueue()
        try databaseQueue.write { db in
            // A snapshot of the key value store as it existed when this migration was
            // added. If the key value store's schema is updated in the future, don't
            // update this call site. It must remain as a snapshot.
            try db.execute(
                sql: "CREATE TABLE keyvalue (key TEXT NOT NULL, collection TEXT NOT NULL, value BLOB NOT NULL, PRIMARY KEY (key, collection))",
            )
            for (collection, key, value) in initialEntries {
                try db.execute(
                    sql: "INSERT INTO keyvalue (collection, key, value) VALUES (?, ?, ?)",
                    arguments: [collection, key, value],
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
            let transaction = DBWriteTransaction(database: db)
            defer { transaction.finalizeTransaction() }
            try GRDBSchemaMigrator.migrateVoiceMessageDrafts(
                transaction: transaction,
                appSharedDataUrl: baseUrl,
                copyItem: copyItem,
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
            keyedArchiverData(rootObject: migratedFilenames["00000000%2D0000%2D4000%2D8000%2D000000000001"]!),
        )

        XCTAssertEqual(rows[1]["collection"], collection)
        XCTAssertEqual(rows[1]["key"], "abc1+/==")
        XCTAssertEqual(
            rows[1]["value"],
            keyedArchiverData(rootObject: migratedFilenames["abc1%2B%2F%3D%3D"]!),
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
            ("UnrelatedCollection", "00000000-0000-4000-8000-000000000001", #"{"author":{"backingUuid":"00000000-0000-4000-8000-00000000000A","backingPhoneNumber":null},"timestamp":1683201600000}"#),
        ]

        // Set up the database with sample data that may have existed.
        let databaseQueue = DatabaseQueue()
        try databaseQueue.write { db in
            // A snapshot of the key value store as it existed when this migration was
            // added. If the key value store's schema is updated in the future, don't
            // update this call site. It must remain as a snapshot.
            try db.execute(
                sql: "CREATE TABLE keyvalue (key TEXT NOT NULL, collection TEXT NOT NULL, value BLOB NOT NULL, PRIMARY KEY (key, collection))",
            )
            for (collection, key, value) in initialEntries {
                try db.execute(
                    sql: "INSERT INTO keyvalue (collection, key, value) VALUES (?, ?, ?)",
                    arguments: [collection, key, try XCTUnwrap(value.data(using: .utf8))],
                )
            }
        }

        // Run the test.
        try databaseQueue.write { db in
            let transaction = DBWriteTransaction(database: db)
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
            (5, 6, 8),
        ]
        try setupEditRecordMigrationTables(
            databaseQueue: databaseQueue,
            initialRecords: initialValues,
            initialInteractionIds: Array(0...8),
        )

        try databaseQueue.write { db in
            let tx = DBWriteTransaction(database: db)
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
            initialInteractionIds: Array(0...8),
        )

        try databaseQueue.write { db in
            let tx = DBWriteTransaction(database: db)
            defer { tx.finalizeTransaction() }
            try GRDBSchemaMigrator.migrateEditRecordTable(tx: tx)
        }
        let exists = checkTableExists(tableName: tableName, databaseQueue: databaseQueue)
        let tempExists = checkTableExists(tableName: tempTableName, databaseQueue: databaseQueue)

        XCTAssertTrue(exists)
        XCTAssertFalse(tempExists)
    }

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
        initialInteractionIds: [Int64],
    ) throws {
        try databaseQueue.write { db in
            try db.execute(
                sql: """
                    CREATE TABLE model_TSInteraction (
                        id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
                    );
                """,
            )

            for x in initialInteractionIds {
                try db.execute(
                    sql: "INSERT INTO model_TSInteraction (id) VALUES (?)",
                    arguments: [x],
                )
            }

            let tx = DBWriteTransaction(database: db)
            try GRDBSchemaMigrator.createEditRecordTable(tx: tx)
            tx.finalizeTransaction()

            for (id, latest, past) in initialRecords {
                try db.execute(
                    sql: "INSERT INTO EditRecord (id, latestRevisionId, pastRevisionId) VALUES (?, ?, ?)",
                    arguments: [id, latest, past],
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
                phoneNumberColumn: "phoneNumber",
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

    func testRemoveDeadEndGroupThreadIdMappings() throws {
        let collection = "TSGroupThread.uniqueIdMappingStore"
        let databaseQueue = DatabaseQueue()
        try databaseQueue.write { db in
            try db.execute(sql: """
            CREATE TABLE "model_TSThread" (uniqueId TEXT NOT NULL);
            CREATE TABLE "keyvalue" (
                collection TEXT NOT NULL,
                key TEXT NOT NULL,
                value BLOB NOT NULL
            );
            INSERT INTO "model_TSThread" VALUES ('A'), ('B');
            """)
            let uniqueIdMappings: [(Data, String)] = [
                (Data(repeating: 0, count: 16), "A"),
                (Data(repeating: 1, count: 32), "B"),
                (Data(repeating: 2, count: 16), "C"),
                (Data(repeating: 3, count: 32), "C"),
            ]
            for (groupId, uniqueId) in uniqueIdMappings {
                try db.execute(
                    sql: "INSERT INTO keyvalue VALUES (?, ?, ?)",
                    arguments: [collection, groupId.hexadecimalString, keyedArchiverData(rootObject: uniqueId)],
                )
            }
            let tx = DBWriteTransaction(database: db)
            defer { tx.finalizeTransaction() }
            try GRDBSchemaMigrator.removeDeadEndGroupThreadIdMappings(tx: tx)
        }
        let groupIdKeys = try databaseQueue.read { db in
            return try String.fetchAll(db, sql: "SELECT key FROM keyvalue")
        }
        XCTAssertEqual(Set(groupIdKeys), [
            Data(repeating: 0, count: 16).hexadecimalString,
            Data(repeating: 1, count: 32).hexadecimalString,
        ])
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
                "recipientUUID" TEXT UNIQUE,
                "pni" TEXT UNIQUE
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
                arguments: ["kOWSBlockingManager_BlockedPhoneNumbersCollection", "kOWSBlockingManager_BlockedUUIDsKey", blockedAciData],
            )
            try db.execute(
                sql: """
                INSERT INTO "keyvalue" ("collection", "key", "value") VALUES (?, ?, ?)
                """,
                arguments: ["kOWSBlockingManager_BlockedPhoneNumbersCollection", "kOWSBlockingManager_BlockedPhoneNumbersKey", blockedPhoneNumberData],
            )
            try db.execute(
                sql: """
                INSERT INTO "keyvalue" ("collection", "key", "value") VALUES (?, ?, ?)
                """,
                arguments: ["kOWSStorageServiceOperation_IdentifierMap", "state", #"{"accountIdChangeMap":{"00000000-0000-4000-B000-000000000009": 0, "00000000-0000-4000-B000-000000000123": 0}}"#],
            )

            do {
                let tx = DBWriteTransaction(database: db)
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
                let tx = DBWriteTransaction(database: db)
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

    func testMigrateBlockedGroups() throws {
        @objc(TSGroupModelMigrateBlockedGroups)
        class TSGroupModelMigrateBlockedGroups: NSObject, NSSecureCoding {
            class var supportsSecureCoding: Bool { true }
            override init() {}
            required init?(coder: NSCoder) {}
            func encode(with coder: NSCoder) {}
        }
        @objc(TSGroupModelV2MigrateBlockedGroups)
        class TSGroupModelV2MigrateBlockedGroups: TSGroupModelMigrateBlockedGroups {
            override class var supportsSecureCoding: Bool { true }
            override init() { super.init() }
            required init?(coder: NSCoder) { super.init(coder: coder) }
        }

        let blockedGroups = [
            Data(count: 16): TSGroupModelMigrateBlockedGroups(),
            Data(count: 32): TSGroupModelV2MigrateBlockedGroups(),
        ]

        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        coder.setClassName("TSGroupModel", for: TSGroupModelMigrateBlockedGroups.self)
        coder.setClassName("SignalServiceKit.TSGroupModelV2", for: TSGroupModelV2MigrateBlockedGroups.self)
        coder.encode(blockedGroups, forKey: NSKeyedArchiveRootObjectKey)

        let groupIds = Set(try GRDBSchemaMigrator.decodeBlockedGroupIds(dataValue: coder.encodedData))
        XCTAssertEqual(groupIds, [Data(count: 16), Data(count: 32)])
    }

    func testPopulateDefaultAvatarColorsTable() throws {
        let groupId = Data(repeating: 9, count: 32)
        let databaseQueue = DatabaseQueue()
        try databaseQueue.write { db in
            try db.execute(sql: """
            CREATE TABLE "model_TSThread"(
                "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
                ,"uniqueId" TEXT NOT NULL UNIQUE ON CONFLICT FAIL
                ,"groupModel" BLOB
            );
            INSERT INTO model_TSThread VALUES
                (1, 'g\(groupId.base64EncodedString())', X'\(encodeGroupIdInGroupModel(groupId: groupId).hexadecimalString)');

            CREATE TABLE model_SignalRecipient(
                "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
                ,"recipientPhoneNumber" TEXT
                ,"recipientUUID" TEXT
                ,"pni" TEXT
            );
            INSERT INTO model_SignalRecipient VALUES
                (1, '+12135550124', NULL, NULL),
                (2, NULL, 'A025BF78-653E-44E0-BEB9-DEB14BA32487', NULL),
                (3, NULL, '+12135550199', 'PNI:11A175E3-FE31-4EDA-87DA-E0BF2A2E250B');
            """)

            do {
                let tx = DBWriteTransaction(database: db)
                defer { tx.finalizeTransaction() }
                try GRDBSchemaMigrator.createDefaultAvatarColorTable(tx: tx)
                try GRDBSchemaMigrator.populateDefaultAvatarColorTable(tx: tx)
            }

            let rows = try Row.fetchAll(db, sql: "SELECT * FROM AvatarDefaultColor")
            XCTAssertEqual(rows.count, 4)
            XCTAssertEqual(rows.filter { $0["groupId"] != nil }.count, 1)
            XCTAssertEqual(rows.filter { $0["recipientRowId"] != nil }.count, 3)
        }
    }

    @objc(SampleSignalServiceAddress)
    private class SampleSignalServiceAddress: NSObject, NSSecureCoding {
        let serviceId: ServiceId?
        let phoneNumber: String?

        init(serviceId: ServiceId?, phoneNumber: String?) {
            self.serviceId = serviceId
            self.phoneNumber = phoneNumber
        }

        class var supportsSecureCoding: Bool { true }

        required init?(coder: NSCoder) { fatalError() }

        func encode(with coder: NSCoder) {
            if let aci = serviceId as? Aci {
                coder.encode(aci.rawUUID, forKey: "backingUuid")
            } else {
                coder.encode(serviceId?.serviceIdBinary, forKey: "backingUuid")
            }
            coder.encode(self.phoneNumber, forKey: "backingPhoneNumber")
        }
    }

    private static func encodedAddresses(_ addresses: [SampleSignalServiceAddress]) throws -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        coder.setClassName("SignalServiceKit.SignalServiceAddress", for: SampleSignalServiceAddress.self)
        coder.encode(addresses, forKey: NSKeyedArchiveRootObjectKey)
        return coder.encodedData
    }

    func testDecodeSignalServiceAddresses() throws {
        let exampleAddresses: [SampleSignalServiceAddress] = [
            .init(serviceId: Aci.parseFrom(aciString: "00000000-0000-4000-8000-000000000000")!, phoneNumber: nil),
            .init(serviceId: Pni.parseFrom(pniString: "00000000-0000-4000-8000-000000000000")!, phoneNumber: nil),
            .init(serviceId: nil, phoneNumber: "+16505550100"),
        ]

        let encodedAddresses = try Self.encodedAddresses(exampleAddresses)
        let decodedAddresses = try GRDBSchemaMigrator.decodeSignalServiceAddresses(dataValue: encodedAddresses)
        XCTAssertEqual(decodedAddresses.map(\.serviceId), exampleAddresses.map(\.serviceId))
        XCTAssertEqual(decodedAddresses.map(\.phoneNumber), exampleAddresses.map(\.phoneNumber))
    }

    func testCreateStoryRecipients() throws {
        // Set up the database with sample data that may have existed.
        let databaseQueue = DatabaseQueue()
        try databaseQueue.write { db in
            try db.execute(sql: """
            CREATE TABLE "model_SignalRecipient" (
                "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                "recordType" INTEGER NOT NULL,
                "uniqueId" TEXT NOT NULL,
                "recipientPhoneNumber" TEXT UNIQUE,
                "recipientUUID" TEXT UNIQUE,
                "pni" TEXT UNIQUE,
                "devices" BLOB
            );

            CREATE TABLE "model_TSThread" (
                id INTEGER PRIMARY KEY,
                recordType INTEGER NOT NULL,
                addresses BLOB
            );

            INSERT INTO "model_SignalRecipient" (
                "recordType", "uniqueId", "recipientPhoneNumber", "recipientUUID", "pni"
            ) VALUES
                (0, '', '+17635550100', '00000000-0000-4000-A000-000000000000', NULL),
                (0, '', '+17635550101', NULL, NULL),
                (0, '', NULL, NULL, 'PNI:00000000-0000-4000-A000-000000000FFF');

            INSERT INTO "model_TSThread" (
                "id", "recordType", "addresses"
            ) VALUES
                (1, 73, X'');
            """)
            try db.execute(
                sql: "INSERT INTO model_TSThread (id, recordType, addresses) VALUES (2, 72, ?)",
                arguments: [Self.encodedAddresses([])],
            )
            try db.execute(
                sql: "INSERT INTO model_TSThread (id, recordType, addresses) VALUES (3, 72, ?)",
                arguments: [Self.encodedAddresses([.init(serviceId: Aci.parseFrom(aciString: "00000000-0000-4000-A000-000000000000")!, phoneNumber: nil)])],
            )
            try db.execute(
                sql: "INSERT INTO model_TSThread (id, recordType, addresses) VALUES (4, 72, ?)",
                arguments: [Self.encodedAddresses([
                    .init(serviceId: Aci.parseFrom(aciString: "00000000-0000-4000-A000-000000000AAA")!, phoneNumber: nil),
                    .init(serviceId: Aci.parseFrom(aciString: "00000000-0000-4000-A000-000000000AAA")!, phoneNumber: nil),
                    .init(serviceId: Pni.parseFrom(pniString: "00000000-0000-4000-A000-000000000BBB")!, phoneNumber: nil),
                    .init(serviceId: Pni.parseFrom(pniString: "00000000-0000-4000-A000-000000000FFF")!, phoneNumber: nil),
                    .init(serviceId: nil, phoneNumber: "+17635550100"),
                    .init(serviceId: nil, phoneNumber: "+17635550142"),
                ])],
            )
            do {
                let tx = DBWriteTransaction(database: db)
                defer { tx.finalizeTransaction() }
                try GRDBSchemaMigrator.createStoryRecipients(tx: tx)
            }

            let storyRecipients = try Row.fetchAll(
                db,
                sql: "SELECT threadId, recipientId FROM StoryRecipient ORDER BY threadId, recipientId",
            ).map { [$0[0] as Int64, $0[1] as Int64] }
            XCTAssertEqual(storyRecipients, [[3, 1], [4, 1], [4, 3], [4, 4], [4, 5], [4, 6]])

            let storyAddresses = try (Data?).fetchAll(
                db,
                sql: "SELECT addresses FROM model_TSThread ORDER BY id",
            )
            XCTAssertEqual(storyAddresses, [Data(), nil, nil, nil])

            let signalRecipients = try Row.fetchAll(
                db,
                sql: "SELECT * FROM model_SignalRecipient ORDER BY id",
            )
            XCTAssertEqual(signalRecipients.count, 6)
            XCTAssertEqual(signalRecipients[3]["recipientUUID"], "00000000-0000-4000-A000-000000000AAA")
            XCTAssertEqual(signalRecipients[3]["recipientPhoneNumber"], nil as String?)
            XCTAssertEqual(signalRecipients[3]["pni"], nil as String?)

            XCTAssertEqual(signalRecipients[4]["recipientUUID"], nil as String?)
            XCTAssertEqual(signalRecipients[4]["recipientPhoneNumber"], nil as String?)
            XCTAssertEqual(signalRecipients[4]["pni"], "PNI:00000000-0000-4000-A000-000000000BBB")

            XCTAssertEqual(signalRecipients[5]["recipientUUID"], nil as String?)
            XCTAssertEqual(signalRecipients[5]["recipientPhoneNumber"], "+17635550142")
            XCTAssertEqual(signalRecipients[5]["pni"], nil as String?)
        }
    }

    private static func encodedDeviceIds(_ deviceIds: [UInt32]) throws -> Data {
        let deviceIdSet = NSOrderedSet(array: deviceIds.map(NSNumber.init(value:)))
        return try NSKeyedArchiver.archivedData(withRootObject: deviceIdSet, requiringSecureCoding: true)
    }

    func testMigrateRecipientDevices() throws {
        // Set up the database with sample data that may have existed.
        let databaseQueue = DatabaseQueue()
        try databaseQueue.write { db in
            try db.execute(sql: """
            CREATE TABLE "model_SignalRecipient" (
                "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                "devices" BLOB
            );
            """)
            let sampleData: [[UInt32]] = [
                [],
                [1],
                [1, 2, 3],
            ]
            for deviceIds in sampleData {
                try db.execute(sql: "INSERT INTO model_SignalRecipient (devices) VALUES (?)", arguments: [Self.encodedDeviceIds(deviceIds)])
            }
            do {
                let tx = DBWriteTransaction(database: db)
                defer { tx.finalizeTransaction() }
                try GRDBSchemaMigrator.migrateRecipientDeviceIds(tx: tx)
            }
            let signalRecipients = try Row.fetchAll(
                db,
                sql: "SELECT * FROM model_SignalRecipient ORDER BY id",
            )
            XCTAssertEqual(signalRecipients.count, 3)
            XCTAssertEqual([UInt8](signalRecipients[0]["devices"] as Data), [])
            XCTAssertEqual([UInt8](signalRecipients[1]["devices"] as Data), [1])
            XCTAssertEqual([UInt8](signalRecipients[2]["devices"] as Data), [1, 2, 3])
        }
    }

    func testMigratePreKeys() throws {
        let now = Date()
        let databaseQueue = DatabaseQueue()
        try databaseQueue.write { db in
            try db.execute(sql: """
            CREATE TABLE keyvalue (collection TEXT NOT NULL, key TEXT NOT NULL, value BLOB NOT NULL);
            """)

            let preKey = SignalServiceKit.PreKeyRecord(
                id: 123,
                keyPair: .generateKeyPair(),
                createdAt: now - 1,
                replacedAt: now,
            )
            let signedKeyPair = ECKeyPair.generateKeyPair()
            let signedPreKey = SignalServiceKit.SignedPreKeyRecord(
                id: 234,
                keyPair: signedKeyPair,
                signature: PrivateKey.generate().generateSignature(message: signedKeyPair.keyPair.publicKey.serialize()),
                generatedAt: now - 1,
                replacedAt: now,
            )
            let kyberKeyPair = KEMKeyPair.generate()
            let kyberPreKeyRecord = try LibSignalClient.KyberPreKeyRecord(
                id: 345,
                timestamp: (now - 1).ows_millisecondsSince1970,
                keyPair: kyberKeyPair,
                signature: PrivateKey.generate().generateSignature(message: kyberKeyPair.publicKey.serialize()),
            )
            let kyberPreKey = SignalServiceKit.KyberPreKeyRecord(
                replacedAt: now,
                libSignalRecord: kyberPreKeyRecord,
                isLastResort: false,
            )

            try db.execute(
                sql: "INSERT INTO keyvalue (collection, key, value) VALUES (?, ?, ?)",
                arguments: ["TSStorageManagerPreKeyStoreCollection", "123", keyedArchiverData(rootObject: preKey)],
            )
            try db.execute(
                sql: "INSERT INTO keyvalue (collection, key, value) VALUES (?, ?, ?)",
                arguments: ["TSStorageManagerPNISignedPreKeyStoreCollection", "234", keyedArchiverData(rootObject: signedPreKey)],
            )
            try db.execute(
                sql: "INSERT INTO keyvalue (collection, key, value) VALUES (?, ?, ?)",
                arguments: ["SSKKyberPreKeyStoreACIKeyStore", "345", try JSONEncoder().encode(kyberPreKey)],
            )

            do {
                let tx = DBWriteTransaction(database: db)
                defer { tx.finalizeTransaction() }
                try GRDBSchemaMigrator.createPreKey(tx: tx)
                try GRDBSchemaMigrator.migratePreKeys(tx: tx)
                try GRDBSchemaMigrator.dropOldPreKeys(tx: tx)
            }

            let preKeys = try Row.fetchAll(db, sql: "SELECT * FROM PreKey")

            XCTAssertEqual(preKeys.count, 3)

            XCTAssertEqual(preKeys[0]["identity"] as Int64, 0)
            XCTAssertEqual(preKeys[0]["namespace"] as Int64, 0)
            XCTAssertEqual(preKeys[0]["keyId"] as UInt32, 123)
            XCTAssertEqual(preKeys[0]["isOneTime"] as Bool, true)
            XCTAssertEqual(preKeys[0]["replacedAt"] as Int64?, Int64(now.timeIntervalSince1970))
            XCTAssertNotNil(preKeys[0]["serializedRecord"] as Data?)

            XCTAssertEqual(preKeys[1]["identity"] as Int64, 1)
            XCTAssertEqual(preKeys[1]["namespace"] as Int64, 2)
            XCTAssertEqual(preKeys[1]["keyId"] as UInt32, 234)
            XCTAssertEqual(preKeys[1]["isOneTime"] as Bool, false)
            XCTAssertEqual(preKeys[1]["replacedAt"] as Int64?, Int64(now.timeIntervalSince1970))
            XCTAssertNotNil(preKeys[1]["serializedRecord"] as Data?)

            XCTAssertEqual(preKeys[2]["identity"] as Int64, 0)
            XCTAssertEqual(preKeys[2]["namespace"] as Int64, 1)
            XCTAssertEqual(preKeys[2]["keyId"] as UInt32, 345)
            XCTAssertEqual(preKeys[2]["isOneTime"] as Bool, true)
            XCTAssertEqual(preKeys[2]["replacedAt"] as Int64?, Int64(now.timeIntervalSince1970))
            XCTAssertNotNil(preKeys[2]["serializedRecord"] as Data?)
        }
    }

    func testUniquifyUsernameLookupRecord_CaseSensitive() throws {
        let databaseQueue = DatabaseQueue()
        try databaseQueue.write { db in
            let aci1 = Aci.randomForTesting().rawUUID.data
            let aci2 = Aci.randomForTesting().rawUUID.data
            let aci3 = Aci.randomForTesting().rawUUID.data

            try db.execute(
                sql: """
                CREATE TABLE UsernameLookupRecord (aci BLOB PRIMARY KEY NOT NULL, username TEXT NOT NULL);
                INSERT INTO UsernameLookupRecord VALUES (?, ?), (?, ?), (?, ?);
                """,
                arguments: [aci1, "florp.01", aci2, "blorp.01", aci3, "florp.01"],
            )

            do {
                let tx = DBWriteTransaction(database: db)
                defer { tx.finalizeTransaction() }
                try GRDBSchemaMigrator.uniquifyUsernameLookupRecord(
                    caseInsensitive: false,
                    tx: tx,
                )
            }

            let usernames = try Row.fetchAll(db, sql: "SELECT * FROM UsernameLookupRecord")

            XCTAssertEqual(usernames.count, 2)
            XCTAssertEqual(usernames[0]["aci"], aci2)
            XCTAssertEqual(usernames[0]["username"], "blorp.01")
            XCTAssertEqual(usernames[1]["aci"], aci3)
            XCTAssertEqual(usernames[1]["username"], "florp.01")
        }
    }

    func testUniquifyUsernameLookupRecord_CaseInsensitive() throws {
        let databaseQueue = DatabaseQueue()
        try databaseQueue.write { db in
            let aci1 = Aci.randomForTesting().rawUUID.data
            let aci2 = Aci.randomForTesting().rawUUID.data

            try db.execute(
                sql: """
                CREATE TABLE UsernameLookupRecord (aci BLOB PRIMARY KEY NOT NULL, username TEXT NOT NULL);
                INSERT INTO UsernameLookupRecord VALUES (?, ?), (?, ?);
                """,
                arguments: [aci1, "florp.01", aci2, "FLORP.01"],
            )

            do {
                let tx = DBWriteTransaction(database: db)
                defer { tx.finalizeTransaction() }
                try GRDBSchemaMigrator.uniquifyUsernameLookupRecord(
                    caseInsensitive: true,
                    tx: tx,
                )
            }

            let usernames = try Row.fetchAll(db, sql: "SELECT * FROM UsernameLookupRecord")

            XCTAssertEqual(usernames.count, 1)
            XCTAssertEqual(usernames[0]["aci"], aci2)
            XCTAssertEqual(usernames[0]["username"], "FLORP.01")
        }
    }

    func testFixUpcomingCallLinks() throws {
        let databaseQueue = DatabaseQueue()
        try databaseQueue.write { db in
            try db.execute(
                sql: """
                CREATE TABLE "CallLink" (isUpcoming BOOLEAN, adminPasskey BLOB);
                INSERT INTO "CallLink" VALUES (?, ?), (?, ?), (?, ?), (?, ?), (?, ?), (?, ?);
                """,
                arguments: [
                    true,
                    Data(count: 32),
                    false,
                    Data(count: 32),
                    nil as Bool?,
                    Data(count: 32),
                    true,
                    nil as Data?,
                    false,
                    nil as Data?,
                    nil as Bool?,
                    nil as Data?,
                ],
            )

            do {
                let tx = DBWriteTransaction(database: db)
                defer { tx.finalizeTransaction() }
                try GRDBSchemaMigrator.fixUpcomingCallLinks(tx: tx)
            }

            let callLinks = try Row.fetchAll(db, sql: "SELECT * FROM CallLink")
            XCTAssertEqual(callLinks.count, 6)
            XCTAssertEqual(callLinks[0][0] as Bool?, true)
            XCTAssertEqual(callLinks[1][0] as Bool?, false)
            XCTAssertEqual(callLinks[2][0] as Bool?, nil)
            XCTAssertEqual(callLinks[3][0] as Bool?, false)
            XCTAssertEqual(callLinks[4][0] as Bool?, false)
            XCTAssertEqual(callLinks[5][0] as Bool?, nil)
        }
    }

    func testFixRevokedForRestoredCallLinks() throws {
        let databaseQueue = DatabaseQueue()
        try databaseQueue.write { db in
            try db.execute(
                sql: """
                CREATE TABLE "CallLink" (revoked BOOLEAN, expiration INTEGER);
                INSERT INTO "CallLink" VALUES (?, ?), (?, ?), (?, ?);
                """,
                arguments: [
                    true,
                    0,
                    nil as Bool?,
                    nil as Int?,
                    nil as Bool?,
                    0,
                ],
            )

            do {
                let tx = DBWriteTransaction(database: db)
                defer { tx.finalizeTransaction() }
                try GRDBSchemaMigrator.fixRevokedForRestoredCallLinks(tx: tx)
            }

            let callLinks = try Row.fetchAll(db, sql: "SELECT * FROM CallLink")
            XCTAssertEqual(callLinks.count, 3)
            XCTAssertEqual(callLinks[0][0] as Bool?, true)
            XCTAssertEqual(callLinks[1][0] as Bool?, nil)
            XCTAssertEqual(callLinks[2][0] as Bool?, false)
        }
    }

    func testFixNameForRestoredCallLinks() throws {
        let databaseQueue = DatabaseQueue()
        try databaseQueue.write { db in
            try db.execute(
                sql: """
                CREATE TABLE "CallLink" (name TEXT);
                INSERT INTO "CallLink" VALUES (NULL), (''), ('Something');
                """,
            )

            do {
                let tx = DBWriteTransaction(database: db)
                defer { tx.finalizeTransaction() }
                try GRDBSchemaMigrator.fixNameForRestoredCallLinks(tx: tx)
            }

            let callLinks = try Row.fetchAll(db, sql: "SELECT * FROM CallLink")
            XCTAssertEqual(callLinks.count, 3)
            XCTAssertEqual(callLinks[0][0] as String?, nil)
            XCTAssertEqual(callLinks[1][0] as String?, nil)
            XCTAssertEqual(callLinks[2][0] as String?, "Something")
        }
    }

    private func keyedArchiverSessionData(deviceIds: [Int32]) -> Data {
        let sessionDictionary = Dictionary(uniqueKeysWithValues: deviceIds.map { ($0, Data()) })
        return keyedArchiverData(rootObject: sessionDictionary)
    }

    func testMigrateSessions() throws {
        let databaseQueue = DatabaseQueue()
        try databaseQueue.write { db in
            try db.execute(sql: """
            CREATE TABLE keyvalue (collection TEXT NOT NULL, key TEXT NOT NULL, value BLOB NOT NULL);
            """)

            try db.execute(sql: """
            CREATE TABLE model_SignalRecipient (id INTEGER PRIMARY KEY, uniqueId TEXT NOT NULL);
            """)

            let recipient1UniqueId = UUID().uuidString
            let recipient2UniqueId = UUID().uuidString
            let recipient3UniqueId = UUID().uuidString
            let recipient4UniqueId = UUID().uuidString

            try db.execute(
                sql: "INSERT INTO model_SignalRecipient (id, uniqueId) VALUES (?, ?)",
                arguments: [1, recipient1UniqueId],
            )
            try db.execute(
                sql: "INSERT INTO model_SignalRecipient (id, uniqueId) VALUES (?, ?)",
                arguments: [2, recipient2UniqueId],
            )
            // Don't insert recipient3UniqueKey.
            try db.execute(
                sql: "INSERT INTO model_SignalRecipient (id, uniqueId) VALUES (?, ?)",
                arguments: [4, recipient4UniqueId],
            )

            try db.execute(
                sql: "INSERT INTO keyvalue (collection, key, value) VALUES (?, ?, ?)",
                arguments: ["TSStorageManagerSessionStoreCollection", recipient1UniqueId, keyedArchiverSessionData(deviceIds: [1, 2, 128])],
            )
            try db.execute(
                sql: "INSERT INTO keyvalue (collection, key, value) VALUES (?, ?, ?)",
                arguments: ["TSStorageManagerPNISessionStoreCollection", recipient1UniqueId, keyedArchiverSessionData(deviceIds: [0, 2, 3])],
            )
            try db.execute(
                sql: "INSERT INTO keyvalue (collection, key, value) VALUES (?, ?, ?)",
                arguments: ["TSStorageManagerSessionStoreCollection", recipient2UniqueId, keyedArchiverSessionData(deviceIds: [1])],
            )
            try db.execute(
                sql: "INSERT INTO keyvalue (collection, key, value) VALUES (?, ?, ?)",
                arguments: ["TSStorageManagerSessionStoreCollection", recipient3UniqueId, keyedArchiverSessionData(deviceIds: [1])],
            )

            @objc(FakeLegacySession)
            class FakeLegacySession: NSObject, NSCoding {
                override init() {}
                required init?(coder: NSCoder) { fatalError("should never be deserialized") }
                func encode(with coder: NSCoder) {}
            }
            let legacyArchivedData: Data
            do {
                let sessionDictionary: [Int32: AnyObject] = [1: FakeLegacySession(), 2: Data() as NSData]
                let archiver = NSKeyedArchiver(requiringSecureCoding: false)
                archiver.setClassName("SSKLegacySessionClassThatNoLongerExists", for: FakeLegacySession.self)
                archiver.encode(sessionDictionary, forKey: NSKeyedArchiveRootObjectKey)
                legacyArchivedData = archiver.encodedData
            }
            try db.execute(
                sql: "INSERT INTO keyvalue (collection, key, value) VALUES (?, ?, ?)",
                arguments: ["TSStorageManagerSessionStoreCollection", recipient4UniqueId, legacyArchivedData],
            )

            do {
                let tx = DBWriteTransaction(database: db)
                defer { tx.finalizeTransaction() }
                try GRDBSchemaMigrator.createSession(tx: tx)
                try GRDBSchemaMigrator.migrateSessions(tx: tx)
                try GRDBSchemaMigrator.dropOldSessions(tx: tx)
            }

            let sessions = try Row.fetchAll(db, sql: "SELECT * FROM Session ORDER BY recipientId, localIdentity, deviceId")

            XCTAssertEqual(sessions.count, 6)

            XCTAssertEqual(sessions[0]["recipientId"] as Int64, 1)
            XCTAssertEqual(sessions[0]["localIdentity"] as Int64, 0)
            XCTAssertEqual(sessions[0]["deviceId"] as Int8, 1)
            XCTAssertEqual(sessions[0]["serializedRecord"] as Data?, Data())

            XCTAssertEqual(sessions[1]["recipientId"] as Int64, 1)
            XCTAssertEqual(sessions[1]["localIdentity"] as Int64, 0)
            XCTAssertEqual(sessions[1]["deviceId"] as Int8, 2)
            XCTAssertEqual(sessions[1]["serializedRecord"] as Data?, Data())

            XCTAssertEqual(sessions[2]["recipientId"] as Int64, 1)
            XCTAssertEqual(sessions[2]["localIdentity"] as Int64, 1)
            XCTAssertEqual(sessions[2]["deviceId"] as Int8, 2)
            XCTAssertEqual(sessions[2]["serializedRecord"] as Data?, Data())

            XCTAssertEqual(sessions[3]["recipientId"] as Int64, 1)
            XCTAssertEqual(sessions[3]["localIdentity"] as Int64, 1)
            XCTAssertEqual(sessions[3]["deviceId"] as Int8, 3)
            XCTAssertEqual(sessions[3]["serializedRecord"] as Data?, Data())

            XCTAssertEqual(sessions[4]["recipientId"] as Int64, 2)
            XCTAssertEqual(sessions[4]["localIdentity"] as Int64, 0)
            XCTAssertEqual(sessions[4]["deviceId"] as Int8, 1)
            XCTAssertEqual(sessions[4]["serializedRecord"] as Data?, Data())

            XCTAssertEqual(sessions[5]["recipientId"] as Int64, 4)
            XCTAssertEqual(sessions[5]["localIdentity"] as Int64, 0)
            XCTAssertEqual(sessions[5]["deviceId"] as Int8, 1)
            XCTAssertEqual(sessions[5]["serializedRecord"] as Data?, nil)
        }
    }

    func testMigrateWhitelist() throws {
        let databaseQueue = DatabaseQueue()
        try databaseQueue.write { db in
            try db.execute(sql: """
            CREATE TABLE "model_SignalRecipient" (
                "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                "recordType" INTEGER NOT NULL,
                "uniqueId" TEXT NOT NULL,
                "recipientPhoneNumber" TEXT UNIQUE,
                "recipientUUID" TEXT UNIQUE,
                "pni" TEXT UNIQUE,
                "devices" BLOB NOT NULL
            );

            CREATE TABLE "keyvalue" (
                "collection" TEXT NOT NULL,
                "key" TEXT NOT NULL,
                "value" BLOB NOT NULL
            );

            INSERT INTO "model_SignalRecipient" (
                "id", "recordType", "uniqueId", "recipientPhoneNumber", "recipientUUID", "pni", "devices"
            ) VALUES
                (1, 0, '', '+17635550100', '00000000-0000-4000-A000-000000000000', NULL, X''),
                (2, 0, '', '+17635550101', NULL, NULL, X''),
                (3, 0, '', NULL, NULL, 'PNI:00000000-0000-4000-A000-000000000FFF', X'');

            INSERT INTO "keyvalue" (
                "collection", "key", "value"
            ) VALUES
                ('kOWSProfileManager_UserWhitelistCollection', '+17635550100', X''),
                ('kOWSProfileManager_UserWhitelistCollection', '+17635550102', X''),
                ('kOWSProfileManager_UserUUIDWhitelistCollection', '00000000-0000-4000-A000-000000000000', X''),
                ('kOWSProfileManager_UserUUIDWhitelistCollection', '00000000-0000-4000-A000-000000000001', X''),
                ('kOWSProfileManager_UserUUIDWhitelistCollection', 'PNI:00000000-0000-4000-A000-000000000FFF', X''),
                ('kOWSProfileManager_UserUUIDWhitelistCollection', 'PNI:00000000-0000-4000-A000-000000000FFE', X'');
            """)

            do {
                let tx = DBWriteTransaction(database: db)
                defer { tx.finalizeTransaction() }
                try GRDBSchemaMigrator.addRecipientStatus(tx: tx)
                try GRDBSchemaMigrator.migrateRecipientWhitelist(tx: tx)
            }

            let recipients = try Row.fetchAll(db, sql: "SELECT * FROM model_SignalRecipient ORDER BY id")
            XCTAssertEqual(recipients.count, 6)
            XCTAssertEqual(recipients[0]["status"] as Int64, 1)
            XCTAssertEqual(recipients[1]["status"] as Int64, 0)
            XCTAssertEqual(recipients[2]["status"] as Int64, 1)
            XCTAssertEqual(recipients[3]["status"] as Int64, 1)
            XCTAssertEqual(recipients[4]["status"] as Int64, 1)
            XCTAssertEqual(recipients[5]["status"] as Int64, 1)
        }
    }
}
