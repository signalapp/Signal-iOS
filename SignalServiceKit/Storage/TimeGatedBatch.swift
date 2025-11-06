//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import GRDB

public enum TimeGatedBatch {
    /// Processes `objects` within one or more transactions.
    ///
    /// You probably don't need this method and shouldn't use it. Splitting an
    /// operation across multiple transactions (whether you're using this method
    /// or not) requires careful consideration to ensure data integrity.
    ///
    /// Most loops should require approximately the same amount of time for each
    /// object. In those cases, it's simpler to split `objects` into batches
    /// with a fixed size and process each batch within its own transaction.
    ///
    /// However, if you are processing objects with significant and
    /// unpredictable variability in their processing time, this pattern may be
    /// useful. If a few elements take orders of magnitude longer to process
    /// than the majority, this will provide a reasonable balance between the
    /// number of transactions and the amount of work performed in each
    /// transaction. You must ensure that it's safe to process each object in a
    /// separate transaction AND you also must ensure it's safe to process all
    /// objects within a single transaction BECAUSE this method will split
    /// transactions at arbitrary points.
    ///
    /// - Parameter yieldTxAfter: A suggestion for the maximum amount of time to
    /// keep the transaction open for a single batch. This method will start a
    /// new transaction when `block` returns if more than `yieldTxAfter` seconds
    /// have elapsed since the transaction was opened. Note: This means the
    /// actual maximum transaction duration is unbounded because `block` may
    /// never return or may run extremely slow queries.
    public static func enumerateObjects<T, E>(
        _ objects: some Sequence<T>,
        db: any DB,
        yieldTxAfter: TimeInterval = 1.0,
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: (T, DBWriteTransaction) throws(E) -> Void
    ) async throws(E) {
        var isDone = false
        var objectEnumerator = objects.makeIterator()
        while !isDone {
            try await db.awaitableWrite(file: file, function: function, line: line) { tx throws(E) -> Void in
                let startTime = CACurrentMediaTime()
                while true {
                    guard let object = objectEnumerator.next() else {
                        // We're done with everything, so exit the outer loop.
                        isDone = true
                        return
                    }
                    try block(object, tx)
                    let elapsedTime = CACurrentMediaTime() - startTime
                    guard elapsedTime < yieldTxAfter else {
                        // We're done with this batch, so we want another transaction.
                        return
                    }
                    // Process another object with this transaction...
                }
            }
        }
    }

    // MARK: -

    /// Processes all elements in batches bound by time, asynchronously.
    ///
    /// Like `processAll`, but `async`. See that method for details.
    public static func processAllAsync<E: Error, TxContext>(
        db: any DB,
        yieldTxAfter maximumDuration: TimeInterval = 0.5,
        errorTxCompletion: GRDB.Database.TransactionCompletion = .commit,
        buildTxContext: (DBWriteTransaction) throws(E) -> TxContext,
        processBatch: (DBWriteTransaction, inout TxContext) throws(E) -> Int,
        concludeTx: (DBWriteTransaction, TxContext) throws(E) -> Void,
    ) async throws(E) -> Int {
        return try await _processAllAsync(
            db: db,
            yieldTxAfter: maximumDuration,
            errorTxCompletion: errorTxCompletion,
            buildTxContext: buildTxContext,
            processBatch: processBatch,
            concludeTx: concludeTx,
        )
    }

    /// Processes all elements in batches bound by time, asynchronously.
    ///
    /// Like `processAll`, but `async` and without "transaction contexts". See
    /// that method for details.
    public static func processAllAsync<E: Error>(
        db: DB,
        yieldTxAfter maximumDuration: TimeInterval = 0.5,
        errorTxCompletion: GRDB.Database.TransactionCompletion = .commit,
        processBatch: (DBWriteTransaction) throws(E) -> Int,
    ) async throws(E) -> Int {
        return try await _processAllAsync(
            db: db,
            yieldTxAfter: maximumDuration,
            errorTxCompletion: errorTxCompletion,
            buildTxContext: { _ throws(E) in DummyTxContext() },
            processBatch: { tx, _ throws(E) in try processBatch(tx) },
            concludeTx: { _, _ throws(E) in }
        )
    }

    /// See docs on `processAll`.
    private static func _processAllAsync<E: Error, TxContext>(
        db: any DB,
        yieldTxAfter maximumDuration: TimeInterval = 0.5,
        errorTxCompletion: GRDB.Database.TransactionCompletion = .commit,
        buildTxContext: (DBWriteTransaction) throws(E) -> TxContext,
        processBatch: (DBWriteTransaction, inout TxContext) throws(E) -> Int,
        concludeTx: (DBWriteTransaction, TxContext) throws(E) -> Void,
    ) async throws(E) -> Int {
        var itemCount = 0
        while true {
            let txBlock: (DBWriteTransaction) throws(E) -> (txItemCount: Int, mightHaveMore: Bool) = { tx in
                return try processBatchesInTransaction(
                    maximumDuration: maximumDuration,
                    buildTxContext: buildTxContext,
                    processBatch: processBatch,
                    concludeTx: concludeTx,
                    tx: tx,
                )
            }

            let (txItemCount, mightHaveMore): (Int, Bool) = switch errorTxCompletion {
            case .commit:
                try await db.awaitableWrite(block: txBlock)
            case .rollback:
                try await db.awaitableWriteWithRollbackIfThrows(block: txBlock)
            }

            itemCount += txItemCount

            if mightHaveMore {
                continue
            } else {
                break
            }
        }

        return itemCount
    }

    // MARK: -

    /// Processes all elements in batches bound by time.
    ///
    /// This method invokes `processBatch` repeatedly & in a tight loop. It
    /// stops when `processBatch` returns zero (indicating an empty batch).
    /// Callers must ensure `processBatch` eventually returns zero; they likely
    /// need to delete objects as part of each batch or maintain a cursor to
    /// avoid processing the same elements multiple times.
    ///
    /// This method is most useful for "fetch and delete" operations that are
    /// trying to avoid DELETE-ing rows from the database while SELECT-ing them
    /// via enumeration. This method will execute multiple batches within a
    /// single transaction (if time allows), so those operations can fetch &
    /// delete in small batches without exploding the number of transactions.
    ///
    /// - parameter errorTxCompletion: The strategy to employ with the latest
    /// transaction if an error is thrown: rollback or commit changes made so far _within_
    /// that last transaction. Prior non-throwing transactions would already be committed.
    ///
    /// - Parameter buildTxContext: A block run once immediately when a new
    /// transaction is opened, returning a context object shared by each batch
    /// processed in that transaction.
    ///
    /// - Parameter concludeTx: A block run once just before a transaction is
    /// closed, which may be used to commit information about the batches
    /// processed in that transaction.
    ///
    /// - Returns: The total number of items processed across all batches.
    public static func processAll<E: Error, TxContext>(
        db: DB,
        yieldTxAfter maximumDuration: TimeInterval = 0.5,
        errorTxCompletion: GRDB.Database.TransactionCompletion = .commit,
        buildTxContext: (DBWriteTransaction) throws(E) -> TxContext,
        processBatch: (DBWriteTransaction, inout TxContext) throws(E) -> Int,
        concludeTx: (DBWriteTransaction, TxContext) throws(E) -> Void,
    ) throws(E) -> Int {
        return try _processAll(
            db: db,
            yieldTxAfter: maximumDuration,
            errorTxCompletion: errorTxCompletion,
            buildTxContext: buildTxContext,
            processBatch: processBatch,
            concludeTx: concludeTx
        )
    }

    /// Processes all elements in batches bound by time.
    ///
    /// Like `processAll` above, but without "transaction contexts". See that
    /// method for details.
    public static func processAll<E: Error>(
        db: DB,
        yieldTxAfter maximumDuration: TimeInterval = 0.5,
        errorTxCompletion: GRDB.Database.TransactionCompletion = .commit,
        processBatch: (DBWriteTransaction) throws(E) -> Int
    ) throws(E) -> Int {
        return try _processAll(
            db: db as any DB,
            yieldTxAfter: maximumDuration,
            errorTxCompletion: errorTxCompletion,
            buildTxContext: { _ throws(E) in DummyTxContext() },
            processBatch: { tx, _ throws(E) in try processBatch(tx) },
            concludeTx: { _, _ throws(E) in }
        )
    }

    /// See docs on `processAll`.
    private static func _processAll<E: Error, TxContext>(
        db: DB,
        yieldTxAfter maximumDuration: TimeInterval,
        errorTxCompletion: GRDB.Database.TransactionCompletion,
        buildTxContext: (DBWriteTransaction) throws(E) -> TxContext,
        processBatch: (DBWriteTransaction, inout TxContext) throws(E) -> Int,
        concludeTx: (DBWriteTransaction, TxContext) throws(E) -> Void,
    ) throws(E) -> Int {
        var itemCount = 0
        while true {
            let txBlock: (DBWriteTransaction) throws(E) -> (txItemCount: Int, mightHaveMore: Bool) = { tx in
                return try processBatchesInTransaction(
                    maximumDuration: maximumDuration,
                    buildTxContext: buildTxContext,
                    processBatch: processBatch,
                    concludeTx: concludeTx,
                    tx: tx,
                )
            }

            let (txItemCount, mightHaveMore): (Int, Bool) = switch errorTxCompletion {
            case .commit:
                try db.write(block: txBlock)
            case .rollback:
                try db.writeWithRollbackIfThrows(block: txBlock)
            }

            itemCount += txItemCount

            if mightHaveMore {
                continue
            } else {
                break
            }
        }

        return itemCount
    }

    // MARK: -

    private struct DummyTxContext {}

    /// Process as many batches in the given transaction as possible in the
    /// given duration.
    private static func processBatchesInTransaction<E: Error, TxContext>(
        maximumDuration: CFTimeInterval,
        buildTxContext: (DBWriteTransaction) throws(E) -> TxContext,
        processBatch: (DBWriteTransaction, inout TxContext) throws(E) -> Int,
        concludeTx: (DBWriteTransaction, TxContext) throws(E) -> Void,
        tx: DBWriteTransaction
    ) throws(E) -> (txItemCount: Int, mightHaveMore: Bool) {
        let yieldDeadline = CACurrentMediaTime() + maximumDuration
        var itemCount = 0
        var mightHaveMore: Bool

        var txContext = try buildTxContext(tx)
        while true {
            let batchCount = try autoreleasepool { () throws(E) -> Int in
                return try processBatch(tx, &txContext)
            }
            if batchCount == 0 {
                mightHaveMore = false
                break
            }
            itemCount += batchCount
            if CACurrentMediaTime() > yieldDeadline {
                mightHaveMore = true
                break
            }
        }
        try concludeTx(tx, txContext)

        return (itemCount, mightHaveMore)
    }
}
