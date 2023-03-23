//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AuthenticationServices
import Foundation
import SignalMessaging
import SignalUI

extension DonateViewController {
    /// Executes a PayPal one-time donation flow.
    func startPaypalBoost(
        with amount: FiatMoney,
        badge: ProfileBadge
    ) {
        Logger.info("[Donations] Starting one-time PayPal donation")

        let badgesSnapshot = BadgeThanksSheet.currentProfileBadgesSnapshot()

        firstly(on: DispatchQueue.main) { [weak self] () -> Promise<URL> in
            guard let self else { throw OWSAssertionError("[Donations] Missing self!") }

            Logger.info("[Donations] Creating one-time PayPal payment")
            return DonationViewsUtil.Paypal.createPaypalPaymentBehindActivityIndicator(
                amount: amount,
                level: .boostBadge,
                fromViewController: self
            )
        }.then(on: DispatchQueue.main) { [weak self] approvalUrl -> Promise<Paypal.OneTimePaymentWebAuthApprovalParams> in
            guard let self else { throw OWSAssertionError("[Donations] Missing self!") }

            Logger.info("[Donations] Presenting PayPal web UI for user approval of one-time donation")
            if #available(iOS 13, *) {
                return Paypal.presentExpectingApprovalParams(
                    approvalUrl: approvalUrl,
                    withPresentationContext: self
                )
            } else {
                return Paypal.presentExpectingApprovalParams(
                    approvalUrl: approvalUrl
                )
            }
        }.then(on: DispatchQueue.main) { [weak self] approvalParams -> Promise<Void> in
            guard let self else { return .value(()) }

            Logger.info("[Donations] Creating and redeeming one-time boost receipt for PayPal donation")
            return DonationViewsUtil.wrapPromiseInProgressView(
                from: self,
                promise: self.confirmPaypalPaymentAndRedeemBoost(
                    amount: amount,
                    approvalParams: approvalParams
                )
            )
        }.done(on: DispatchQueue.main) { [weak self] in
            guard let self else { return }

            Logger.info("[Donations] One-time PayPal donation finished")
            self.didCompleteDonation(badge: badge, thanksSheetType: .boost, oldBadgesSnapshot: badgesSnapshot)
        }.catch(on: DispatchQueue.main) { [weak self] error in
            guard let self else { return }

            if let webAuthError = error as? Paypal.AuthError {
                switch webAuthError {
                case .userCanceled:
                    Logger.info("[Donations] One-time PayPal donation canceled")
                    self.didCancelDonation()
                }
            } else {
                Logger.info("[Donations] One-time PayPal donation failed")
                self.didFailDonation(error: error, mode: .oneTime, paymentMethod: .paypal)
            }
        }
    }

    private func confirmPaypalPaymentAndRedeemBoost(
        amount: FiatMoney,
        approvalParams: Paypal.OneTimePaymentWebAuthApprovalParams
    ) -> Promise<Void> {
        firstly { () -> Promise<String> in
            Paypal.confirmOneTimePayment(
                amount: amount,
                level: .boostBadge,
                approvalParams: approvalParams
            )
        }.then(on: DispatchQueue.main) { (paymentIntentId: String) -> Promise<Void> in
            SubscriptionManagerImpl.createAndRedeemBoostReceipt(
                for: paymentIntentId,
                withPaymentProcessor: .braintree,
                amount: amount
            )
            return DonationViewsUtil.waitForSubscriptionJob()
        }
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension DonateViewController: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        view.window!
    }
}
