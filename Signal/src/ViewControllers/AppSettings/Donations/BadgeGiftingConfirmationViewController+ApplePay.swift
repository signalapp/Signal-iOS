//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import PassKit
import SignalMessaging

extension BadgeGiftingConfirmationViewController {
    func startApplePay() {
        Logger.info("[Gifting] Requesting Apple Pay...")

        let request = DonationUtilities.newPaymentRequest(for: self.price, isRecurring: false)

        let paymentController = PKPaymentAuthorizationController(paymentRequest: request)
        paymentController.delegate = self
        paymentController.present { presented in
            if !presented {
                // This can happen under normal conditions if the user double-taps the button,
                // but may also indicate a problem.
                Logger.warn("[Gifting] Failed to present payment controller")
            }
        }
    }
}

extension BadgeGiftingConfirmationViewController: PKPaymentAuthorizationControllerDelegate {
    func paymentAuthorizationController(
        _ controller: PKPaymentAuthorizationController,
        didAuthorizePayment payment: PKPayment,
        handler completion: @escaping (PKPaymentAuthorizationResult) -> Void
    ) {
        var hasCalledCompletion = false
        func wrappedCompletion(_ result: PKPaymentAuthorizationResult) {
            guard !hasCalledCompletion else { return }
            hasCalledCompletion = true
            completion(result)
        }

        firstly(on: .global()) { () -> Promise<Void> in
            try self.databaseStorage.read { transaction in
                try DonationViewsUtil.Gifts.throwIfAlreadySendingGift(
                    to: self.thread,
                    transaction: transaction
                )
            }
            return Promise.value(())
        }.then(on: .global()) {
            DonationViewsUtil.Gifts.prepareToPay(amount: self.price, applePayPayment: payment)
        }.then(on: .main) { [weak self] preparedPayment -> Promise<DonationViewsUtil.Gifts.PreparedGiftPayment> in
            guard let self else {
                throw DonationViewsUtil.Gifts.SendGiftError.userCanceledBeforeChargeCompleted
            }

            let safetyNumberConfirmationResult = DonationViewsUtil.Gifts.showSafetyNumberConfirmationIfNecessary(
                for: self.thread
            )
            if safetyNumberConfirmationResult.needsUserInteraction {
                wrappedCompletion(.init(status: .success, errors: nil))
            }

            return safetyNumberConfirmationResult.promise.map { safetyNumberConfirmationResult in
                switch safetyNumberConfirmationResult {
                case .userDidNotConfirmSafetyNumberChange:
                    throw DonationViewsUtil.Gifts.SendGiftError.userCanceledBeforeChargeCompleted
                case .userConfirmedSafetyNumberChangeOrNoChangeWasNeeded:
                    return preparedPayment
                }
            }
        }.then { [weak self] preparedPayment -> Promise<Void> in
            guard let self else {
                throw DonationViewsUtil.Gifts.SendGiftError.userCanceledBeforeChargeCompleted
            }

            var modalActivityIndicatorViewController: ModalActivityIndicatorViewController?
            var shouldDismissActivityIndicator = false
            func presentModalActivityIndicatorIfNotAlreadyPresented() {
                guard modalActivityIndicatorViewController == nil else { return }
                ModalActivityIndicatorViewController.present(fromViewController: self, canCancel: false) { modal in
                    DispatchQueue.main.async {
                        modalActivityIndicatorViewController = modal
                        // Depending on how things are dispatched, we could need the modal closed immediately.
                        if shouldDismissActivityIndicator {
                            modal.dismiss {}
                        }
                    }
                }
            }

            // This is unusual, but can happen if the Apple Pay sheet was dismissed earlier in the
            // process, which can happen if the user needed to confirm a safety number change.
            if hasCalledCompletion {
                presentModalActivityIndicatorIfNotAlreadyPresented()
            }

            func finish() {
                if let modalActivityIndicatorViewController = modalActivityIndicatorViewController {
                    modalActivityIndicatorViewController.dismiss {}
                } else {
                    shouldDismissActivityIndicator = true
                }
            }

            return DonationViewsUtil.Gifts.startJob(
                amount: self.price,
                paymentProcessor: .stripe,
                preparedPayment: preparedPayment,
                thread: self.thread,
                messageText: self.messageText,
                databaseStorage: self.databaseStorage,
                blockingManager: self.blockingManager,
                onChargeSucceeded: {
                    wrappedCompletion(.init(status: .success, errors: nil))
                    controller.dismiss()
                    presentModalActivityIndicatorIfNotAlreadyPresented()
                }
            ).done(on: .main) {
                finish()
            }.recover(on: .main) { error in
                finish()
                throw error
            }
        }.done { [weak self] in
            // We shouldn't need to dismiss the Apple Pay sheet here, but if the `chargeSucceeded`
            // event was missed, we do our best.
            wrappedCompletion(.init(status: .success, errors: nil))
            self?.didCompleteDonation()
        }.catch { error in
            guard let error = error as? DonationViewsUtil.Gifts.SendGiftError else {
                owsFail("\(error)")
            }

            wrappedCompletion(.init(status: .failure, errors: [error]))

            DonationViewsUtil.Gifts.presentErrorSheetIfApplicable(for: error)
        }
    }

    func paymentAuthorizationControllerDidFinish(_ controller: PKPaymentAuthorizationController) {
        controller.dismiss()
    }
}
