//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
import GRDB
@testable import SignalServiceKit

final class UsernameLookupRecordTest: XCTestCase {
    private func createDatabaseQueue() throws -> DatabaseQueue {
        let result = DatabaseQueue()

        try result.write { db in
            try db.create(table: UsernameLookupRecord.databaseTableName) { table in
                table.column("aci", .blob).primaryKey().notNull()
                table.column("username", .text).notNull()
            }
        }

        return result
    }

    func testRoundTrip() throws {
        let aci = UUID()
        let username = "boba_fett.42"

        let databaseQueue = try createDatabaseQueue()

        try databaseQueue.write { db in
            let record = UsernameLookupRecord(
                aci: aci,
                username: username
            )

            try record.insert(db)
        }

        guard let loadedRecord = try databaseQueue.read({ db in
            UsernameLookupRecord.fetchOne(forAci: aci, database: db)
        }) else {
            XCTFail("Failed to load record!")
            return
        }

        XCTAssertEqual(loadedRecord.aci, aci)
        XCTAssertEqual(loadedRecord.username, username)
    }

    func testUpsert() throws {
        let aci1 = UUID()
        let aci2 = UUID()
        let username1 = "jango_fett.42"
        let username2 = "boba_fett.42"

        let databaseQueue = try createDatabaseQueue()

        try databaseQueue.write { db in
            let recordsToUpsert: [UsernameLookupRecord] = [
                .init(aci: aci1, username: username1),
                .init(aci: aci2, username: username2),
                .init(aci: aci1, username: username2)
            ]

            for record in recordsToUpsert {
                record.upsert(database: db)
            }
        }

        let (record1, record2) = try databaseQueue.read { db in (
            UsernameLookupRecord.fetchOne(forAci: aci1, database: db),
            UsernameLookupRecord.fetchOne(forAci: aci2, database: db)
        )}

        guard let record1, let record2 else {
            XCTFail("Missing records!")
            return
        }

        XCTAssertEqual(record1.aci, aci1)
        XCTAssertEqual(record1.username, username2)

        XCTAssertEqual(record2.aci, aci2)
        XCTAssertEqual(record2.username, username2)
    }
}
