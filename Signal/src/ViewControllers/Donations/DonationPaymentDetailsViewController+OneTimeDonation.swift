//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import SignalUI

extension DonationPaymentDetailsViewController {
    /// Make a one-time donation.
    ///
    /// See also: code for other payment methods, such as Apple Pay.
    func oneTimeDonation(with validForm: FormState.ValidForm) {
        let db = DependenciesBridge.shared.db
        let donationPermitFetcher = DependenciesBridge.shared.donationPermitFetcher
        let donationSubscriptionManager = DependenciesBridge.shared.donationSubscriptionManager
        let idealStore = DependenciesBridge.shared.pendingIDEALDonationStore
        let networkManager = SSKEnvironment.shared.networkManagerRef

        Logger.info("[Donations] Starting one-time donation")

        let amount = self.donationAmount

        Task {
            do {
                try await DonationViewsUtil.wrapInProgressView(
                    from: self,
                    operation: {
                        let confirmedIntent = try await Retry.performWithBackoff(maxAttempts: 3) {
                            let donationPermit = try await donationPermitFetcher.fetchDonationPermit()

                            return try await Stripe.boost(
                                amount: amount,
                                level: .boostBadge,
                                for: validForm.stripePaymentMethod,
                                donationPermit: donationPermit,
                                networkManager: networkManager,
                            )
                        }

                        let intentId: String
                        if let redirectUrl = confirmedIntent.redirectToUrl {
                            if case .ideal = validForm.donationPaymentMethod {
                                Logger.info("[Donations] One-time iDEAL donation requires authentication. Presenting...")
                                let donation = PendingOneTimeIDEALDonation(
                                    paymentIntentId: confirmedIntent.paymentIntentId,
                                    amount: amount,
                                )
                                await db.awaitableWrite { tx in
                                    // Set the unclaimed iDEAL paymentID
                                    idealStore.setDonationNeedsHandling(
                                        isOneTime: true,
                                        intentId: donation.paymentIntentId,
                                        tx: tx,
                                    )
                                    idealStore.setPendingOneTimeDonation(
                                        donation: donation,
                                        tx: tx,
                                    )
                                }
                            } else {
                                Logger.info("[Donations] One-time donation needed 3DS. Presenting...")
                            }
                            intentId = try await self.show3DS(for: redirectUrl).awaitable()
                        } else {
                            Logger.info("[Donations] One-time donation did not need 3DS. Continuing")
                            intentId = confirmedIntent.paymentIntentId
                        }

                        if case .ideal = validForm.donationPaymentMethod {
                            let hasDonationToClaim = await db.awaitableWrite { tx in
                                idealStore.claimDonationHandling(
                                    isOneTime: true,
                                    intentId: intentId,
                                    tx: tx,
                                )
                            }
                            if !hasDonationToClaim {
                                Logger.info("[Donations] One-time iDEAL donation already handled. Continuing")
                                return
                            }
                        }
                        Logger.info("[Donations] Creating and redeeming one-time boost receipt")
                        try await DonationViewsUtil.redeemOneTimeDonation(
                            paymentIntentId: intentId,
                            amount: amount,
                            paymentProcessor: .stripe,
                            paymentMethod: validForm.donationPaymentMethod,
                            db: db,
                            donationSubscriptionManager: donationSubscriptionManager,
                            idealStore: idealStore,
                        )
                    },
                )
                Logger.info("[Donations] One-time donation finished")
                self.onFinished(nil)
            } catch {
                Logger.warn("[Donations] One-time donation UX dismissing with error. \(error)")
                self.onFinished(error)
            }
        }
    }
}
