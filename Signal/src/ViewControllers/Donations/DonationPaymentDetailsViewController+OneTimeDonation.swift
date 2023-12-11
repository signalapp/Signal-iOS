//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging
import SignalUI

extension DonationPaymentDetailsViewController {
    /// Make a one-time donation.
    /// 
    /// See also: code for other payment methods, such as Apple Pay.
    func oneTimeDonation(with validForm: FormState.ValidForm) {
        Logger.info("[Donations] Starting one-time donation")

        let amount = self.donationAmount

        DonationViewsUtil.wrapPromiseInProgressView(
            from: self,
            promise: firstly(on: DispatchQueue.sharedUserInitiated) {
                Stripe.boost(
                    amount: amount,
                    level: .boostBadge,
                    for: validForm.stripePaymentMethod
                )
            }.then(on: DispatchQueue.main) { confirmedIntent in
                if let redirectUrl = confirmedIntent.redirectToUrl {
                    Logger.info("[Donations] One-time card donation needed 3DS. Presenting...")
                    return self.show3DS(for: redirectUrl)
                } else {
                    Logger.info("[Donations] One-time card donation did not need 3DS. Continuing")
                    return Promise.value(confirmedIntent.paymentIntentId)
                }
            }.then(on: DispatchQueue.sharedUserInitiated) { intentId in
                Logger.info("[Donations] Creating and redeeming one-time boost receipt for card donation")

                return DonationViewsUtil.createAndRedeemOneTimeDonation(
                    paymentIntentId: intentId,
                    amount: amount,
                    paymentMethod: validForm.donationPaymentMethod
                )
            }
        ).done(on: DispatchQueue.main) { [weak self] in
            Logger.info("[Donations] One-time card donation finished")
            self?.onFinished(nil)
        }.catch(on: DispatchQueue.main) { [weak self] error in
            Logger.warn("[Donations] One-time card donation failed")
            self?.onFinished(error)
        }
    }
}
