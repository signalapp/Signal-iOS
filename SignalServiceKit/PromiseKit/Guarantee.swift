//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public final class Guarantee<Value>: Thenable {
    private let future = Future<Value>()
    public var result: Result<Value, Error>? { future.result }
    public var isSealed: Bool { future.isSealed }

    public static func pending() -> (Guarantee<Value>, GuaranteeFuture<Value>) {
        let guarantee = Guarantee<Value>()
        return (guarantee, GuaranteeFuture(future: guarantee.future))
    }

    public init() {}

    public static func value(_ value: Value) -> Self {
        let guarantee = Self()
        guarantee.future.resolve(value)
        return guarantee
    }

    public convenience init(
        _ block: (@escaping (Value) -> Void) -> Void
    ) {
        self.init()
        block { self.future.resolve($0) }
    }

    public convenience init(
        on scheduler: Scheduler,
        _ block: @escaping (@escaping (Value) -> Void) -> Void
    ) {
        self.init()
        scheduler.asyncIfNecessary { block { self.future.resolve($0) } }
    }

    public func observe(on scheduler: Scheduler? = nil, block: @escaping (Result<Value, Error>) -> Void) {
        future.observe(on: scheduler, block: block)
    }
}

public extension Guarantee {
    func wait() -> Value {
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
            owsFail("Unexpectedly received error result from unfailable promise \(error)")
        }
    }

    func asVoid() -> Guarantee<Void> { map { _ in } }
}

extension Guarantee {
    /// Wraps a Swift Concurrency async function in a Guarantee.
    ///
    /// The Task is created with the default arguments. To configure the task's
    /// priority, the caller should create its own Guarantee instance.
    public static func wrapAsync(_ block: @escaping () async -> Value) -> Self {
        let guarantee = Self()
        Task {
            guarantee.future.resolve(await block())
        }
        return guarantee
    }

    /// Converts a Guarantee to a Swift Concurrency async function.
    public func awaitable() async -> Value {
        await withCheckedContinuation { continuation in
            observe(on: SyncScheduler()) { result in
                switch result {
                case .success(let value):
                    continuation.resume(returning: value)
                case .failure(let error):
                    owsFail("Unexpectedly received error result from unfailable promise \(error)")
                }
            }
        }
    }
}

public extension Guarantee {
    func map<T>(
        on scheduler: Scheduler? = nil,
        _ block: @escaping (Value) -> T
    ) -> Guarantee<T> {
        observe(on: scheduler, block: block)
    }

    @discardableResult
    func done(
        on scheduler: Scheduler? = nil,
        _ block: @escaping (Value) -> Void
    ) -> Guarantee<Void> {
        observe(on: scheduler, block: block)
    }

    @discardableResult
    func then<T>(
        on scheduler: Scheduler? = nil,
        _ block: @escaping (Value) -> Guarantee<T>
    ) -> Guarantee<T> {
        observe(on: scheduler, block: block)
    }
}

fileprivate extension Guarantee {
    func observe<T>(
        on scheduler: Scheduler? = nil,
        block: @escaping (Value) -> T
    ) -> Guarantee<T> {
        let (guarantee, future) = Guarantee<T>.pending()
        observe(on: scheduler) { result in
            switch result {
            case .success(let value):
                future.resolve(block(value))
            case .failure(let error):
                owsFail("Unexpectedly received error result from unfailable promise \(error)")
            }
        }
        return guarantee
    }

    func observe<T>(
        on scheduler: Scheduler? = nil,
        block: @escaping (Value) -> Guarantee<T>
    ) -> Guarantee<T> {
        let (guarantee, future) = Guarantee<T>.pending()
        observe(on: scheduler) { result in
            switch result {
            case .success(let value):
                future.resolve(on: scheduler, with: block(value))
            case .failure(let error):
                owsFail("Unexpectedly received error result from unfailable promise \(error)")
            }
        }
        return guarantee
    }
}

public struct GuaranteeFuture<Value> {
    private let future: Future<Value>
    fileprivate init(future: Future<Value>) { self.future = future }
    public var isSealed: Bool { future.isSealed }
    public func resolve(_ value: Value) { future.resolve(value) }
    public func resolve<T: Thenable>(on scheduler: Scheduler? = nil, with thenable: T) where T.Value == Value {
        future.resolve(on: scheduler, with: thenable)
    }
}

public extension GuaranteeFuture where Value == Void {
    func resolve() { resolve(()) }
}
