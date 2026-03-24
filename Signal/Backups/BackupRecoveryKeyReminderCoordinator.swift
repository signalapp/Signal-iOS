//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import UIKit

class BackupRecoveryKeyReminderCoordinator {
    private let aep: AccountEntropyPool
    private let fromViewController: UIViewController
    private let onSuccess: () -> Void

    private weak var backupKeyReminderNavController: UINavigationController?

    init(
        aep: AccountEntropyPool,
        fromViewController: UIViewController,
        onSuccess: @escaping () -> Void,
    ) {
        self.aep = aep
        self.fromViewController = fromViewController
        self.onSuccess = onSuccess
    }

    func presentVerifyFlow() {
        let navController = UINavigationController()
        backupKeyReminderNavController = navController

        // Retain ourselves as long as the nav controller is presented.
        ObjectRetainer.retainObject(self, forLifetimeOf: navController)

        navController.viewControllers = [
            ReminderEnterRecoveryKeyViewController(
                aep: aep,
                onForgotKeyTapped: { [weak self] in
                    self?.showRecordRecoveryKey()
                },
                onEntryConfirmed: { [weak self] in
                    self?.showKeepKeySafeSheet()
                },
            ),
        ]

        fromViewController.present(navController, animated: true)
    }

    private func showKeepKeySafeSheet() {
        let keepKeySafeSheet = BackupKeepKeySafeSheet(
            onContinue: { [weak self] in
                guard let self else { return }

                backupKeyReminderNavController?.dismiss(animated: true)
                onSuccess()
            },
            secondaryButton: .dismissing(
                title: CommonStrings.cancelButton,
                style: .secondary,
            ),
        )

        backupKeyReminderNavController?.present(keepKeySafeSheet, animated: true)
    }

    private func showRecordRecoveryKey() {
        Task { @MainActor in
            guard
                let authSuccess = await LocalDeviceAuthentication().performBiometricAuth(),
                let backupKeyReminderNavController
            else { return }

            _showRecordRecoveryKey(
                backupKeyReminderNavController: backupKeyReminderNavController,
                localDeviceAuthSuccess: authSuccess,
                aep: aep,
            )
        }
    }

    private func _showRecordRecoveryKey(
        backupKeyReminderNavController: UINavigationController,
        localDeviceAuthSuccess: LocalDeviceAuthentication.AuthSuccess,
        aep: AccountEntropyPool,
    ) {
        backupKeyReminderNavController.pushViewController(
            BackupRecordKeyViewController(
                aepMode: .current(aep, localDeviceAuthSuccess),
                options: [],
            ),
            animated: true,
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
