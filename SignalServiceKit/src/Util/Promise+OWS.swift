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

// MARK: -

public func firstly<U: Thenable>(on dispatchQueue: DispatchQueue,
                                 execute body: @escaping () throws -> U) -> Promise<U.T> {
    let (promise, resolver) = Promise<U.T>.pending()
    dispatchQueue.async {
        firstly {
            return try body()
        }.done(on: .global()) { value in
            resolver.fulfill(value)
        }.catch(on: .global()) { error in
            resolver.reject(error)
        }
    }
    return promise
}
