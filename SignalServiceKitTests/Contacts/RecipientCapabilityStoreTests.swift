//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import Testing

@testable import SignalServiceKit

struct RecipientCapabilityStoreTests {
    private let db = InMemoryDB()
    private let store = RecipientCapabilityStore()

    private func insertRecipient() -> SignalRecipient {
        return db.write { tx in
            try! SignalRecipient.insertRecord(aci: .randomForTesting(), phoneNumber: nil, tx: tx)
        }
    }

    private func isEnabled(_ recipient: SignalRecipient) -> Bool? {
        return db.read { tx in
            store.isEnabled(capability: .adminRemoveAndDelete, recipientRowId: recipient.id, tx: tx)
        }
    }

    @Test
    func testUnknownReturnsNil() {
        let recipient = insertRecipient()

        #expect(isEnabled(recipient) == nil)
    }

    @Test(arguments: [true, false])
    func testRoundTrip(isEnabled: Bool) {
        let recipient = insertRecipient()

        db.write { tx in
            store.setCapabilities([.adminRemoveAndDelete: isEnabled], recipientRowId: recipient.id, tx: tx)
        }

        #expect(self.isEnabled(recipient) == isEnabled)
    }

    @Test
    func testSetReplacesExistingValue() {
        let recipient = insertRecipient()

        db.write { tx in
            store.setCapabilities([.adminRemoveAndDelete: true], recipientRowId: recipient.id, tx: tx)
        }
        db.write { tx in
            store.setCapabilities([.adminRemoveAndDelete: false], recipientRowId: recipient.id, tx: tx)
        }

        #expect(isEnabled(recipient) == false)
    }

    @Test
    func testMissingCapabilityBecomesUnknown() {
        let recipient = insertRecipient()

        db.write { tx in
            store.setCapabilities([.adminRemoveAndDelete: true], recipientRowId: recipient.id, tx: tx)
        }
        db.write { tx in
            store.setCapabilities([:], recipientRowId: recipient.id, tx: tx)
        }

        #expect(isEnabled(recipient) == nil)
    }

    @Test
    func testRecipientsAreIndependent() {
        let capableRecipient = insertRecipient()
        let otherRecipient = insertRecipient()

        db.write { tx in
            store.setCapabilities([.adminRemoveAndDelete: true], recipientRowId: capableRecipient.id, tx: tx)
        }

        #expect(isEnabled(capableRecipient) == true)
        #expect(isEnabled(otherRecipient) == nil)
    }

    @Test
    func testDeletingRecipientDeletesCapabilities() {
        let recipient = insertRecipient()
        db.write { tx in
            store.setCapabilities([.adminRemoveAndDelete: true], recipientRowId: recipient.id, tx: tx)
        }

        db.write { tx in RecipientDatabaseTable().removeRecipient(recipient, transaction: tx) }

        #expect(isEnabled(recipient) == nil)
    }
}
