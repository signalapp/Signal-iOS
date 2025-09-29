//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import UIKit

@MainActor
final class BackupOnboardingCoordinator {
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
            "Unsafe to let a linked device do Backups Onboarding!"
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
                    onboardingNavController?.popViewController(animated: true)
                }
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
                }
            ),
            animated: true
        )
    }

    // MARK: -

    private func showRecordRecoveryKey(
        localDeviceAuthSuccess: LocalDeviceAuthentication.AuthSuccess
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
            ),
            animated: true
        )
    }

    // MARK: -

    private func showConfirmRecoveryKey(aep: AccountEntropyPool) {
        guard let onboardingNavController else { return }

        onboardingNavController.pushViewController(
            BackupConfirmKeyViewController(
                aep: aep,
                onContinue: { [self] in
                    Task {
                        await showChooseBackupPlan()
                    }
                },
                onSeeKeyAgain: {
                    onboardingNavController.popViewController(animated: true)
                }
            ),
            animated: true
        )
    }

    // MARK: -

    private func showChooseBackupPlan() async {
        guard let onboardingNavController else { return }

        let chooseBackupPlanViewController: ChooseBackupPlanViewController
        do throws(OWSAssertionError) {
            chooseBackupPlanViewController = try await .load(
                fromViewController: onboardingNavController,
                initialPlanSelection: nil,
            ) { [self] chooseBackupPlanViewController, planSelection in
                Task {
                    do throws(BackupEnablingManager.DisplayableError) {
                        try await backupEnablingManager.enableBackups(
                            fromViewController: chooseBackupPlanViewController,
                            planSelection: planSelection
                        )
                    } catch {
                        OWSActionSheets.showActionSheet(
                            message: error.localizedActionSheetMessage,
                            fromViewController: chooseBackupPlanViewController,
                        )
                        return
                    }

                    completeOnboarding()
                }
            }
        } catch {
            return
        }

        onboardingNavController.pushViewController(
            chooseBackupPlanViewController,
            animated: true
        )
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
            animated: true
        )
    }
}
