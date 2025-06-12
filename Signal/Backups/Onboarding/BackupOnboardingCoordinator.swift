//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import UIKit

@MainActor
class BackupOnboardingCoordinator {
    private let accountKeyStore: AccountKeyStore
    private let backupEnablingManager: BackupEnablingManager
    private let backupSubscriptionManager: BackupSubscriptionManager
    private let db: DB

    private weak var onboardingNavController: UINavigationController?

    convenience init() {
        self.init(
            accountKeyStore: DependenciesBridge.shared.accountKeyStore,
            backupEnablingManager: AppEnvironment.shared.backupEnablingManager,
            backupSubscriptionManager: DependenciesBridge.shared.backupSubscriptionManager,
            db: DependenciesBridge.shared.db,
        )
    }

    init(
        accountKeyStore: AccountKeyStore,
        backupEnablingManager: BackupEnablingManager,
        backupSubscriptionManager: BackupSubscriptionManager,
        db: DB,
    ) {
        self.accountKeyStore = accountKeyStore
        self.backupEnablingManager = backupEnablingManager
        self.backupSubscriptionManager = backupSubscriptionManager
        self.db = db
    }

    func present(fromViewController: UIViewController) {
        let navController = UINavigationController()
        onboardingNavController = navController

        // Retain ourselves as long as the nav controller is presented.
        ObjectRetainer.retainObject(self, forLifetimeOf: navController)

        navController.viewControllers = [
            BackupOnboardingIntroViewController(
                onContinue: { [weak self] in
                    self?.showBackupKeyIntro()
                },
                onNotNow: { [weak self] in
                    self?.onboardingNavController?.dismiss(animated: true)
                }
            ),
        ]

        fromViewController.present(navController, animated: true)
    }

    // MARK: -

    private func showBackupKeyIntro() {
        guard let onboardingNavController else { return }

        onboardingNavController.pushViewController(
            BackupOnboardingKeyIntroViewController(onDeviceAuthSucceeded: { [weak self] in
                self?.showRecordBackupKey()
            }),
            animated: true
        )
    }

    // MARK: -

    private func showRecordBackupKey() {
        guard
            let onboardingNavController,
            let aep = db.read(block: { accountKeyStore.getAccountEntropyPool(tx: $0) })
        else { return }

        onboardingNavController.pushViewController(
            BackupRecordKeyViewController(
                aep: aep,
                isOnboardingFlow: true,
                onCompletion: { [weak self] _ in
                    self?.showConfirmBackupKey(aep: aep)
                },
            ),
            animated: true
        )
    }

    // MARK: -

    private func showConfirmBackupKey(aep: AccountEntropyPool) {
        guard let onboardingNavController else { return }

        onboardingNavController.pushViewController(
            BackupOnboardingConfirmKeyViewController(
                aep: aep,
                onContinue: { [weak self] in
                    Task { [weak self] in
                        await self?.showChooseBackupPlan()
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
            ) { [weak self] chooseBackupPlanViewController, planSelection in
                Task { [weak self] in
                    guard let self else { return }

                    await enableBackups(
                        fromViewController: chooseBackupPlanViewController,
                        planSelection: planSelection
                    )
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

    private func enableBackups(
        fromViewController: ChooseBackupPlanViewController,
        planSelection: ChooseBackupPlanViewController.PlanSelection
    ) async {
        guard let onboardingNavController else { return }

        do throws(BackupEnablingManager.DisplayableError) {
            try await backupEnablingManager.enableBackups(
                fromViewController: fromViewController,
                planSelection: planSelection
            )
        } catch {
            OWSActionSheets.showActionSheet(
                message: error.localizedActionSheetMessage,
                fromViewController: fromViewController,
            )
            return
        }

        onboardingNavController.setViewControllers(
            [BackupSettingsViewController(onLoadAction: .presentWelcomeToBackupsSheet)],
            animated: true
        )
    }
}
