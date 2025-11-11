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
        var items = [OWSTableItem]()

        items += [
            OWSTableItem(title: "Set Backups subscription already redeemed", actionBlock: {
                let db = DependenciesBridge.shared.db
                let issueStore = BackupSubscriptionIssueStore()
                db.write { tx in
                    issueStore.setShouldWarnIAPSubscriptionAlreadyRedeemed(endOfCurrentPeriod: Date(), tx: tx)
                }
            }),
            OWSTableItem(title: "Unset Backups subscription already redeemed", actionBlock: {
                let db = DependenciesBridge.shared.db
                let issueStore = BackupSubscriptionIssueStore()
                db.write { tx in
                    issueStore.setStopWarningIAPSubscriptionAlreadyRedeemed(tx: tx)
                }
            }),
        ]
        return OWSTableSection(title: name, items: items)
    }
}

#endif
