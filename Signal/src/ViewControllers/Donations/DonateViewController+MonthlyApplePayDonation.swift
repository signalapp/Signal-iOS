//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import PassKit
import SignalCoreKit
import SignalMessaging
import SignalUI

extension DonateViewController {
    /// Handle Apple Pay authorization for a monthly payment.
    ///
    /// See also: code for other payment methods, such as credit/debit cards.
    func paymentAuthorizationControllerForMonthly(
        _ controller: PKPaymentAuthorizationController,
        didAuthorizePayment payment: PKPayment,
        handler completion: @escaping (PKPaymentAuthorizationResult) -> Void
    ) {
        guard
            let monthly = state.monthly,
            let selectedSubscriptionLevel = monthly.selectedSubscriptionLevel
        else {
            owsFail("[Donations] Invalid state; cannot pay")
        }

        Logger.info("[Donations] Starting monthly Apple Pay donation")

        // See also: code for other payment methods, such as credit/debit card.
        firstly(on: DispatchQueue.sharedUserInitiated) { () -> Promise<Void> in
            if let existingSubscriberId = monthly.subscriberID, monthly.currentSubscription != nil {
                Logger.info("[Donations] Cancelling existing subscription")

                return SubscriptionManagerImpl.cancelSubscription(for: existingSubscriberId)
            } else {
                Logger.info("[Donations] No existing subscription to cancel")

                return Promise.value(())
            }
        }.then(on: DispatchQueue.sharedUserInitiated) { () -> Promise<Data> in
            Logger.info("[Donations] Preparing new monthly subscription with Apple Pay")

            return SubscriptionManagerImpl.prepareNewSubscription(
                currencyCode: monthly.selectedCurrencyCode
            )
        }.then(on: DispatchQueue.sharedUserInitiated) { subscriberId -> Promise<(Data, String)> in
            firstly { () -> Promise<String> in
                Logger.info("[Donations] Creating Signal payment method for new monthly subscription with Apple Pay")

                return Stripe.createSignalPaymentMethodForSubscription(subscriberId: subscriberId)
            }.then(on: DispatchQueue.sharedUserInitiated) { clientSecret -> Promise<String> in
                Logger.info("[Donations] Authorizing payment for new monthly subscription with Apple Pay")

                return Stripe.setupNewSubscription(
                    clientSecret: clientSecret,
                    paymentMethod: .applePay(payment: payment),
                    show3DS: { _ in
                        owsFail("[Donations] 3D Secure should not be shown for Apple Pay")
                    }
                )
            }.map(on: DispatchQueue.sharedUserInitiated) { paymentId in
                (subscriberId, paymentId)
            }
        }.then(on: DispatchQueue.sharedUserInitiated) { (subscriberId, paymentId) -> Promise<Data> in
            Logger.info("[Donations] Finalizing new subscription for Apple Pay donation")

            return SubscriptionManagerImpl.finalizeNewSubscription(
                forSubscriberId: subscriberId,
                withPaymentId: paymentId,
                usingPaymentMethod: .applePay,
                subscription: selectedSubscriptionLevel,
                currencyCode: monthly.selectedCurrencyCode
            ).map(on: DispatchQueue.sharedUserInitiated) { _ in subscriberId }
        }.done(on: DispatchQueue.main) { subscriberID in
            let authResult = PKPaymentAuthorizationResult(status: .success, errors: nil)
            completion(authResult)

            Logger.info("[Donations] Redeeming monthly receipt for Apple Pay donation")

            DonationViewsUtil.redeemMonthlyReceipts(
                usingPaymentProcessor: .stripe,
                subscriberID: subscriberID,
                newSubscriptionLevel: selectedSubscriptionLevel,
                priorSubscriptionLevel: monthly.currentSubscriptionLevel
            )

            DonationViewsUtil.wrapPromiseInProgressView(
                from: self,
                promise: DonationViewsUtil.waitForSubscriptionJob()
            ).done(on: DispatchQueue.main) {
                Logger.info("[Donations] Monthly card donation finished")

                self.didCompleteDonation(
                    badge: selectedSubscriptionLevel.badge,
                    thanksSheetType: .subscription
                )
            }.catch(on: DispatchQueue.main) { [weak self] error in
                Logger.info("[Donations] Monthly card donation failed")

                self?.didFailDonation(error: error, mode: .monthly, paymentMethod: .applePay)
            }
        }.catch(on: DispatchQueue.main) { error in
            let authResult = PKPaymentAuthorizationResult(status: .failure, errors: [error])
            completion(authResult)
            owsFailDebug("[Donations] Error setting up subscription, \(error)")
        }
    }
}
