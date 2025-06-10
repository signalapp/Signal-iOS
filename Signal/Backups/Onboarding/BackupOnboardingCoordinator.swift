//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import UIKit

@MainActor
class BackupOnboardingCoordinator {
    private let backupEnablingManager: BackupEnablingManager
    private let backupSubscriptionManager: BackupSubscriptionManager

    private let onboardingNavController: UINavigationController

    convenience init() {
        self.init(
            backupEnablingManager: AppEnvironment.shared.backupEnablingManager,
            backupSubscriptionManager: DependenciesBridge.shared.backupSubscriptionManager
        )
    }

    init(
        backupEnablingManager: BackupEnablingManager,
        backupSubscriptionManager: BackupSubscriptionManager,
    ) {
        self.backupEnablingManager = backupEnablingManager
        self.backupSubscriptionManager = backupSubscriptionManager

        self.onboardingNavController = UINavigationController()

        onboardingNavController.viewControllers = [
            BackupOnboardingIntroductionViewController(
                onContinue: { [self] in
                    Task {
                        await showChooseBackupPlan()
                    }
                },
                onNotNow: { [self] in
                    onboardingNavController.dismiss(animated: true)
                }
            ),
        ]
    }

    func present(fromViewController: UIViewController) {
        fromViewController.present(onboardingNavController, animated: true)
    }

    // MARK: -

    private func showChooseBackupPlan() async {
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
