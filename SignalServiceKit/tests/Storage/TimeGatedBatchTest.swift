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

        await TimeGatedBatch.enumerateObjects(
            1...enumerationCount,
            db: db,
            yieldTxAfter: yieldTxAfter
        ) { _, tx in
            currentTransaction = tx
        }

        return uniqueRetainedTransactions
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
}

private final class MockTransaction: DBWriteTransaction {
    init() {}

    public var databaseConnection: GRDB.Database { fatalError() }

    func addFinalization(forKey key: String, block: @escaping () -> Void) {
        fatalError()
    }

    func addSyncCompletion(_ block: @escaping () -> Void) {
        fatalError()
    }

    func addAsyncCompletion(on scheduler: Scheduler, _ block: @escaping () -> Void) {
        fatalError()
    }
}

private class MockDB: DB {

    private let queue: Scheduler
    /// A block invoked when an externally-retained transaction is detected.
    private let retainedTransactionBlock: () -> Void

    /// Create a mock DB.
    ///
    /// - Parameter retainedTransactionBlock
    /// A block called if a read or write completes and a transaction has been
    /// retained by the caller. Useful for, e.g., detecting retained
    /// transactions in tests.
    public init(
        schedulers: Schedulers = DispatchQueueSchedulers(),
        retainedTransactionBlock: @escaping () -> Void = { fatalError("Retained transaction!") }
    ) {
        self.queue = schedulers.queue(label: "mockDB")
        self.retainedTransactionBlock = retainedTransactionBlock
    }

    private var weaklyHeldTransactions = WeakArray<MockTransaction>()

    private func performRead<R>(block: (MockTransaction) throws -> R) rethrows -> R {
        return try performWrite(block: block)
    }

    private func performWrite<R>(block: (MockTransaction) throws -> R) rethrows -> R {
        var callIsReentrant = false

        if !weaklyHeldTransactions.elements.isEmpty {
            // If we're entering this method with live transactions, that means
            // we're re-entering.
            callIsReentrant = true
        }

        defer {
            // If we're in a reentrant call skip the retention check, since
            // otherwise we'll have transactions that may be alive via recursion
            // rather than retention.
            if !callIsReentrant {
                weaklyHeldTransactions.removeAll { _ in
                    // If we're leaving this method with live transactions, that
                    // means they've been retained outside our `autoreleasepool`.
                    //
                    // Call the block for each retained transaction, and chuck 'em.
                    retainedTransactionBlock()
                    return true
                }
            }
        }

        // This may result in objects created during the `block` being released
        // in addition to the transaction. If your block cares about when ARC
        // releases its objects (e.g., if you find yourself here to understand
        // why your objects are being released), you may wish to consider an
        // explicit memory management technique.
        return try autoreleasepool {
            let tx = MockTransaction()
            weaklyHeldTransactions.append(tx)

            let blockValue = try block(tx)

            return blockValue
        }
    }

    // MARK: - Async Methods

    public func asyncRead<T>(
        file: String,
        function: String,
        line: Int,
        block: @escaping (MockTransaction) -> T,
        completionQueue: DispatchQueue,
        completion: ((T) -> Void)?
    ) {
        queue.sync {
            let result = performRead(block: block)

            guard let completion else { return }

            completionQueue.sync {
                completion(result)
            }
        }
    }

    public func asyncWrite<T>(
        file: String,
        function: String,
        line: Int,
        block: @escaping (MockTransaction) -> T,
        completionQueue: DispatchQueue,
        completion: ((T) -> Void)?
    ) {
        queue.sync {
            let result = performWrite(block: block)

            guard let completion else { return }

            completionQueue.sync {
                completion(result)
            }
        }
    }

    public func asyncWriteWithTxCompletion<T>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: @escaping (MockTransaction) -> TransactionCompletion<T>,
        completionQueue: DispatchQueue,
        completion: ((T) -> Void)?
    ) {
        asyncWrite(
            file: file,
            function: function,
            line: line,
            block: { tx in
                switch block(tx) {
                case .commit(let t):
                    return t
                case .rollback(let t):
                    return t
                }
            },
            completionQueue: completionQueue,
            completion: completion
        )
    }

    public func awaitableWrite<T>(
        file: String,
        function: String,
        line: Int,
        block: (MockTransaction) throws -> T
    ) async rethrows -> T {
        await Task.yield()
        return try queue.sync {
            return try self.performWrite(block: block)
        }
    }

    public func awaitableWriteWithTxCompletion<T>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: (MockTransaction) -> TransactionCompletion<T>
    ) async -> T? {
        return await awaitableWrite(
            file: file,
            function: function,
            line: line,
            block: { tx in
                switch block(tx) {
                case .commit(let t):
                    return t
                case .rollback:
                    return nil
                }
            }
        )
    }

    // MARK: - Promises

    public func readPromise<T>(
        file: String,
        function: String,
        line: Int,
        _ block: @escaping (MockTransaction) throws -> T
    ) -> Promise<T> {
        do {
            let t = try queue.sync {
                return try performRead(block: block)
            }
            return Promise<T>.value(t)
        } catch {
            return Promise<T>.init(error: error)
        }
    }

    public func writePromise<T>(
        file: String,
        function: String,
        line: Int,
        _ block: @escaping (MockTransaction) throws -> T
    ) -> Promise<T> {
        do {
            let t = try queue.sync {
                return try performWrite(block: block)
            }
            return Promise<T>.value(t)
        } catch {
            return Promise<T>(error: error)
        }
    }

    // MARK: - Value Methods

    public func read<T>(
        file: String,
        function: String,
        line: Int,
        block: (MockTransaction) throws -> T
    ) rethrows -> T {
        return try queue.sync {
            return try performRead(block: block)
        }
    }

    public func write<T>(
        file: String,
        function: String,
        line: Int,
        block: (MockTransaction) throws -> T
    ) rethrows -> T {
        return try queue.sync {
            return try performWrite(block: block)
        }
    }

    public func writeWithTxCompletion<T>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: (MockTransaction) -> TransactionCompletion<T>
    ) -> T {
        return write(
            file: file,
            function: function,
            line: line,
            block: { tx in
                switch block(tx) {
                case .commit(let t):
                    return t
                case .rollback(let t):
                    return t
                }
            }
        )
    }

    public func add(
        transactionObserver: TransactionObserver,
        extent: Database.TransactionObservationExtent
    ) {
        // Do nothing.
    }

    // MARK: - Touching

    public func touch(_ interaction: TSInteraction, shouldReindex: Bool, tx: DBWriteTransaction) {
        // Do nothing.
    }

    public func touch(_ thread: TSThread, shouldReindex: Bool, shouldUpdateChatListUi: Bool, tx: DBWriteTransaction) {
        // Do nothing.
    }

    public func touch(_ storyMessage: StoryMessage, tx: DBWriteTransaction) {
        // Do nothing.
    }
}
