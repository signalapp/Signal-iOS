//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging
import SignalUI

extension CreditOrDebitCardDonationViewController {
    /// Make a one-time donation.
    /// 
    /// See also: code for other payment methods, such as Apple Pay.
    func oneTimeDonation(with creditOrDebitCard: Stripe.PaymentMethod.CreditOrDebitCard) {
        let amount = self.donationAmount

        DonationViewsUtil.wrapPromiseInProgressView(
            from: self,
            promise: firstly(on: .sharedUserInitiated) {
                Stripe.boost(
                    amount: amount,
                    level: .boostBadge,
                    for: .creditOrDebitCard(creditOrDebitCard: creditOrDebitCard)
                )
            }.then(on: .main) { [weak self] confirmedIntent in
                guard let self else { throw DonationJobError.assertion }
                if let redirectUrl = confirmedIntent.redirectToUrl {
                    return self.show3DS(for: redirectUrl)
                } else {
                    return Promise.value(confirmedIntent.intentId)
                }
            }.then(on: .sharedUserInitiated) { intentId in
                SubscriptionManager.terminateTransactionIfPossible = false
                SubscriptionManager.createAndRedeemBoostReceipt(for: intentId, amount: amount)
                return DonationViewsUtil.waitForSubscriptionJob()
            }
        ).done(on: .main) { [weak self] in
            self?.onFinished()
        }.catch(on: .main) { [weak self] error in
            self?.didFailDonation(error: error)
        }
    }
}
