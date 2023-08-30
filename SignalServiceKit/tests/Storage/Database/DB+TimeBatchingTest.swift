//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalServiceKit

class DBTimeBatchingTest: XCTestCase {
    func testAllElements() {
        let elements = [1, 2, 3, 4]
        var seenElements = [Int]()
        MockDB().enumerateWithTimeBatchedWriteTx(elements) { item, tx in
            seenElements.append(item)
        }
        XCTAssertEqual(seenElements, elements)
    }

    func testSeparateTransactions() {
        let uniqueTransactions = countUniqueTransactions(
            enumerationCount: 100,
            yieldTxAfter: -1
        )

        XCTAssertEqual(uniqueTransactions, 100)
    }

    func testSingleTransaction() {
        let uniqueTransactions = countUniqueTransactions(
            enumerationCount: 1,
            yieldTxAfter: .infinity
        )

        XCTAssertEqual(uniqueTransactions, 1)
    }

    private func countUniqueTransactions(
        enumerationCount: Int,
        yieldTxAfter: TimeInterval
    ) -> Int {
        var uniqueRetainedTransactions = 0
        let db = MockDB(
            retainedTransactionBlock: {
                // This will be called each time the DB's write block closes,
                // because we hang onto the transactions we're given.
                uniqueRetainedTransactions += 1
            }
        )

        var currentTransaction: DBWriteTransaction?
        defer { _ = currentTransaction }

        db.enumerateWithTimeBatchedWriteTx(
            1...enumerationCount,
            yieldTxAfter: yieldTxAfter
        ) { _, tx in
            currentTransaction = tx
        }

        return uniqueRetainedTransactions
    }

    func testThrownError() {
        var seenElements = [Int]()
        XCTAssertThrowsError(try MockDB().enumerateWithTimeBatchedWriteTx(1...100, block: { item, tx in
            seenElements.append(item)
            if item == 5 {
                throw OWSGenericError("")
            }
        }))
        XCTAssertEqual(seenElements, [1, 2, 3, 4, 5])
    }
}
