//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

class UsernameSelectionCoordinator {
    struct Context {
        let usernameEducationManager: UsernameEducationManager
        let networkManager: NetworkManager
        let databaseStorage: SDSDatabaseStorage
        let usernameLookupManager: UsernameLookupManager
        let schedulers: Schedulers
        let storageServiceManager: StorageServiceManagerProtocol
    }

    private let localAci: UUID
    private let currentUsername: String?

    private weak var usernameSelectionDelegate: UsernameSelectionDelegate?

    private let context: Context

    init(
        localAci: UUID,
        currentUsername: String?,
        usernameSelectionDelegate: UsernameSelectionDelegate? = nil,
        context: Context
    ) {
        self.localAci = localAci
        self.currentUsername = currentUsername
        self.usernameSelectionDelegate = usernameSelectionDelegate
        self.context = context
    }

    func present(fromViewController: UIViewController) {
        let shouldShowUsernameEducation: Bool = context.databaseStorage.read { transaction in
            context.usernameEducationManager.shouldShowUsernameEducation(transaction: transaction.asV2Read)
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

            self.context.databaseStorage.write { transaction in
                self.context.usernameEducationManager.setShouldShowUsernameEducation(
                    false,
                    transaction: transaction.asV2Write
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
            localAci: localAci,
            context: .init(
                networkManager: context.networkManager,
                databaseStorage: context.databaseStorage,
                usernameLookupManager: context.usernameLookupManager,
                schedulers: context.schedulers,
                storageServiceManager: context.storageServiceManager
            )
        )

        vc.usernameSelectionDelegate = usernameSelectionDelegate

        fromViewController.presentFormSheet(
            OWSNavigationController(rootViewController: vc),
            animated: true
        )
    }
}
