//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import Testing

@testable import SignalServiceKit

struct AciContactShareNameStoreTests {
    private let db = InMemoryDB()
    private let store = AciContactShareNameStore()

    private func insertRecipient() -> SignalRecipient {
        return db.write { tx in
            try! SignalRecipient.insertRecord(aci: .randomForTesting(), phoneNumber: nil, tx: tx)
        }
    }

    @Test
    func testRoundTrip() throws {
        let recipient = insertRecipient()
        let name = try #require(AciContactShareName(recipient: recipient, givenName: "Shared", familyName: "Name"))

        db.write { tx in store.insertOne(name, tx: tx) }

        #expect(db.read { tx in store.fetchOne(forRecipientRowID: recipient.id, tx: tx) } == name)
    }

    @Test
    func testFetchMissingReturnsNil() {
        let recipient = insertRecipient()

        #expect(db.read { tx in store.fetchOne(forRecipientRowID: recipient.id, tx: tx) } == nil)
    }

    @Test
    func testDelete() throws {
        let recipient = insertRecipient()
        let name = try #require(AciContactShareName(recipient: recipient, givenName: "Shared", familyName: nil))
        db.write { tx in
            store.insertOne(name, tx: tx)
        }

        db.write { tx in store.deleteOne(forRecipientRowID: recipient.id, tx: tx) }

        #expect(db.read { tx in store.fetchOne(forRecipientRowID: recipient.id, tx: tx) } == nil)
    }

    @Test
    func testDeletingRecipientDeletesName() throws {
        let recipient = insertRecipient()
        let name = try #require(AciContactShareName(recipient: recipient, givenName: "Shared", familyName: nil))
        db.write { tx in
            store.insertOne(name, tx: tx)
        }

        db.write { tx in RecipientDatabaseTable().removeRecipient(recipient, transaction: tx) }

        #expect(db.read { tx in store.fetchOne(forRecipientRowID: recipient.id, tx: tx) } == nil)
    }

    @Test
    func testEnumerateAll() throws {
        let recipients = [insertRecipient(), insertRecipient()]
        let names = try recipients.map { recipient in
            try #require(AciContactShareName(recipient: recipient, givenName: "Shared", familyName: nil))
        }
        db.write { tx in
            for name in names {
                store.insertOne(name, tx: tx)
            }
        }

        var enumerated = [AciContactShareName]()
        db.read { tx in store.enumerateAll(tx: tx) { enumerated.append($0) } }

        #expect(Set(enumerated.map(\.recipientRowID)) == Set(recipients.map(\.id)))
    }
}
