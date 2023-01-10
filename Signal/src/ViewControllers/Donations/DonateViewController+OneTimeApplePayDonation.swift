//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import PassKit
import SignalCoreKit
import SignalMessaging
import SignalUI
import SignalServiceKit

extension DonateViewController {
    /// Handle Apple Pay authorization for a one-time payment.
    ///
    /// See also: code for other payment methods, such as credit/debit cards.
    func paymentAuthorizationControllerForOneTime(
        _ controller: PKPaymentAuthorizationController,
        didAuthorizePayment payment: PKPayment,
        handler completion: @escaping (PKPaymentAuthorizationResult) -> Void
    ) {
        var hasCalledCompletion = false
        func wrappedCompletion(_ result: PKPaymentAuthorizationResult) {
            guard !hasCalledCompletion else { return }
            hasCalledCompletion = true
            completion(result)
        }

        guard let oneTime = state.oneTime, let amount = oneTime.amount else {
            owsFail("Amount or currency code are missing")
        }
        let boostBadge = oneTime.profileBadge

        firstly(on: .global()) {
            Stripe.boost(
                amount: amount,
                level: .boostBadge,
                for: .applePay(payment: payment)
            )
        }.done(on: .main) { confirmedIntent -> Void in
            owsAssert(
                confirmedIntent.redirectToUrl == nil,
                "[Donations] There shouldn't be a 3DS redirect for Apple Pay"
            )

            wrappedCompletion(.init(status: .success, errors: nil))

            SubscriptionManager.createAndRedeemBoostReceipt(
                for: confirmedIntent.intentId,
                withPaymentProcessor: .stripe,
                amount: amount
            )

            DonationViewsUtil.wrapPromiseInProgressView(
                from: self,
                promise: DonationViewsUtil.waitForSubscriptionJob()
            ).done(on: .main) {
                self.didCompleteDonation(badge: boostBadge, thanksSheetType: .boost)
            }.catch(on: .main) { [weak self] error in
                self?.didFailDonation(error: error, mode: .oneTime, paymentMethod: .applePay)
            }
        }.catch(on: .main) { error in
            wrappedCompletion(.init(status: .failure, errors: [error]))
            owsFailDebugUnlessNetworkFailure(error)
        }
    }
}
