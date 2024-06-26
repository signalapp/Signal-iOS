//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public extension Thenable {
    func nilTimeout(
        on scheduler: Scheduler? = nil,
        seconds: TimeInterval
    ) -> Promise<Value?> {
        let timeout: Promise<Value?> = Guarantee.after(on: scheduler, seconds: seconds).asPromise().map(on: scheduler) { nil }

        return Promise.race([
            map(on: scheduler) { (a: Value?) -> (Value?, Bool) in
                (a, false)
            },
            timeout.map(on: scheduler) { (a: Value?) -> (Value?, Bool) in
                (a, true)
            }
        ]).map(on: scheduler) { result, didTimeout in
            if didTimeout {
                Logger.info("Timed out, returning nil value.")
            }
            return result
        }
    }

    func timeout(
        on scheduler: Scheduler? = nil,
        seconds: TimeInterval,
        substituteValue: Value
    ) -> Promise<Value> {
        let timeout: Promise<Value> = Guarantee.after(on: scheduler, seconds: seconds).asPromise().map(on: scheduler) {
            return substituteValue
        }

        return Promise.race([
            map(on: scheduler) { ($0, false) },
            timeout.map(on: scheduler) { ($0, true) }
        ]).map(on: scheduler) { result, didTimeout in
            if didTimeout {
                Logger.info("Timed out, returning substitute value.")
            }
            return result
        }
    }
}

public extension Promise {
    func timeout(
        on scheduler: Scheduler? = nil,
        seconds: TimeInterval,
        ticksWhileSuspended: Bool = false,
        description: String? = nil,
        timeoutErrorBlock: @escaping () -> Error
    ) -> Promise<Value> {
        let timeout: Promise<Value>
        if ticksWhileSuspended {
            timeout = Guarantee.after(on: scheduler, wallInterval: seconds)
                .asPromise()
                .map(on: scheduler) { throw TimeoutError.wallTimeout }
        } else {
            timeout = Guarantee.after(on: scheduler, seconds: seconds)
                .asPromise()
                .map(on: scheduler) { throw TimeoutError.relativeTimeout }
        }

        return Promise.race(on: scheduler, [self, timeout]).recover(on: scheduler) { error -> Promise<Value> in
            switch error {
            case is TimeoutError:
                let underlyingError = timeoutErrorBlock()
                let prefix: String
                if let description = description {
                    prefix = "\(description) timed out:"
                } else {
                    prefix = "Timed out:"
                }
                Logger.info("\(prefix): \(error). Resolving promise with underlying error: \(underlyingError)")
                return Promise(error: underlyingError)
            default:
                return Promise(error: error)
            }
        }
    }
}

enum TimeoutError: Error {
    case wallTimeout
    case relativeTimeout
}

public extension Thenable where Value == Void {
    func timeout(
        on scheduler: Scheduler? = nil,
        seconds: TimeInterval
    ) -> Promise<Void> {
        return timeout(on: scheduler, seconds: seconds, substituteValue: ())
    }
}
