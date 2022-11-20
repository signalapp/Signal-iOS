//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging

extension DonationViewsUtil {
    public static func waitForSubscriptionJob() -> Promise<Void> {
        // TODO: This function should take a job ID to help avoid bugs when
        // multiple jobs are running at the same time.

        let nc = NotificationCenter.default
        let (promise, future) = Promise<Void>.pending()

        var isDone = false
        var observers = [Any]()
        func done(fn: @escaping () -> Void) {
            DispatchQueue.sharedUserInitiated.async {
                if isDone { return }
                isDone = true

                for observer in observers {
                    nc.removeObserver(observer)
                }

                fn()
            }
        }

        DispatchQueue.sharedUserInitiated.async {
            observers.append(
                nc.addObserver(
                    forName: SubscriptionManager.SubscriptionJobQueueDidFinishJobNotification,
                    object: nil,
                    queue: nil
                ) { _ in
                    done { future.resolve() }
                }
            )

            observers.append(
                nc.addObserver(
                    forName: SubscriptionManager.SubscriptionJobQueueDidFailJobNotification,
                    object: nil,
                    queue: nil
                ) { _ in
                    done { future.reject(DonationJobError.assertion) }
                }
            )

            // We could clean this up, but the promise API doesn't support it
            // and it's not worth the developer effort.
            Guarantee.after(seconds: 30).done {
                done { future.reject(DonationJobError.timeout) }
            }
        }

        return promise
    }
}
