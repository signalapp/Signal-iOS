//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

extension DonationPaymentDetailsViewController {
    /// Make a gift donation.
    ///
    /// See also: code for other payment methods, such as Apple Pay.
    func giftDonation(
        with creditOrDebitCard: Stripe.PaymentMethod.CreditOrDebitCard,
        in thread: TSContactThread,
        messageText: String,
    ) {
        Logger.info("[Gifting] Starting gift donation with credit/debit card")

        Task {
            do {
                try await DonationViewsUtil.wrapInProgressView(
                    from: self,
                    operation: {
                        try await throwIfAlreadySendingGift(threadUniqueId: thread.uniqueId)

                        let preparedPayment = try await DonationViewsUtil.Gifts.prepareToPay(
                            amount: self.donationAmount,
                            creditOrDebitCard: creditOrDebitCard,
                        )

                        guard await DonationViewsUtil.Gifts.showSafetyNumberConfirmationIfNecessary(for: thread) else {
                            throw DonationViewsUtil.Gifts.SendGiftError.userCanceledBeforeChargeCompleted
                        }

                        try await DonationViewsUtil.Gifts.startJob(
                            amount: self.donationAmount,
                            preparedPayment: preparedPayment,
                            thread: thread,
                            messageText: messageText,
                            databaseStorage: SSKEnvironment.shared.databaseStorageRef,
                            blockingManager: SSKEnvironment.shared.blockingManagerRef,
                        )
                    },
                )
                Logger.info("[Gifting] Gifting card donation finished")
                self.onFinished(nil)
            } catch {
                owsPrecondition(error is DonationViewsUtil.Gifts.SendGiftError)
                Logger.warn("[Gifting] Gifting card donation failed")
                self.onFinished(error)
            }
        }
    }

    private nonisolated func throwIfAlreadySendingGift(threadUniqueId: String) async throws {
        try SSKEnvironment.shared.databaseStorageRef.read { transaction in
            try DonationViewsUtil.Gifts.throwIfAlreadySendingGift(
                threadId: threadUniqueId,
                transaction: transaction,
            )
        }
    }
}
