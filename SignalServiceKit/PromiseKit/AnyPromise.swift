//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
public class AnyPromise: NSObject {
    private let (anyPromise, anyFuture) = Promise<Any>.pending()

    public convenience init<T: Thenable>(_ thenable: T) {
        self.init()

        if let promise = thenable as? Promise<T.Value> {
            promise.done { value in
                self.anyFuture.resolve(value)
            }.catch { error in
                self.anyFuture.reject(error)
            }
        } else {
            thenable.done { self.anyFuture.resolve($0) }.cauterize()
        }
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public class func promiseWithValue(_ value: Any) -> AnyPromise {
        let promise = AnyPromise()
        promise.resolve(value)
        return promise
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public class func promiseWithError(_ error: Error) -> AnyPromise {
        let promise = AnyPromise()
        promise.reject(error)
        return promise
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public class var withFuture: ((@escaping (AnyFuture) -> Void) -> AnyPromise) {
        { block in
            let promise = AnyPromise()
            block(AnyFuture(promise.anyFuture))
            return promise
        }
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public class var withFutureOn: ((DispatchQueue, @escaping (AnyFuture) -> Void) -> AnyPromise) {
        { queue, block in
            let promise = AnyPromise()
            queue.async {
                block(AnyFuture(promise.anyFuture))
            }
            return promise
        }
    }

    @objc
    public convenience init(future: (AnyFuture) -> Void) {
        self.init()
        future(AnyFuture(anyFuture))
    }

    public required override init() {
        super.init()
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public var map: ((@escaping (Any) -> Any) -> AnyPromise) {
        { AnyPromise(self.anyPromise.map($0)) }
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public var mapOn: ((DispatchQueue, @escaping (Any) -> Any) -> AnyPromise) {
        { AnyPromise(self.anyPromise.map(on: $0, $1)) }
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public var done: ((@escaping (Any) -> Void) -> AnyPromise) {
        { AnyPromise(self.anyPromise.done($0)) }
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public var doneOn: ((DispatchQueue, @escaping (Any) -> Void) -> AnyPromise) {
        { AnyPromise(self.anyPromise.done(on: $0, $1)) }
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public var doneInBackground: ((@escaping (Any) -> Void) -> AnyPromise) {
        { AnyPromise(self.anyPromise.done(on: DispatchQueue.global(), $0)) }
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public var then: ((@escaping (Any) -> AnyPromise) -> AnyPromise) {
        { block in
            AnyPromise(self.anyPromise.then { block($0).anyPromise })
        }
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public var thenOn: ((DispatchQueue, @escaping (Any) -> AnyPromise) -> AnyPromise) {
        { queue, block in
            AnyPromise(self.anyPromise.then(on: queue) { block($0).anyPromise })
        }
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public var thenInBackground: ((@escaping (Any) -> AnyPromise) -> AnyPromise) {
        { block in
            AnyPromise(self.anyPromise.then(on: DispatchQueue.global()) { block($0).anyPromise })
        }
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public var `catch`: ((@escaping (Error) -> Void) -> AnyPromise) {
        { AnyPromise(self.anyPromise.catch($0)) }
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public var catchOn: ((DispatchQueue, @escaping (Error) -> Void) -> AnyPromise) {
        { AnyPromise(self.anyPromise.catch(on: $0, $1)) }
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public var catchInBackground: ((@escaping (Error) -> Void) -> AnyPromise) {
        { AnyPromise(self.anyPromise.catch(on: DispatchQueue.global(), $0)) }
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public var ensure: ((@escaping () -> Void) -> AnyPromise) {
        { AnyPromise(self.anyPromise.ensure($0)) }
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public var ensureOn: ((DispatchQueue, @escaping () -> Void) -> AnyPromise) {
        { AnyPromise(self.anyPromise.ensure(on: $0, $1)) }
    }

    public func asVoid() -> Promise<Void> {
        anyPromise.asVoid()
    }

    public func asAny() -> Promise<Any> {
        return anyPromise
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public class func when(fulfilled promises: [AnyPromise]) -> AnyPromise {
        let when: Promise<[Any]> = Promise.when(fulfilled: promises.map { $0.anyPromise })
        return AnyPromise(when)
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public class func when(resolved promises: [AnyPromise]) -> AnyPromise {
        let (promise, future) = Promise<[Any]>.pending()
        Promise.when(resolved: promises.map { $0.anyPromise }).done { results in
            var hasFailure = false
            let values: [Any] = results.compactMap { result in
                switch result {
                case .success(let value):
                    return value
                case .failure:
                    hasFailure = true
                    return nil
                }
            }
            if hasFailure {
                future.reject(PromiseError.whenResolvedRejected)
            } else {
                future.resolve(values)
            }
        }
        return AnyPromise(promise)
    }
}

extension AnyPromise: Thenable, Catchable {

    public typealias Value = Any

    public var result: Result<Value, Error>? { anyPromise.result }

    public func observe(on queue: DispatchQueue? = nil, block: @escaping (Result<Value, Error>) -> Void) {
        anyPromise.observe(on: queue, block: block)
    }

    public func observe(on scheduler: Scheduler?, block: @escaping (Result<Value, Error>) -> Void) {
        anyPromise.observe(on: scheduler, block: block)
    }

    public func resolve(_ value: Any) {
        anyFuture.resolve(value)
    }

    public func resolve<T>(on queue: DispatchQueue? = nil, with thenable: T) where T: Thenable, Any == T.Value {
        anyFuture.resolve(on: queue, with: thenable)
    }

    public func reject(_ error: Error) {
        anyFuture.reject(error)
    }
}

@objc
public class AnyFuture: NSObject {
    private let future: Future<Any>
    required init(_ future: Future<Any>) {
        self.future = future
        super.init()
    }

    @objc
    public func resolve(value: Any) { future.resolve(value) }

    @objc
    public func reject(error: Error) { future.reject(error) }

    @objc
    public func resolveWithPromise(_ promise: AnyPromise) {
        future.resolve(with: promise)
    }

    @objc
    public func resolve(onQueue queue: DispatchQueue, withPromise promise: AnyPromise) {
        future.resolve(on: queue, with: promise)
    }
}
