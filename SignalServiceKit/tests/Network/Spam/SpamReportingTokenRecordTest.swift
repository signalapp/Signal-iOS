//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
import GRDB
import SignalServiceKit

final class SpamReportingTokenRecordTest: XCTestCase {
    private func createDatabaseQueue() throws -> DatabaseQueue {
        let result = DatabaseQueue()

        try result.write { db in
            try db.create(table: SpamReportingTokenRecord.databaseTableName) { table in
                table.column("sourceUuid", .blob).primaryKey().notNull()
                table.column("spamReportingToken", .blob).notNull()
            }
        }

        return result
    }

    func testRoundTrip() throws {
        let sourceUuid = UUID()
        let spamReportingToken = SpamReportingToken(data: .init([1, 2, 3]))!

        let databaseQueue = try createDatabaseQueue()

        try databaseQueue.write { db in
            let record = SpamReportingTokenRecord(
                sourceUuid: sourceUuid,
                spamReportingToken: spamReportingToken
            )
            try record.insert(db)
        }

        let loadedRecord = try databaseQueue.read { db in
            try SpamReportingTokenRecord.fetchOne(db, key: sourceUuid)!
        }
        XCTAssertEqual(loadedRecord.sourceUuid, sourceUuid)
        XCTAssertEqual(loadedRecord.spamReportingToken, spamReportingToken)
    }

    func testUpsert() throws {
        let sourceUuid1 = UUID()
        let sourceUuid2 = UUID()
        let spamReportingToken1 = SpamReportingToken(data: .init([1]))!
        let spamReportingToken2 = SpamReportingToken(data: .init([2]))!

        let databaseQueue = try createDatabaseQueue()

        try databaseQueue.write { db in
            let recordsToUpsert: [SpamReportingTokenRecord] = [
                .init(sourceUuid: sourceUuid1, spamReportingToken: spamReportingToken1),
                .init(sourceUuid: sourceUuid2, spamReportingToken: spamReportingToken1),
                .init(sourceUuid: sourceUuid1, spamReportingToken: spamReportingToken2)
            ]
            for record in recordsToUpsert {
                try record.upsert(db)
            }
        }

        let (tokenForUuid1, tokenForUuid2) = try databaseQueue.read { db in (
            try SpamReportingTokenRecord.fetchOne(db, key: sourceUuid1)?.spamReportingToken,
            try SpamReportingTokenRecord.fetchOne(db, key: sourceUuid2)?.spamReportingToken
        )}
        XCTAssertEqual(tokenForUuid1, spamReportingToken2)
        XCTAssertEqual(tokenForUuid2, spamReportingToken1)
    }
}
