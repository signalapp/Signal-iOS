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
        Logger.info("[Donations] Starting one-time donation")

        let amount = self.donationAmount

        Task {
            do {
                try await DonationViewsUtil.wrapInProgressView(
                    from: self,
                    operation: {
                        let confirmedIntent = try await Stripe.boost(
                            amount: amount,
                            level: .boostBadge,
                            for: validForm.stripePaymentMethod,
                        )

                        let intentId: String
                        if let redirectUrl = confirmedIntent.redirectToUrl {
                            if case .ideal = validForm.donationPaymentMethod {
                                Logger.info("[Donations] One-time iDEAL donation requires authentication. Presenting...")
                                let donation = PendingOneTimeIDEALDonation(
                                    paymentIntentId: confirmedIntent.paymentIntentId,
                                    amount: amount,
                                )
                                await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { transaction in
                                    do {
                                        try DependenciesBridge.shared.externalPendingIDEALDonationStore.setPendingOneTimeDonation(
                                            donation: donation,
                                            tx: transaction,
                                        )
                                    } catch {
                                        owsFailDebug("[Donations] Failed to persist pending One-time iDEAL donation")
                                    }
                                }
                            } else {
                                Logger.info("[Donations] One-time donation needed 3DS. Presenting...")
                            }
                            intentId = try await self.show3DS(for: redirectUrl).awaitable()
                        } else {
                            Logger.info("[Donations] One-time donation did not need 3DS. Continuing")
                            intentId = confirmedIntent.paymentIntentId
                        }

                        Logger.info("[Donations] Creating and redeeming one-time boost receipt")
                        try await DonationViewsUtil.completeOneTimeDonation(
                            paymentIntentId: intentId,
                            amount: amount,
                            paymentMethod: validForm.donationPaymentMethod,
                            databaseStorage: SSKEnvironment.shared.databaseStorageRef,
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
