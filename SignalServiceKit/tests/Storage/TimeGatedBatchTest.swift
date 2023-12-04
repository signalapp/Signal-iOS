//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalServiceKit

class DBTimeBatchingTest: XCTestCase {
    func testEnumerateAllElements() {
        let elements = [1, 2, 3, 4]
        var seenElements = [Int]()
        TimeGatedBatch.enumerateObjects(elements, db: MockDB()) { item, tx in
            seenElements.append(item)
        }
        XCTAssertEqual(seenElements, elements)
    }

    func testEnumerateSeparateTransactions() {
        let uniqueTransactions = countUniqueTransactions(
            enumerationCount: 100,
            yieldTxAfter: -1
        )

        XCTAssertEqual(uniqueTransactions, 100)
    }

    func testEnumerateSingleTransaction() {
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

        TimeGatedBatch.enumerateObjects(
            1...enumerationCount,
            db: db,
            yieldTxAfter: yieldTxAfter
        ) { _, tx in
            currentTransaction = tx
        }

        return uniqueRetainedTransactions
    }

    func testEnumerateThrownError() {
        var seenElements = [Int]()
        XCTAssertThrowsError(try TimeGatedBatch.enumerateObjects(1...100, db: MockDB(), block: { item, tx in
            seenElements.append(item)
            if item == 5 {
                throw OWSGenericError("")
            }
        }))
        XCTAssertEqual(seenElements, [1, 2, 3, 4, 5])
    }

    func testProcessSeparateTransactions() {
        weak var priorTx: DBWriteTransaction?
        var batchCounter = 0
        let expectedResult = 3
        let actualResult = TimeGatedBatch.processAll(db: MockDB(), yieldTxAfter: -1) { tx in
            // Every iteration should use a new transaction, so it should never match.
            // In practice, `priorTx` is always `nil`, but this code is right even in
            // situations where some other component retains the transaction.
            XCTAssert(priorTx !== tx)
            priorTx = tx
            batchCounter += 1
            return batchCounter > expectedResult ? 0 : 1
        }
        XCTAssertEqual(actualResult, expectedResult)
    }

    func testProcessSingleTransaction() {
        weak var priorTx: DBWriteTransaction?
        var batchCounter = 0
        let expectedResult = 3
        let actualResult = TimeGatedBatch.processAll(db: MockDB(), yieldTxAfter: .infinity) { tx in
            // If we're on the 2nd or later batch, then the tx must match.
            XCTAssert(batchCounter == 0 || priorTx === tx)
            priorTx = tx
            batchCounter += 1
            return batchCounter > expectedResult ? 0 : 1
        }
        XCTAssertEqual(actualResult, expectedResult)
    }

    func testProcessMultipleBatchesMultipleTransactions() {
        // Start with a tiny value and increment it each time the test fails. Even
        // on a slow machine, we should eventually process two batches within a
        // single transaction before running out of time.
        var yieldTxAfter: TimeInterval = 0.000001
        while yieldTxAfter < 10 {
            weak var priorTx: DBWriteTransaction?
            var batchCounter = 0
            var multipleBatchesInOneTx = false
            let actualResult = TimeGatedBatch.processAll(db: MockDB(), yieldTxAfter: yieldTxAfter) { tx in
                batchCounter += 1
                // If this is the 2nd batch and we're using same transaction, then we've
                // satisfied the requirement of multiple batches with one transaction.
                if batchCounter == 2, priorTx === tx {
                    multipleBatchesInOneTx = true
                }
                // If this is the 2nd batch or later and we're using a different
                // transaction, then we've satisfied the requirement of executing multiple
                // transactions if necessary.
                let isNewTx = batchCounter >= 2 && priorTx !== tx
                priorTx = tx
                return isNewTx ? 0 : 1
            }
            XCTAssertEqual(actualResult, batchCounter - 1)
            if multipleBatchesInOneTx {
                return
            }
            yieldTxAfter *= 10
        }
        XCTFail("Couldn't satisfy the test conditions even with a 10s yield.")
    }
}
