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
            do {
                if let existingSubscriberId = monthly.subscriberID {
                    Logger.info("[Donations] Cancelling existing subscription")
                    try await DonationSubscriptionManager.cancelSubscription(for: existingSubscriberId)
                } else {
                    Logger.info("[Donations] No existing subscription to cancel")
                }

                Logger.info("[Donations] Preparing new monthly subscription with Apple Pay")
                subscriberId = try await DonationSubscriptionManager.prepareNewSubscription(
                    currencyCode: monthly.selectedCurrencyCode,
                )

                Logger.info("[Donations] Creating Signal payment method for new monthly subscription with Apple Pay")
                let clientSecret = try await Stripe.createSignalPaymentMethodForSubscription(subscriberId: subscriberId)

                Logger.info("[Donations] Authorizing payment for new monthly subscription with Apple Pay")
                let confirmedIntent = try await Stripe.setupNewSubscription(
                    clientSecret: clientSecret,
                    paymentMethod: .applePay(payment: payment),
                )
                let paymentMethodId = confirmedIntent.paymentMethodId

                Logger.info("[Donations] Finalizing new subscription for Apple Pay donation")
                _ = try await DonationSubscriptionManager.finalizeNewSubscription(
                    forSubscriberId: subscriberId,
                    paymentType: .applePay(paymentMethodId: paymentMethodId),
                    subscription: selectedSubscriptionLevel,
                    currencyCode: monthly.selectedCurrencyCode,
                )

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
                        try await DonationViewsUtil.waitForRedemption(paymentMethod: .applePay) {
                            try await DonationSubscriptionManager.requestAndRedeemReceipt(
                                subscriberId: subscriberId,
                                subscriptionLevel: selectedSubscriptionLevel.level,
                                priorSubscriptionLevel: monthly.currentSubscriptionLevel?.level,
                                paymentProcessor: .stripe,
                                paymentMethod: .applePay,
                                isNewSubscription: true,
                            )
                        }
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
