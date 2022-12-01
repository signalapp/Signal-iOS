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
        Logger.info("[Donations] Starting one-time card donation")

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
                    Logger.info("[Donations] One-time card donation needed 3DS. Presenting...")
                    return self.show3DS(for: redirectUrl)
                } else {
                    Logger.info("[Donations] One-time card donation did not need 3DS. Continuing")
                    return Promise.value(confirmedIntent.intentId)
                }
            }.then(on: .sharedUserInitiated) { intentId in
                Logger.info("[Donations] Creating and redeeming one-time boost receipt for card donation")
                SubscriptionManager.terminateTransactionIfPossible = false
                SubscriptionManager.createAndRedeemBoostReceipt(
                    for: intentId,
                    withPaymentProcessor: .stripe,
                    amount: amount
                )
                return DonationViewsUtil.waitForSubscriptionJob()
            }
        ).done(on: .main) { [weak self] in
            Logger.info("[Donations] One-time card donation finished")
            self?.onFinished()
        }.catch(on: .main) { [weak self] error in
            Logger.warn("[Donations] One-time card donation failed")
            self?.didFailDonation(error: error)
        }
    }
}
