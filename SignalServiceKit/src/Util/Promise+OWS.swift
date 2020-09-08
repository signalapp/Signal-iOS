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

public func firstly<T>(on dispatchQueue: DispatchQueue,
                       execute body: @escaping () throws -> T) -> Promise<T> {
    return dispatchQueue.async(.promise, execute: body)
}

// MARK: -

public class Promises {

    public static func performWithImmediateRetry<T>(promiseBlock: @escaping () -> Promise<T>,
                                                    remainingRetries: UInt = 3) -> Promise<T> {

        let (promise, resolver) = Promise<T>.pending()

        firstly(on: .global()) { () -> Promise<T> in
            return promiseBlock()
        }.done(on: .global()) { (value: T) -> Void  in
            resolver.fulfill(value)
        }.catch(on: .global()) { (error: Error) -> Void in
            guard remainingRetries > 0,
                IsNetworkConnectivityFailure(error) else {
                    resolver.reject(error)
                    return
            }

            Logger.warn("Error: \(error)")

            firstly(on: .global()) { () -> Promise<T> in
                return Self.performWithImmediateRetry(promiseBlock: promiseBlock,
                                                      remainingRetries: remainingRetries - 1)
            }.done(on: .global()) { (value: T) in
                resolver.fulfill(value)
            }.catch(on: .global()) { (error: Error)in
                resolver.reject(error)
            }
        }

        return promise
    }
}

public extension CatchMixin {
    /// Catches a cancellation error and throws the replacement in its place
    /// - Parameter replacementError: The error to be thrown if a cancellation is caught
    ///
    /// By default, PromiseKit will suppress any cancellations. They're not a success and not a failure
    /// This function is a convenience wrapper around adding a recovery block that will rethrow any cancellations as the provided error
    func catchCancellation(andThrow replacementError: Error) -> PromiseKit.Promise<Self.T> {
        recover(on: conf.Q.map, policy: .allErrors) { (originalError) -> Promise<Self.T> in
            throw originalError.isCancelled ? replacementError : originalError
        }
    }
}
