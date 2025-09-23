//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
import GRDB

@testable import SignalServiceKit

class DBTimeBatchingTest: XCTestCase {
    func testEnumerateAllElements() async {
        let elements = [1, 2, 3, 4]
        var seenElements = [Int]()
        await TimeGatedBatch.enumerateObjects(elements, db: InMemoryDB()) { item, tx in
            seenElements.append(item)
        }
        XCTAssertEqual(seenElements, elements)
    }

    func testEnumerateSeparateTransactions() async {
        let uniqueTransactions = await countUniqueTransactions(
            enumerationCount: 100,
            yieldTxAfter: -1
        )

        XCTAssertEqual(uniqueTransactions, 100)
    }

    func testEnumerateSingleTransaction() async {
        let uniqueTransactions = await countUniqueTransactions(
            enumerationCount: 1,
            yieldTxAfter: .infinity
        )

        XCTAssertEqual(uniqueTransactions, 1)
    }

    private func countUniqueTransactions(
        enumerationCount: Int,
        yieldTxAfter: TimeInterval
    ) async -> Int {
        var uniqueTransactions = 0
        let db = InMemoryDB()

        var currentTransaction: DBWriteTransaction?

        await TimeGatedBatch.enumerateObjects(
            1...enumerationCount,
            db: db,
            yieldTxAfter: yieldTxAfter
        ) { _, tx in
            if tx !== currentTransaction {
                uniqueTransactions += 1
            }

            currentTransaction = tx
        }

        return uniqueTransactions
    }

    func testEnumerateThrownError() async {
        var seenElements = [Int]()
        do {
            try await TimeGatedBatch.enumerateObjects(1...100, db: InMemoryDB(), block: { item, tx in
                seenElements.append(item)
                if item == 5 {
                    throw OWSGenericError("")
                }
            })
            XCTFail("Must throw error.")
        } catch {
            // Ok
        }
        XCTAssertEqual(seenElements, [1, 2, 3, 4, 5])
    }

    func testProcessSeparateTransactions() {
        weak var priorTx: DBWriteTransaction?
        var batchCounter = 0
        let expectedResult = 3
        let actualResult = TimeGatedBatch.processAll(db: InMemoryDB(), yieldTxAfter: -1) { tx in
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
        let actualResult = TimeGatedBatch.processAll(db: InMemoryDB(), yieldTxAfter: .infinity) { tx in
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
            let actualResult = TimeGatedBatch.processAll(db: InMemoryDB(), yieldTxAfter: yieldTxAfter) { tx in
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

    func testProcessMultipleTransactionsAndRollback() async throws {
        let tableName = "ljfdhslgkjabglakjh"
        let db = InMemoryDB()
        try await db.awaitableWrite { tx in
            try tx.database.create(table: tableName) { table in
                table.column("id", .integer).primaryKey()
            }
        }

        weak var priorTx: DBWriteTransaction?
        var batchCounter = 0
        do {
            _ = try TimeGatedBatch.processAll(
                db: db,
                yieldTxAfter: -1,
                errorTxCompletion: .rollback,
            ) { tx in
                // Every iteration should use a new transaction.
                // In practice, `priorTx` is always `nil`, but this code is right even in
                // situations where some other component retains the transaction.
                XCTAssert(priorTx !== tx)
                priorTx = tx

                batchCounter += 1

                // Write some rows.
                for i in 0..<10 {
                    try tx.database.execute(
                        sql: "INSERT INTO \(tableName) (id) VALUES (?);",
                        arguments: [i * batchCounter]
                    )
                }
                if batchCounter == 2 {
                    // Trigger a rollback
                    struct SomeError: Error {}
                    throw SomeError()
                } else {
                    return 10
                }
            }
            XCTFail("Should have thrown an error!")
        } catch {
            // Good, we expect an error
        }

        let numRows = try db.read { tx in
            return try Int.fetchOne(tx.database, sql: "SELECT COUNT(id) FROM \(tableName);")
        }
        XCTAssertEqual(numRows, 10)
    }

    // MARK: -

    func testTxContext_sync() {
        let maxBatchCount = 3
        var buildTxContextCount = 0
        var processBatchCount = 0
        var concludeTxCount = 0

        struct TxContext {
            var id = 0
        }

        _ = TimeGatedBatch.processAll(
            db: InMemoryDB(),
            yieldTxAfter: -1, // Each iteration a new transaction
            buildTxContext: { _ in
                buildTxContextCount += 1
                return TxContext()
            },
            processBatch: { _, context in
                XCTAssertEqual(context.id, 0)
                context.id += 1
                processBatchCount += 1
                return processBatchCount == maxBatchCount ? 0 : 1
            },
            concludeTx: { _, context in
                XCTAssertEqual(context.id, 1)
                concludeTxCount += 1
            },
        )

        XCTAssertEqual(buildTxContextCount, maxBatchCount)
        XCTAssertEqual(processBatchCount, maxBatchCount)
        XCTAssertEqual(concludeTxCount, maxBatchCount)
    }

    func testTxContext_async() async {
        let maxBatchCount = 3
        var buildTxContextCount = 0
        var processBatchCount = 0
        var concludeTxCount = 0

        struct TxContext {
            var id = 0
        }

        _ = await TimeGatedBatch.processAllAsync(
            db: InMemoryDB(),
            yieldTxAfter: -1, // Each iteration a new transaction
            buildTxContext: { _ in
                buildTxContextCount += 1
                return TxContext()
            },
            processBatch: { _, context in
                XCTAssertEqual(context.id, 0)
                context.id += 1
                processBatchCount += 1
                return processBatchCount == maxBatchCount ? 0 : 1
            },
            concludeTx: { _, context in
                XCTAssertEqual(context.id, 1)
                concludeTxCount += 1
            },
        )

        XCTAssertEqual(buildTxContextCount, maxBatchCount)
        XCTAssertEqual(processBatchCount, maxBatchCount)
        XCTAssertEqual(concludeTxCount, maxBatchCount)
    }
}
