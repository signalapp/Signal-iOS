//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

#if USE_DEBUG_UI

class DebugUISyncMessages: DebugUIPage {

    let name = "Sync Messages"

    func section(thread: TSThread?) -> OWSTableSection? {
        return OWSTableSection(title: name, items: [
            OWSTableItem(title: "Send Contacts Sync Message",
                         actionBlock: { DebugUISyncMessages.sendContactsSyncMessage() }),
            OWSTableItem(title: "Send Blocklist Sync Message",
                         actionBlock: { DebugUISyncMessages.sendBlockListSyncMessage() }),
            OWSTableItem(title: "Send Configuration Sync Message",
                         actionBlock: { DebugUISyncMessages.sendConfigurationSyncMessage() })
        ])
    }

    // MARK: -

    private static func sendContactsSyncMessage() {
        SSKEnvironment.shared.syncManagerRef.syncAllContacts()
            .catch(on: DispatchQueue.global()) { error in
                Logger.info("Error: \(error)")
            }
    }

    private static func sendBlockListSyncMessage() {
        SSKEnvironment.shared.blockingManagerRef.syncBlockList(completion: { })
    }

    private static func sendConfigurationSyncMessage() {
        SSKEnvironment.shared.syncManagerRef.sendConfigurationSyncMessage()
    }
}

#endif
