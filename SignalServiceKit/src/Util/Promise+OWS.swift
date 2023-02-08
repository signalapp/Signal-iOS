//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

// MARK: -

public class Promises {

    public static func performWithImmediateRetry<T>(promiseBlock: @escaping () -> Promise<T>,
                                                    remainingRetries: UInt = 3) -> Promise<T> {

        return firstly(on: DispatchQueue.global()) { () -> Promise<T> in
            return promiseBlock()
        }.recover(on: DispatchQueue.global()) { (error: Error) -> Promise<T> in
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
