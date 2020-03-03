//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import PromiseKit

public extension Promise {
    func nilTimeout(seconds: TimeInterval) -> Promise<T?> {
        let timeout: Promise<T?> = after(seconds: seconds).map {
            return nil
        }

        return race(
            self.map { (a: T?) -> (T?, Bool) in
                (a, false)
            },
            timeout.map { (a: T?) -> (T?, Bool) in
                (a, true)
            }
        ).map { result, didTimeout in
            if didTimeout {
                Logger.info("Timed out, returning nil value.")
            }
            return result
        }
    }

    func timeout(seconds: TimeInterval, substituteValue: T) -> Promise<T> {
        let timeout: Promise<T> = after(seconds: seconds).map {
            return substituteValue
        }

        return race(
            self.map { ($0, false) },
            timeout.map { ($0, true) }
        ).map { result, didTimeout in
            if didTimeout {
                Logger.info("Timed out, returning substitute value.")
            }
            return result
        }
    }

    func timeout(seconds: TimeInterval, description: String? = nil, timeoutErrorBlock: @escaping () -> Error) -> Promise<T> {
        let timeout: Promise<T> = after(seconds: seconds).map {
            throw TimeoutError(underlyingError: timeoutErrorBlock())
        }

        return race(self, timeout).recover { error -> Promise<T> in
            switch error {
            case let timeoutError as TimeoutError:
                if let description = description {
                    Logger.info("Timed out, throwing error: \(description).")
                } else {
                    Logger.info("Timed out, throwing error.")
                }
                return Promise(error: timeoutError.underlyingError)
            default:
                return Promise(error: error)
            }
        }
    }
}

struct TimeoutError: Error {
    let underlyingError: Error
}

public extension Promise where T == Void {
    func timeout(seconds: TimeInterval) -> Promise<Void> {
        return timeout(seconds: seconds, substituteValue: ())
    }
}

public extension Guarantee {
    func nilTimeout(seconds: TimeInterval) -> Guarantee<T?> {
        let timeout: Guarantee<T?> = after(seconds: seconds).map {
            return nil
        }

        return race(
            self.map { ($0, false) },
            timeout.map { ($0, true) }
        ).map { result, didTimeout in
            if didTimeout {
                Logger.info("Timed out, returning nil value.")
            }
            return result
        }
    }

    func timeout(seconds: TimeInterval, substituteValue: T) -> Guarantee<T> {
        let timeout: Guarantee<T> = after(seconds: seconds).map {
            return substituteValue
        }

        return race(
            self.map { ($0, false) },
            timeout.map { ($0, true) }
        ).map { result, didTimeout in
            if didTimeout {
                Logger.info("Timed out, returning substitute value.")
            }
            return result
        }
    }
}

public extension Guarantee where T == Void {
    func timeout(seconds: TimeInterval) -> Guarantee<Void> {
        timeout(seconds: seconds, substituteValue: ())
    }
}

@objc
public extension AnyPromise {
    /**
     * Sometimes there isn't a straight forward candidate to retain a promise, in that case we tell the
     * promise to self retain, until it completes to avoid the risk it's GC'd before completion.
     */
    func retainUntilComplete() {
        var retainCycle: AnyPromise? = self
        _ = self.ensure {
            assert(retainCycle != nil)
            retainCycle = nil
        }
    }
}

public extension PMKFinalizer {
    /**
     * Sometimes there isn't a straight forward candidate to retain a promise, in that case we tell the
     * promise to self retain, until it completes to avoid the risk it's GC'd before completion.
     */
    func retainUntilComplete() {
        var retainCycle: PMKFinalizer? = self
        _ = self.finally {
            assert(retainCycle != nil)
            retainCycle = nil
        }
    }
}

public extension Promise {
    /**
     * Sometimes there isn't a straight forward candidate to retain a promise, in that case we tell the 
     * promise to self retain, until it completes to avoid the risk it's GC'd before completion.
     */
    func retainUntilComplete() {
        var retainCycle: Promise<T>? = self
        _ = self.ensure {
            assert(retainCycle != nil)
            retainCycle = nil
        }
    }
}

public extension Guarantee {
    /**
     * Sometimes there isn't a straight forward candidate to retain a promise, in that case we tell the
     * promise to self retain, until it completes to avoid the risk it's GC'd before completion.
     */
    func retainUntilComplete() {
        var retainCycle: Guarantee<T>? = self
        _ = self.done { _ in
            assert(retainCycle != nil)
            retainCycle = nil
        }
    }
}
