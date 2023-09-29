//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

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

/// A perfectly transparent proxy to `SDSDatabaseStorage` (note: most methods
/// are actually implemented on `SDSTransactable`). Uses V2 types instead.
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

    fileprivate final class ReadTx: DBReadTransaction {
        fileprivate let tx: SDSAnyReadTransaction
        init(_ tx: SDSAnyReadTransaction) { self.tx = tx }
    }

    fileprivate final class WriteTx: DBWriteTransaction {
        fileprivate let tx: SDSAnyWriteTransaction
        init(_ tx: SDSAnyWriteTransaction) { self.tx = tx }

        func addAsyncCompletion(on scheduler: Scheduler, _ block: @escaping () -> Void) {
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

    // MARK: - API

    public func read(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: (DBReadTransaction) -> Void
    ) {
        databaseStorage.read(file: file, function: function, line: line, block: {block(ReadTx($0))})
    }

    public func write(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: (DBWriteTransaction) -> Void
    ) {
        databaseStorage.write(file: file, function: function, line: line, block: {block(WriteTx($0))})
    }

    // MARK: Async Methods

    public func asyncRead(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: @escaping (DBReadTransaction) -> Void,
        completionQueue: DispatchQueue = .main,
        completion: (() -> Void)? = nil
    ) {
        databaseStorage.asyncRead(file: file, function: function, line: line, block: {block(ReadTx($0))}, completionQueue: completionQueue, completion: completion)
    }

    public func asyncWrite(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: @escaping (DBWriteTransaction) -> Void,
        completionQueue: DispatchQueue = .main,
        completion: (() -> Void)? = nil
    ) {
        databaseStorage.asyncWrite(file: file, function: function, line: line, block: {block(WriteTx($0))}, completionQueue: completionQueue, completion: completion)
    }

    // MARK: Awaitable Methods

    public func awaitableWrite<T>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: @escaping (DBWriteTransaction) throws -> T
    ) async rethrows -> T {
        return try await databaseStorage.awaitableWrite(file: file, function: function, line: line, block: {try block(WriteTx($0))})
    }

    // MARK: Promises

    public func readPromise(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        _ block: @escaping (DBReadTransaction) -> Void
    ) -> AnyPromise {
        return databaseStorage.readPromise(file: file, function: function, line: line, {block(ReadTx($0))})
    }

    public func readPromise<T>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        _ block: @escaping (DBReadTransaction) -> T
    ) -> Promise<T> {
        return databaseStorage.read(.promise, file: file, function: function, line: line, {block(ReadTx($0))})
    }

    // throws version
    public func readPromise<T>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        _ block: @escaping (DBReadTransaction) throws -> T
    ) -> Promise<T> {
        return databaseStorage.read(.promise, file: file, function: function, line: line, {try block(ReadTx($0))})
    }

    public func writePromise(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        _ block: @escaping (DBWriteTransaction) -> Void
    ) -> AnyPromise {
        return AnyPromise(databaseStorage.write(.promise, file: file, function: function, line: line, {block(WriteTx($0))}))
    }

    public func writePromise<T>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        _ block: @escaping (DBWriteTransaction) -> T
    ) -> Promise<T> {
        return databaseStorage.write(.promise, file: file, function: function, line: line, {block(WriteTx($0))})
    }

    // throws version
    public func writePromise<T>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        _ block: @escaping (DBWriteTransaction) throws -> T
    ) -> Promise<T> {
        return databaseStorage.write(.promise, file: file, function: function, line: line, {try block(WriteTx($0))})
    }

    // MARK: Value Methods

    public func read<T>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: (DBReadTransaction) throws -> T
    ) rethrows -> T {
        return try databaseStorage.read(file: file, function: function, line: line, block: {try block(ReadTx($0))})
    }

    public func write<T>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: (DBWriteTransaction) throws -> T
    ) rethrows -> T {
        return try databaseStorage.write(file: file, function: function, line: line, block: {try block(WriteTx($0))})
    }

    // MARK: - Observation

    public func appendDbChangeDelegate(_ dbChangeDelegate: DBChangeDelegate) {
        self.databaseStorage.appendDatabaseChangeDelegate(DBChangeDelegateWrapper(dbChangeDelegate))
    }
}

extension SDSAnyWriteTransaction {
    var asRead: SDSAnyReadTransaction { self }
}

private class DBChangeDelegateWrapper: NSObject, DatabaseChangeDelegate {

    /// Retains a strong reference to self intentionally, to avoid observation being lost when this object
    /// is deallocated.
    /// This reference is released if we ever find the dbChangeDelegate has been deallocated.
    /// This isn't perfect, as this object can persist indefinitely if no callbacks happen, but presumably
    /// the DatabaseChangeDelegate itself checks for deallocation on callbacks so...is it any worse?
    private var strongSelf: Any?
    private weak var dbChangeDelegate: DBChangeDelegate?

    init(_ dbChangeDelegate: DBChangeDelegate) {
        self.dbChangeDelegate = dbChangeDelegate
        super.init()
        strongSelf = self
    }

    func databaseChangesDidUpdate(databaseChanges: DatabaseChanges) {
        checkRetain()
    }

    func databaseChangesDidUpdateExternally() {
        checkRetain()?.dbChangesDidUpdateExternally()
    }

    func databaseChangesDidReset() {
        checkRetain()
    }

    @discardableResult
    private func checkRetain() -> DBChangeDelegate? {
        guard let dbChangeDelegate else {
            strongSelf = nil
            return nil
        }
        return dbChangeDelegate
    }
}
