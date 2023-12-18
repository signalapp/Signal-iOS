//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import PassKit
import SignalMessaging
import SignalUI

extension DonationViewsUtil {
    /// Utilities for sending gift donations.
    ///
    /// The gifting process is as follows:
    ///
    /// 1. Throw if we're already sending a gift. See ``throwIfAlreadySendingGift``.
    /// 2. Prepare to pay. This is different for each payment method. For example, Apple Pay will
    ///    create a payment intent and a payment method, but not actually do a charge. See
    ///    ``prepareToPay``.
    /// 3. Show the safety number confirmation dialog if necessary, throwing if the user rejects.
    ///    See ``showSafetyNumberConfirmationIfNecessary``.
    /// 4. Start the job and wait for it to finish/fail. See ``startJob``.
    ///
    /// Each payment method behaves slightly differently, but has these four steps.
    ///
    /// Errors should all be displayed the same way.
    enum Gifts {
        enum SendGiftError: Error {
            case recipientIsBlocked
            case failedAndUserNotCharged
            case failedAndUserMaybeCharged
            case userCanceledBeforeChargeCompleted
        }

        enum SafetyNumberConfirmationResult {
            case userDidNotConfirmSafetyNumberChange
            case userConfirmedSafetyNumberChangeOrNoChangeWasNeeded
        }

        /// Throw if the user is already sending a gift to this person. This should be checked
        /// before sending a gift as the first step.
        ///
        /// This unusual situation can happen if:
        ///
        /// 1. The user enqueues a "send gift badge" job for this recipient
        /// 2. The app is terminated (e.g., due to a crash)
        /// 3. Before the job finishes, the user restarts the app and tries to gift another badge to
        ///    the same person
        ///
        /// This *could* happen without a Signal developer making a mistake, if the app is
        /// terminated at the right time and network conditions are right.
        static func throwIfAlreadySendingGift(
            to thread: TSContactThread,
            transaction: SDSAnyReadTransaction
        ) throws {
            let isAlreadyGifting = DonationUtilities.sendGiftBadgeJobQueue.alreadyHasJob(
                for: thread,
                transaction: transaction
            )
            if isAlreadyGifting {
                Logger.warn("[Gifting] Already sending a gift to this recipient")
                throw SendGiftError.failedAndUserNotCharged
            }
        }

        /// Prepare a payment with Apple Pay, using Stripe.
        static func prepareToPay(
            amount: FiatMoney,
            applePayPayment: PKPayment
        ) -> Promise<PreparedGiftPayment> {
            prepareToPay(
                amount: amount,
                withStripePaymentMethod: .applePay(payment: applePayPayment)
            )
        }

        /// Prepare a payment with a credit/debit card, using Stripe.
        static func prepareToPay(
            amount: FiatMoney,
            creditOrDebitCard: Stripe.PaymentMethod.CreditOrDebitCard
        ) -> Promise<PreparedGiftPayment> {
            prepareToPay(
                amount: amount,
                withStripePaymentMethod: .creditOrDebitCard(creditOrDebitCard: creditOrDebitCard)
            )
        }

        /// Prepare a payment with Stripe.
        private static func prepareToPay(
            amount: FiatMoney,
            withStripePaymentMethod paymentMethod: Stripe.PaymentMethod
        ) -> Promise<PreparedGiftPayment> {
            firstly(on: DispatchQueue.sharedUserInitiated) {
                Stripe.createBoostPaymentIntent(for: amount, level: .giftBadge(.signalGift), paymentMethod: paymentMethod.stripePaymentMethod)
            }.then(on: DispatchQueue.sharedUserInitiated) { paymentIntent -> Promise<PreparedGiftPayment> in
                Stripe.createPaymentMethod(with: paymentMethod).map { paymentMethodId in
                    .forStripe(paymentIntent: paymentIntent, paymentMethodId: paymentMethodId)
                }
            }.timeout(seconds: 30) {
                Logger.warn("[Gifting] Timed out after preparing gift badge payment")
                return SendGiftError.failedAndUserNotCharged
            }
        }

        /// Show a safety number sheet if necessary for the thread.
        ///
        /// Because some screens care, returns the promise and whether the user needs to intervene.
        static func showSafetyNumberConfirmationIfNecessary(
            for thread: TSContactThread
        ) -> (needsUserInteraction: Bool, promise: Promise<SafetyNumberConfirmationResult>) {
            let (promise, future) = Promise<SafetyNumberConfirmationResult>.pending()

            let needsUserInteraction = SafetyNumberConfirmationSheet.presentIfNecessary(
                address: thread.contactAddress,
                confirmationText: SafetyNumberStrings.confirmSendButton
            ) { didConfirm in
                if didConfirm {
                    // After confirming, show it again if it changed *again*.
                    future.resolve(
                        on: DispatchQueue.main,
                        with: showSafetyNumberConfirmationIfNecessary(for: thread).promise
                    )
                } else {
                    future.resolve(.userDidNotConfirmSafetyNumberChange)
                }
            }
            if needsUserInteraction {
                Logger.info("[Gifting] Showing safety number confirmation sheet")
            } else {
                Logger.info("[Gifting] Not showing safety number confirmation sheet; it was not needed")
                future.resolve(.userConfirmedSafetyNumberChangeOrNoChangeWasNeeded)
            }

            return (needsUserInteraction: needsUserInteraction, promise: promise)
        }

        /// Runs the gifting job.
        ///
        /// Durably enqueues a job to (1) do the charge (2) redeem the receipt
        /// credential (3) enqueue a gift badge message (and optionally a text
        /// message) to the reipient.
        ///
        /// Before attempting the job, we double-check that the recipient isn't
        /// blocked. This isn't required from a correctness perspective -- the job
        /// will triple-check that the recipient isn't blocked. However, once we
        /// attempt the job, we have to report a "might have been charged" error, so
        /// it's good to double-check before issuing a charge.
        ///
        /// The `onChargeSucceeded` block will be called when the charge succeeds
        /// but before the message is sent. This may be useful for the UI. However,
        /// note that the block isn't invoked until *after* the charge succeeds, so
        /// the charge may succeed even if the block hasn't yet been invoked.
        static func startJob(
            amount: FiatMoney,
            preparedPayment: PreparedGiftPayment,
            thread: TSContactThread,
            messageText: String,
            databaseStorage: SDSDatabaseStorage,
            blockingManager: BlockingManager,
            onChargeSucceeded: @escaping () -> Void = {}
        ) -> Promise<Void> {
            let jobRecord = SendGiftBadgeJobQueue.createJob(
                preparedPayment: preparedPayment,
                receiptRequest: SubscriptionManagerImpl.generateReceiptRequest(),
                amount: amount,
                thread: thread,
                messageText: messageText
            )
            return Promise.wrapAsync {
                let chargePromise: Promise<Void>
                let completionPromise: Promise<Void>
                (chargePromise, completionPromise) = try await databaseStorage.awaitableWrite { tx in
                    if blockingManager.isAddressBlocked(thread.contactAddress, transaction: tx) {
                        throw SendGiftError.recipientIsBlocked
                    }
                    return DonationUtilities.sendGiftBadgeJobQueue.addJob(jobRecord, tx: tx)
                }
                do {
                    try await chargePromise.awaitable()
                    await MainActor.run { onChargeSucceeded() }
                    try await completionPromise.awaitable()
                } catch {
                    throw SendGiftError.failedAndUserMaybeCharged
                }
            }
        }

        /// Show an error message for a given error.
        static func presentErrorSheetIfApplicable(for error: SendGiftError) {
            let title: String
            let message: String

            switch error {
            case .userCanceledBeforeChargeCompleted:
                return
            case .recipientIsBlocked:
                title = OWSLocalizedString(
                    "DONATION_ON_BEHALF_OF_A_FRIEND_RECIPIENT_IS_BLOCKED_ERROR_TITLE",
                    comment: "Users can donate on a friend's behalf. This is the title for an error message that appears if the try to do this, but the recipient is blocked."
                )
                message = OWSLocalizedString(
                    "DONATION_ON_BEHALF_OF_A_FRIEND_RECIPIENT_IS_BLOCKED_ERROR_BODY",
                    comment: "Users can donate on a friend's behalf. This is the error message that appears if the try to do this, but the recipient is blocked."
                )
            case .failedAndUserNotCharged:
                title = OWSLocalizedString(
                    "DONATION_ON_BEHALF_OF_A_FRIEND_PAYMENT_FAILED_ERROR_TITLE",
                    comment: "Users can donate on a friend's behalf. If the payment fails and the user has not been charged, an error dialog will be shown. This is the title of that dialog."
                )
                message = OWSLocalizedString(
                    "DONATION_ON_BEHALF_OF_A_FRIEND_PAYMENT_FAILED_ERROR_BODY",
                    comment: "Users can donate on a friend's behalf. If the payment fails and the user has not been charged, this error message is shown."
                )
            case .failedAndUserMaybeCharged:
                title = OWSLocalizedString(
                    "DONATION_ON_BEHALF_OF_A_FRIEND_PAYMENT_SUCCEEDED_BUT_MESSAGE_FAILED_ERROR_TITLE",
                    comment: "Users can donate on a friend's behalf. If the payment was processed but the donation failed to send, an error dialog will be shown. This is the title of that dialog."
                )
                message = OWSLocalizedString(
                    "DONATION_ON_BEHALF_OF_A_FRIEND_PAYMENT_SUCCEEDED_BUT_MESSAGE_FAILED_ERROR_BODY",
                    comment: "Users can donate on a friend's behalf. If the payment was processed but the donation failed to send, this error message will be shown."
                )
            }

            OWSActionSheets.showActionSheet(title: title, message: message)
        }
    }
}
