//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import AuthenticationServices
import SignalMessaging

extension BadgeGiftingConfirmationViewController {
    typealias SendGiftError = DonationViewsUtil.Gifts.SendGiftError

    func startPaypal() {
        Logger.info("[Gifting] Starting PayPal...")

        var hasCharged = false

        firstly(on: DispatchQueue.sharedUserInitiated) { () -> Void in
            try self.databaseStorage.read { transaction in
                try DonationViewsUtil.Gifts.throwIfAlreadySendingGift(
                    to: self.thread,
                    transaction: transaction
                )
            }
        }.then(on: DispatchQueue.main) { () -> Promise<URL> in
            DonationViewsUtil.Paypal.createPaypalPaymentBehindActivityIndicator(
                amount: self.price,
                level: .giftBadge(.signalGift),
                fromViewController: self
            )
        }.then(on: DispatchQueue.main) { [weak self] approvalUrl -> Promise<PreparedGiftPayment> in
            guard let self else {
                throw SendGiftError.userCanceledBeforeChargeCompleted
            }
            return self.presentPaypal(with: approvalUrl)
        }.then(on: DispatchQueue.main) { [weak self] preparedPayment -> Promise<PreparedGiftPayment> in
            guard let self else { throw SendGiftError.userCanceledBeforeChargeCompleted }
            return DonationViewsUtil.Gifts.showSafetyNumberConfirmationIfNecessary(for: self.thread)
                .promise
                .map { safetyNumberConfirmationResult in
                    switch safetyNumberConfirmationResult {
                    case .userDidNotConfirmSafetyNumberChange:
                        throw DonationViewsUtil.Gifts.SendGiftError.userCanceledBeforeChargeCompleted
                    case .userConfirmedSafetyNumberChangeOrNoChangeWasNeeded:
                        return preparedPayment
                    }
                }
        }.then(on: DispatchQueue.main) { [weak self] preparedPayment -> Promise<Void> in
            guard let self else { throw SendGiftError.userCanceledBeforeChargeCompleted }
            return DonationViewsUtil.wrapPromiseInProgressView(
                from: self,
                promise: DonationViewsUtil.Gifts.startJob(
                    amount: self.price,
                    preparedPayment: preparedPayment,
                    thread: self.thread,
                    messageText: self.messageText,
                    databaseStorage: self.databaseStorage,
                    blockingManager: self.blockingManager,
                    onChargeSucceeded: { hasCharged = true }
                )
            )
        }.done(on: DispatchQueue.main) { [weak self] in
            Logger.info("[Gifting] Gifting PayPal donation finished")
            self?.didCompleteDonation()
        }.catch { error in
            let sendGiftError: SendGiftError
            if let error = error as? SendGiftError {
                sendGiftError = error
            } else {
                owsFailDebug("[Gifting] Expected a SendGiftError but got \(error)")
                sendGiftError = hasCharged ? .failedAndUserMaybeCharged : .failedAndUserNotCharged
            }
            DonationViewsUtil.Gifts.presentErrorSheetIfApplicable(for: sendGiftError)
        }
    }

    private func presentPaypal(with approvalUrl: URL) -> Promise<PreparedGiftPayment> {
        firstly(on: DispatchQueue.main) { () -> Promise<Paypal.OneTimePaymentWebAuthApprovalParams> in
            Logger.info("[Gifting] Presenting PayPal web UI for user approval of gift donation")
            return Paypal.presentExpectingApprovalParams(
                approvalUrl: approvalUrl,
                withPresentationContext: self
            )
        }.map(on: DispatchQueue.sharedUserInitiated) { approvalParams -> PreparedGiftPayment in
            .forPaypal(approvalParams: approvalParams)
        }.recover(on: DispatchQueue.sharedUserInitiated) { error -> Promise<PreparedGiftPayment> in
            let errorToThrow: Error

            if let paypalAuthError = error as? Paypal.AuthError {
                switch paypalAuthError {
                case .userCanceled:
                    Logger.info("[Gifting] User canceled PayPal")
                    errorToThrow = DonationViewsUtil.Gifts.SendGiftError.userCanceledBeforeChargeCompleted
                }
            } else {
                owsFailDebug("[Gifting] PayPal failed with error \(error)")
                errorToThrow = error
            }

            return Promise<PreparedGiftPayment>(error: errorToThrow)
        }
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension BadgeGiftingConfirmationViewController: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        view.window!
    }
}
