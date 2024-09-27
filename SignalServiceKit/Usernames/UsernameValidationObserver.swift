//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class UsernameValidationObserver {
    private let manager: UsernameValidationManager
    private let database: DB

    public init(manager: UsernameValidationManager, database: DB) {
        self.manager = manager
        self.database = database

        observeNotifications()

        AppReadinessGlobal.runNowOrWhenAppDidBecomeReadyAsync {
            self.database.read { transaction in
                self.manager.validateUsernameIfNecessary(transaction)
            }
        }
    }

    // MARK: Notifications

    private func observeNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didBecomeActive),
            name: .OWSApplicationWillEnterForeground,
            object: nil)
    }

    @objc
    func didBecomeActive() {
        AssertIsOnMainThread()
        AppReadinessGlobal.runNowOrWhenAppDidBecomeReadyAsync {
            self.database.read { transaction in
                self.manager.validateUsernameIfNecessary(transaction)
            }
        }
    }
}
