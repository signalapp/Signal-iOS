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
        let sourceServiceId = ServiceId(UUID())
        let spamReportingToken = SpamReportingToken(data: .init([1, 2, 3]))!

        let databaseQueue = try createDatabaseQueue()

        try databaseQueue.write { db in
            let record = SpamReportingTokenRecord(
                sourceUuid: sourceServiceId,
                spamReportingToken: spamReportingToken
            )
            try record.insert(db)
        }

        let loadedRecord = try databaseQueue.read { db in
            try SpamReportingTokenRecord.fetchOne(db, key: sourceServiceId)!
        }
        XCTAssertEqual(loadedRecord.sourceUuid, sourceServiceId)
        XCTAssertEqual(loadedRecord.spamReportingToken, spamReportingToken)
    }

    func testUpsert() throws {
        let sourceServiceId1 = ServiceId(UUID())
        let sourceServiceId2 = ServiceId(UUID())
        let spamReportingToken1 = SpamReportingToken(data: .init([1]))!
        let spamReportingToken2 = SpamReportingToken(data: .init([2]))!

        let databaseQueue = try createDatabaseQueue()

        try databaseQueue.write { db in
            let recordsToUpsert: [SpamReportingTokenRecord] = [
                .init(sourceUuid: sourceServiceId1, spamReportingToken: spamReportingToken1),
                .init(sourceUuid: sourceServiceId2, spamReportingToken: spamReportingToken1),
                .init(sourceUuid: sourceServiceId1, spamReportingToken: spamReportingToken2)
            ]
            for record in recordsToUpsert {
                try record.upsert(db)
            }
        }

        let (tokenForUuid1, tokenForUuid2) = try databaseQueue.read { db in (
            try SpamReportingTokenRecord.fetchOne(db, key: sourceServiceId1)?.spamReportingToken,
            try SpamReportingTokenRecord.fetchOne(db, key: sourceServiceId2)?.spamReportingToken
        )}
        XCTAssertEqual(tokenForUuid1, spamReportingToken2)
        XCTAssertEqual(tokenForUuid2, spamReportingToken1)
    }
}
