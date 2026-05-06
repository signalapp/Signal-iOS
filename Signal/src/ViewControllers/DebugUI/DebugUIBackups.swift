//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

#if USE_DEBUG_UI

class DebugUIBackups: DebugUIPage {

    let name = "Backups"

    func section(thread: TSThread?) -> OWSTableSection? {
        let backupSettingsStore = BackupSettingsStore()
        let db = DependenciesBridge.shared.db
        let issueStore = BackupSubscriptionIssueStore()

        var items = [OWSTableItem]()

        items += [
            OWSTableItem(title: "Suspend download queue", actionBlock: {
                db.write { tx in
                    backupSettingsStore.setIsBackupDownloadQueueSuspended(true, tx: tx)
                }
            }),
            OWSTableItem(title: "Unsuspend download queue", actionBlock: {
                db.write { tx in
                    backupSettingsStore.setIsBackupDownloadQueueSuspended(false, tx: tx)
                }
            }),
            OWSTableItem(title: "Set Backups subscription already redeemed", actionBlock: {
                db.write { tx in
                    issueStore.setShouldWarnIAPSubscriptionAlreadyRedeemed(endOfCurrentPeriod: Date(), tx: tx)
                }
            }),
            OWSTableItem(title: "Unset Backups subscription already redeemed", actionBlock: {
                db.write { tx in
                    issueStore.setStopWarningIAPSubscriptionAlreadyRedeemed(tx: tx)
                }
            }),
        ]
        return OWSTableSection(title: name, items: items)
    }
}

#endif
