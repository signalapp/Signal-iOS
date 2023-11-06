//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging

private extension Optional where Wrapped == DonationPaymentMethod {
    var timeoutDuration: TimeInterval {
        // Default to the longer duration if we don't know what payment method
        // we are.
        return self?.timeoutDuration ?? 30
    }
}

private extension DonationPaymentMethod {
    var timeoutDuration: TimeInterval {
        switch self {
        case .applePay, .creditOrDebitCard, .paypal:
            // We hope these payments will process quickly, so we'll wait a
            // decent amount of time before timing out in the hopes that we can
            // learn the status of the completed payment synchronously.
            return 30
        case .sepa:
            // We expect SEPA payments will not process in a realistically-
            // waitable time, so use a shortened window before timing out for
            // them.
            return 10
        }
    }
}

extension DonationViewsUtil {
    public static func waitForSubscriptionJob(
        paymentMethod: DonationPaymentMethod?
    ) -> Promise<Void> {
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
                    forName: SubscriptionReceiptCredentialRedemptionOperation.DidSucceedNotification,
                    object: nil,
                    queue: nil
                ) { _ in
                    done { future.resolve() }
                }
            )

            observers.append(
                nc.addObserver(
                    forName: SubscriptionReceiptCredentialRedemptionOperation.DidFailNotification,
                    object: nil,
                    queue: nil
                ) { _ in
                    done { future.reject(DonationJobError.assertion) }
                }
            )

            // We could clean this up, but the promise API doesn't support it
            // and it's not worth the developer effort.
            Guarantee.after(seconds: paymentMethod.timeoutDuration).done {
                done { future.reject(DonationJobError.timeout) }
            }
        }

        return promise
    }
}
