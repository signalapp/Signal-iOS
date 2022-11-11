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

        guard
            let oneTime = state.oneTime,
            let amount = oneTime.amount,
            let boostBadge = oneTime.profileBadge
        else {
            owsFail("Amount, currency code, or boost badge are missing")
        }

        firstly(on: .global()) { () -> Promise<String> in
            Stripe.boost(
                amount: amount,
                level: .boostBadge,
                for: payment
            )
        }.done(on: .main) { (intentId: String) -> Void in
            SubscriptionManager.terminateTransactionIfPossible = false
            wrappedCompletion(.init(status: .success, errors: nil))

            SubscriptionManager.createAndRedeemBoostReceipt(for: intentId, amount: amount)

            ModalActivityIndicatorViewController.present(fromViewController: self, canCancel: false) { (modal) -> Void in
                // TODO: We don't clean these up, which leads to memory leaks (at best) and
                // state bugs (at worst).
                Promise.race(
                    NotificationCenter.default.observe(
                        once: SubscriptionManager.SubscriptionJobQueueDidFinishJobNotification,
                        object: nil
                    ),
                    NotificationCenter.default.observe(
                        once: SubscriptionManager.SubscriptionJobQueueDidFailJobNotification,
                        object: nil
                    )
                ).timeout(seconds: 30) {
                    return DonationJobError.timeout
                }.done { notification in
                    modal.dismiss {}

                    if notification.name == SubscriptionManager.SubscriptionJobQueueDidFailJobNotification {
                        throw DonationJobError.assertion
                    }

                    self.onFinished(.completedDonation(
                        donateSheet: self,
                        badgeThanksSheet: BadgeThanksSheet(badge: boostBadge, type: .boost)
                    ))
                }.catch { [weak self] error in
                    modal.dismiss {}
                    guard let error = error as? DonationJobError else {
                        return owsFailDebug("Unexpected error \(error)")
                    }

                    guard let self = self else { return }
                    switch error {
                    case .timeout:
                        self.presentStillProcessingSheet()
                    case .assertion:
                        self.presentBadgeCantBeAddedSheet()
                    }
                }
            }
        }.catch(on: .main) { error in
            SubscriptionManager.terminateTransactionIfPossible = false
            wrappedCompletion(.init(status: .failure, errors: [error]))
            owsFailDebugUnlessNetworkFailure(error)
        }
    }
}
