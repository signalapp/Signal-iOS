//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// MARK: - Fulfilled

public extension Thenable {
    static func when<T: Thenable>(
        on scheduler: Scheduler? = nil,
        fulfilled thenables: [T]
    ) -> Promise<[Value]> where T.Value == Value {
        _when(on: scheduler, fulfilled: thenables).map(on: scheduler) { thenables.compactMap { $0.value } }
    }

    static func when<T: Thenable, U: Thenable>(
        on scheduler: Scheduler? = nil,
        fulfilled tt: T,
        _ tu: U
    ) -> Promise<(T.Value, U.Value)> where T.Value == Value {
        Guarantee<Any>._when(on: scheduler, fulfilled: [
            tt.asVoid(on: scheduler), tu.asVoid(on: scheduler)
        ]).map(on: scheduler) { (tt.value!, tu.value!) }
    }

    static func when<T: Thenable, U: Thenable, V: Thenable>(
        on scheduler: Scheduler? = nil,
        fulfilled tt: T,
        _ tu: U,
        _ tv: V
    ) -> Promise<(T.Value, U.Value, V.Value)> where T.Value == Value {
        Guarantee<Any>._when(on: scheduler, fulfilled: [
            tt.asVoid(on: scheduler), tu.asVoid(on: scheduler), tv.asVoid(on: scheduler)
        ]).map(on: scheduler) { (tt.value!, tu.value!, tv.value!) }
    }

    static func when<T: Thenable, U: Thenable, V: Thenable, W: Thenable>(
        on scheduler: Scheduler? = nil,
        fulfilled tt: T,
        _ tu: U,
        _ tv: V,
        _ tw: W
    ) -> Promise<(T.Value, U.Value, V.Value, W.Value)> where T.Value == Value {
        Guarantee<Any>._when(on: scheduler, fulfilled: [
            tt.asVoid(on: scheduler), tu.asVoid(on: scheduler), tv.asVoid(on: scheduler), tw.asVoid(on: scheduler)
        ]).map(on: scheduler) { (tt.value!, tu.value!, tv.value!, tw.value!) }
    }
}

public extension Thenable where Value == Void {
    static func when<T: Thenable>(
        on scheduler: Scheduler? = nil,
        fulfilled thenables: T...
    ) -> Promise<Void> {
        _when(on: scheduler, fulfilled: thenables)
    }

    static func when<T: Thenable>(
        on scheduler: Scheduler? = nil,
        fulfilled thenables: [T]
    ) -> Promise<Void> {
        _when(on: scheduler, fulfilled: thenables)
    }
}

fileprivate extension Thenable {
    static func _when<T: Thenable>(
        on scheduler: Scheduler?,
        fulfilled thenables: [T]
    ) -> Promise<Void> {
        guard !thenables.isEmpty else { return Promise.value(()) }

        let (returnPromise, future) = Promise<Void>.pending()

        let remainingCount = AtomicValue<Int>(thenables.count, lock: .init())

        for thenable in thenables {
            thenable.observe(on: scheduler) { result in
                switch result {
                case .success:
                    if remainingCount.update(block: { $0 -= 1; return $0 }) == 0 {
                        future.resolve()
                    }
                case .failure(let error):
                    future.reject(error)
                }
            }
        }

        return returnPromise
    }
}

// MARK: - Resolved

public extension Thenable {
    static func when<T: Thenable>(
        on scheduler: Scheduler? = nil,
        resolved thenables: T...
    ) -> Guarantee<[Result<Value, Error>]> where T.Value == Value {
        when(on: scheduler, resolved: thenables)
    }

    static func when<T: Thenable>(
        on scheduler: Scheduler? = nil,
        resolved thenables: [T]
    ) -> Guarantee<[Result<Value, Error>]> where T.Value == Value {
        _when(on: scheduler, resolved: thenables).map(on: scheduler) { thenables.compactMap { $0.result } }
    }
}

public extension Thenable where Value == Void {

}

fileprivate extension Thenable {
    static func _when<T: Thenable>(
        on scheduler: Scheduler?,
        resolved thenables: [T]
    ) -> Guarantee<Void> {
        guard !thenables.isEmpty else { return Guarantee.value(()) }

        let (returnGuarantee, future) = Guarantee<Void>.pending()

        let remainingCount = AtomicValue<Int>(thenables.count, lock: .init())

        for thenable in thenables {
            thenable.observe(on: scheduler) { _ in
                if remainingCount.update(block: { $0 -= 1; return $0 }) == 0 {
                    future.resolve()
                }
            }
        }

        return returnGuarantee
    }
}
