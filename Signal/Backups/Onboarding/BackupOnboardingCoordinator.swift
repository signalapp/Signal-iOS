//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import UIKit

@MainActor
class BackupOnboardingCoordinator {
    private static let onboardingRootViewControllerType = BackupOnboardingIntroViewController.self

    private let accountKeyStore: AccountKeyStore
    private let backupEnablingManager: BackupEnablingManager
    private let backupSettingsStore: BackupSettingsStore
    private let db: DB

    private weak var onboardingNavController: UINavigationController?

    convenience init() {
        self.init(
            accountKeyStore: DependenciesBridge.shared.accountKeyStore,
            backupEnablingManager: AppEnvironment.shared.backupEnablingManager,
            backupSettingsStore: BackupSettingsStore(),
            db: DependenciesBridge.shared.db,
            tsAccountManager: DependenciesBridge.shared.tsAccountManager,
        )
    }

    init(
        accountKeyStore: AccountKeyStore,
        backupEnablingManager: BackupEnablingManager,
        backupSettingsStore: BackupSettingsStore,
        db: DB,
        tsAccountManager: TSAccountManager,
    ) {
        owsPrecondition(
            db.read { tsAccountManager.registrationState(tx: $0).isPrimaryDevice == true },
            "Unsafe to let a linked device do Backups Onboarding!",
        )

        self.accountKeyStore = accountKeyStore
        self.backupEnablingManager = backupEnablingManager
        self.backupSettingsStore = backupSettingsStore
        self.db = db
    }

    func prepareForPresentation(
        inNavController navController: UINavigationController,
    ) -> UIViewController {
        let haveBackupsEverBeenEnabled = db.read { tx in
            backupSettingsStore.haveBackupsEverBeenEnabled(tx: tx)
        }

        if haveBackupsEverBeenEnabled {
            return BackupSettingsViewController(onAppearAction: nil)
        } else {
            // Weakly retain the nav controller, so we can use it throughout
            // onboarding.
            onboardingNavController = navController

            // Strongly retain this instance through the various view controller
            // callbacks, so that we stay alive to facilitate navigation. We
            // don't retain any of the view controllers retaining us, so we'll
            // be released when they are: when the user finishes or dismisses
            // onboarding.
            let introViewController = BackupOnboardingIntroViewController(
                onContinue: { [self] in
                    showRecoveryKeyIntro()
                },
                onNotNow: { [self] in
                    onboardingNavController?.popViewController(animated: true) { [self] in
                        onboardingNavController?.presentToast(text: OWSLocalizedString(
                            "BACKUP_ONBOARDING_INTRO_NOT_NOW_TOAST",
                            comment: "A toast shown when 'Not Now' is tapped from the Backups onboarding intro.",
                        ))
                    }
                },
            )

            // At the end of onboarding we'll look for this as the "root" of the
            // onboarding view controller stack, so we don't want to update the
            // returned type here without updating that site too.
            owsPrecondition(type(of: introViewController) == Self.onboardingRootViewControllerType)

            return introViewController
        }
    }

    // MARK: -

    private func showRecoveryKeyIntro() {
        guard let onboardingNavController else { return }

        onboardingNavController.pushViewController(
            BackupOnboardingKeyIntroViewController(
                onDeviceAuthSucceeded: { [self] authSuccess in
                    showRecordRecoveryKey(localDeviceAuthSuccess: authSuccess)
                },
            ),
            animated: true,
        )
    }

    // MARK: -

    private func showRecordRecoveryKey(
        localDeviceAuthSuccess: LocalDeviceAuthentication.AuthSuccess,
    ) {
        guard
            let onboardingNavController,
            let aep = db.read(block: { accountKeyStore.getAccountEntropyPool(tx: $0) })
        else { return }

        onboardingNavController.pushViewController(
            BackupRecordKeyViewController(
                aepMode: .current(aep, localDeviceAuthSuccess),
                options: [.showContinueButton],
                onContinuePressed: { [self] _ in
                    showConfirmRecoveryKey(aep: aep)
                },
                onBackPressed: { [weak self] in
                    self?.promptToCancelOnboarding()
                },
            ),
            animated: true,
        )
    }

    // MARK: -

    private func showConfirmRecoveryKey(aep: AccountEntropyPool) {
        guard let onboardingNavController else { return }

        let confirmKeyViewController = BackupConfirmKeyViewController(
            aep: aep,
            onContinue: { [self] confirmKeyViewController in
                Task {
                    do throws(SheetDisplayableError) {
                        try await showChooseBackupPlan()
                    } catch {
                        error.showSheet(from: confirmKeyViewController)
                    }
                }
            },
            onSeeKeyAgain: {
                onboardingNavController.popViewController(animated: true)
            },
            onBackPressed: { [weak self] in
                self?.promptToCancelOnboarding()
            },
        )

        onboardingNavController.pushViewController(
            confirmKeyViewController,
            animated: true,
        )
    }

    // MARK: -

    private func showChooseBackupPlan() async throws(SheetDisplayableError) {
        guard let onboardingNavController else { return }

        let chooseBackupPlanViewController: ChooseBackupPlanViewController = try await .load(
            fromViewController: onboardingNavController,
            initialPlanSelection: nil,
        ) { [self] chooseBackupPlanViewController, planSelection in
            Task {
                await enableBackups(
                    planSelection: planSelection,
                    fromViewController: chooseBackupPlanViewController,
                )
            }
        }

        onboardingNavController.pushViewController(
            chooseBackupPlanViewController,
            animated: true,
        )
    }

    private func enableBackups(
        planSelection: ChooseBackupPlanViewController.PlanSelection,
        fromViewController: UIViewController,
    ) async {
        do throws(SheetDisplayableError) {
            try await backupEnablingManager.enableBackups(
                fromViewController: fromViewController,
                planSelection: planSelection,
            )

            completeOnboarding()
        } catch {
            error.showSheet(from: fromViewController)
        }
    }

    private func completeOnboarding() {
        guard
            let onboardingNavController,
            let onboardingRootVCIndex = onboardingNavController.viewControllers
                .firstIndex(where: { type(of: $0) == Self.onboardingRootViewControllerType })
        else {
            return
        }

        let preOnboardingViewControllers = onboardingNavController.viewControllers[0..<onboardingRootVCIndex]
        let backupSettingsViewController = BackupSettingsViewController(onAppearAction: .presentWelcomeToBackupsSheet)

        onboardingNavController.setViewControllers(
            preOnboardingViewControllers + [backupSettingsViewController],
            animated: true,
        )
    }

    private func promptToCancelOnboarding() {
        let actionSheet = ActionSheetController(
            title: OWSLocalizedString(
                "BACKUP_ONBOARDING_CANCEL_SHEET_TITLE",
                comment: "Title for action sheet when attempting to cancel backup onboarding",
            ),
            message: OWSLocalizedString(
                "BACKUP_ONBOARDING_CANCEL_SHEET_MESSAGE",
                comment: "Message for action sheet when attempting to cancel backup onboarding",
            ),
        )
        actionSheet.addAction(.init(
            title: OWSLocalizedString(
                "BACKUP_ONBOARDING_CANCEL_SHEET_ACTION",
                comment: "Button label for action sheet to cancel backup onboarding",
            ),
            style: .default,
            handler: { [weak onboardingNavController] _ in
                onboardingNavController?.popToRootViewController(animated: true)
            },
        ))
        actionSheet.addAction(.cancel)

        onboardingNavController?.topViewController?.presentActionSheet(actionSheet)
    }
}
