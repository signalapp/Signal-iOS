//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging
import SignalUI
import UIKit

extension DonationViewsUtil {

    /// If the donation can't be continued, build back up the donation UI and attempt to complete the donation.
    static func restartAndCompleteInterruptedIDEALDonation(
        type donationType: Stripe.IDEALCallbackType,
        rootViewController: UIViewController,
        databaseStorage: SDSDatabaseStorage
    ) -> Promise<Void> {
        let donationStore = DependenciesBridge.shared.externalPendingIDEALDonationStore
        let (success, intent, localIntent) = databaseStorage.read { tx in
            switch donationType {
            case let .oneTime(didSucceed: success, paymentIntentId: intentId):
                let localIntentId = donationStore.getPendingOneTimeDonation(tx: tx.asV2Read)
                return (success, intentId, localIntentId?.paymentIntentId)
            case let .monthly(didSucceed: success, _, setupIntentId: intentId):
                let localIntentId = donationStore.getPendingSubscription(tx: tx.asV2Read)
                return (success, intentId, localIntentId?.setupIntentId)
            }
        }

        let (promise, future) = Promise<Void>.pending()

        let completion = {
            guard let frontVc = CurrentAppContext().frontmostViewController() else {
                future.resolve(())
                return
            }

            // Build up the Donation UI
            let appSettings = AppSettingsViewController.inModalNavigationController()
            let donationsVC = DonationSettingsViewController()
            donationsVC.showExpirationSheet = false
            appSettings.viewControllers += [ donationsVC ]

            frontVc.presentFormSheet(appSettings, animated: false) {
                AssertIsOnMainThread()
                firstly(on: DispatchQueue.main) {
                    if
                        success,
                        let localIntent,
                        intent == localIntent
                    {
                        return Self.completeDonation(
                            type: donationType,
                            from: donationsVC,
                            databaseStorage: databaseStorage
                        )
                    } else {
                        Self.handleIDEALDonationIssue(
                            success: success,
                            donationType: donationType,
                            from: donationsVC,
                            databaseStorage: databaseStorage
                        )
                        return Promise.value(())
                    }
                }.done {
                    future.resolve()
                }.catch { error in
                    future.reject(error)
                }
            }
        }

        if rootViewController.presentedViewController != nil {
            rootViewController.dismiss(animated: false) {
                completion()
            }
        } else {
            completion()
        }
        return promise
    }

    /// Attempts to seamlessly continue the donation, if the app state is still at the appropriate step in the iDEAL donation flow.
    ///
    /// - Returns:
    /// `true` if the donation was continued by previously-constructed UI.
    /// `false` otherwise,  in which case the caller is responsible for "reconstructing" the appropriate step in the
    /// donation flow and continuing the donation.
    static func attemptToContinueActiveIDEALDonation(
        type donationType: Stripe.IDEALCallbackType,
        databaseStorage: SDSDatabaseStorage
    ) -> Promise<Bool> {
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
            return .value(false)
        }

        let (promise, future) = Promise<Bool>.pending()

        frontVC.dismiss(animated: true) {
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
            let continuedWithActiveDonation = donationPaymentVC.completeExternal3DS(
                success: success,
                intentID: intentId
            )

            future.resolve(continuedWithActiveDonation)
        }
        return promise
    }

    private static func completeDonation(
        type donationType: Stripe.IDEALCallbackType,
        from donationsVC: DonationSettingsViewController,
        databaseStorage: SDSDatabaseStorage
    ) -> Promise<Void> {
        firstly(on: DispatchQueue.sharedUserInitiated) {
            return Self.loadBadgeForDonation(type: donationType, databaseStorage: databaseStorage)
        }.then(on: DispatchQueue.main) { badge in
            DonationViewsUtil.wrapPromiseInProgressView(
                from: donationsVC,
                promise: DonationViewsUtil.completeIDEALDonation(
                    donationType: donationType,
                    databaseStorage: databaseStorage
                )
            ).done(on: DispatchQueue.main) {
                // Do this after the `wrapPromiseInProgressView` completes
                // to dismiss the progress spinner.  Then display the
                // result of the donation.
                let badgeThanksSheetPresenter = BadgeThanksSheetPresenter.loadWithSneakyTransaction(
                    successMode: donationType.asSuccessMode
                )
                badgeThanksSheetPresenter?.presentBadgeThanksAndClearSuccess(
                    fromViewController: donationsVC
                )
            }.recover(on: DispatchQueue.main) { error in
                if let badge {
                    DonationViewsUtil.presentErrorSheet(
                        from: donationsVC,
                        error: error,
                        mode: donationType.asDonationMode,
                        badge: badge,
                        paymentMethod: .ideal
                    )
                } else {
                    owsFailDebug("[Donations] Failed to load donation badge")
                }
                throw error
            }.ensure(on: DispatchQueue.main) {
                // refresh the local state upon completing the donation
                // to refresh any pending donation messages
                _ = donationsVC.loadAndUpdateState()
            }
        }
    }

    private static func handleIDEALDonationIssue(
        success: Bool,
        donationType: Stripe.IDEALCallbackType,
        from donationsVC: DonationSettingsViewController,
        databaseStorage: SDSDatabaseStorage
    ) {
        let clearPendingDonation = {
            let idealStore = DependenciesBridge.shared.externalPendingIDEALDonationStore
            databaseStorage.write { tx in
                switch donationType {
                case .monthly:
                    idealStore.clearPendingSubscription(tx: tx.asV2Write)
                case .oneTime:
                    idealStore.clearPendingOneTimeDonation(tx: tx.asV2Write)
                }
            }
        }

        let actionSheet = ActionSheetController(
            title: OWSLocalizedString(
                "DONATION_SETTINGS_MY_SUPPORT_DONATION_FAILED_ALERT_TITLE",
                comment: "Title for a sheet explaining that a payment failed."
            ),
            message: OWSLocalizedString(
                "DONATION_REDIRECT_ERROR_PAYMENT_DENIED_MESSAGE",
                comment: "Error message displayed if something goes wrong with 3DSecure/iDEAL payment authorization.  This will be encountered if the user denies the payment."
            )
        )
        actionSheet.addAction(.init(title: CommonStrings.okButton, style: .default, handler: { _ in
            if !success {
                // Failing a donation will cause it to fail on the Stripe
                // side no matter what, so clear it out before presenting
                clearPendingDonation()
            }
        }))
        actionSheet.addAction(.init(
            title: OWSLocalizedString(
                "DONATION_BADGE_ISSUE_SHEET_TRY_AGAIN_BUTTON_TITLE",
                comment: "Title for a button asking the user to try their donation again, because something went wrong."
            ),
            style: .default,
            handler: { _ in
                clearPendingDonation()
                donationsVC.showDonateViewController(preferredDonateMode: donationType.asDonationMode)
            })
        )

        if let frontVc = CurrentAppContext().frontmostViewController() {
            frontVc.presentActionSheet(actionSheet, animated: true)
        }
    }

    private static func loadBadgeForDonation(
        type donationType: Stripe.IDEALCallbackType,
        databaseStorage: SDSDatabaseStorage
    ) -> Promise<ProfileBadge?> {
        let donationStore = DependenciesBridge.shared.externalPendingIDEALDonationStore
        return databaseStorage.read { tx in
            switch donationType {
            case .oneTime:
                return SubscriptionManagerImpl.getCachedBadge(level: .boostBadge)
                    .fetchIfNeeded()
                    .map(on: DispatchQueue.main) { result in
                        switch result {
                        case .notFound:
                            return nil
                        case let .profileBadge(profileBadge):
                            return profileBadge
                        }
                    }
            case .monthly:
                guard let monthlyDonation = donationStore.getPendingSubscription(tx: tx.asV2Read) else {
                    return .value(nil)
                }
                return OWSProfileManager.shared.badgeStore.populateAssetsOnBadge(
                    monthlyDonation.newSubscriptionLevel.badge
                )
                .map {
                    return monthlyDonation.newSubscriptionLevel.badge
                }
            }
        }
    }
}

private extension Stripe.IDEALCallbackType {

    var asSuccessMode: ReceiptCredentialResultStore.Mode {
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
