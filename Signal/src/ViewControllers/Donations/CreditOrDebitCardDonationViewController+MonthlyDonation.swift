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
        subscriberID: Data?
    ) {
        DonationViewsUtil.wrapPromiseInProgressView(
            from: self,
            promise: firstly(on: .sharedUserInitiated) { () -> Promise<Void> in
                if let subscriberID, priorSubscriptionLevel != nil {
                    return SubscriptionManager.cancelSubscription(for: subscriberID)
                } else {
                    return Promise.value(())
                }
            }.then(on: .sharedUserInitiated) {
                SubscriptionManager.setupNewSubscription(
                    subscription: newSubscriptionLevel,
                    paymentMethod: .creditOrDebitCard(creditOrDebitCard: creditOrDebitCard),
                    currencyCode: self.donationAmount.currencyCode
                )
            }.then(on: .sharedUserInitiated) { (subscriberID: Data) in
                DonationViewsUtil.redeemMonthlyReceipts(
                    subscriberID: subscriberID,
                    newSubscriptionLevel: newSubscriptionLevel,
                    priorSubscriptionLevel: priorSubscriptionLevel
                )
                return DonationViewsUtil.waitForSubscriptionJob()
            }
        ).done(on: .main) { [weak self] in
            self?.onFinished()
        }.catch(on: .main) { [weak self] error in
            self?.didFailDonation(error: error)
        }
    }
}
