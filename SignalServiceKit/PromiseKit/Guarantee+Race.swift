//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public extension Guarantee {
    static func race<T>(
        on scheduler: Scheduler,
        _ guarantees: Guarantee<T>...
    ) -> Guarantee<T> {
        return race(on: scheduler, guarantees)
    }

    static func race<T>(
        on scheduler: Scheduler,
        _ guarantees: [Guarantee<T>]
    ) -> Guarantee<T> {
        let (result, future) = Guarantee<T>.pending()

        for guarantee in guarantees {
            guarantee.done(on: scheduler) { result in
                guard !future.isSealed else { return }
                future.resolve(result)
            }
        }

        return result
    }
}
