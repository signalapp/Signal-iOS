//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import PassKit
import SignalServiceKit
import SignalUI

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
        handler completion: @escaping (PKPaymentAuthorizationResult) -> Void,
    ) {
        var hasCalledCompletion = false
        @MainActor
        func wrappedCompletion(_ result: PKPaymentAuthorizationResult) {
            guard !hasCalledCompletion else { return }
            hasCalledCompletion = true
            completion(result)
        }

        Task {
            do {
                try SSKEnvironment.shared.databaseStorageRef.read { transaction in
                    try DonationViewsUtil.Gifts.throwIfAlreadySendingGift(
                        threadId: self.thread.uniqueId,
                        transaction: transaction,
                    )
                }

                let preparedPayment = try await DonationViewsUtil.Gifts.prepareToPay(amount: self.price, applePayPayment: payment)

                let safetyNumberConfirmationResult = await DonationViewsUtil.Gifts.showSafetyNumberConfirmationIfNecessary(
                    for: self.thread,
                    didPresent: {
                        wrappedCompletion(.init(status: .success, errors: nil))
                    },
                )
                guard safetyNumberConfirmationResult else {
                    throw DonationViewsUtil.Gifts.SendGiftError.userCanceledBeforeChargeCompleted
                }

                var modalActivityIndicatorViewController: ModalActivityIndicatorViewController?
                var shouldDismissActivityIndicator = false
                @MainActor
                func presentModalActivityIndicatorIfNotAlreadyPresented() {
                    guard modalActivityIndicatorViewController == nil else { return }
                    ModalActivityIndicatorViewController.present(fromViewController: self, canCancel: false) { modal in
                        DispatchQueue.main.async {
                            modalActivityIndicatorViewController = modal
                            // Depending on how things are dispatched, we could need the modal closed immediately.
                            if shouldDismissActivityIndicator {
                                modal.dismiss()
                            }
                        }
                    }
                }

                // This is unusual, but can happen if the Apple Pay sheet was dismissed earlier in the
                // process, which can happen if the user needed to confirm a safety number change.
                if hasCalledCompletion {
                    presentModalActivityIndicatorIfNotAlreadyPresented()
                }

                do {
                    defer {
                        if let modalActivityIndicatorViewController {
                            modalActivityIndicatorViewController.dismiss()
                        } else {
                            shouldDismissActivityIndicator = true
                        }
                    }

                    try await DonationViewsUtil.Gifts.startJob(
                        amount: self.price,
                        preparedPayment: preparedPayment,
                        thread: self.thread,
                        messageText: self.messageText,
                        databaseStorage: SSKEnvironment.shared.databaseStorageRef,
                        blockingManager: SSKEnvironment.shared.blockingManagerRef,
                        onChargeSucceeded: {
                            wrappedCompletion(.init(status: .success, errors: nil))
                            controller.dismiss()
                            presentModalActivityIndicatorIfNotAlreadyPresented()
                        },
                    )
                }

                // We shouldn't need to dismiss the Apple Pay sheet here, but if the `chargeSucceeded`
                // event was missed, we do our best.
                wrappedCompletion(.init(status: .success, errors: nil))
                self.didCompleteDonation()
            } catch {
                guard let error = error as? DonationViewsUtil.Gifts.SendGiftError else {
                    owsFail("\(error)")
                }

                wrappedCompletion(.init(status: .failure, errors: [error]))
                DonationViewsUtil.Gifts.presentErrorSheetIfApplicable(for: error)
            }
        }
    }

    func paymentAuthorizationControllerDidFinish(_ controller: PKPaymentAuthorizationController) {
        controller.dismiss()
    }
}
