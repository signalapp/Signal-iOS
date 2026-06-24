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
        let db = DependenciesBridge.shared.db
        let donationPermitFetcher = DependenciesBridge.shared.donationPermitFetcher
        let donationSubscriptionManager = DependenciesBridge.shared.donationSubscriptionManager
        let idealStore = DependenciesBridge.shared.externalPendingIDEALDonationStore
        let networkManager = SSKEnvironment.shared.networkManagerRef

        guard let oneTime = state.oneTime, let amount = oneTime.amount else {
            owsFail("Amount or currency code are missing")
        }

        let boostBadge = oneTime.profileBadge

        Task {
            let confirmedPaymentIntent: Stripe.ConfirmedPaymentIntent
            do {
                confirmedPaymentIntent = try await Retry.performWithBackoff(maxAttempts: 3) {
                    let donationPermit = try await donationPermitFetcher.fetchDonationPermit()

                    Logger.info("[Donations] Starting one-time Apple Pay donation")
                    return try await Stripe.boost(
                        amount: amount,
                        level: .boostBadge,
                        for: .applePay(payment: payment),
                        donationPermit: donationPermit,
                        networkManager: networkManager,
                    )
                }
                owsAssertBeta(
                    confirmedPaymentIntent.redirectToUrl == nil,
                    "[Donations] There shouldn't be a 3DS redirect for Apple Pay",
                )
                completion(PKPaymentAuthorizationResult(status: .success, errors: nil))
            } catch {
                Logger.warn("[Donations] One-time Apple Pay donation failed")
                completion(PKPaymentAuthorizationResult(status: .failure, errors: [error]))
                self.didFailDonation(
                    error: error,
                    mode: .oneTime,
                    badge: boostBadge,
                    paymentMethod: .applePay,
                )
                return
            }

            do {
                try await DonationViewsUtil.wrapInProgressView(
                    from: self,
                    operation: {
                        try await DonationViewsUtil.redeemOneTimeDonation(
                            paymentIntentId: confirmedPaymentIntent.paymentIntentId,
                            amount: amount,
                            paymentProcessor: .stripe,
                            paymentMethod: .applePay,
                            db: db,
                            donationSubscriptionManager: donationSubscriptionManager,
                            idealStore: idealStore,
                        )
                    },
                )

                Logger.info("[Donations] One-time Apple Pay donation finished")
                self.didCompleteDonation(receiptCredentialSuccessMode: .oneTimeBoost)
            } catch {
                Logger.warn("[Donations] One-time Apple Pay donation failed")
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
