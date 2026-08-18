//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import UIKit

@MainActor
class BackupOnboardingCoordinator {
    enum BackupType {
        case remote
        case local
    }

    private let accountKeyStore: AccountKeyStore
    private let backupEnablingManager: BackupEnablingManager
    private let backupSettingsStore: BackupSettingsStore
    private let localFileBackupStore: LocalFileBackupStore
    private let localFileBackupManager: LocalFileBackupManager
    private let db: DB
    private let backupType: BackupType

    private weak var onboardingNavController: UINavigationController?

    convenience init(backupType: BackupType) {
        self.init(
            accountKeyStore: DependenciesBridge.shared.accountKeyStore,
            backupEnablingManager: AppEnvironment.shared.backupEnablingManager,
            backupSettingsStore: BackupSettingsStore(),
            localFileBackupStore: LocalFileBackupStore(),
            localFileBackupManager: DependenciesBridge.shared.localFileBackupManager,
            db: DependenciesBridge.shared.db,
            tsAccountManager: DependenciesBridge.shared.tsAccountManager,
            backupType: backupType,
        )
    }

    init(
        accountKeyStore: AccountKeyStore,
        backupEnablingManager: BackupEnablingManager,
        backupSettingsStore: BackupSettingsStore,
        localFileBackupStore: LocalFileBackupStore,
        localFileBackupManager: LocalFileBackupManager,
        db: DB,
        tsAccountManager: TSAccountManager,
        backupType: BackupType,
    ) {
        owsPrecondition(
            db.read { tsAccountManager.registrationState(tx: $0).isPrimaryDevice == true },
            "Unsafe to let a linked device do Backups Onboarding!",
        )

        self.accountKeyStore = accountKeyStore
        self.backupEnablingManager = backupEnablingManager
        self.backupSettingsStore = backupSettingsStore
        self.localFileBackupStore = localFileBackupStore
        self.localFileBackupManager = localFileBackupManager
        self.db = db
        self.backupType = backupType
    }

    deinit {
        Logger.verbose("")
    }

    /// - Parameter onAppearAction
    /// An on-appear action for Backup Settings, if onboarding is not necessary.
    func prepareForPresentation(
        inNavController navController: UINavigationController,
        onAppearAction: BackupSettingsViewController.OnAppearAction? = nil,
        shouldSkipOnboarding: Bool,
    ) -> UIViewController {
        if shouldSkipOnboarding {
            switch backupType {
            case .remote:
                return BackupSettingsViewController(onAppearAction: onAppearAction)
            case .local:
                return LocalFileBackupsSettingsViewController(
                    localFileBackupExportJobRunner: DependenciesBridge.shared.localFileBackupExportJobRunner,
                    localFileBackupStore: localFileBackupStore,
                    db: db,
                    accountKeyStore: accountKeyStore,
                    localFileBackupManager: localFileBackupManager,
                    localFileBackupExportJobStore: LocalFileBackupExportJobStore(),
                )
            }
        } else {
            // Weakly retain the nav controller, so we can use it throughout
            // onboarding.
            onboardingNavController = navController

            // Strongly retain this instance through the various view controller
            // callbacks, so that we stay alive to facilitate navigation. We
            // don't retain any of the view controllers retaining us, so we'll
            // be released when they are: when the user finishes or dismisses
            // onboarding.
            let introViewController: UIViewController
            switch backupType {
            case .remote:
                introViewController = BackupOnboardingIntroViewController(
                    onContinue: { [self] in
                        showRecoveryKeyIntro()
                    },
                    onNotNow: { [self] in
                        onboardingNavController?.popViewController(animated: true) { [self] in
                            onboardingNavController?.presentToast(
                                text: OWSLocalizedString(
                                    "BACKUP_ONBOARDING_INTRO_NOT_NOW_TOAST",
                                    comment: "A toast shown when 'Not Now' is tapped from the Backups onboarding intro.",
                                ),
                            )
                        }
                    },
                )
            case .local:
                let optimizeStorageEnabled = isOptimizeLocalStorageEnabled()
                introViewController = LocalFileBackupOnboardingIntroViewController(onContinue: { fromViewController in
                    let presentChooseFile: () -> Void = { [self] in
                        fromViewController.present(
                            LocalFileBackupSelectFolderHeroSheetViewController(
                                onContinue: { [self] in
                                    localFileBackupManager.promptUserToChooseFileLocationForArchiving(fromViewController: fromViewController, completion: { [self] in
                                        showRecoveryKeyIntro()
                                    })
                                },
                            ),
                            animated: true,
                        )
                    }

                    if optimizeStorageEnabled {
                        let actionSheet = ActionSheetController(
                            message: OWSLocalizedString(
                                "LOCAL_FILE_BACKUPS_OPTIMIZE_MEDIA_WARNING_ACTION_SHEET",
                                comment: "Warning shown when a user tries to enable local file backups with optimize media enabled",
                            ),
                        )
                        actionSheet.addAction(.init(
                            title: OWSLocalizedString(
                                "LOCAL_FILE_BACKUPS_OPTIMIZE_MEDIA_WARNING_ACTION_SHEET_VIEW_SETTING",
                                comment: "Action in an action sheet offering to go to the optimize local storage setting.",
                            ),
                            handler: { [weak self] _ in
                                guard let self else { return }
                                onboardingNavController?.dismiss(animated: true) {
                                    SignalApp.shared.showAppSettings(mode: .backups(page: .remote()))
                                }
                            },
                        ))
                        actionSheet.addAction(.init(
                            title: OWSLocalizedString(
                                "LOCAL_FILE_BACKUPS_OPTIMIZE_MEDIA_WARNING_ACTION_SHEET_CONTINUE",
                                comment: "Action in an action sheet offering to continue anyway.",
                            ),
                            handler: { _ in
                                presentChooseFile()
                            },
                        ))
                        actionSheet.addAction(.cancel)
                        fromViewController.present(actionSheet, animated: true)
                    } else {
                        presentChooseFile()
                    }
                })
            }
            return introViewController
        }
    }

    private func isOptimizeLocalStorageEnabled() -> Bool {
        let currentBackupPlan = db.read(block: { tx in backupSettingsStore.backupPlan(tx: tx) })
        var optimizeLocalStorageEnabled = false
        switch currentBackupPlan {
        case .disabled, .disabling, .free:
            break
        case .paid(optimizeLocalStorage: let optimizeLocalStorage):
            optimizeLocalStorageEnabled = optimizeLocalStorage
        case .paidExpiringSoon(optimizeLocalStorage: let optimizeLocalStorage):
            optimizeLocalStorageEnabled = optimizeLocalStorage
        case .paidAsTester(optimizeLocalStorage: let optimizeLocalStorage):
            optimizeLocalStorageEnabled = optimizeLocalStorage
        }
        return optimizeLocalStorageEnabled
    }

    // MARK: -

    private func showRecoveryKeyIntro() {
        guard let onboardingNavController else { return }

        onboardingNavController.pushViewController(
            BackupOnboardingKeyIntroViewController(
                onBackPressed: { [self] keyIntroViewController in
                    promptToCancelOnboarding(fromViewController: keyIntroViewController)
                },
                onContinue: { [self] _ in
                    showSaveAndConfirmKey()
                },
            ),
            animated: true,
        )
    }

    // MARK: -

    private func showSaveAndConfirmKey() {
        Task {
            guard
                let authSuccess = await LocalDeviceAuthentication().performBiometricAuth(),
                let aep = db.read(block: { accountKeyStore.getAccountEntropyPool(tx: $0) })
            else {
                return
            }

            _showSaveAndConfirmKey(
                aep: aep,
                localDeviceAuthSuccess: authSuccess,
            )
        }
    }

    private func _showSaveAndConfirmKey(
        aep: AccountEntropyPool,
        localDeviceAuthSuccess: LocalDeviceAuthentication.AuthSuccess,
    ) {
        guard let onboardingNavController else {
            return
        }

        let onConfirmed: () -> Void = { [self] in
            Task {
                do throws(SheetDisplayableError) {
                    switch backupType {
                    case .remote:
                        try await showChooseBackupPlan()
                    case .local:
                        db.write { tx in
                            localFileBackupStore.setLocalBackupsEnabled(value: true, tx: tx)
                            localFileBackupStore.setShouldOverrideShowLocalBackupsOnboarding(false, tx: tx)
                        }
                        onboardingNavController.setViewControllers(
                            [
                                onboardingNavController.viewControllers[0],
                                LocalFileBackupsSettingsViewController(
                                    localFileBackupExportJobRunner: DependenciesBridge.shared.localFileBackupExportJobRunner,
                                    localFileBackupStore: localFileBackupStore,
                                    db: db,
                                    accountKeyStore: accountKeyStore,
                                    localFileBackupManager: localFileBackupManager,
                                    localFileBackupExportJobStore: LocalFileBackupExportJobStore(),
                                ),
                            ],
                            animated: true,
                        )
                    }
                } catch {
                    error.showSheet(from: onboardingNavController)
                }
            }
        }

        let saveAndConfirmKeyCoordinator = BackupSaveAndConfirmKeyCoordinator(
            navigationController: onboardingNavController,
        )
        saveAndConfirmKeyCoordinator.present(
            aepMode: .current(aep, localDeviceAuthSuccess),
            options: [
                .showSaveKeyToPasswordManager(onConfirmed: onConfirmed),
                .showSaveKeyManually(onConfirmed: onConfirmed),
            ],
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
        planSelection: BackupEnablingManager.PlanSelection,
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
        guard let onboardingNavController else {
            return
        }

        db.write { tx in
            backupSettingsStore.setShouldOverrideShowBackupsOnboarding(false, tx: tx)
        }

        onboardingNavController.setViewControllers(
            [
                onboardingNavController.viewControllers.first!,
                BackupSettingsViewController(onAppearAction: .presentWelcomeToBackupsSheet),
            ],
            animated: true,
        )
    }

    private func promptToCancelOnboarding(fromViewController: UIViewController) {
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
                guard let onboardingNavController else {
                    return
                }

                onboardingNavController.popToRootViewController(animated: true)
            },
        ))
        actionSheet.addAction(.cancel)

        fromViewController.presentActionSheet(actionSheet)
    }
}
