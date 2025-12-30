//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import PassKit
import SignalServiceKit
import SignalUI

extension DonateViewController {
    /// Handle Apple Pay authorization for a one-time payment.
    ///
    /// See also: code for other payment methods, such as credit/debit cards.
    func paymentAuthorizationControllerForOneTime(
        _ controller: PKPaymentAuthorizationController,
        didAuthorizePayment payment: PKPayment,
        handler completion: @escaping (PKPaymentAuthorizationResult) -> Void,
    ) {
        guard let oneTime = state.oneTime, let amount = oneTime.amount else {
            owsFail("Amount or currency code are missing")
        }

        let boostBadge = oneTime.profileBadge

        Task {
            let confirmedIntent: Stripe.ConfirmedPaymentIntent
            do {
                confirmedIntent = try await Stripe.boost(
                    amount: amount,
                    level: .boostBadge,
                    for: .applePay(payment: payment),
                )
                owsPrecondition(
                    confirmedIntent.redirectToUrl == nil,
                    "[Donations] There shouldn't be a 3DS redirect for Apple Pay",
                )
                completion(.init(status: .success, errors: nil))
            } catch {
                completion(.init(status: .failure, errors: [error]))
                owsFailDebugUnlessNetworkFailure(error)
                return
            }

            do {
                try await DonationViewsUtil.wrapInProgressView(
                    from: self,
                    operation: {
                        try await DonationViewsUtil.waitForRedemption(paymentMethod: .applePay) {
                            try await DonationSubscriptionManager.requestAndRedeemReceipt(
                                boostPaymentIntentId: confirmedIntent.paymentIntentId,
                                amount: amount,
                                paymentProcessor: .stripe,
                                paymentMethod: .applePay,
                            )
                        }
                    },
                )
                self.didCompleteDonation(receiptCredentialSuccessMode: .oneTimeBoost)
            } catch {
                owsFailDebugUnlessNetworkFailure(error)
                self.didFailDonation(
                    error: error,
                    mode: .oneTime,
                    badge: boostBadge,
                    paymentMethod: .applePay,
                )
            }
        }
    }
}
