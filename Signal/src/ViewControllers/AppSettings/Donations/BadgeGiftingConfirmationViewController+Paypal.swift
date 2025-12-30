//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AuthenticationServices
import Foundation
import SignalServiceKit

extension BadgeGiftingConfirmationViewController {
    typealias SendGiftError = DonationViewsUtil.Gifts.SendGiftError

    func startPaypal() {
        Logger.info("[Gifting] Starting PayPal...")

        // This variable doesn't actually do anything because `startJob` will
        // always throw a `SendGiftError` and there aren't any other throwable
        // things that come after it.
        var mightHaveBeenCharged = false

        let threadId = self.thread.uniqueId
        Task.detached(priority: .userInitiated) {
            do {
                try SSKEnvironment.shared.databaseStorageRef.read { transaction in
                    try DonationViewsUtil.Gifts.throwIfAlreadySendingGift(threadId: threadId, transaction: transaction)
                }
                let (approvalUrl, paymentId) = try await DonationViewsUtil.Paypal.createPaypalPaymentBehindActivityIndicator(
                    amount: self.price,
                    level: .giftBadge(.signalGift),
                    fromViewController: self,
                )
                let preparedPayment = try await self.presentPaypal(with: approvalUrl, paymentId: paymentId)
                guard await DonationViewsUtil.Gifts.showSafetyNumberConfirmationIfNecessary(for: self.thread) else {
                    throw DonationViewsUtil.Gifts.SendGiftError.userCanceledBeforeChargeCompleted
                }
                mightHaveBeenCharged = true
                try await DonationViewsUtil.wrapInProgressView(
                    from: self,
                    operation: {
                        try await DonationViewsUtil.Gifts.startJob(
                            amount: self.price,
                            preparedPayment: preparedPayment,
                            thread: self.thread,
                            messageText: self.messageText,
                            databaseStorage: SSKEnvironment.shared.databaseStorageRef,
                            blockingManager: SSKEnvironment.shared.blockingManagerRef,
                        )
                    },
                )

                Logger.info("[Gifting] Gifting PayPal donation finished")
                await self.didCompleteDonation()
            } catch let error as SendGiftError {
                DonationViewsUtil.Gifts.presentErrorSheetIfApplicable(for: error)
            } catch {
                owsFailDebug("[Gifting] Expected a SendGiftError but got \(error)")
                DonationViewsUtil.Gifts.presentErrorSheetIfApplicable(for: mightHaveBeenCharged ? .failedAndUserMaybeCharged : .failedAndUserNotCharged)
            }
        }
    }

    private func presentPaypal(with approvalUrl: URL, paymentId: String) async throws -> PreparedGiftPayment {
        Logger.info("[Gifting] Presenting PayPal web UI for user approval of gift donation")
        do {
            let approvalParams: Paypal.OneTimePaymentWebAuthApprovalParams = try await Paypal.presentExpectingApprovalParams(
                approvalUrl: approvalUrl,
                withPresentationContext: self,
            )
            return .forPaypal(approvalParams: approvalParams, paymentId: paymentId)
        } catch let paypalAuthError as Paypal.AuthError {
            switch paypalAuthError {
            case .userCanceled:
                Logger.info("[Gifting] User canceled PayPal")
                throw DonationViewsUtil.Gifts.SendGiftError.userCanceledBeforeChargeCompleted
            }
        } catch {
            owsFailDebug("[Gifting] PayPal failed with error \(error)")
            throw error
        }
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension BadgeGiftingConfirmationViewController: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        view.window!
    }
}
