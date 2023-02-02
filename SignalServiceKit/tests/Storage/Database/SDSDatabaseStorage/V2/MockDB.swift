//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
@testable import SignalServiceKit

/// Mock implementation of `DBReadTransaction`.
/// Empty stub that does nothing, serves only to crash and fail tests if
/// it is ever attempted to be unwrapped as a real SDS transaction.
private class MockReadTransaction: DBReadTransaction {
    init() {}
}

/// Mock implementation of `DBWriteTransaction`.
/// Empty stub that does nothing, serves only to crash and fail tests if
/// it is ever attempted to be unwrapped as a real SDS transaction.
private class MockWriteTransaction: DBWriteTransaction {
    init() {}
}

/// Mock database which does literally nothing.
/// It creates mock transaction objects which do...nothing.
/// It is expected (indeed, required) that classes under test that use DB
/// will stub out _every_ dependency that unwraps the db transactions and
/// just blindly pass the ones created by this class around.
public class MockDB: DB {

    public init() {}

    public func read(
        file: String,
        function: String,
        line: Int,
        block: (DBReadTransaction) -> Void
    ) {
        block(MockReadTransaction())
    }

    public func write(
        file: String,
        function: String,
        line: Int,
        block: (DBWriteTransaction) -> Void
    ) {
        block(MockWriteTransaction())
    }

    // MARK: - Async Methods

    public func asyncRead(
        file: String,
        function: String,
        line: Int,
        block: @escaping (DBReadTransaction) -> Void,
        completionQueue: DispatchQueue,
        completion: (() -> Void)?
    ) {
        block(MockReadTransaction())
        guard let completion = completion else {
             return
        }
        completionQueue.async {
            completion()
        }
    }

    public func asyncWrite(
        file: String,
        function: String,
        line: Int,
        block: @escaping (DBWriteTransaction) -> Void,
        completionQueue: DispatchQueue,
        completion: (() -> Void)?
    ) {
        block(MockWriteTransaction())
        guard let completion = completion else {
             return
        }
        completionQueue.async {
            completion()
        }
    }

    // MARK: - Promises

    public func readPromise(
        file: String,
        function: String,
        line: Int,
        _ block: @escaping (DBReadTransaction) -> Void
    ) -> AnyPromise {
        block(MockReadTransaction())
        return AnyPromise(Promise<Void>.value(()))
    }

    public func readPromise<T>(
        file: String,
        function: String,
        line: Int,
        _ block: @escaping (DBReadTransaction) -> T
    ) -> Promise<T> {
        let t = block(MockWriteTransaction())
        return Promise<T>.value(t)
    }

    // throws version
    public func readPromise<T>(
        file: String,
        function: String,
        line: Int,
        _ block: @escaping (DBReadTransaction) throws -> T
    ) -> Promise<T> {
        do {
            let t = try block(MockReadTransaction())
            return Promise<T>.value(t)
        } catch {
            return Promise<T>.init(error: error)
        }
    }

    public func writePromise(
        file: String,
        function: String,
        line: Int,
        _ block: @escaping (DBWriteTransaction) -> Void
    ) -> AnyPromise {
        block(MockWriteTransaction())
        return AnyPromise(Promise<Void>.value(()))
    }

    public func writePromise<T>(
        file: String,
        function: String,
        line: Int,
        _ block: @escaping (DBWriteTransaction) -> T
    ) -> Promise<T> {
        let t = block(MockWriteTransaction())
        return Promise<T>.value(t)
    }

    // throws version
    public func writePromise<T>(
        file: String,
        function: String,
        line: Int,
        _ block: @escaping (DBWriteTransaction) throws -> T
    ) -> Promise<T> {
        do {
            let t = try block(MockWriteTransaction())
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
        block: (DBReadTransaction) -> T
    ) -> T {
        return block(MockReadTransaction())
    }

    // throws version
    public func read<T>(
        file: String,
        function: String,
        line: Int,
        block: (DBReadTransaction) throws -> T
    ) throws -> T {
        return try block(MockReadTransaction())
    }

    public func write<T>(
        file: String,
        function: String,
        line: Int,
        block: (DBWriteTransaction) -> T
    ) -> T {
        return block(MockWriteTransaction())
    }

    // throws version
    public func write<T>(
        file: String,
        function: String,
        line: Int,
        block: (DBWriteTransaction) throws -> T
    ) throws -> T {
        return try block(MockWriteTransaction())
    }
}
