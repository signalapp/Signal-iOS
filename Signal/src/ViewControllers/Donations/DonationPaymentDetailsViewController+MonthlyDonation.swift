//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

extension DonationPaymentDetailsViewController {
    /// Make a monthly donation.
    ///
    /// See also: code for other payment methods, such as Apple Pay.
    func monthlyDonation(
        with validForm: FormState.ValidForm,
        newSubscriptionLevel: DonationSubscriptionLevel,
        priorSubscriptionLevel: DonationSubscriptionLevel?,
        subscriberID existingSubscriberId: Data?,
    ) {
        let currencyCode = self.donationAmount.currencyCode
        let donationStore = DependenciesBridge.shared.externalPendingIDEALDonationStore

        Logger.info("[Donations] Starting monthly donation")

        Task {
            do {
                try await DonationViewsUtil.wrapInProgressView(
                    from: self,
                    operation: {
                        if let existingSubscriberId {
                            Logger.info("[Donations] Cancelling existing subscription")
                            try await DonationSubscriptionManager.cancelSubscription(for: existingSubscriberId)
                        } else {
                            Logger.info("[Donations] No existing subscription to cancel")
                        }

                        Logger.info("[Donations] Preparing new monthly subscription")
                        let subscriberId = try await DonationSubscriptionManager.prepareNewSubscription(currencyCode: currencyCode)

                        Logger.info("[Donations] Creating Signal payment method for new monthly subscription")
                        let clientSecret = try await Stripe.createSignalPaymentMethodForSubscription(subscriberId: subscriberId)

                        Logger.info("[Donations] Authorizing payment for new monthly subscription")
                        let confirmedIntent = try await Stripe.setupNewSubscription(
                            clientSecret: clientSecret,
                            paymentMethod: validForm.stripePaymentMethod,
                        )

                        if let redirectToUrl = confirmedIntent.redirectToUrl {
                            if case .ideal = validForm.donationPaymentMethod {
                                Logger.info("[Donations] Subscription requires iDEAL authentication. Presenting...")
                                let confirmedDonation = PendingMonthlyIDEALDonation(
                                    subscriberId: subscriberId,
                                    clientSecret: clientSecret,
                                    setupIntentId: confirmedIntent.setupIntentId,
                                    newSubscriptionLevel: newSubscriptionLevel,
                                    oldSubscriptionLevel: priorSubscriptionLevel,
                                    amount: self.donationAmount,
                                )
                                await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
                                    do {
                                        try donationStore.setPendingSubscription(donation: confirmedDonation, tx: tx)
                                    } catch {
                                        owsFailDebug("[Donations] Failed to persist pending iDEAL subscription.")
                                    }
                                }
                            } else {
                                Logger.info("[Donations] Subscription requires 3DS authentication. Presenting...")
                            }
                            _ = try await self.show3DS(for: redirectToUrl).awaitable()
                        }

                        let paymentType: DonationSubscriptionManager.RecurringSubscriptionPaymentType
                        switch validForm {
                        case .card:
                            paymentType = .creditOrDebitCard(paymentMethodId: confirmedIntent.paymentMethodId)
                        case .sepa:
                            paymentType = .sepa(paymentMethodId: confirmedIntent.paymentMethodId)
                        case .ideal:
                            paymentType = .ideal(setupIntentId: confirmedIntent.setupIntentId)
                        }

                        try await DonationViewsUtil.completeMonthlyDonations(
                            subscriberId: subscriberId,
                            paymentType: paymentType,
                            newSubscriptionLevel: newSubscriptionLevel,
                            priorSubscriptionLevel: priorSubscriptionLevel,
                            currencyCode: currencyCode,
                            databaseStorage: SSKEnvironment.shared.databaseStorageRef,
                        )
                    },
                )
                Logger.info("[Donations] Monthly donation finished")
                self.onFinished(nil)
            } catch {
                Logger.info("[Donations] Monthly donation UX dismissing with error. \(error)")
                self.onFinished(error)
            }
        }
    }
}
