//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import SignalUI
import UIKit

extension DonationViewsUtil {

    /// If the donation can't be continued, build back up the donation UI and attempt to complete the donation.
    @MainActor
    static func restartAndCompleteInterruptedIDEALDonation(
        type donationType: Stripe.IDEALCallbackType,
        rootViewController: UIViewController,
        databaseStorage: SDSDatabaseStorage,
        donationSubscriptionManager: DonationSubscriptionManager,
        idealStore: PendingIDEALDonationStore,
        profileBadgeManager: ProfileBadgeManager,
    ) async throws {
        let idealStore = DependenciesBridge.shared.pendingIDEALDonationStore
        let (success, intent, localIntent) = databaseStorage.read { tx in
            switch donationType {
            case let .oneTime(didSucceed: success, paymentIntentId: intentId):
                let localIntentId = idealStore.getPendingOneTimeDonation(tx: tx)
                return (success, intentId, localIntentId?.paymentIntentId)
            case let .monthly(didSucceed: success, _, setupIntentId: intentId):
                let localIntentId = idealStore.getPendingSubscription(tx: tx)
                return (success, intentId, localIntentId?.setupIntentId)
            }
        }

        if rootViewController.presentedViewController != nil {
            await rootViewController.awaitableDismiss(animated: false)
        }

        guard let frontVc = CurrentAppContext().frontmostViewController() else {
            return
        }

        // Build up the Donation UI
        let appSettings = AppSettingsViewController.inModalNavigationController()
        let donationsVC = DonationSettingsViewController()
        donationsVC.showExpirationSheet = false
        appSettings.viewControllers += [donationsVC]

        await frontVc.awaitablePresentFormSheet(appSettings, animated: false)

        if success, let localIntent, intent == localIntent {
            try await Self.completeIDEALDonation(
                fromViewController: donationsVC,
                donationType: donationType,
                databaseStorage: databaseStorage,
                donationSubscriptionManager: donationSubscriptionManager,
                idealStore: idealStore,
                profileBadgeManager: profileBadgeManager,
            )
        } else {
            Self.handleIDEALDonationIssue(
                success: success,
                donationType: donationType,
                from: donationsVC,
                databaseStorage: databaseStorage,
            )
        }
    }

    /// Attempts to seamlessly continue the donation, if the app state is still at the appropriate step in the iDEAL donation flow.
    ///
    /// - Returns:
    /// `true` if the donation was continued by previously-constructed UI.
    /// `false` otherwise,  in which case the caller is responsible for "reconstructing" the appropriate step in the
    /// donation flow and continuing the donation.
    @MainActor
    static func attemptToContinueActiveIDEALDonation(
        type donationType: Stripe.IDEALCallbackType,
        databaseStorage: SDSDatabaseStorage,
    ) async -> Bool {
        // Inspect this view controller to find out if the layout is as expected.
        guard
            let frontVC = CurrentAppContext().frontmostViewController(),
            let navController = frontVC.presentingViewController as? UINavigationController,
            let vc = navController.viewControllers.last,
            let donationPaymentVC = vc as? DonationPaymentDetailsViewController,
            donationPaymentVC.threeDSecureAuthenticationSession != nil
        else {
            // Not in the expected donation flow, so revert to building
            // the donation view stack from scratch
            return false
        }

        await frontVC.awaitableDismiss(animated: true)

        let (success, intentId) = {
            switch donationType {
            case
                let .oneTime(success, intent),
                let .monthly(success, _, intent):
                return (success, intent)
            }
        }()

        // Attempt to slide back into the current donation flow by completing
        // the active 3DS session with the intent.  If the payment was externally
        // failed, pass that into the existing donation flow to be handled inline
        return donationPaymentVC.completeExternal3DS(
            success: success,
            intentID: intentId,
        )
    }

    @MainActor
    private static func completeIDEALDonation(
        fromViewController donationsVC: DonationSettingsViewController,
        donationType: Stripe.IDEALCallbackType,
        databaseStorage: SDSDatabaseStorage,
        donationSubscriptionManager: DonationSubscriptionManager,
        idealStore: PendingIDEALDonationStore,
        profileBadgeManager: ProfileBadgeManager,
    ) async throws {
        defer {
            // refresh the local state upon completing the donation
            // to refresh any pending donation messages
            Task { await donationsVC.loadAndUpdateState() }
        }

        let profileBadge: ProfileBadge?
        switch donationType {
        case .oneTime:
            profileBadge = databaseStorage.read { tx in
                profileBadgeManager.fetchBoostBadge(id: .boost, tx: tx)
            }
        case .monthly:
            let pendingSubscriptionLevel = databaseStorage.read { tx in
                idealStore.getPendingSubscription(tx: tx)?.newSubscriptionLevel
            }
            if let pendingSubscriptionLevel {
                profileBadge = try? await donationSubscriptionManager
                    .getSubscriptionLevel(rawLevel: pendingSubscriptionLevel)
                    .badge
            } else {
                profileBadge = nil
            }
        }

        do {
            try await DonationViewsUtil.wrapInProgressView(
                from: donationsVC,
                operation: {
                    try await DonationViewsUtil.completeIDEALDonation(
                        donationType: donationType,
                        databaseStorage: databaseStorage,
                        donationSubscriptionManager: donationSubscriptionManager,
                        idealStore: idealStore,
                    )
                },
            )
            // Do this after the `wrapPromiseInProgressView` completes
            // to dismiss the progress spinner.  Then display the
            // result of the donation.
            let badgeThanksSheetPresenter = BadgeThanksSheetPresenter.fromGlobalsWithSneakyTransaction(
                successMode: donationType.asSuccessMode,
            )

            Task {
                await badgeThanksSheetPresenter?.presentAndRecordBadgeThanks(
                    fromViewController: donationsVC,
                )
            }
        } catch {
            if let profileBadge {
                DonationViewsUtil.presentErrorSheet(
                    from: donationsVC,
                    error: error,
                    mode: donationType.asDonationMode,
                    badge: profileBadge,
                    paymentMethod: .ideal,
                )
            } else {
                owsFailDebug("[Donations] Failed to load donation badge")
            }
            throw error
        }
    }

    @MainActor
    private static func handleIDEALDonationIssue(
        success: Bool,
        donationType: Stripe.IDEALCallbackType,
        from donationsVC: DonationSettingsViewController,
        databaseStorage: SDSDatabaseStorage,
    ) {
        let clearPendingDonation = { @MainActor in
            let idealStore = DependenciesBridge.shared.pendingIDEALDonationStore
            databaseStorage.write { tx in
                switch donationType {
                case .monthly:
                    idealStore.clearPendingSubscription(tx: tx)
                case .oneTime:
                    idealStore.clearPendingOneTimeDonation(tx: tx)
                }
            }
        }

        let actionSheet = ActionSheetController(
            title: OWSLocalizedString(
                "DONATION_SETTINGS_MY_SUPPORT_DONATION_FAILED_ALERT_TITLE",
                comment: "Title for a sheet explaining that a payment failed.",
            ),
            message: OWSLocalizedString(
                "DONATION_REDIRECT_ERROR_PAYMENT_DENIED_MESSAGE",
                comment: "Error message displayed if something goes wrong with 3DSecure/iDEAL payment authorization.  This will be encountered if the user denies the payment.",
            ),
        )
        actionSheet.addAction(.init(title: CommonStrings.okButton, style: .default, handler: { _ in
            if !success {
                // Failing a donation will cause it to fail on the Stripe
                // side no matter what, so clear it out before presenting
                clearPendingDonation()
            }
        }))
        actionSheet.addAction(
            .init(
                title: CommonStrings.tryAgainButton,
                style: .default,
                handler: { _ in
                    clearPendingDonation()
                    donationsVC.showDonateViewController(preferredDonateMode: donationType.asDonationMode)
                },
            ),
        )

        if let frontVc = CurrentAppContext().frontmostViewController() {
            frontVc.presentActionSheet(actionSheet, animated: true)
        }
    }
}

private extension Stripe.IDEALCallbackType {

    var asSuccessMode: DonationReceiptCredentialResultStore.Mode {
        switch self {
        case .oneTime: return .oneTimeBoost
        case .monthly: return .recurringSubscriptionInitiation
        }
    }

    var asDonationMode: DonateViewController.DonateMode {
        switch self {
        case .oneTime: return .oneTime
        case .monthly: return .monthly
        }
    }
}
