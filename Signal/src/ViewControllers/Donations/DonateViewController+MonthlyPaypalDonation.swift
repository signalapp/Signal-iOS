//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

extension DonateViewController {
    /// Start a monthly subscription using PayPal.
    ///
    /// Please note related methods/code for subscriptions via Apple Pay and cards.
    func startPaypalSubscription(
        with amount: FiatMoney,
        badge: ProfileBadge,
    ) {
        guard
            let monthly = state.monthly,
            let selectedSubscriptionLevel = monthly.selectedSubscriptionLevel
        else {
            owsFail("[Donations] Invalid state; cannot pay")
        }

        Task {
            do {
                Logger.info("[Donations] Starting monthly PayPal donation")
                let (subscriberId, authorizationParams) = try await self.preparePaypalSubscriptionBehindActivityIndicator(
                    monthlyState: monthly,
                    selectedSubscriptionLevel: selectedSubscriptionLevel,
                )
                let paymentMethodId = authorizationParams.paymentMethodId

                Logger.info("[Donations] Authorizing payment for new monthly subscription with PayPal")
                _ = try await Paypal.presentExpectingApprovalParams(
                    approvalUrl: authorizationParams.approvalUrl,
                    withPresentationContext: self,
                ) as Paypal.MonthlyPaymentWebAuthApprovalParams

                try await self.finalizePaypalSubscriptionBehindProgressView(
                    subscriberId: subscriberId,
                    paymentMethodId: paymentMethodId,
                    monthlyState: monthly,
                    selectedSubscriptionLevel: selectedSubscriptionLevel,
                )

                Logger.info("[Donations] Monthly PayPal donation finished")
                self.didCompleteDonation(
                    receiptCredentialSuccessMode: .recurringSubscriptionInitiation,
                )
            } catch Paypal.AuthError.userCanceled {
                Logger.info("[Donations] Monthly PayPal donation canceled")
                self.didCancelDonation()
            } catch {
                Logger.info("[Donations] Monthly PayPal donation failed")
                self.didFailDonation(
                    error: error,
                    mode: .monthly,
                    badge: selectedSubscriptionLevel.badge,
                    paymentMethod: .paypal,
                )
            }
        }
    }

    /// Prepare a PayPal subscription for web authentication behind blocking
    /// UI.
    ///
    /// - Returns
    /// A subscriber ID and parameters for authorizing the subscription via web
    /// auth.
    private func preparePaypalSubscriptionBehindActivityIndicator(
        monthlyState monthly: State.MonthlyState,
        selectedSubscriptionLevel: DonationSubscriptionLevel,
    ) async throws -> (Data, Paypal.SubscriptionAuthorizationParams) {
        return try await ModalActivityIndicatorViewController.presentAndPropagateResult(
            from: self,
            title: CommonStrings.preparingModal,
            wrappedAsyncBlock: {
                if let existingSubscriberId = monthly.subscriberID {
                    Logger.info("[Donations] Cancelling existing subscription")
                    try await DependenciesBridge.shared.donationSubscriptionManager.cancelSubscription(for: existingSubscriberId)
                } else {
                    Logger.info("[Donations] No existing subscription to cancel")
                }

                Logger.info("[Donations] Preparing new monthly subscription with PayPal")
                let subscriberId = try await DependenciesBridge.shared.donationSubscriptionManager.prepareNewSubscription(
                    currencyCode: monthly.selectedCurrencyCode,
                )

                Logger.info("[Donations] Creating Signal payment method for new monthly subscription with PayPal")
                let createParams = try await Paypal.createSignalPaymentMethodForSubscription(subscriberId: subscriberId)
                return (subscriberId, createParams)
            },
        )
    }

    /// Finalize a PayPal subscription after web authentication, behind blocking
    /// UI.
    private func finalizePaypalSubscriptionBehindProgressView(
        subscriberId: Data,
        paymentMethodId: String,
        monthlyState monthly: State.MonthlyState,
        selectedSubscriptionLevel: DonationSubscriptionLevel,
    ) async throws {
        let db = DependenciesBridge.shared.db
        let donationSubscriptionManager = DependenciesBridge.shared.donationSubscriptionManager
        let idealStore = DependenciesBridge.shared.externalPendingIDEALDonationStore

        return try await DonationViewsUtil.wrapInProgressView(
            from: self,
            operation: {
                try await DonationViewsUtil.finalizeAndRedeemMonthlyDonation(
                    subscriberId: subscriberId,
                    paymentType: .paypal(paymentMethodId: paymentMethodId),
                    newSubscriptionLevel: selectedSubscriptionLevel,
                    priorSubscriptionLevel: monthly.currentSubscriptionLevel,
                    currencyCode: monthly.selectedCurrencyCode,
                    db: db,
                    donationSubscriptionManager: donationSubscriptionManager,
                    idealStore: idealStore,
                )
            },
        )
    }
}
