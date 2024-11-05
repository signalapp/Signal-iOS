//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import GRDB

/// Wrapper around `SDSDatabaseStorage` that allows for an access pattern identical
/// to the original (you get a transaction object you pass around to perform database operations)
/// but which is easily stubbed out in tests.
/// Method signatures are identical to those in `SDSDatabaseStorage`.
///
/// This protocol is **not** for testing or stubbing actual database operations (SQL statements).
/// It allows you to write classes that utilize persistent storage, in the abstract, but which hand off the
/// actual queries to lower level helper classes (e.g. the "FooFinder" and "FooModel: SDSCodableModel" classes.)
///
/// Consumers of this protocol should **never** inspect the transaction objects, and should treat them
/// as black boxes. Any class that _actually_ wants to talk to the database to perform reads
/// and writes should use SDS- classes directly, unwrapping these transactions by using `SDSDB.shimOnlyBridge`.
///
/// Check out ToyExample.swift in the SDSDatabaseStorage/V2 directory under SignalServiceKitTests for a walkthrough
/// of the reasoning and how to use this class.
public protocol DB {

    associatedtype ReadTransaction: DBReadTransaction
    associatedtype WriteTransaction: DBWriteTransaction

    // MARK: - Async Methods

    func asyncRead<T>(
        file: String,
        function: String,
        line: Int,
        block: @escaping (ReadTransaction) -> T,
        completionQueue: DispatchQueue,
        completion: ((T) -> Void)?
    )

    func asyncWrite<T>(
        file: String,
        function: String,
        line: Int,
        block: @escaping (WriteTransaction) -> T,
        completionQueue: DispatchQueue,
        completion: ((T) -> Void)?
    )

    func asyncWriteWithTxCompletion<T>(
        file: String,
        function: String,
        line: Int,
        block: @escaping (WriteTransaction) -> TransactionCompletion<T>,
        completionQueue: DispatchQueue,
        completion: ((T) -> Void)?
    )

    // MARK: - Awaitable Methods

    func awaitableWrite<T>(
        file: String,
        function: String,
        line: Int,
        block: (WriteTransaction) throws -> T
    ) async rethrows -> T

    func awaitableWriteWithTxCompletion<T>(
        file: String,
        function: String,
        line: Int,
        block: (WriteTransaction) -> TransactionCompletion<T>
    ) async -> T

    // MARK: - Promises

    func readPromise<T>(
        file: String,
        function: String,
        line: Int,
        _ block: @escaping (ReadTransaction) throws -> T
    ) -> Promise<T>

    func writePromise<T>(
        file: String,
        function: String,
        line: Int,
        _ block: @escaping (WriteTransaction) throws -> T
    ) -> Promise<T>

    // MARK: - Value Methods

    func read<T>(
        file: String,
        function: String,
        line: Int,
        block: (ReadTransaction) throws -> T
    ) rethrows -> T

    func write<T>(
        file: String,
        function: String,
        line: Int,
        block: (WriteTransaction) throws -> T
    ) rethrows -> T

    func writeWithTxCompletion<T>(
        file: String,
        function: String,
        line: Int,
        block: (WriteTransaction) -> TransactionCompletion<T>
    ) -> T

    // MARK: - Observation

    func add(
        transactionObserver: TransactionObserver,
        extent: Database.TransactionObservationExtent
    )

    // MARK: - Touching

    func touch(_ interaction: TSInteraction, shouldReindex: Bool, tx: DBWriteTransaction)

    /// See note on `shouldUpdateChatListUi` parameter in docs for ``TSGroupThread.updateWithGroupModel:shouldUpdateChatListUi:transaction``.
    func touch(_ thread: TSThread, shouldReindex: Bool, shouldUpdateChatListUi: Bool, tx: DBWriteTransaction)

    func touch(_ storyMessage: StoryMessage, tx: DBWriteTransaction)
}

// MARK: - Default arguments

extension DB {
    // MARK: - Async Methods

    public func asyncRead<T>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: @escaping (ReadTransaction) -> T,
        completionQueue: DispatchQueue = .main,
        completion: ((T) -> Void)? = nil
    ) {
        asyncRead(file: file, function: function, line: line, block: block, completionQueue: completionQueue, completion: completion)
    }

    public func asyncWrite<T>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: @escaping (WriteTransaction) -> T,
        completionQueue: DispatchQueue = .main,
        completion: ((T) -> Void)? = nil
    ) {
        asyncWrite(file: file, function: function, line: line, block: block, completionQueue: completionQueue, completion: completion)
    }

    public func asyncWriteWithTxCompletion<T>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: @escaping (WriteTransaction) -> TransactionCompletion<T>,
        completionQueue: DispatchQueue = .main,
        completion: ((T) -> Void)? = nil
    ) {
        asyncWriteWithTxCompletion(file: file, function: function, line: line, block: block, completionQueue: completionQueue, completion: completion)
    }

    // MARK: - Awaitable Methods

    public func awaitableWrite<T>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: (WriteTransaction) throws -> T
    ) async rethrows -> T {
        return try await awaitableWrite(file: file, function: function, line: line, block: block)
    }

    public func awaitableWriteWithTxCompletion<T>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: (WriteTransaction) -> TransactionCompletion<T>
    ) async -> T {
        return await awaitableWriteWithTxCompletion(file: file, function: function, line: line, block: block)
    }

    // MARK: - Promises

    public func readPromise<T>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        _ block: @escaping (ReadTransaction) throws -> T
    ) -> Promise<T> {
        return readPromise(file: file, function: function, line: line, block)
    }

    public func writePromise<T>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        _ block: @escaping (WriteTransaction) throws -> T
    ) -> Promise<T> {
        return writePromise(file: file, function: function, line: line, block)
    }

    // MARK: - Value Methods

    public func read<T>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: (ReadTransaction) throws -> T
    ) rethrows -> T {
        return try read(file: file, function: function, line: line, block: block)
    }

    public func write<T>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: (WriteTransaction) throws -> T
    ) rethrows -> T {
        return try write(file: file, function: function, line: line, block: block)
    }

    public func writeWithTxCompletion<T>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: (WriteTransaction) -> TransactionCompletion<T>
    ) -> T {
        return writeWithTxCompletion(file: file, function: function, line: line, block: block)
    }

    // MARK: - Touching

    public func touch(_ thread: TSThread, shouldReindex: Bool, tx: DBWriteTransaction) {
        self.touch(thread, shouldReindex: shouldReindex, shouldUpdateChatListUi: true, tx: tx)
    }

    // MARK: - Observation

    public func add(transactionObserver: TransactionObserver) {
        self.add(transactionObserver: transactionObserver, extent: .observerLifetime)
    }
}
