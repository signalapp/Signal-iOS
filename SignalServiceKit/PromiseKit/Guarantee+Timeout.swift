//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public extension Guarantee {
    func nilTimeout(
        on scheduler: Scheduler,
        seconds: TimeInterval
    ) -> Guarantee<Value?> {
        let withOptionalValue: Guarantee<Value?> = self.map(on: scheduler) { $0 }
        return withOptionalValue.timeout(on: scheduler, seconds: seconds, substituteValue: nil)
    }

    func timeout(
        on scheduler: Scheduler,
        seconds: TimeInterval,
        substituteValue: Value
    ) -> Guarantee<Value> {
        let substitute: Guarantee<Value> = Guarantee<Void>
            .after(on: scheduler, seconds: seconds)
            .map(on: scheduler) { substituteValue }
        return Guarantee<Value>.race(on: scheduler, [self, substitute])
    }
}
