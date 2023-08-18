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
        var transactions = [DBWriteTransaction]()
        MockDB().enumerateWithTimeBatchedWriteTx(1...100, yieldTxAfter: -1) { _, tx in
            transactions.append(tx)
        }
        let uniqueTransactions = Set(transactions.map { ObjectIdentifier($0) })
        XCTAssertEqual(uniqueTransactions.count, 100)
    }

    func testSingleTransaction() {
        var transactions = [DBWriteTransaction]()
        MockDB().enumerateWithTimeBatchedWriteTx(1...100, yieldTxAfter: .infinity) { _, tx in
            transactions.append(tx)
        }
        let uniqueTransactions = Set(transactions.map { ObjectIdentifier($0) })
        XCTAssertEqual(uniqueTransactions.count, 1)
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
