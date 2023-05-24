//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

class AppIconBadgeUpdater {
    private let badgeManager: BadgeManager

    init(badgeManager: BadgeManager) {
        self.badgeManager = badgeManager
    }

    func startObserving() {
        badgeManager.addObserver(self)
    }
}

extension AppIconBadgeUpdater: BadgeObserver {
    func didUpdateBadgeValue(_ badgeManager: BadgeManager, badgeValue: UInt) {
        UIApplication.shared.applicationIconBadgeNumber = Int(badgeValue)
    }
}
