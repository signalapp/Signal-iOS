//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public final class Future<Value> {
    public typealias ResultType = Swift.Result<Value, Error>

    private let lock = UnfairLock()
    private var resultUnsynchronized: ResultType?
    private var observersUnsynchronized = [(ResultType) -> Void]()

    public init() {}

    public convenience init(value: Value) {
        self.init()
        self.resultUnsynchronized = .success(value)
    }

    public convenience init(error: Error) {
        self.init()
        self.resultUnsynchronized = .failure(error)
    }

    public func observe(on scheduler: Scheduler? = nil, block: @escaping (ResultType) -> Void) {
        lock.withLock {
            func execute(_ result: ResultType) {
                // If a scheduler is not specified, try and run on the main
                // queue. Eventually we'll want to switch this default,
                // but for now it matches the behavior we expect from
                // PromiseKit.
                (scheduler ?? DispatchQueue.main).asyncIfNecessary {
                    block(result)
                }
            }

            if let result = resultUnsynchronized {
                execute(result)
                return
            }
            observersUnsynchronized.append(execute)
        }
    }
    private func sealResult(_ result: ResultType) {
        let observers: [(ResultType) -> Void] = lock.withLock {
            guard self.resultUnsynchronized == nil else { return [] }
            self.resultUnsynchronized = result

            let observers = observersUnsynchronized
            observersUnsynchronized.removeAll()
            return observers
        }

        observers.forEach { $0(result) }
    }

    public func resolve(_ value: Value) {
        sealResult(.success(value))
    }

    public func resolve<T: Thenable>(
        on scheduler: Scheduler? = nil,
        with thenable: T
    ) where T.Value == Value {
        thenable.done(on: scheduler) { value in
            self.sealResult(.success(value))
        }.catch(on: scheduler) { error in
            self.sealResult(.failure(error))
        }
    }

    public func reject(_ error: Error) {
        sealResult(.failure(error))
    }

    public var result: ResultType? {
        return lock.withLock { self.resultUnsynchronized }
    }

    public var isSealed: Bool {
        return lock.withLock { self.resultUnsynchronized != nil }
    }
}

public extension Future where Value == Void {
    func resolve() { resolve(()) }
}
