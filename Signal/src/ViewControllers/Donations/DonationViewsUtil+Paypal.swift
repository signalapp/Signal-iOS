//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

extension DonationViewsUtil {
    enum Paypal {
        /// Create a PayPal payment, returning a PayPal URL to present to the user
        /// for authentication. Presents an activity indicator while in-progress.
        @MainActor
        static func createPaypalPaymentBehindActivityIndicator(
            amount: FiatMoney,
            level: OneTimeBadgeLevel,
            fromViewController: UIViewController,
        ) async throws -> (URL, String) {
            return try await ModalActivityIndicatorViewController.presentAndPropagateResult(
                from: fromViewController,
            ) {
                return try await SignalServiceKit.Paypal.createBoost(
                    amount: amount,
                    level: level,
                )
            }
        }
    }
}
