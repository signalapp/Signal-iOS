//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum PromiseError: String, Error {
    case cancelled
    case whenResolvedRejected
}

public final class Promise<Value>: Thenable, Catchable {
    private let future: Future<Value>
    public var result: Result<Value, Error>? { future.result }
    public var isSealed: Bool { future.isSealed }

    public init(future: Future<Value> = Future()) {
        self.future = future
    }

    public convenience init() {
        self.init(future: Future())
    }

    public static func value(_ value: Value) -> Self {
        let promise = Self()
        promise.future.resolve(value)
        return promise
    }

    public convenience init(error: Error) {
        self.init(future: Future(error: error))
    }

    public convenience init(
        _ block: (Future<Value>) throws -> Void
    ) {
        self.init()
        do {
            try block(self.future)
        } catch {
            self.future.reject(error)
        }
    }

    public convenience init(
        on scheduler: Scheduler,
        _ block: @escaping (Future<Value>) throws -> Void
    ) {
        self.init()
        scheduler.asyncIfNecessary {
            do {
                try block(self.future)
            } catch {
                self.future.reject(error)
            }
        }
    }

    public func observe(on scheduler: Scheduler? = nil, block: @escaping (Result<Value, Error>) -> Void) {
        future.observe(on: scheduler, block: block)
    }
}

public extension Promise {
    func wait() throws -> Value {
        var result = future.result

        if result == nil {
            let group = DispatchGroup()
            group.enter()
            observe(on: DispatchQueue.global()) { result = $0; group.leave() }
            group.wait()
        }

        switch result! {
        case .success(let value):
            return value
        case .failure(let error):
            throw error
        }
    }
}

extension Promise {
    /// Wraps a Swift Concurrency async function in a Promise.
    ///
    /// The Task is created with the default arguments. To configure the task's
    /// priority, the caller should create its own Promise instance.
    public static func wrapAsync(_ block: @escaping () async throws -> Value) -> Self {
        let promise = Self()
        Task {
            do {
                promise.future.resolve(try await block())
            } catch {
                promise.future.reject(error)
            }
        }
        return promise
    }

    /// Converts a Promise to a Swift Concurrency async function.
    public func awaitable() async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            self.observe(on: SyncScheduler()) { result in
                continuation.resume(with: result)
            }
        }
    }
}

public extension Promise {
    class func pending() -> (Promise<Value>, Future<Value>) {
        let promise = Promise<Value>()
        return (promise, promise.future)
    }
}

public extension Guarantee {
    func asPromise() -> Promise<Value> {
        let (promise, future) = Promise<Value>.pending()
        observe { result in
            switch result {
            case .success(let value):
                future.resolve(value)
            case .failure(let error):
                owsFail("Unexpectedly received error result from unfailable promise \(error)")
            }
        }
        return promise
    }
}
