//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import Testing

@testable import SignalServiceKit

struct TableRecordSSKTest {
    @Test
    func testSelectDistinct() throws {
        let db = InMemoryDB()
        try db.write { tx in
            try tx.database.execute(sql: """
            CREATE TABLE "SelectDistinct" ("id" INTEGER PRIMARY KEY, "value" TEXT NOT NULL);
            CREATE INDEX "SelectDistinctIndex" ON "SelectDistinct" ("value");
            """)
            for value in ["A", "B", "A", "C", "D", "C", "B", "B", "B", "B"] {
                try tx.database.execute(
                    sql: """
                    INSERT INTO "SelectDistinct" ("value") VALUES (?)
                    """,
                    arguments: [value],
                )
            }
            struct SelectDistinctRecord: TableRecord {
                static let databaseTableName: String = "SelectDistinct"
            }
            let valueColumn = Column("value")
            let actualValues = try SelectDistinctRecord.selectDistinct(valueColumn, as: String.self, tx: tx)
            #expect(actualValues == ["A", "B", "C", "D"])
        }
    }
}
