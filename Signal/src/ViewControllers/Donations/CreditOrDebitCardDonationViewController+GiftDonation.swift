//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging

extension CreditOrDebitCardDonationViewController {
    /// Make a gift donation.
    ///
    /// See also: code for other payment methods, such as Apple Pay.
    func giftDonation(
        with creditOrDebitCard: Stripe.PaymentMethod.CreditOrDebitCard,
        in thread: TSContactThread,
        messageText: String
    ) {
        Logger.info("[Gifting] Starting gift donation with credit/debit card")

        DonationViewsUtil.wrapPromiseInProgressView(
            from: self,
            promise: firstly(on: .sharedUserInitiated) { () -> Promise<Void> in
                try self.databaseStorage.read { transaction in
                    try DonationViewsUtil.Gifts.throwIfAlreadySendingGift(
                        to: thread,
                        transaction: transaction
                    )
                }
                return Promise.value(())
            }.then(on: .sharedUserInitiated) { [weak self] () -> Promise<PreparedGiftPayment> in
                guard let self else {
                    throw DonationViewsUtil.Gifts.SendGiftError.userCanceledBeforeChargeCompleted

                }
                return DonationViewsUtil.Gifts.prepareToPay(
                    amount: self.donationAmount, creditOrDebitCard: creditOrDebitCard
                )
            }.then(on: .main) { [weak self] preparedPayment -> Promise<PreparedGiftPayment> in
                if self == nil {
                    throw DonationViewsUtil.Gifts.SendGiftError.userCanceledBeforeChargeCompleted

                }
                return DonationViewsUtil.Gifts.showSafetyNumberConfirmationIfNecessary(for: thread)
                    .promise
                    .map { safetyNumberConfirmationResult in
                        switch safetyNumberConfirmationResult {
                        case .userDidNotConfirmSafetyNumberChange:
                            throw DonationViewsUtil.Gifts.SendGiftError.userCanceledBeforeChargeCompleted
                        case .userConfirmedSafetyNumberChangeOrNoChangeWasNeeded:
                            return preparedPayment
                        }
                    }
            }.then(on: .sharedUserInitiated) { [weak self] preparedPayment -> Promise<Void> in
                guard let self else {
                    throw DonationViewsUtil.Gifts.SendGiftError.userCanceledBeforeChargeCompleted
                }

                return DonationViewsUtil.Gifts.startJob(
                    amount: self.donationAmount,
                    preparedPayment: preparedPayment,
                    thread: thread,
                    messageText: messageText,
                    databaseStorage: self.databaseStorage,
                    blockingManager: self.blockingManager
                )
            }
        ).done(on: .main) { [weak self] in
            Logger.info("[Gifting] Gifting card donation finished")
            self?.onFinished()
        }.catch(on: .main) { [weak self] error in
            Logger.warn("[Gifting] Gifting card donation failed")
            self?.didFailDonation(error: error)
        }
    }
}
