//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension DB {
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
    public func enumerateWithTimeBatchedWriteTx<T>(
        _ objects: some Sequence<T>,
        yieldTxAfter: TimeInterval = 1.0,
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: (T, DBWriteTransaction) throws -> Void
    ) rethrows {
        try _enumerateWithTimeBatchedWriteTx(
            objects,
            yieldTxAfter: yieldTxAfter,
            file: file,
            function: function,
            line: line,
            block: block,
            rescue: { throw $0 }
        )
    }

    // The "rescue" pattern is used in LibDispatch (and replicated here) to
    // allow "rethrows" to work properly.
    private func _enumerateWithTimeBatchedWriteTx<T>(
        _ objects: some Sequence<T>,
        yieldTxAfter: TimeInterval,
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: (T, DBWriteTransaction) throws -> Void,
        rescue: (Error) throws -> Void
    ) rethrows {
        var isDone = false
        var thrownError: Error?
        var objectEnumerator = objects.makeIterator()
        while !isDone {
            write(file: file, function: function, line: line) { tx in
                let startTime = CACurrentMediaTime()
                while true {
                    guard let object = objectEnumerator.next() else {
                        // We're done with everything, so exit the outer loop.
                        isDone = true
                        return
                    }
                    do {
                        try block(object, tx)
                    } catch {
                        thrownError = error
                        isDone = true
                        return
                    }
                    let elapsedTime = CACurrentMediaTime() - startTime
                    guard elapsedTime < yieldTxAfter else {
                        // We're done with this batch, so we want another transaction.
                        return
                    }
                    // Process another object with this transaction...
                }
            }
        }
        if let thrownError {
            try rescue(thrownError)
        }
    }
}
