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

        // See also: code for other payment methods, such as credit/debit card.
        firstly(on: .sharedUserInitiated) { () -> Promise<Void> in
            if let subscriberID = monthly.subscriberID, monthly.currentSubscription != nil {
                return SubscriptionManager.cancelSubscription(for: subscriberID)
            } else {
                return Promise.value(())
            }
        }.then(on: .sharedUserInitiated) {
            SubscriptionManager.setupNewSubscription(
                subscription: selectedSubscriptionLevel,
                applePayPayment: payment,
                currencyCode: monthly.selectedCurrencyCode
            )
        }.done(on: .main) { (subscriberID: Data) in
            let authResult = PKPaymentAuthorizationResult(status: .success, errors: nil)
            completion(authResult)

            DonationViewsUtil.redeemMonthlyReceipts(
                usingPaymentProcessor: .stripe,
                subscriberID: subscriberID,
                newSubscriptionLevel: selectedSubscriptionLevel,
                priorSubscriptionLevel: monthly.currentSubscriptionLevel
            )

            DonationViewsUtil.wrapPromiseInProgressView(
                from: self,
                promise: DonationViewsUtil.waitForSubscriptionJob()
            ).done(on: .main) {
                self.didCompleteDonation(
                    badge: selectedSubscriptionLevel.badge,
                    thanksSheetType: .subscription
                )
            }.catch(on: .main) { [weak self] error in
                self?.didFailDonation(error: error, mode: .monthly, paymentMethod: .applePay)
            }
        }.catch(on: .main) { error in
            let authResult = PKPaymentAuthorizationResult(status: .failure, errors: [error])
            completion(authResult)
            SubscriptionManager.terminateTransactionIfPossible = false
            owsFailDebug("[Donations] Error setting up subscription, \(error)")
        }
    }
}
