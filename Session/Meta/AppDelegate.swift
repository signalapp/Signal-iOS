// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import PromiseKit
import SessionMessagingKit
import SessionUtilitiesKit

extension AppDelegate {

    @objc(syncConfigurationIfNeeded)
    func syncConfigurationIfNeeded() {
        let lastSync: Date = (UserDefaults.standard[.lastConfigurationSync] ?? .distantPast)
        
        guard Date().timeIntervalSince(lastSync) > (7 * 24 * 60 * 60) else { return } // Sync every 2 days
        
        GRDBStorage.shared.write { db in
            MessageSender.syncConfiguration(db, forceSyncNow: false)
                .done {
                    // Only update the 'lastConfigurationSync' timestamp if we have done the
                    // first sync (Don't want a new device config sync to override config
                    // syncs from other devices)
                    if UserDefaults.standard[.hasSyncedInitialConfiguration] {
                        UserDefaults.standard[.lastConfigurationSync] = Date()
                    }
                }
                .retainUntilComplete()
        }
    }

    @objc func startClosedGroupPoller() {
        guard Identity.userExists() else { return }
        
        ClosedGroupPoller.shared.start()
    }

    @objc func stopClosedGroupPoller() {
        ClosedGroupPoller.shared.stop()
    }
}
