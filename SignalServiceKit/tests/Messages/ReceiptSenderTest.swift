//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

class ReceiptSenderTest: XCTestCase {
    private var mockDb: InMemoryDB!
    private var receiptSender: ReceiptSender!
    private var recipientDatabaseTable: MockRecipientDatabaseTable!

    override func setUp() {
        super.setUp()

        mockDb = InMemoryDB()
        recipientDatabaseTable = MockRecipientDatabaseTable()
        receiptSender = ReceiptSender(
            appReadiness: AppReadinessMock(),
            recipientDatabaseTable: recipientDatabaseTable
        )
    }

    func testMergeAll() {
        // Setup – Store two different receipt sets for an ACI and an e164.
        let aci = Aci.constantForTesting("00000000-0000-4000-8000-0000000000a1")
        let aciReceiptSet = MessageReceiptSet()
        aciReceiptSet.insert(timestamp: 1234, messageUniqueId: "00000000-0000-4000-8000-000000000AAA")

        let e164 = E164("+16505550101")!
        let e164ReceiptSet = MessageReceiptSet()
        e164ReceiptSet.insert(timestamp: 5678, messageUniqueId: "00000000-0000-4000-8000-000000000BBB")

        mockDb.write { tx in
            recipientDatabaseTable.insertRecipient(SignalRecipient(aci: aci, pni: nil, phoneNumber: e164), transaction: tx)
            receiptSender._storeReceiptSet(aciReceiptSet, receiptType: .delivery, identifier: aci.serviceIdUppercaseString, tx: tx)
            receiptSender._storeReceiptSet(e164ReceiptSet, receiptType: .delivery, identifier: e164.stringValue, tx: tx)
        }

        // Test – Fetch the receipt set for a merged address
        let results = mockDb.read { tx in
            receiptSender.fetchAllReceiptSets(receiptType: .delivery, tx: tx)
        }

        // Verify – All timestamps were fetched and batched together.
        XCTAssertEqual(results.count, 1)
        let receiptSets = results[aci]!.sorted(by: { $0.identifier < $1.identifier })
        XCTAssertEqual(receiptSets[0].identifier, e164.stringValue)
        XCTAssertEqual(receiptSets[0].receiptSet.timestamps, [5678])
        XCTAssertEqual(receiptSets[1].identifier, aci.serviceIdUppercaseString)
        XCTAssertEqual(receiptSets[1].receiptSet.timestamps, [1234])
    }
}
