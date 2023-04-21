//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
import GRDB
import SignalServiceKit

final class SqliteUtilTest: XCTestCase {
    func testIsSafe() {
        let unsafeNames: [String] = [
            "",
            " table",
            "1table",
            "_table",
            "'table'",
            "táble",
            "sqlite",
            "sqlite_master",
            "SQLITE_master",
            String(repeating: "x", count: 2000)
        ]
        for unsafeName in unsafeNames {
            XCTAssertFalse(SqliteUtil.isSafe(sqlName: unsafeName))
        }

        let safeNames: [String] = ["table", "table_name", "table1"]
        for safeName in safeNames {
            XCTAssertTrue(SqliteUtil.isSafe(sqlName: safeName))
        }
    }

    func testBarrierFsync() throws {
        let databasePath = OWSFileSystem.temporaryFilePath(fileExtension: "sqlite")

        let databaseQueue = try DatabaseQueue(path: databasePath)
        defer { try? databaseQueue.close() }

        try databaseQueue.write { db in
            XCTAssertFalse(SqliteUtil.isUsingBarrierFsync(db: db))

            try SqliteUtil.setBarrierFsync(db: db, enabled: true)
            XCTAssertTrue(SqliteUtil.isUsingBarrierFsync(db: db))

            try SqliteUtil.setBarrierFsync(db: db, enabled: false)
            XCTAssertFalse(SqliteUtil.isUsingBarrierFsync(db: db))
        }
    }

    func testIntegrityCheckResult() {
        let ok = SqliteUtil.IntegrityCheckResult.ok
        let notOk = SqliteUtil.IntegrityCheckResult.notOk

        XCTAssertEqual(ok && ok, .ok)
        XCTAssertEqual(ok && notOk, .notOk)
        XCTAssertEqual(notOk && ok, .notOk)
        XCTAssertEqual(notOk && notOk, .notOk)
    }

    func testCipherProvider() throws {
        let databasePath = OWSFileSystem.temporaryFilePath(fileExtension: "sqlite")

        let databaseQueue = try DatabaseQueue(path: databasePath)
        defer { try? databaseQueue.close() }

        try databaseQueue.write { db in
            try db.usePassphrase("test key")
        }

        let result = try databaseQueue.read { SqliteUtil.cipherProvider(db: $0) }
        XCTAssertFalse(result.isEmpty, "PRAGMA cipher_provider should return something")
    }

    func testCipherIntegrityCheck() throws {
        let databasePath = OWSFileSystem.temporaryFilePath(fileExtension: "sqlite")

        let databaseQueue = try DatabaseQueue(path: databasePath)
        defer { try? databaseQueue.close() }

        let result = try databaseQueue.read { SqliteUtil.cipherIntegrityCheck(db: $0) }
        XCTAssertEqual(result, .ok)
    }

    func testQuickCheck() throws {
        guard #available(iOS 16, *) else { throw XCTSkip() }

        let databasePath = OWSFileSystem.temporaryFilePath(fileExtension: "sqlite")
        let databaseUrl = URL(filePath: databasePath)

        let happyResult: SqliteUtil.IntegrityCheckResult = try {
            let databaseQueue = try DatabaseQueue(path: databasePath)
            defer { try? databaseQueue.close() }

            try databaseQueue.write { db in
                try db.create(table: "colors") { $0.column("name", .text).notNull() }
            }
            return try databaseQueue.read { SqliteUtil.quickCheck(db: $0) }
        }()
        XCTAssertEqual(happyResult, .ok)

        let unhappyResult: SqliteUtil.IntegrityCheckResult = try {
            let databaseQueue = try DatabaseQueue(path: databasePath)
            defer { try? databaseQueue.close() }

            try Data([1, 2, 3]).write(to: databaseUrl)

            return try databaseQueue.read { SqliteUtil.quickCheck(db: $0) }
        }()
        XCTAssertEqual(unhappyResult, .notOk)
    }

    // MARK: - FTS tests

    func testFtsIntegrityCheckNoExternalContent() throws {
        let databaseQueue = DatabaseQueue()

        try databaseQueue.write { db in
            try db.execute(sql: "CREATE VIRTUAL TABLE fts USING fts5 (content)")

            let result = try SqliteUtil.Fts5.integrityCheck(
                db: db,
                ftsTableName: "fts",
                compareToExternalContentTable: false
            )

            XCTAssertEqual(result, .ok)
        }
    }

    func testFtsIntegrityCheckWithExternalContent() throws {
        try DatabaseQueue().write { db in
            try db.execute(sql: "CREATE TABLE people (name TEXT NOT NULL)")
            try db.execute(sql: "CREATE VIRTUAL TABLE fts USING fts5 (name, content='people')")
            try db.execute(sql: "INSERT INTO people (name) VALUES ('Alice')")
            try db.execute(sql: "INSERT INTO fts (name) VALUES ('Alice')")

            let resultBeforeCorruption = try SqliteUtil.Fts5.integrityCheck(
                db: db,
                ftsTableName: "fts",
                compareToExternalContentTable: true
            )
            XCTAssertEqual(resultBeforeCorruption, .ok)

            // This should corrupt the FTS table because the content table is now out of sync.
            try db.execute(sql: "DELETE FROM people")

            let resultAfterCorruption = try SqliteUtil.Fts5.integrityCheck(
                db: db,
                ftsTableName: "fts",
                compareToExternalContentTable: true
            )
            XCTAssertEqual(resultAfterCorruption, .corrupted)
        }
    }

    func testFtsRebuild() throws {
        try DatabaseQueue().write { db in
            try db.execute(sql: "CREATE TABLE people (name TEXT NOT NULL)")
            try db.execute(sql: "CREATE VIRTUAL TABLE fts USING fts5 (name, content='people')")
            try db.execute(sql: "INSERT INTO people (name) VALUES ('Alice')")

            try SqliteUtil.Fts5.rebuild(db: db, ftsTableName: "fts")

            XCTAssertEqual(
                try! Int.fetchOne(db, sql: "SELECT COUNT(*) FROM fts('Alice')"),
                1
            )
        }
    }
}
