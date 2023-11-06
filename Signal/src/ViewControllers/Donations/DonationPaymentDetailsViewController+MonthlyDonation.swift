//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging

extension DonationPaymentDetailsViewController {
    /// Make a monthly donation.
    ///
    /// See also: code for other payment methods, such as Apple Pay.
    func monthlyDonation(
        with validForm: FormState.ValidForm,
        newSubscriptionLevel: SubscriptionLevel,
        priorSubscriptionLevel: SubscriptionLevel?,
        subscriberID existingSubscriberId: Data?
    ) {
        let currencyCode = self.donationAmount.currencyCode

        Logger.info("[Donations] Starting monthly card donation")

        DonationViewsUtil.wrapPromiseInProgressView(
            from: self,
            promise: firstly(on: DispatchQueue.sharedUserInitiated) { () -> Promise<Void> in
                if let existingSubscriberId {
                    Logger.info("[Donations] Cancelling existing subscription")

                    return SubscriptionManagerImpl.cancelSubscription(for: existingSubscriberId)
                } else {
                    Logger.info("[Donations] No existing subscription to cancel")

                    return Promise.value(())
                }
            }.then(on: DispatchQueue.sharedUserInitiated) { () -> Promise<Data> in
                Logger.info("[Donations] Preparing new monthly subscription with card")

                return SubscriptionManagerImpl.prepareNewSubscription(currencyCode: currencyCode)
            }.then(on: DispatchQueue.sharedUserInitiated) { subscriberId -> Promise<(Data, String)> in
                firstly { () -> Promise<String> in
                    Logger.info("[Donations] Creating Signal payment method for new monthly subscription with card")

                    return Stripe.createSignalPaymentMethodForSubscription(subscriberId: subscriberId)
                }.then(on: DispatchQueue.sharedUserInitiated) { clientSecret -> Promise<String> in
                    Logger.info("[Donations] Authorizing payment for new monthly subscription with card")

                    return Stripe.setupNewSubscription(
                        clientSecret: clientSecret,
                        paymentMethod: validForm.stripePaymentMethod,
                        show3DS: { redirectUrl in
                            Logger.info("[Donations] Monthly card donation needs 3DS. Presenting...")
                            return self.show3DS(for: redirectUrl).asVoid()
                        }
                    )
                }.map(on: DispatchQueue.sharedUserInitiated) { paymentId -> (Data, String) in
                    (subscriberId, paymentId)
                }
            }.then(on: DispatchQueue.sharedUserInitiated) { (subscriberId, paymentId) -> Promise<Data> in
                Logger.info("[Donations] Finalizing new subscription for card donation")

                return SubscriptionManagerImpl.finalizeNewSubscription(
                    forSubscriberId: subscriberId,
                    withPaymentId: paymentId,
                    usingPaymentProcessor: .stripe,
                    usingPaymentMethod: .creditOrDebitCard,
                    subscription: newSubscriptionLevel,
                    currencyCode: currencyCode
                ).map(on: DispatchQueue.sharedUserInitiated) { _ in subscriberId }
            }.then(on: DispatchQueue.sharedUserInitiated) { subscriberId in
                Logger.info("[Donations] Redeeming monthly receipts for card donation")

                SubscriptionManagerImpl.requestAndRedeemReceipt(
                    subscriberId: subscriberId,
                    subscriptionLevel: newSubscriptionLevel.level,
                    priorSubscriptionLevel: priorSubscriptionLevel?.level,
                    paymentProcessor: .stripe,
                    paymentMethod: validForm.donationPaymentMethod
                )

                return DonationViewsUtil.waitForSubscriptionJob(
                    paymentMethod: .creditOrDebitCard
                )
            }
        ).done(on: DispatchQueue.main) { [weak self] in
            Logger.info("[Donations] Monthly card donation finished")
            self?.onFinished(nil)
        }.catch(on: DispatchQueue.main) { [weak self] error in
            Logger.info("[Donations] Monthly card donation failed")
            self?.onFinished(error)
        }
    }
}
