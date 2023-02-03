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
