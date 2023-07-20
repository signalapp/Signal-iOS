//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// TODO: [DBV2] Ideally, these would live in a test target.
//
// The types in here are used in both SignalServiceKitTests and SignalTests,
// and we want to share them across the two. Unfortunately, that means they
// cannot live in SignalServiceKitTests. In the future, we should add a
// separate target (e.g., "SignalTestMocks") that encompasses classes that we
// want to share across our various test targets.

#if TESTABLE_BUILD

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

    struct AsyncCompletion {
        let scheduler: Scheduler
        let block: () -> Void
    }

    var asyncCompletions = [AsyncCompletion]()

    func addAsyncCompletion(on scheduler: Scheduler, _ block: @escaping () -> Void) {
        asyncCompletions.append(AsyncCompletion(scheduler: scheduler, block: block))
    }
}

/// Mock database which does literally nothing.
/// It creates mock transaction objects which do...nothing.
/// It is expected (indeed, required) that classes under test that use DB
/// will stub out _every_ dependency that unwraps the db transactions and
/// just blindly pass the ones created by this class around.
public class MockDB: DB {

    private let queue: Scheduler

    public convenience init() {
        self.init(schedulers: DispatchQueueSchedulers())
    }

    public init(schedulers: Schedulers) {
        self.queue = schedulers.queue(label: "mockDB")
    }

    private var openTransaction: DBReadTransaction?

    private func makeRead() -> MockReadTransaction {
        guard openTransaction == nil else {
            fatalError("Re-entrant transaction opened")
        }
        let tx = MockReadTransaction()
        openTransaction = tx
        return tx
    }

    private func makeWrite() -> MockWriteTransaction {
        guard openTransaction == nil else {
            fatalError("Re-entrant transaction opened")
        }
        let tx = MockWriteTransaction()
        openTransaction = tx
        return tx
    }

    private func closeTransaction() {
        guard openTransaction != nil else {
            fatalError("Closing transaction with none open")
        }
        if let oldValue = openTransaction as? MockWriteTransaction {
            oldValue.asyncCompletions.forEach {
                $0.scheduler.async($0.block)
            }
        }
        openTransaction = nil
    }

    public func read(
        file: String,
        function: String,
        line: Int,
        block: (DBReadTransaction) -> Void
    ) {
        queue.sync {
            block(self.makeRead())
            self.closeTransaction()
        }
    }

    public func write(
        file: String,
        function: String,
        line: Int,
        block: (DBWriteTransaction) -> Void
    ) {
        queue.sync {
            block(self.makeWrite())
            self.closeTransaction()
        }
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
        queue.sync {
            block(self.makeRead())
            self.closeTransaction()
            guard let completion = completion else {
                return
            }
            completionQueue.sync {
                completion()
            }
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
        queue.sync {
            block(self.makeWrite())
            self.closeTransaction()
            guard let completion = completion else {
                return
            }
            completionQueue.sync {
                completion()
            }
        }
    }

    // MARK: - Promises

    public func readPromise(
        file: String,
        function: String,
        line: Int,
        _ block: @escaping (DBReadTransaction) -> Void
    ) -> AnyPromise {
        queue.sync {
            block(self.makeRead())
            self.closeTransaction()
        }
        return AnyPromise(Promise<Void>.value(()))
    }

    public func readPromise<T>(
        file: String,
        function: String,
        line: Int,
        _ block: @escaping (DBReadTransaction) -> T
    ) -> Promise<T> {
        let t = queue.sync {
            let t = block(self.makeRead())
            self.closeTransaction()
            return t
        }
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
            let t = try queue.sync {
                let t = try block(self.makeRead())
                self.closeTransaction()
                return t
            }
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
        queue.sync {
            block(self.makeWrite())
            self.closeTransaction()
        }
        return AnyPromise(Promise<Void>.value(()))
    }

    public func writePromise<T>(
        file: String,
        function: String,
        line: Int,
        _ block: @escaping (DBWriteTransaction) -> T
    ) -> Promise<T> {
        let t = queue.sync {
            let t = block(self.makeWrite())
            self.closeTransaction()
            return t
        }
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
            let t = try queue.sync {
                let t = try block(self.makeWrite())
                self.closeTransaction()
                return t
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
        block: (DBReadTransaction) -> T
    ) -> T {
        return queue.sync {
            let t = block(self.makeRead())
            self.closeTransaction()
            return t
        }
    }

    // throws version
    public func read<T>(
        file: String,
        function: String,
        line: Int,
        block: (DBReadTransaction) throws -> T
    ) throws -> T {
        return try queue.sync {
            let t = try block(self.makeRead())
            self.closeTransaction()
            return t
        }
    }

    public func write<T>(
        file: String,
        function: String,
        line: Int,
        block: (DBWriteTransaction) -> T
    ) -> T {
        return queue.sync {
            let t = block(self.makeWrite())
            self.closeTransaction()
            return t
        }
    }

    // throws version
    public func write<T>(
        file: String,
        function: String,
        line: Int,
        block: (DBWriteTransaction) throws -> T
    ) throws -> T {
        return try queue.sync {
            let t = try block(self.makeWrite())
            self.closeTransaction()
            return t
        }
    }
}

#endif
