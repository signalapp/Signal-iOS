//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

// MARK: -

public class Promises {

    public static func performWithImmediateRetry<T>(promiseBlock: @escaping () -> Promise<T>,
                                                    remainingRetries: UInt = 3) -> Promise<T> {

        return firstly(on: .global()) { () -> Promise<T> in
            return promiseBlock()
        }.recover(on: .global()) { (error: Error) -> Promise<T> in
            guard remainingRetries > 0,
                error.isNetworkConnectivityFailure else {
                    throw error
            }

            Logger.warn("Error: \(error)")

            return Self.performWithImmediateRetry(promiseBlock: promiseBlock,
                                                  remainingRetries: remainingRetries - 1)
        }
    }
}
