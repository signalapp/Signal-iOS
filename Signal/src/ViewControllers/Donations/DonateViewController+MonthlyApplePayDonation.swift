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
    func paymentAuthorizationControllerForMonthly(
        _ controller: PKPaymentAuthorizationController,
        didAuthorizePayment payment: PKPayment,
        handler completion: @escaping (PKPaymentAuthorizationResult) -> Void
    ) {
        guard
            let monthly = state.monthly,
            let selectedSubscriptionLevel = monthly.selectedSubscriptionLevel
        else {
            owsFail("Invalid state; cannot pay")
        }

        let subscriptionLevels = monthly.subscriptionLevels
        let selectedCurrencyCode = monthly.selectedCurrencyCode

        if let currentSubscription = monthly.currentSubscription,
           let priorSubscriptionLevel = DonationViewsUtil.subscriptionLevelForSubscription(
            subscriptionLevels: subscriptionLevels,
            subscription: currentSubscription
           ),
           let subscriberID = monthly.subscriberID {
            firstly {
                try SubscriptionManager.updateSubscriptionLevel(
                    for: subscriberID,
                    to: selectedSubscriptionLevel,
                    payment: payment,
                    currencyCode: selectedCurrencyCode
                )
            }.done(on: .main) {
                let authResult = PKPaymentAuthorizationResult(status: .success, errors: nil)
                completion(authResult)
                SubscriptionManager.terminateTransactionIfPossible = false
                self.fetchAndRedeemReceipts(
                    newSubscriptionLevel: selectedSubscriptionLevel,
                    priorSubscriptionLevel: priorSubscriptionLevel
                )
            }.catch { error in
                let authResult = PKPaymentAuthorizationResult(status: .failure, errors: [error])
                completion(authResult)
                SubscriptionManager.terminateTransactionIfPossible = false
                owsFailDebug("Error setting up subscription, \(error)")
            }

        } else {
            firstly {
                return try SubscriptionManager.setupNewSubscription(
                    subscription: selectedSubscriptionLevel,
                    payment: payment,
                    currencyCode: selectedCurrencyCode
                )
            }.done(on: .main) {
                let authResult = PKPaymentAuthorizationResult(status: .success, errors: nil)
                completion(authResult)
                SubscriptionManager.terminateTransactionIfPossible = false
                self.fetchAndRedeemReceipts(
                    newSubscriptionLevel: selectedSubscriptionLevel,
                    priorSubscriptionLevel: nil
                )
            }.catch(on: .main) { error in
                let authResult = PKPaymentAuthorizationResult(status: .failure, errors: [error])
                completion(authResult)
                SubscriptionManager.terminateTransactionIfPossible = false
                owsFailDebug("Error setting up subscription, \(error)")
            }
        }
    }

    private func fetchAndRedeemReceipts(
        newSubscriptionLevel: SubscriptionLevel,
        priorSubscriptionLevel: SubscriptionLevel?
    ) {
        guard let subscriberID = databaseStorage.read(
            block: { SubscriptionManager.getSubscriberID(transaction: $0) }
        ) else {
            return owsFailDebug("Did not fetch subscriberID")
        }

        SubscriptionManager.requestAndRedeemReceiptsIfNecessary(
            for: subscriberID,
            subscriptionLevel: newSubscriptionLevel.level,
            priorSubscriptionLevel: priorSubscriptionLevel?.level
        )

        let backdropView = UIView()
        backdropView.backgroundColor = Theme.backdropColor
        backdropView.alpha = 0
        view.addSubview(backdropView)
        backdropView.autoPinEdgesToSuperviewEdges()

        let progressViewContainer = UIView()
        progressViewContainer.backgroundColor = Theme.backgroundColor
        progressViewContainer.layer.cornerRadius = 12
        backdropView.addSubview(progressViewContainer)
        progressViewContainer.autoCenterInSuperview()

        let progressView = AnimatedProgressView(loadingText: NSLocalizedString(
            "SUSTAINER_VIEW_PROCESSING_PAYMENT",
            comment: "Loading indicator on the sustainer view"
        ))
        view.addSubview(progressView)
        progressView.autoCenterInSuperview()
        progressViewContainer.autoMatch(.width, to: .width, of: progressView, withOffset: 32)
        progressViewContainer.autoMatch(.height, to: .height, of: progressView, withOffset: 32)

        progressView.startAnimating {
            backdropView.alpha = 1
        }

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
            if notification.name == SubscriptionManager.SubscriptionJobQueueDidFailJobNotification {
                throw DonationJobError.assertion
            }

            progressView.stopAnimating(success: true) {
                backdropView.alpha = 0
            } completion: {
                backdropView.removeFromSuperview()
                progressView.removeFromSuperview()

                self.onFinished(.completedDonation(
                    donateSheet: self,
                    badgeThanksSheet: BadgeThanksSheet(badge: newSubscriptionLevel.badge, type: .subscription)
                ))
            }
        }.catch { error in
            progressView.stopAnimating(success: false) {
                backdropView.alpha = 0
            } completion: { [weak self] in
                backdropView.removeFromSuperview()
                progressView.removeFromSuperview()

                guard let error = error as? DonationJobError else {
                    return owsFailDebug("Unexpected error \(error)")
                }

                guard let self = self else { return }
                switch error {
                case .timeout:
                    DonationViewsUtil.presentStillProcessingSheet(from: self)
                case .assertion:
                    DonationViewsUtil.presentBadgeCantBeAddedSheet(
                        from: self,
                        currentSubscription: self.state.monthly?.currentSubscription
                    )
                }
            }
        }
    }
}
