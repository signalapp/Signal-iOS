//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public func firstly<T: Thenable>(
    on scheduler: Scheduler? = nil,
    _ block: () throws -> T
) -> Promise<T.Value> {
    let (promise, future) = Promise<T.Value>.pending()
    do {
        future.resolve(on: scheduler, with: try block())
    } catch {
        future.reject(error)
    }
    return promise
}

public func firstly<T>(
    on scheduler: Scheduler? = nil,
    _ block: () -> Guarantee<T>
) -> Guarantee<T> {
    let (promise, future) = Guarantee<T>.pending()
    future.resolve(on: scheduler, with: block())
    return promise
}

public func firstly<T: Thenable>(
    on scheduler: Scheduler,
    _ block: @escaping () throws -> T
) -> Promise<T.Value> {
    let (promise, future) = Promise<T.Value>.pending()
    scheduler.asyncIfNecessary {
        do {
            future.resolve(on: scheduler, with: try block())
        } catch {
            future.reject(error)
        }
    }
    return promise
}

public func firstly<T>(on scheduler: Scheduler, _ block: @escaping () -> Guarantee<T>) -> Guarantee<T> {
    let (promise, future) = Guarantee<T>.pending()
    scheduler.asyncIfNecessary {
        future.resolve(on: scheduler, with: block())
    }
    return promise
}

public func firstly<T>(
    on scheduler: Scheduler,
    _ block: @escaping () throws -> T
) -> Promise<T> {
    let (promise, future) = Promise<T>.pending()
    scheduler.asyncIfNecessary {
        do {
            future.resolve(try block())
        } catch {
            future.reject(error)
        }
    }
    return promise
}

public func firstly<T>(
    on scheduler: Scheduler,
    _ block: @escaping () -> T
) -> Guarantee<T> {
    let (guarantee, future) = Guarantee<T>.pending()
    scheduler.asyncIfNecessary {
        future.resolve(block())
    }
    return guarantee
}
