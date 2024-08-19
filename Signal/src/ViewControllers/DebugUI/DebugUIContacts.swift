//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalServiceKit
import SignalUI

#if USE_DEBUG_UI

class DebugUIContacts: DebugUIPage {

    let name = "Contacts"

    func section(thread: TSThread?) -> OWSTableSection? {
        return OWSTableSection(title: name, items: [
            OWSTableItem(title: "Create 1 Random Contact",
                         actionBlock: { Task { await DebugContactsUtils.createRandomContacts(1) } }),
            OWSTableItem(title: "Create 100 Random Contacts",
                         actionBlock: { Task { await DebugContactsUtils.createRandomContacts(100) } }),
            OWSTableItem(title: "Create 1k Random Contacts",
                         actionBlock: { Task { await DebugContactsUtils.createRandomContacts(1000) } }),
            OWSTableItem(title: "Create 10k Random Contacts",
                         actionBlock: { Task { await DebugContactsUtils.createRandomContacts(10 * 1000) } }),
            OWSTableItem(title: "Delete Random Contacts",
                         actionBlock: { Task { await DebugContactsUtils.deleteRandomContacts() } }),
            OWSTableItem(title: "Delete All Contacts",
                         actionBlock: { Task { await DebugContactsUtils.deleteAllContacts() } }),
            OWSTableItem(title: "New Unregistered Contact Thread",
                         actionBlock: { DebugUIContacts.createUnregisteredContactThread() }),
        ])
    }

    // MARK: -

    private static func createUnregisteredContactThread() {
        let thread = TSContactThread.getOrCreateThread(contactAddress: SignalServiceAddress(Aci(fromUUID: UUID())))
        SignalApp.shared.presentConversationForThread(thread, animated: true)
     }
}

#endif
