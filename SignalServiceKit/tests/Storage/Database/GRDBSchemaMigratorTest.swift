//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
import SignalServiceKit

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
}
