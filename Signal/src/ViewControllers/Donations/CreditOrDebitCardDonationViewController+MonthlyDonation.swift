//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging

extension CreditOrDebitCardDonationViewController {
    /// Make a monthly donation.
    ///
    /// See also: code for other payment methods, such as Apple Pay.
    func monthlyDonation(
        with creditOrDebitCard: Stripe.PaymentMethod.CreditOrDebitCard,
        newSubscriptionLevel: SubscriptionLevel,
        priorSubscriptionLevel: SubscriptionLevel?,
        subscriberID existingSubscriberId: Data?
    ) {
        let currencyCode = self.donationAmount.currencyCode

        Logger.info("[Donations] Starting monthly card donation")

        DonationViewsUtil.wrapPromiseInProgressView(
            from: self,
            promise: firstly(on: .sharedUserInitiated) { () -> Promise<Void> in
                if let existingSubscriberId, priorSubscriptionLevel != nil {
                    Logger.info("[Donations] Cancelling existing subscription")

                    return SubscriptionManager.cancelSubscription(for: existingSubscriberId)
                } else {
                    Logger.info("[Donations] No existing subscription to cancel")

                    return Promise.value(())
                }
            }.then(on: .sharedUserInitiated) { () -> Promise<Data> in
                Logger.info("[Donations] Preparing new monthly subscription with card")

                return SubscriptionManager.prepareNewSubscription(currencyCode: currencyCode)
            }.then(on: .sharedUserInitiated) { subscriberId -> Promise<(Data, String)> in
                firstly { () -> Promise<String> in
                    Logger.info("[Donations] Creating Signal payment method for new monthly subscription with card")

                    return Stripe.createSignalPaymentMethodForSubscription(subscriberId: subscriberId)
                }.then(on: .sharedUserInitiated) { clientSecret -> Promise<String> in
                    Logger.info("[Donations] Authorizing payment for new monthly subscription with card")

                    return Stripe.setupNewSubscription(
                        clientSecret: clientSecret,
                        paymentMethod: .creditOrDebitCard(creditOrDebitCard: creditOrDebitCard),
                        show3DS: { redirectUrl in
                            Logger.info("[Donations] Monthly card donation needs 3DS. Presenting...")
                            return self.show3DS(for: redirectUrl).asVoid()
                        }
                    )
                }.map(on: .sharedUserInitiated) { paymentId -> (Data, String) in
                    (subscriberId, paymentId)
                }
            }.then(on: .sharedUserInitiated) { (subscriberId, paymentId) -> Promise<Data> in
                Logger.info("[Donations] Finalizing new subscription for card donation")

                return SubscriptionManager.finalizeNewSubscription(
                    forSubscriberId: subscriberId,
                    withPaymentId: paymentId,
                    usingPaymentMethod: .creditOrDebitCard,
                    subscription: newSubscriptionLevel,
                    currencyCode: currencyCode
                ).map(on: .sharedUserInitiated) { _ in subscriberId }
            }.then(on: .sharedUserInitiated) { subscriberId in
                Logger.info("[Donations] Redeeming monthly receipts for card donation")

                DonationViewsUtil.redeemMonthlyReceipts(
                    usingPaymentProcessor: .stripe,
                    subscriberID: subscriberId,
                    newSubscriptionLevel: newSubscriptionLevel,
                    priorSubscriptionLevel: priorSubscriptionLevel
                )

                return DonationViewsUtil.waitForSubscriptionJob()
            }
        ).done(on: .main) { [weak self] in
            Logger.info("[Donations] Monthly card donation finished")
            self?.onFinished()
        }.catch(on: .main) { [weak self] error in
            Logger.info("[Donations] Monthly card donation failed")
            self?.didFailDonation(error: error)
        }
    }
}
