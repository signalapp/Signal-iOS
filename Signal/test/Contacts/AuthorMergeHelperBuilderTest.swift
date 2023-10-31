//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import LibSignalClient
import XCTest

@testable import Signal
@testable import SignalServiceKit

final class AuthorMergeHelperBuilderTest: XCTestCase {
    func testBuildTableIfNeeded() async {
        await MainActor.run { _ = OWSBackgroundTaskManager.shared() }

        let appContext = TestAppContext()
        let authorMergeHelper = AuthorMergeHelper(keyValueStoreFactory: InMemoryKeyValueStoreFactory())
        let inMemoryDb = InMemoryDB()
        let recipientDatabaseTable = MockRecipientDatabaseTable()

        let aci1 = Aci.constantForTesting("00000000-0000-4000-8000-0000000000a1")
        let aci2 = Aci.constantForTesting("00000000-0000-4000-8000-0000000000a2")
        let phoneNumber1 = E164("+16505550101")!
        let phoneNumber2 = E164("+16505550102")!

        inMemoryDb.write { tx in
            recipientDatabaseTable.insertRecipient(SignalRecipient(aci: aci1, pni: nil, phoneNumber: phoneNumber1), transaction: tx)
        }

        inMemoryDb.write { tx in
            let db = InMemoryDB.shimOnlyBridge(tx).db
            insertObject(rowId: 1, aci: aci1, phoneNumber: phoneNumber1, db: db)
            insertObject(rowId: 2, aci: aci1, phoneNumber: phoneNumber2, db: db)
            insertObject(rowId: 3, aci: aci2, phoneNumber: phoneNumber1, db: db)
            insertObject(rowId: 4, aci: aci2, phoneNumber: phoneNumber2, db: db)
            insertObject(rowId: 5, aci: nil, phoneNumber: phoneNumber1, db: db)
            insertObject(rowId: 6, aci: nil, phoneNumber: phoneNumber1, db: db)
            insertObject(rowId: 7, aci: nil, phoneNumber: phoneNumber2, db: db)
            insertObject(rowId: 8, aci: nil, phoneNumber: phoneNumber2, db: db)
            insertObject(rowId: 9, aci: aci1, phoneNumber: nil, db: db)
        }

        await AuthorMergeHelperBuilder(
            appContext: appContext,
            authorMergeHelper: authorMergeHelper,
            db: inMemoryDb,
            dbFromTx: { tx in InMemoryDB.shimOnlyBridge(tx).db },
            modelReadCaches: AuthorMergeHelperBuilder_MockModelReadCaches(),
            recipientDatabaseTable: recipientDatabaseTable
        ).buildTableIfNeeded()

        inMemoryDb.read { tx in
            XCTAssertEqual(authorMergeHelper.shouldCleanUp(phoneNumber: phoneNumber1.stringValue, tx: tx), false)
            XCTAssertEqual(authorMergeHelper.shouldCleanUp(phoneNumber: phoneNumber2.stringValue, tx: tx), true)

            let db = InMemoryDB.shimOnlyBridge(tx).db
            XCTAssert(containsObject(rowId: 1, aci: aci1, phoneNumber: nil, db: db))
            XCTAssert(containsObject(rowId: 2, aci: aci1, phoneNumber: nil, db: db))
            XCTAssert(containsObject(rowId: 3, aci: aci2, phoneNumber: nil, db: db))
            XCTAssert(containsObject(rowId: 4, aci: aci2, phoneNumber: nil, db: db))
            XCTAssert(containsObject(rowId: 5, aci: aci1, phoneNumber: nil, db: db))
            XCTAssert(containsObject(rowId: 6, aci: aci1, phoneNumber: nil, db: db))
            XCTAssert(containsObject(rowId: 7, aci: nil, phoneNumber: phoneNumber2, db: db))
            XCTAssert(containsObject(rowId: 8, aci: nil, phoneNumber: phoneNumber2, db: db))
            XCTAssert(containsObject(rowId: 9, aci: aci1, phoneNumber: nil, db: db))
        }
    }

    private func insertObject(rowId: Int64, aci: Aci?, phoneNumber: E164?, db: Database) {
        let sqlQuery = """
            INSERT INTO "pending_read_receipts" ("id", "threadId", "messageTimestamp", "authorPhoneNumber", "authorUuid")
            VALUES (?, 0, 0, ?, ?)
        """
        try! db.execute(sql: sqlQuery, arguments: [rowId, phoneNumber?.stringValue, aci?.serviceIdUppercaseString])
    }

    private func containsObject(rowId: Int64, aci: Aci?, phoneNumber: E164?, db: Database) -> Bool {
        let sqlQuery = """
            SELECT 1 FROM "pending_read_receipts" WHERE "id" = ? AND "authorPhoneNumber" IS ? AND "authorUuid" IS ?
        """
        return try! Bool.fetchOne(db, sql: sqlQuery, arguments: [rowId, phoneNumber?.stringValue, aci?.serviceIdUppercaseString]) ?? false
    }
}
