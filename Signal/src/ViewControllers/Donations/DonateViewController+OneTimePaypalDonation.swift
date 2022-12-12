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
        badge: ProfileBadge?
    ) {
        Logger.info("[Donations] Starting one-time PayPal donation")

        guard let badge else {
            owsFail("[Donations] Missing badge!")
        }

        firstly(on: .main) { [weak self] () -> Promise<URL> in
            guard let self else { throw OWSAssertionError("[Donations] Missing self!") }

            // First, create a PayPal payment.

            return self.createPaypalPaymentBehindActivityIndicator(
                amount: amount,
                level: .boostBadge
            )
        }.then(on: .main) { [weak self] approvalUrl -> Promise<Paypal.WebAuthApprovalParams> in
            guard let self else { throw OWSAssertionError("[Donations] Missing self!") }

            Logger.info("[Donations] Presenting PayPal web UI for user approval of one-time donation")
            if #available(iOS 13, *) {
                return Paypal.present(approvalUrl: approvalUrl, withPresentationContext: self)
            } else {
                return Paypal.present(approvalUrl: approvalUrl)
            }
        }.then(on: .main) { [weak self] approvalParams -> Promise<Void> in
            guard let self else { return .value(()) }

            Logger.info("[Donations] Creating and redeeming one-time boost receipt for PayPal donation")
            return DonationViewsUtil.wrapPromiseInProgressView(
                from: self,
                promise: self.confirmPaypalPaymentAndRedeemBoost(
                    amount: amount,
                    approvalParams: approvalParams
                )
            ).map(on: .main) { [weak self] in
                Logger.info("[Donations] One-time PayPal donation finished")
                guard let self else { return }
                self.didCompleteDonation(badge: badge, thanksSheetType: .boost)
            }
        }.catch(on: .main) { [weak self] error in
            Logger.info("[Donations] One-time PayPal donation failed")

            guard let self else { return }

            if let webAuthError = error as? Paypal.AuthError {
                switch webAuthError {
                case .userCanceled:
                    self.didCancelDonation()
                }
            } else {
                SubscriptionManager.terminateTransactionIfPossible = false
                self.didFailDonation(error: error, mode: .oneTime, paymentMethod: .paypal)
            }
        }
    }

    /// Create a PayPal payment, returning a PayPal URL to present to the user
    /// for authentication. Presents an activity indicator while in-progress.
    private func createPaypalPaymentBehindActivityIndicator(
        amount: FiatMoney,
        level: OneTimeBadgeLevel
    ) -> Promise<URL> {
        let (promise, future) = Promise<URL>.pending()

        ModalActivityIndicatorViewController.present(
            fromViewController: self,
            canCancel: false
        ) { modal in
            firstly {
                Paypal.createBoost(amount: amount, level: level)
            }.map(on: .main) { approvalUrl in
                modal.dismiss { future.resolve(approvalUrl) }
            }.catch(on: .main) { error in
                modal.dismiss { future.reject(error) }
            }
        }

        return promise
    }

    private func confirmPaypalPaymentAndRedeemBoost(
        amount: FiatMoney,
        approvalParams: Paypal.WebAuthApprovalParams
    ) -> Promise<Void> {
        firstly { () -> Promise<String> in
            Paypal.confirmBoost(
                amount: amount,
                level: .boostBadge,
                approvalParams: approvalParams
            )
        }.then(on: .main) { (paymentIntentId: String) -> Promise<Void> in
            SubscriptionManager.terminateTransactionIfPossible = false
            SubscriptionManager.createAndRedeemBoostReceipt(
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
