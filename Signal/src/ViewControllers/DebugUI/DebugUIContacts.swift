//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

#if USE_DEBUG_UI

class DebugUIContacts: DebugUIPage {

    let name = "Contacts"

    func section(thread: TSThread?) -> OWSTableSection? {
        return OWSTableSection(title: name, items: [
            OWSTableItem(title: "Create 1 Random Contact",
                         actionBlock: { DebugContactsUtils.createRandomContacts(1) }),
            OWSTableItem(title: "Create 100 Random Contacts",
                         actionBlock: { DebugContactsUtils.createRandomContacts(100) }),
            OWSTableItem(title: "Create 1k Random Contacts",
                         actionBlock: { DebugContactsUtils.createRandomContacts(1000) }),
            OWSTableItem(title: "Create 10k Random Contacts",
                         actionBlock: { DebugContactsUtils.createRandomContacts(10 * 1000) }),
            OWSTableItem(title: "Delete Random Contacts",
                         actionBlock: { DebugContactsUtils.deleteRandomContacts() }),
            OWSTableItem(title: "Delete All Contacts",
                         actionBlock: { DebugContactsUtils.deleteAllContacts() }),
            OWSTableItem(title: "New Unregistered Contact Thread",
                         actionBlock: { DebugUIContacts.createUnregisteredContactThread() }),
            OWSTableItem(title: "Log SignalAccounts",
                         actionBlock: { DebugContactsUtils.logSignalAccounts() })
        ])
    }

    // MARK: -

    private static func createUnregisteredContactThread() {
        // We ensure that the phone number is invalid by using an invalid area code.
        var recipientId = "+1999"
        for _ in 1...7 {
            recipientId += "\(Int.random(in: 0...9))"
        }
        let thread = TSContactThread.getOrCreateThread(contactAddress: SignalServiceAddress(phoneNumber: recipientId))
        SignalApp.shared().presentConversationForThread(thread, animated: true)
     }
}

#endif
