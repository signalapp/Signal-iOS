//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

final class UsernameSelectionCoordinator {
    struct Context {
        let databaseStorage: SDSDatabaseStorage
        let networkManager: NetworkManager
        let storageServiceManager: StorageServiceManager
        let usernameEducationManager: UsernameEducationManager
        let localUsernameManager: LocalUsernameManager
    }

    private let currentUsername: String?
    private let isAttemptingRecovery: Bool

    private weak var usernameChangeDelegate: UsernameChangeDelegate?
    private weak var usernameSelectionDelegate: (any UsernameSelectionDelegate)?

    private let context: Context

    init(
        currentUsername: String?,
        isAttemptingRecovery: Bool = false,
        usernameChangeDelegate: UsernameChangeDelegate? = nil,
        usernameSelectionDelegate: (any UsernameSelectionDelegate)? = nil,
        context: Context
    ) {
        self.currentUsername = currentUsername
        self.isAttemptingRecovery = isAttemptingRecovery
        self.usernameChangeDelegate = usernameChangeDelegate
        self.usernameSelectionDelegate = usernameSelectionDelegate
        self.context = context
    }

    func present(fromViewController: UIViewController) {
        let shouldShowUsernameEducation: Bool = context.databaseStorage.read { tx in
            context.usernameEducationManager.shouldShowUsernameEducation(tx: tx)
        }

        if shouldShowUsernameEducation {
            presentUsernameEducation(fromViewController: fromViewController)
        } else {
            presentUsernameSelection(fromViewController: fromViewController)
        }
    }

    private func presentUsernameEducation(fromViewController: UIViewController) {
        let usernameEducationSheet = UsernameEducationViewController()

        usernameEducationSheet.continueCompletion = { [self, weak fromViewController] in
            // Intentional strong self capture
            guard let fromViewController else { return }

            self.context.databaseStorage.write { tx in
                self.context.usernameEducationManager.setShouldShowUsernameEducation(
                    false,
                    tx: tx
                )
            }

            self.context.storageServiceManager.recordPendingLocalAccountUpdates()

            self.presentUsernameSelection(fromViewController: fromViewController)
        }

        fromViewController.presentFormSheet(usernameEducationSheet, animated: true)
    }

    private func presentUsernameSelection(fromViewController: UIViewController) {
        let vc = UsernameSelectionViewController(
            existingUsername: .init(rawUsername: currentUsername),
            isAttemptingRecovery: isAttemptingRecovery,
            context: .init(
                networkManager: context.networkManager,
                databaseStorage: context.databaseStorage,
                localUsernameManager: context.localUsernameManager,
                storageServiceManager: context.storageServiceManager
            )
        )

        vc.usernameChangeDelegate = usernameChangeDelegate
        vc.usernameSelectionDelegate = usernameSelectionDelegate

        fromViewController.presentFormSheet(
            OWSNavigationController(rootViewController: vc),
            animated: true
        )
    }
}
