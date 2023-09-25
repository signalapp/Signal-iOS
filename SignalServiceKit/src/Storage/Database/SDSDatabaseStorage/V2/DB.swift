//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

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

    func read(
        file: String,
        function: String,
        line: Int,
        block: (DBReadTransaction) -> Void
    )

    func write(
        file: String,
        function: String,
        line: Int,
        block: (DBWriteTransaction) -> Void
    )

    // MARK: - Async Methods

    func asyncRead(
        file: String,
        function: String,
        line: Int,
        block: @escaping (DBReadTransaction) -> Void,
        completionQueue: DispatchQueue,
        completion: (() -> Void)?
    )

    func asyncWrite(
        file: String,
        function: String,
        line: Int,
        block: @escaping (DBWriteTransaction) -> Void,
        completionQueue: DispatchQueue,
        completion: (() -> Void)?
    )

    // MARK: - Awaitable Methods

    func awaitableWrite<T>(
        file: String,
        function: String,
        line: Int,
        block: @escaping (DBWriteTransaction) throws -> T
    ) async rethrows -> T

    // MARK: - Promises

    func readPromise(
        file: String,
        function: String,
        line: Int,
        _ block: @escaping (DBReadTransaction) -> Void
    ) -> AnyPromise

    func readPromise<T>(
        file: String,
        function: String,
        line: Int,
        _ block: @escaping (DBReadTransaction) -> T
    ) -> Promise<T>

    // throws version
    func readPromise<T>(
        file: String,
        function: String,
        line: Int,
        _ block: @escaping (DBReadTransaction) throws -> T
    ) -> Promise<T>

    func writePromise(
        file: String,
        function: String,
        line: Int,
        _ block: @escaping (DBWriteTransaction) -> Void
    ) -> AnyPromise

    func writePromise<T>(
        file: String,
        function: String,
        line: Int,
        _ block: @escaping (DBWriteTransaction) -> T
    ) -> Promise<T>

    // throws version
    func writePromise<T>(
        file: String,
        function: String,
        line: Int,
        _ block: @escaping (DBWriteTransaction) throws -> T
    ) -> Promise<T>

    // MARK: - Value Methods

    func read<T>(
        file: String,
        function: String,
        line: Int,
        block: (DBReadTransaction) throws -> T
    ) rethrows -> T

    func write<T>(
        file: String,
        function: String,
        line: Int,
        block: (DBWriteTransaction) throws -> T
    ) rethrows -> T
}

// MARK: - Default arguments

extension DB {
    public func read(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: (DBReadTransaction) -> Void
    ) {
        read(file: file, function: function, line: line, block: block)
    }

    public func write(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: (DBWriteTransaction) -> Void
    ) {
        write(file: file, function: function, line: line, block: block)
    }

    // MARK: - Async Methods

    public func asyncRead(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: @escaping (DBReadTransaction) -> Void,
        completionQueue: DispatchQueue = .main,
        completion: (() -> Void)? = nil
    ) {
        asyncRead(file: file, function: function, line: line, block: block, completionQueue: completionQueue, completion: completion)
    }

    public func asyncWrite(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: @escaping (DBWriteTransaction) -> Void,
        completionQueue: DispatchQueue = .main,
        completion: (() -> Void)? = nil
    ) {
        asyncWrite(file: file, function: function, line: line, block: block, completionQueue: completionQueue, completion: completion)
    }

    // MARK: - Awaitable Methods

    func awaitableWrite<T>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: @escaping (DBWriteTransaction) throws -> T
    ) async rethrows -> T {
        return try await awaitableWrite(file: file, function: function, line: line, block: block)
    }

    // MARK: - Promises

    public func readPromise(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        _ block: @escaping (DBReadTransaction) -> Void
    ) -> AnyPromise {
        return readPromise(file: file, function: function, line: line, block)
    }

    public func readPromise<T>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        _ block: @escaping (DBReadTransaction) -> T
    ) -> Promise<T> {
        return readPromise(file: file, function: function, line: line, block)
    }

    // throws version
    public func readPromise<T>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        _ block: @escaping (DBReadTransaction) throws -> T
    ) -> Promise<T> {
        return readPromise(file: file, function: function, line: line, block)
    }

    public func writePromise(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        _ block: @escaping (DBWriteTransaction) -> Void
    ) -> AnyPromise {
        return writePromise(file: file, function: function, line: line, block)
    }

    public func writePromise<T>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        _ block: @escaping (DBWriteTransaction) -> T
    ) -> Promise<T> {
        return writePromise(file: file, function: function, line: line, block)
    }

    // throws version
    public func writePromise<T>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        _ block: @escaping (DBWriteTransaction) throws -> T
    ) -> Promise<T> {
        return writePromise(file: file, function: function, line: line, block)
    }

    // MARK: - Value Methods

    public func read<T>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: (DBReadTransaction) throws -> T
    ) rethrows -> T {
        return try read(file: file, function: function, line: line, block: block)
    }

    public func write<T>(
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: (DBWriteTransaction) throws -> T
    ) rethrows -> T {
        return try write(file: file, function: function, line: line, block: block)
    }
}
