//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class UsernameValidationObserver {
    private let appReadiness: AppReadiness
    private let manager: UsernameValidationManager
    private let database: any DB

    public init(appReadiness: AppReadiness, manager: UsernameValidationManager, database: any DB) {
        self.appReadiness = appReadiness
        self.manager = manager
        self.database = database

        observeNotifications()

        appReadiness.runNowOrWhenAppDidBecomeReadyAsync {
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
        appReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            self.database.read { transaction in
                self.manager.validateUsernameIfNecessary(transaction)
            }
        }
    }
}
