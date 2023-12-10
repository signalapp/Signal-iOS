//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

enum TimeGatedBatch {
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
    public static func enumerateObjects<T>(
        _ objects: some Sequence<T>,
        db: DB,
        yieldTxAfter: TimeInterval = 1.0,
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: (T, DBWriteTransaction) throws -> Void
    ) rethrows {
        var isDone = false
        var objectEnumerator = objects.makeIterator()
        while !isDone {
            try db.write(file: file, function: function, line: line) { tx in
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
    /// - Returns: The total number of items processed across all batches.
    static func processAll(
        db: DB,
        yieldTxAfter maximumDuration: TimeInterval = 0.5,
        processBatch: (DBWriteTransaction) throws -> Int
    ) rethrows -> Int {
        var itemCount = 0
        while true {
            let (txItemCount, mightHaveMore) = try db.write { tx in
                let startTime = CACurrentMediaTime()
                return try processSome(yieldDeadline: startTime + maximumDuration, processBatch: processBatch, tx: tx)
            }
            itemCount += txItemCount
            guard mightHaveMore else {
                break
            }
        }
        return itemCount
    }

    private static func processSome(
        yieldDeadline: CFTimeInterval,
        processBatch: (DBWriteTransaction) throws -> Int,
        tx: DBWriteTransaction
    ) rethrows -> (txItemCount: Int, mightHaveMore: Bool) {
        var itemCount = 0
        while true {
            let batchCount = try autoreleasepool { try processBatch(tx) }
            if batchCount == 0 {
                return (itemCount, mightHaveMore: false)
            }
            itemCount += batchCount
            guard CACurrentMediaTime() < yieldDeadline else {
                return (itemCount, mightHaveMore: true)
            }
        }
    }
}
