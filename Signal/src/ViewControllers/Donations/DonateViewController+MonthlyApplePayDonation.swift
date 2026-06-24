//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import PassKit
import SignalServiceKit
import SignalUI

extension DonateViewController {
    /// Handle Apple Pay authorization for a monthly payment.
    ///
    /// See also: code for other payment methods, such as credit/debit cards.
    func paymentAuthorizationControllerForMonthly(
        _ controller: PKPaymentAuthorizationController,
        didAuthorizePayment payment: PKPayment,
        handler completion: @escaping (PKPaymentAuthorizationResult) -> Void,
    ) {
        let db = DependenciesBridge.shared.db
        let donationSubscriptionManager = DependenciesBridge.shared.donationSubscriptionManager
        let idealStore = DependenciesBridge.shared.externalPendingIDEALDonationStore
        let networkManager = SSKEnvironment.shared.networkManagerRef

        guard
            let monthly = state.monthly,
            let selectedSubscriptionLevel = monthly.selectedSubscriptionLevel
        else {
            owsFail("[Donations] Invalid state; cannot pay")
        }

        Logger.info("[Donations] Starting monthly Apple Pay donation")

        // See also: code for other payment methods, such as credit/debit card.

        Task {
            let subscriberId: Data
            let confirmedSetupIntent: Stripe.ConfirmedSetupIntent
            do {
                if let existingSubscriberId = monthly.subscriberID {
                    Logger.info("[Donations] Cancelling existing subscription")
                    try await donationSubscriptionManager.cancelSubscription(for: existingSubscriberId)
                } else {
                    Logger.info("[Donations] No existing subscription to cancel")
                }

                Logger.info("[Donations] Preparing new monthly subscription with Apple Pay")
                subscriberId = try await donationSubscriptionManager.prepareNewSubscription(
                    currencyCode: monthly.selectedCurrencyCode,
                )

                Logger.info("[Donations] Creating Signal payment method for new monthly subscription with Apple Pay")
                let clientSecret = try await Retry.performWithBackoff(maxAttempts: 3) {
                    return try await Stripe.createSignalPaymentMethodForSubscription(
                        subscriberId: subscriberId,
                        networkManager: networkManager,
                    )
                }

                Logger.info("[Donations] Authorizing payment for new monthly subscription with Apple Pay")
                confirmedSetupIntent = try await Retry.performWithBackoff(maxAttempts: 3) {
                    return try await Stripe.setupNewSubscription(
                        clientSecret: clientSecret,
                        paymentMethod: .applePay(payment: payment),
                    )
                }

                let authResult = PKPaymentAuthorizationResult(status: .success, errors: nil)
                completion(authResult)
            } catch {
                let authResult = PKPaymentAuthorizationResult(status: .failure, errors: [error])
                completion(authResult)
                owsFailDebug("[Donations] Error setting up subscription, \(error)")
                return
            }

            do {
                Logger.info("[Donations] Redeeming monthly receipt for Apple Pay donation")
                try await DonationViewsUtil.wrapInProgressView(
                    from: self,
                    operation: {
                        try await DonationViewsUtil.finalizeAndRedeemMonthlyDonation(
                            subscriberId: subscriberId,
                            paymentType: .applePay(paymentMethodId: confirmedSetupIntent.paymentMethodId),
                            newSubscriptionLevel: selectedSubscriptionLevel,
                            priorSubscriptionLevel: monthly.currentSubscriptionLevel,
                            currencyCode: monthly.selectedCurrencyCode,
                            db: db,
                            donationSubscriptionManager: donationSubscriptionManager,
                            idealStore: idealStore,
                        )
                    },
                )
                Logger.info("[Donations] Monthly card donation finished")
                self.didCompleteDonation(
                    receiptCredentialSuccessMode: .recurringSubscriptionInitiation,
                )
            } catch {
                Logger.info("[Donations] Monthly card donation failed")
                self.didFailDonation(
                    error: error,
                    mode: .monthly,
                    badge: selectedSubscriptionLevel.badge,
                    paymentMethod: .applePay,
                )
            }
        }
    }
}
