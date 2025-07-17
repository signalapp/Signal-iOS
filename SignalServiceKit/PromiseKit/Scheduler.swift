//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Protocol-ization of DispatchQueue which allows different
/// scheduling behaviors, particularly in the context of tests.
/// In production code usage, DispatchQueues _are_ schedulers
/// and should be used directly as such.
public protocol Scheduler {

    func async(_ work: @escaping () -> Void)

    func sync(_ work: () -> Void)

    func sync<T>(_ work: () -> T) -> T

    func sync<T>(_ work: () throws -> T) rethrows -> T

    func asyncAfter(deadline: DispatchTime, _ work: @escaping () -> Void)

    func asyncAfter(wallDeadline: DispatchWallTime, _ work: @escaping () -> Void)

    func asyncIfNecessary(execute work: @escaping () -> Void)
}

public extension Scheduler {

    func async<T>(_ namespace: PromiseNamespace, execute work: @escaping () -> T) -> Guarantee<T> {
        let (guarantee, future) = Guarantee<T>.pending()
        async {
            future.resolve(work())
        }
        return guarantee
    }

    func async<T>(_ namespace: PromiseNamespace, execute work: @escaping () throws -> T) -> Promise<T> {
        let (promise, future) = Promise<T>.pending()
        async {
            do {
                future.resolve(try work())
            } catch {
                future.reject(error)
            }
        }
        return promise
    }
}
