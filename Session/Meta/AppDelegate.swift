// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import PromiseKit
import SessionMessagingKit
import SessionUtilitiesKit

extension AppDelegate {

    @objc(syncConfigurationIfNeeded)
    func syncConfigurationIfNeeded() {
        guard Storage.shared.getUser()?.name != nil else { return }
        let userDefaults = UserDefaults.standard
        let lastSync = userDefaults[.lastConfigurationSync] ?? .distantPast
        guard Date().timeIntervalSince(lastSync) > 7 * 24 * 60 * 60 else { return } // Sync every 2 days
        
        MessageSender.syncConfiguration(forceSyncNow: false)
            .done {
                // Only update the 'lastConfigurationSync' timestamp if we have done the first sync (Don't want
                // a new device config sync to override config syncs from other devices)
                if userDefaults[.hasSyncedInitialConfiguration] {
                    userDefaults[.lastConfigurationSync] = Date()
                }
            }
            .retainUntilComplete()
    }

    @objc func startClosedGroupPoller() {
        guard Identity.fetchUserKeyPair() != nil else { return }
        
        ClosedGroupPoller.shared.start()
    }

    @objc func stopClosedGroupPoller() {
        ClosedGroupPoller.shared.stop()
    }
}
