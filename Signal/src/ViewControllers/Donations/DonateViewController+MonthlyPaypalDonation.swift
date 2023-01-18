//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging

extension DonateViewController {
    /// Start a monthly subscription using PayPal.
    ///
    /// Please note related methods/code for subscriptions via Apple Pay and cards.
    func startPaypalSubscription(
        with amount: FiatMoney,
        badge: ProfileBadge
    ) {
        guard
            let monthly = state.monthly,
            let selectedSubscriptionLevel = monthly.selectedSubscriptionLevel
        else {
            owsFail("[Donations] Invalid state; cannot pay")
        }

        Logger.info("[Donations] Starting monthly PayPal donation")

        firstly(on: .main) { () -> Promise<(Data, Paypal.SubscriptionAuthorizationParams)> in
            self.preparePaypalSubscriptionBehindActivityIndicator(
                monthlyState: monthly,
                selectedSubscriptionLevel: selectedSubscriptionLevel
            )
        }.then(on: .main) { (subscriberId, authorizationParams) -> Promise<(Data, String)> in
            Logger.info("[Donations] Authorizing payment for new monthly subscription with PayPal")

            return firstly { () -> Promise<Paypal.MonthlyPaymentWebAuthApprovalParams> in
                if #available(iOS 13, *) {
                    return Paypal.presentExpectingApprovalParams(
                        approvalUrl: authorizationParams.approvalUrl,
                        withPresentationContext: self
                    )
                } else {
                    return Paypal.presentExpectingApprovalParams(
                        approvalUrl: authorizationParams.approvalUrl
                    )
                }
            }.map(on: .sharedUserInitiated) { _ in
                (subscriberId, authorizationParams.paymentMethodId)
            }
        }.then(on: .main) { (subscriberId, paymentId) -> Promise<Void> in
            self.finalizePaypalSubscriptionBehindProgressView(
                subscriberId: subscriberId,
                paymentId: paymentId,
                monthlyState: monthly,
                selectedSubscriptionLevel: selectedSubscriptionLevel
            )
        }.done(on: .main) { () throws in
            Logger.info("[Donations] Monthly PayPal donation finished")

            self.didCompleteDonation(
                badge: selectedSubscriptionLevel.badge,
                thanksSheetType: .subscription
            )
        }.catch(on: .main) { [weak self] error in
            guard let self else { return }

            if let webAuthError = error as? Paypal.AuthError {
                switch webAuthError {
                case .userCanceled:
                    Logger.info("[Donations] Monthly PayPal donation canceled")

                    self.didCancelDonation()
                }
            } else {
                Logger.info("[Donations] Monthly PayPal donation failed")

                self.didFailDonation(error: error, mode: .monthly, paymentMethod: .paypal)
            }
        }
    }

    /// Prepare a PayPal subscription for web authentication behind blocking
    /// UI. Must be called on the main thread.
    ///
    /// - Returns
    /// A subscriber ID and parameters for authorizing the subscription via web
    /// auth.
    private func preparePaypalSubscriptionBehindActivityIndicator(
        monthlyState monthly: State.MonthlyState,
        selectedSubscriptionLevel: SubscriptionLevel
    ) -> Promise<(Data, Paypal.SubscriptionAuthorizationParams)> {
        AssertIsOnMainThread()

        let (promise, future) = Promise<(Data, Paypal.SubscriptionAuthorizationParams)>.pending()

        ModalActivityIndicatorViewController.present(
            fromViewController: self,
            canCancel: false
        ) { modal in
            firstly { () -> Promise<Void> in
                if let existingSubscriberId = monthly.subscriberID, monthly.currentSubscription != nil {
                    Logger.info("[Donations] Cancelling existing subscription")

                    return SubscriptionManager.cancelSubscription(for: existingSubscriberId)
                } else {
                    Logger.info("[Donations] No existing subscription to cancel")

                    return Promise.value(())
                }
            }.then(on: .sharedUserInitiated) { () -> Promise<Data> in
                Logger.info("[Donations] Preparing new monthly subscription with PayPal")

                return SubscriptionManager.prepareNewSubscription(
                    currencyCode: monthly.selectedCurrencyCode
                )
            }.then(on: .sharedUserInitiated) { subscriberId -> Promise<(Data, Paypal.SubscriptionAuthorizationParams)> in
                Logger.info("[Donations] Creating Signal payment method for new monthly subscription with PayPal")

                return Paypal.createSignalPaymentMethodForSubscription(subscriberId: subscriberId)
                    .map(on: .sharedUserInitiated) { createParams in (subscriberId, createParams) }
            }.map(on: .main) { retVal in
                modal.dismiss { future.resolve(retVal) }
            }.catch(on: .main) { error in
                modal.dismiss { future.reject(error) }
            }
        }

        return promise
    }

    /// Finalize a PayPal subscription after web authentication, behind blocking
    /// UI. Must be called on the main thread.
    private func finalizePaypalSubscriptionBehindProgressView(
        subscriberId: Data,
        paymentId: String,
        monthlyState monthly: State.MonthlyState,
        selectedSubscriptionLevel: SubscriptionLevel
    ) -> Promise<Void> {
        AssertIsOnMainThread()

        let finalizePromise: Promise<Void> = firstly { () -> Promise<Subscription> in
            Logger.info("[Donations] Finalizing new subscription for PayPal donation")

            return SubscriptionManager.finalizeNewSubscription(
                forSubscriberId: subscriberId,
                withPaymentId: paymentId,
                usingPaymentMethod: .paypal,
                subscription: selectedSubscriptionLevel,
                currencyCode: monthly.selectedCurrencyCode
            )
        }.then(on: .sharedUserInitiated) { _ -> Promise<Void> in
            Logger.info("[Donations] Redeeming monthly receipt for PayPal donation")

            DonationViewsUtil.redeemMonthlyReceipts(
                usingPaymentProcessor: .braintree,
                subscriberID: subscriberId,
                newSubscriptionLevel: selectedSubscriptionLevel,
                priorSubscriptionLevel: monthly.currentSubscriptionLevel
            )

            return DonationViewsUtil.waitForSubscriptionJob()
        }

        return DonationViewsUtil.wrapPromiseInProgressView(
            from: self,
            promise: finalizePromise
        )
    }
}
