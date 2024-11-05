//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import GRDB

public extension SDSAnyReadTransaction {
    /// Bridging from a SDS transaction to a DB transaction can be done at the seams;
    /// when you have an old class using SDS classes talking to a new one using DB classes.
    var asV2Read: DBReadTransaction { return SDSDB.ReadTx(self) }
}

public extension SDSAnyWriteTransaction {
    /// Bridging from a SDS transaction to a DB transaction can be done at the seams;
    /// when you have an old class using SDS classes talking to a new one using DB classes.
    var asV2Write: DBWriteTransaction { return SDSDB.WriteTx(self) }
}

/// A perfectly transparent proxy to `SDSDatabaseStorage`. Uses V2 types instead.
///
/// Classes using `DB` can simply interact with that protocol the same way in both
/// production code and tests, producing transaction objects which they pass down to
/// lower-level classes which perform database operations.
/// In production code, the transaction instances will be produced by this class, get converted
/// at some point before actually being used with `shimOnlyBridge` methods, and everything
/// will be fine.
/// In tests, the transactions will be stubs, and will crash (failing tests) if they ever are passed to
/// `shimOnlyBridge` methods. This means you _have_ to stub out all your db operations
/// within test setup code; if you don't and hit an actual db operation code path, your test will fail.
/// This is a good thing; it helps you ensure your tests are scoped explicitly (what isn't explicitly
/// mocked doesn't work!), and ensures your tests aren't subject to random external behavior changes.
public class SDSDB: DB {

    public final class ReadTx: DBReadTransaction {
        fileprivate let tx: SDSAnyReadTransaction
        fileprivate init(_ tx: SDSAnyReadTransaction) { self.tx = tx }

        public var databaseConnection: GRDB.Database {
            return tx.unwrapGrdbRead.database
        }
    }

    public final class WriteTx: DBWriteTransaction {
        fileprivate let tx: SDSAnyWriteTransaction
        fileprivate init(_ tx: SDSAnyWriteTransaction) { self.tx = tx }

        public var databaseConnection: GRDB.Database {
            return tx.unwrapGrdbWrite.database
        }

        public func addFinalization(forKey key: String, block: @escaping () -> Void) {
            tx.addTransactionFinalizationBlock(forKey: key, block: { _ in block() })
        }

        public func addSyncCompletion(_ block: @escaping () -> Void) {
            tx.addSyncCompletion(block)
        }

        public func addAsyncCompletion(on scheduler: Scheduler, _ block: @escaping () -> Void) {
            tx.addAsyncCompletion(on: scheduler, block: block)
        }
    }

    // MARK: - Bridging

    public static func shimOnlyBridge(_ readTx: DBReadTransaction) -> SDSAnyReadTransaction {
        // This is why `ReadTx` should be the **ONLY** concrete implementor of DBReadTransaction
        // in production code.
        // A stub test transaction will crash if it ever gets here; this is good because if it got
        // here in a test it means you didn't sub out the things that actually need an SDS transaction
        // and talk to the db.
        if let write = readTx as? WriteTx {
            return write.tx
        }
        return (readTx as! ReadTx).tx
    }

    public static func shimOnlyBridge(_ writeTx: DBWriteTransaction) -> SDSAnyWriteTransaction {
        // This is why `WriteTx` should be the **ONLY** concrete implementor of DBWriteTransaction
        // in production code.
        // A stub test transaction will crash if it ever gets here; this is good because if it got
        // here in a test it means you didn't sub out the things that actually need an SDS transaction
        // and talk to the db.
        return (writeTx as! WriteTx).tx
    }

    // MARK: - Init

    private let databaseStorage: SDSDatabaseStorage

    public init(databaseStorage: SDSDatabaseStorage) {
        self.databaseStorage = databaseStorage
    }

    // MARK: Async Methods

    public func asyncRead<T>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: @escaping (ReadTx) -> T,
        completionQueue: DispatchQueue = .main,
        completion: ((T) -> Void)? = nil
    ) {
        databaseStorage.asyncRead(file: file, function: function, line: line, block: {block(ReadTx($0))}, completionQueue: completionQueue, completion: completion)
    }

    public func asyncWrite<T>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: @escaping (WriteTx) -> T,
        completionQueue: DispatchQueue = .main,
        completion: ((T) -> Void)? = nil
    ) {
        databaseStorage.asyncWrite(file: file, function: function, line: line, block: {block(WriteTx($0))}, completionQueue: completionQueue, completion: completion)
    }

    public func asyncWriteWithTxCompletion<T>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: @escaping (WriteTx) -> TransactionCompletion<T>,
        completionQueue: DispatchQueue,
        completion: ((T) -> Void)?
    ) {
        databaseStorage.asyncWriteWithTxCompletion(file: file, function: function, line: line, block: {block(WriteTx($0))}, completionQueue: completionQueue, completion: completion)
    }

    // MARK: Awaitable Methods

    public func awaitableWrite<T>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: (WriteTx) throws -> T
    ) async rethrows -> T {
        return try await databaseStorage.awaitableWrite(file: file, function: function, line: line, block: {try block(WriteTx($0))})
    }

    public func awaitableWriteWithTxCompletion<T>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: (WriteTx) -> TransactionCompletion<T>
    ) async -> T {
        return await databaseStorage.awaitableWriteWithTxCompletion(file: file, function: function, line: line, block: {block(WriteTx($0))})
    }

    // MARK: Promises

    public func readPromise<T>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        _ block: @escaping (ReadTx) throws -> T
    ) -> Promise<T> {
        return databaseStorage.read(.promise, file: file, function: function, line: line, {try block(ReadTx($0))})
    }

    public func writePromise<T>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        _ block: @escaping (WriteTx) throws -> T
    ) -> Promise<T> {
        return databaseStorage.write(.promise, file: file, function: function, line: line, {try block(WriteTx($0))})
    }

    // MARK: Value Methods

    public func read<T>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: (ReadTx) throws -> T
    ) rethrows -> T {
        return try databaseStorage.read(file: file, function: function, line: line, block: {try block(ReadTx($0))})
    }

    public func write<T>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: (WriteTx) throws -> T
    ) rethrows -> T {
        return try databaseStorage.write(file: file, function: function, line: line, block: {try block(WriteTx($0))})
    }

    public func writeWithTxCompletion<T>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: (WriteTx) -> TransactionCompletion<T>
    ) -> T {
        return databaseStorage.writeWithTxCompletion(file: file, function: function, line: line, block: {block(WriteTx($0))})
    }

    // MARK: - Observation

    public func add(
        transactionObserver: TransactionObserver,
        extent: Database.TransactionObservationExtent
    ) {
        self.databaseStorage.grdbStorage.pool.add(transactionObserver: transactionObserver, extent: extent)
    }

    // MARK: - Touching

    public func touch(_ interaction: TSInteraction, shouldReindex: Bool, tx: DBWriteTransaction) {
        self.databaseStorage.touch(interaction: interaction, shouldReindex: shouldReindex, transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func touch(_ thread: TSThread, shouldReindex: Bool, shouldUpdateChatListUi: Bool, tx: DBWriteTransaction) {
        self.databaseStorage.touch(
            thread: thread,
            shouldReindex: shouldReindex,
            shouldUpdateChatListUi: shouldUpdateChatListUi,
            transaction: SDSDB.shimOnlyBridge(tx)
        )
    }

    public func touch(_ storyMessage: StoryMessage, tx: DBWriteTransaction) {
        self.databaseStorage.touch(storyMessage: storyMessage, transaction: SDSDB.shimOnlyBridge(tx))
    }
}

extension SDSAnyWriteTransaction {
    var asRead: SDSAnyReadTransaction { self }
}
