//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import UIKit

@MainActor
class BackupRecoveryKeyReminderCoordinator {
    private weak var backupKeyReminderNavController: UINavigationController?

    init() {}

    deinit {
        Logger.verbose("")
    }

    func present(
        aep: AccountEntropyPool,
        fromViewController: UIViewController,
        onSuccess _onSuccess: @escaping () -> Void,
    ) {
        let navController = UINavigationController()
        backupKeyReminderNavController = navController

        let onSuccess: () -> Void = { [self] in
            backupKeyReminderNavController?.dismiss(animated: true)
            _onSuccess()
        }

        navController.viewControllers = [
            ReminderEnterRecoveryKeyViewController(
                aep: aep,
                onForgotKeyTapped: { [self] in
                    showSaveAndConfirmRecoveryKey(
                        aep: aep,
                        onSuccess: onSuccess,
                    )
                },
                onEntryConfirmed: { [self] in
                    showKeepKeySafeSheet(
                        onSuccess: onSuccess,
                    )
                },
            ),
        ]

        fromViewController.present(navController, animated: true)
    }

    private func showKeepKeySafeSheet(
        onSuccess: @escaping () -> Void,
    ) {
        let keepKeySafeSheet = BackupKeepKeySafeSheet(
            onContinue: {
                onSuccess()
            },
            secondaryButton: .dismissing(
                title: CommonStrings.cancelButton,
                style: .secondary,
            ),
        )

        backupKeyReminderNavController?.present(keepKeySafeSheet, animated: true)
    }

    private func showSaveAndConfirmRecoveryKey(
        aep: AccountEntropyPool,
        onSuccess: @escaping () -> Void,
    ) {
        Task { @MainActor in
            guard
                let authSuccess = await LocalDeviceAuthentication(
                    useCase: .recoveryKeyReminder,
                ).performBiometricAuth()
            else {
                return
            }

            _showSaveAndConfirmRecoveryKey(
                aep: aep,
                localDeviceAuthSuccess: authSuccess,
                onSuccess: onSuccess,
            )
        }
    }

    private func _showSaveAndConfirmRecoveryKey(
        aep: AccountEntropyPool,
        localDeviceAuthSuccess: LocalDeviceAuthentication.AuthSuccess,
        onSuccess: @escaping () -> Void,
    ) {
        guard let backupKeyReminderNavController else {
            return
        }

        let saveAndConfirmKeyCoordinator = BackupSaveAndConfirmKeyCoordinator(
            navigationController: backupKeyReminderNavController,
        )
        saveAndConfirmKeyCoordinator.present(
            aepMode: .current(aep, localDeviceAuthSuccess),
            options: [
                .showSaveKeyToPasswordManager(onConfirmed: onSuccess),
                .showSaveKeyManually(onConfirmed: onSuccess),
            ],
        )
    }
}

// MARK: -

private final class ReminderEnterRecoveryKeyViewController: EnterAccountEntropyPoolViewController {
    init(
        aep: AccountEntropyPool,
        onForgotKeyTapped: @escaping () -> Void,
        onEntryConfirmed: @escaping () -> Void,
    ) {
        super.init()

        configure(
            aepValidationPolicy: .acceptOnly(aep),
            colorConfig: ColorConfig(
                background: UIColor.Signal.background,
                aepEntryBackground: UIColor.Signal.quaternaryFill,
            ),
            headerStrings: HeaderStrings(
                title: OWSLocalizedString(
                    "BACKUP_RECOVERY_KEY_REMINDER_TITLE",
                    comment: "Title for a screen asking users to enter their recovery key, for reminder purposes.",
                ),
                subtitle: OWSLocalizedString(
                    "BACKUP_RECOVERY_KEY_REMINDER_SUBTITLE",
                    comment: "Subtitle for a screen asking users to enter their recovery key, for reminder purposes.",
                ),
            ),
            footerButtonConfig: FooterButtonConfig(
                title: OWSLocalizedString(
                    "BACKUP_RECOVERY_KEY_REMINDER_FORGOT_KEY_BUTTON",
                    comment: "Title for a button offering help if the user has forgotten their recovery key.",
                ),
                action: {
                    onForgotKeyTapped()
                },
            ),
            onEntryConfirmed: { _ in
                onEntryConfirmed()
            },
        )
    }
}
