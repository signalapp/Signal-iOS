//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol Catchable: Thenable {}

public extension Catchable {
    @discardableResult
    func `catch`(
        on scheduler: Scheduler? = nil,
        _ block: @escaping (Error) -> Void
    ) -> Promise<Void> {
        observe(on: scheduler, successBlock: { _ in }, failureBlock: block)
    }

    @discardableResult
    func recover(
        on scheduler: Scheduler? = nil,
        _ block: @escaping (Error) -> Guarantee<Value>
    ) -> Guarantee<Value> {
        observe(on: scheduler, successBlock: { $0 }, failureBlock: block)
    }

    func recover<T: Thenable>(
        on scheduler: Scheduler? = nil,
        _ block: @escaping (Error) throws -> T
    ) -> Promise<Value> where T.Value == Value {
        observe(on: scheduler, successBlock: { $0 }, failureBlock: block)
    }

    func ensure(
        on scheduler: Scheduler? = nil,
        _ block: @escaping () -> Void
    ) -> Promise<Value> {
        observe(on: scheduler) { value in
            block()
            return value
        } failureBlock: { _ in
            block()
        }
    }

    @discardableResult
    func cauterize() -> Self { self }

    func asVoid() -> Promise<Void> { map { _ in } }
}

fileprivate extension Thenable where Self: Catchable {
    func observe<T>(
        on scheduler: Scheduler?,
        successBlock: @escaping (Value) throws -> T,
        failureBlock: @escaping (Error) throws -> Void = { _ in }
    ) -> Promise<T> {
        let (promise, future) = Promise<T>.pending()
        observe(on: scheduler) { result in
            do {
                switch result {
                case .success(let value):
                    future.resolve(try successBlock(value))
                case .failure(let error):
                    try failureBlock(error)
                    future.reject(error)
                }
            } catch {
                future.reject(error)
            }
        }
        return promise
    }

    func observe(
        on scheduler: Scheduler?,
        successBlock: @escaping (Value) -> Value,
        failureBlock: @escaping (Error) -> Value
    ) -> Guarantee<Value> {
        let (guarantee, future) = Guarantee<Value>.pending()
        observe(on: scheduler) { result in
            switch result {
            case .success(let value):
                future.resolve(successBlock(value))
            case .failure(let error):
                future.resolve(failureBlock(error))
            }
        }
        return guarantee
    }

    func observe(
        on scheduler: Scheduler?,
        successBlock: @escaping (Value) -> Value,
        failureBlock: @escaping (Error) -> Guarantee<Value>
    ) -> Guarantee<Value> {
        let (guarantee, future) = Guarantee<Value>.pending()
        observe(on: scheduler) { result in
            switch result {
            case .success(let value):
                future.resolve(successBlock(value))
            case .failure(let error):
                future.resolve(on: scheduler, with: failureBlock(error))
            }
        }
        return guarantee
    }

    func observe(
        on scheduler: Scheduler?,
        successBlock: @escaping (Value) throws -> Value,
        failureBlock: @escaping (Error) throws -> Value
    ) -> Promise<Value> {
        let (promise, future) = Promise<Value>.pending()
        observe(on: scheduler) { result in
            do {
                switch result {
                case .success(let value):
                    future.resolve(try successBlock(value))
                case .failure(let error):
                    future.resolve(try failureBlock(error))
                }
            } catch {
                future.reject(error)
            }
        }
        return promise
    }

    func observe<T: Thenable>(
        on scheduler: Scheduler?,
        successBlock: @escaping (Value) throws -> Value,
        failureBlock: @escaping (Error) throws -> T
    ) -> Promise<Value> where T.Value == Value {
        let (promise, future) = Promise<Value>.pending()
        observe(on: scheduler) { result in
            do {
                switch result {
                case .success(let value):
                    future.resolve(try successBlock(value))
                case .failure(let error):
                    future.resolve(on: scheduler, with: try failureBlock(error))
                }
            } catch {
                future.reject(error)
            }
        }
        return promise
    }
}

public extension Catchable where Value == Void {
    @discardableResult
    func recover(
        on scheduler: Scheduler? = nil,
        _ block: @escaping (Error) -> Void
    ) -> Guarantee<Void> {
        observe(on: scheduler, successBlock: { $0 }, failureBlock: block)
    }

    func recover(
        on scheduler: Scheduler? = nil,
        _ block: @escaping (Error) throws -> Void
    ) -> Promise<Void> {
        observe(on: scheduler, successBlock: { $0 }, failureBlock: block)
    }
}
