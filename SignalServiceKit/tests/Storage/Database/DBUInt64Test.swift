//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import Testing

@testable import SignalServiceKit

struct DBUInt64Test {
    struct TestRecord: Codable, FetchableRecord, PersistableRecord {
        static let databaseTableName = "Test"
        @DBUInt64 var foo: UInt64
        @DBUInt64Optional var bar: UInt64?

        static func createTable(database: Database) throws {
            try database.execute(sql: """
                CREATE TABLE Test (foo INTEGER NOT NULL, bar INTEGER)
            """)
        }
    }

    @Test
    func roundTrip() throws {
        try InMemoryDB().write { tx in
            try TestRecord.createTable(database: tx.database)

            try tx.database.execute(sql: """
                INSERT INTO Test (foo, bar) VALUES
                    (123, 456),
                    (234, NULL)
            """)

            let prepopulated = try TestRecord.fetchAll(tx.database)
            #expect(prepopulated.count == 2)
            #expect(prepopulated[0].foo == 123)
            #expect(prepopulated[0].bar == 456)
            #expect(prepopulated[1].foo == 234)
            #expect(prepopulated[1].bar == nil)

            #expect(try TestRecord.deleteAll(tx.database) == 2)

            try TestRecord(foo: 123, bar: 456).insert(tx.database)
            try TestRecord(foo: 234, bar: nil).insert(tx.database)

            let inserted = try TestRecord.fetchAll(tx.database)
            #expect(inserted.count == 2)
            #expect(inserted[0].foo == 123)
            #expect(inserted[0].bar == 456)
            #expect(inserted[1].foo == 234)
            #expect(inserted[1].bar == nil)
        }
    }

    @Test
    func testZero() throws {
        try InMemoryDB().write { tx in
            try TestRecord.createTable(database: tx.database)

            try TestRecord(foo: 0, bar: 0).insert(tx.database)
            try TestRecord(foo: 0, bar: nil).insert(tx.database)

            let persisted = try TestRecord.fetchAll(tx.database)
            #expect(persisted.count == 2)
            #expect(persisted[0].foo == 0)
            #expect(persisted[0].bar == 0)
            #expect(persisted[1].foo == 0)
            #expect(persisted[1].bar == nil)
        }
    }

    @Test
    func testMax() throws {
        try InMemoryDB().write { tx in
            try TestRecord.createTable(database: tx.database)

            try TestRecord(foo: .max, bar: .max).insert(tx.database)
            try TestRecord(foo: .max, bar: nil).insert(tx.database)

            let persisted = try TestRecord.fetchAll(tx.database)
            #expect(persisted.count == 2)
            #expect(persisted[0].foo == .max)
            #expect(persisted[0].bar == .max)
            #expect(persisted[1].foo == .max)
            #expect(persisted[1].bar == nil)
        }
    }
}
