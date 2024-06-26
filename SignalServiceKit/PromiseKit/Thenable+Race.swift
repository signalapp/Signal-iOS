//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public extension Thenable {
    static func race<T: Thenable>(
        on scheduler: Scheduler? = nil,
        _ thenables: T...
    ) -> Promise<T.Value> where T.Value == Value {
        race(on: scheduler, thenables)
    }

    static func race<T: Thenable>(
        on scheduler: Scheduler? = nil,
        _ thenables: [T]
    ) -> Promise<T.Value> where T.Value == Value {
        let (returnPromise, future) = Promise<T.Value>.pending()

        for thenable in thenables {
            thenable.observe(on: scheduler) { result in
                switch result {
                case .success(let result):
                    guard !future.isSealed else { return }
                    future.resolve(result)
                case .failure(let error):
                    guard !future.isSealed else { return }
                    future.reject(error)
                }
            }
        }

        return returnPromise
    }
}
