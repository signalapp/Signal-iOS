//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AuthenticationServices
import Foundation
import SignalServiceKit
import SignalUI

extension DonateViewController {
    /// Executes a PayPal one-time donation flow.
    func startPaypalBoost(
        with amount: FiatMoney,
        badge: ProfileBadge,
    ) {
        Logger.info("[Donations] Starting one-time PayPal donation")
        Task {
            await self._startPaypalBoost(amount: amount, badge: badge)
        }
    }

    private func _startPaypalBoost(amount: FiatMoney, badge: ProfileBadge) async {
        do {
            Logger.info("[Donations] Creating one-time PayPal payment")
            let (approvalUrl, paymentId) = try await DonationViewsUtil.Paypal.createPaypalPaymentBehindActivityIndicator(
                amount: amount,
                level: .boostBadge,
                fromViewController: self,
            )

            Logger.info("[Donations] Presenting PayPal web UI for user approval of one-time donation")
            let approvalParams: Paypal.OneTimePaymentWebAuthApprovalParams = try await Paypal.presentExpectingApprovalParams(
                approvalUrl: approvalUrl,
                withPresentationContext: self,
            )

            Logger.info("[Donations] Creating and redeeming one-time boost receipt for PayPal donation")
            try await DonationViewsUtil.wrapInProgressView(
                from: self,
                operation: {
                    try await self.confirmPaypalPaymentAndRedeemBoost(
                        amount: amount,
                        paymentId: paymentId,
                        approvalParams: approvalParams,
                    )
                },
            )

            Logger.info("[Donations] One-time PayPal donation finished")
            self.didCompleteDonation(
                receiptCredentialSuccessMode: .oneTimeBoost,
            )
        } catch {
            if let webAuthError = error as? Paypal.AuthError {
                switch webAuthError {
                case .userCanceled:
                    Logger.info("[Donations] One-time PayPal donation canceled")
                    self.didCancelDonation()
                }
            } else {
                Logger.info("[Donations] One-time PayPal donation failed")
                self.didFailDonation(
                    error: error,
                    mode: .oneTime,
                    badge: badge,
                    paymentMethod: .paypal,
                )
            }
        }
    }

    private func confirmPaypalPaymentAndRedeemBoost(
        amount: FiatMoney,
        paymentId: String,
        approvalParams: Paypal.OneTimePaymentWebAuthApprovalParams,
    ) async throws {
        let paymentIntentId = try await Paypal.confirmOneTimePayment(
            amount: amount,
            level: .boostBadge,
            paymentId: paymentId,
            approvalParams: approvalParams,
        )

        try await DonationViewsUtil.waitForRedemption(paymentMethod: .paypal) {
            try await DonationSubscriptionManager.requestAndRedeemReceipt(
                boostPaymentIntentId: paymentIntentId,
                amount: amount,
                paymentProcessor: .braintree,
                paymentMethod: .paypal,
            )
        }
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension DonateViewController: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        view.window!
    }
}
