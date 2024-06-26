//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol Thenable: AnyObject {
    associatedtype Value
    var result: Result<Value, Error>? { get }
    init()
    func observe(on scheduler: Scheduler?, block: @escaping (Result<Value, Error>) -> Void)
}

public extension Thenable {
    func map<T>(
        on scheduler: Scheduler? = nil,
        _ block: @escaping (Value) throws -> T
    ) -> Promise<T> {
        observe(on: scheduler, block: block)
    }

    func done(
        on queue: Scheduler? = nil,
        _ block: @escaping (Value) throws -> Void
    ) -> Promise<Void> {
        observe(on: queue, block: block)
    }

    func then<T: Thenable>(
        on scheduler: Scheduler? = nil,
        _ block: @escaping (Value) throws -> T
    ) -> Promise<T.Value> {
        let (promise, future) = Promise<T.Value>.pending()
        observe(on: scheduler) { result in
            do {
                switch result {
                case .success(let value):
                    future.resolve(on: scheduler, with: try block(value))
                case .failure(let error):
                    future.reject(error)
                }
            } catch {
                future.reject(error)
            }
        }
        return promise
    }

    var value: Value? {
        guard case .success(let value) = result else { return nil }
        return value
    }

    func asVoid(
        on scheduler: Scheduler? = nil
    ) -> Promise<Void> {
        map(on: scheduler) { _ in }
    }
}

fileprivate extension Thenable {
    func observe<T>(
        on scheduler: Scheduler?,
        block: @escaping (Value) throws -> T
    ) -> Promise<T> {
        let (promise, future) = Promise<T>.pending()
        observe(on: scheduler) { result in
            do {
                switch result {
                case .success(let value):
                    future.resolve(try block(value))
                case .failure(let error):
                    future.reject(error)
                }
            } catch {
                future.reject(error)
            }
        }
        return promise
    }
}
