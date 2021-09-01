//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

// MARK: -

public class Promises {

    public static func performWithImmediateRetry<T>(promiseBlock: @escaping () -> Promise<T>,
                                                    remainingRetries: UInt = 3) -> Promise<T> {

        let (promise, future) = Promise<T>.pending()

        firstly(on: .global()) { () -> Promise<T> in
            return promiseBlock()
        }.done(on: .global()) { (value: T) -> Void  in
            future.resolve(value)
        }.catch(on: .global()) { (error: Error) -> Void in
            guard remainingRetries > 0,
                IsNetworkConnectivityFailure(error) else {
                    future.reject(error)
                    return
            }

            Logger.warn("Error: \(error)")

            firstly(on: .global()) { () -> Promise<T> in
                return Self.performWithImmediateRetry(promiseBlock: promiseBlock,
                                                      remainingRetries: remainingRetries - 1)
            }.done(on: .global()) { (value: T) in
                future.resolve(value)
            }.catch(on: .global()) { (error: Error)in
                future.reject(error)
            }
        }

        return promise
    }
}
