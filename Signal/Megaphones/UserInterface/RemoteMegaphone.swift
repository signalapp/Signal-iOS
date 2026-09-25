//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class RemoteMegaphone: Megaphone {
    private let megaphoneModel: RemoteMegaphoneModel

    init(
        experienceUpgrade: ExperienceUpgrade,
        remoteMegaphoneModel: RemoteMegaphoneModel,
        fromViewController: UIViewController,
    ) {
        megaphoneModel = remoteMegaphoneModel

        super.init(experienceUpgrade: experienceUpgrade)

        titleText = megaphoneModel.translation.title
        bodyText = megaphoneModel.translation.body

        if megaphoneModel.translation.hasImage {
            let imageLocalUrl = RemoteMegaphoneModel.imagesDirectory.appendingPathComponent(megaphoneModel.translation.imageLocalRelativePath)
            if let image = UIImage(contentsOfFile: imageLocalUrl.path) {
                self.image = image
            } else {
                owsFailDebug("Expected local image, but image was not loaded!")
            }
        }

        if let primary = megaphoneModel.presentablePrimaryAction {
            let primaryButton = Button(title: primary.presentableText) { [weak self, weak fromViewController] in
                guard
                    let self,
                    let fromViewController
                else { return }

                self.performAction(
                    primary.action,
                    fromViewController: fromViewController,
                    buttonDescriptor: "primary",
                )
            }

            if let secondary = megaphoneModel.presentableSecondaryAction {
                let secondaryButton = Button(title: secondary.presentableText) { [weak self, weak fromViewController] in
                    guard
                        let self,
                        let fromViewController
                    else { return }

                    self.performAction(
                        secondary.action,
                        fromViewController: fromViewController,
                        buttonDescriptor: "secondary",
                    )
                }

                buttons = [primaryButton, secondaryButton]
            } else {
                buttons = [primaryButton]
            }
        }
    }

    // MARK: Perform actions

    /// Perform the given action.
    private func performAction(
        _ action: RemoteMegaphoneModel.Manifest.Action,
        fromViewController: UIViewController,
        buttonDescriptor: String,
    ) {
        switch action {
        case .snooze:
            markAsSnoozedWithSneakyTransaction()
        case .finish:
            markAsCompleteWithSneakyTransaction()
        case .donate:
            let done = { [weak self] in
                guard let self else { return }
                // Snooze regardless of outcome.
                self.markAsSnoozedWithSneakyTransaction()
            }

            let tsAccountManager = DependenciesBridge.shared.tsAccountManager
            guard
                let registeredState = try? tsAccountManager.registeredStateWithMaybeSneakyTransaction(),
                let donationAllowedToken = DonationAllowedToken(registeredState: registeredState, remoteConfig: .current)
            else {
                done()
                DonationViewsUtil.openDonateWebsite()
                return
            }

            let donateVc = DonateViewController(preferredDonateMode: .oneTime, donationAllowedToken: donationAllowedToken) { finishResult in
                let frontVc = { CurrentAppContext().frontmostViewController() }
                switch finishResult {
                case let .completedDonation(donateSheet, receiptCredentialSuccessMode):
                    donateSheet.dismiss(animated: true) {
                        guard
                            let frontVc = frontVc(),
                            let badgeThanksSheetPresenter = BadgeThanksSheetPresenter.fromGlobalsWithSneakyTransaction(
                                successMode: receiptCredentialSuccessMode,
                            )
                        else { return }

                        Task {
                            await badgeThanksSheetPresenter.presentAndRecordBadgeThanks(
                                fromViewController: frontVc,
                            )
                        }
                    }
                case let .monthlySubscriptionCancelled(donateSheet, toastText):
                    donateSheet.dismiss(animated: true) {
                        frontVc()?.presentToast(text: toastText)
                    }
                }
            }

            let navController = OWSNavigationController(rootViewController: donateVc)
            fromViewController.present(navController, animated: true, completion: done)
        case .donateFriend:
            let done = { [weak self] in
                guard let self else { return }
                // Snooze regardless of outcome.
                self.markAsSnoozedWithSneakyTransaction()
            }

            let tsAccountManager = DependenciesBridge.shared.tsAccountManager
            guard
                let registeredState = try? tsAccountManager.registeredStateWithMaybeSneakyTransaction(),
                let donationAllowedToken = DonationAllowedToken(registeredState: registeredState, remoteConfig: .current),
                donationAllowedToken.canDonate(inMode: .gift)
            else {
                done()
                DonationViewsUtil.openDonateWebsite()
                return
            }

            let donateVc = BadgeGiftingChooseBadgeViewController(donationAllowedToken: donationAllowedToken)
            let navController = OWSNavigationController(rootViewController: donateVc)
            fromViewController.present(navController, animated: true, completion: done)
        case .unrecognized(let actionId):
            owsFailDebug("Unrecognized action with ID \(actionId) should never have made it into \(buttonDescriptor) button!")
        }
    }
}

// MARK: - Presentable actions

private extension RemoteMegaphoneModel {
    struct PresentableAction {
        let action: Manifest.Action
        let presentableText: String

        fileprivate init?(
            action: Manifest.Action?,
            presentableText: String?,
        ) {
            guard
                let action,
                let presentableText
            else {
                return nil
            }

            self.action = action
            self.presentableText = presentableText
        }
    }

    var presentablePrimaryAction: PresentableAction? {
        PresentableAction(
            action: manifest.primaryAction,
            presentableText: translation.primaryActionText,
        )
    }

    var presentableSecondaryAction: PresentableAction? {
        PresentableAction(
            action: manifest.secondaryAction,
            presentableText: translation.secondaryActionText,
        )
    }
}
