//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import Testing

@testable import SignalServiceKit

struct AciContactShareNameManagerTests {
    private let db = InMemoryDB()
    private let manager = AciContactShareNameManagerImpl(aciContactShareNameStore: AciContactShareNameStore())

    private func insertRecipient() -> SignalRecipient {
        return db.write { tx in
            try! SignalRecipient.insertRecord(aci: .randomForTesting(), phoneNumber: nil, tx: tx)
        }
    }

    @Test
    func testSaveAndFetch() {
        let recipient = insertRecipient()

        db.write { tx in
            manager.saveName(givenName: "Shared", familyName: "Name", for: recipient, tx: tx)
        }

        let name = db.read { tx in manager.fetchName(for: recipient, tx: tx) }
        #expect(name?.givenName == "Shared")
        #expect(name?.familyName == "Name")
    }

    @Test
    func testSaveOverwritesPreviousName() {
        let recipient = insertRecipient()

        db.write { tx in
            manager.saveName(givenName: "First", familyName: nil, for: recipient, tx: tx)
            manager.saveName(givenName: "Second", familyName: nil, for: recipient, tx: tx)
        }

        #expect(db.read { tx in manager.fetchName(for: recipient, tx: tx) }?.givenName == "Second")
    }

    @Test
    func testDeleteName() {
        let recipient = insertRecipient()

        db.write { tx in
            manager.saveName(givenName: "Shared", familyName: "Name", for: recipient, tx: tx)
            manager.deleteName(for: recipient, tx: tx)
        }

        #expect(db.read { tx in manager.fetchName(for: recipient, tx: tx) } == nil)
    }

    @Test
    func testDeleteNameForUnknownRecipientDoesNothing() {
        let knownRecipient = insertRecipient()
        let otherRecipient = insertRecipient()

        db.write { tx in
            manager.saveName(givenName: "Shared", familyName: nil, for: knownRecipient, tx: tx)
            manager.deleteName(for: otherRecipient, tx: tx)
        }

        #expect(db.read { tx in manager.fetchName(for: knownRecipient, tx: tx) }?.givenName == "Shared")
    }

    @Test
    func testSaveEmptyNameDeletesRecord() {
        let recipient = insertRecipient()

        db.write { tx in
            manager.saveName(givenName: "Shared", familyName: nil, for: recipient, tx: tx)
            manager.saveName(givenName: nil, familyName: nil, for: recipient, tx: tx)
        }

        #expect(db.read { tx in manager.fetchName(for: recipient, tx: tx) } == nil)
    }

    @Test
    func testSaveWhitespaceOnlyNameDeletesRecord() {
        let recipient = insertRecipient()

        db.write { tx in
            manager.saveName(givenName: "Shared", familyName: nil, for: recipient, tx: tx)
            manager.saveName(givenName: "  ", familyName: "\n", for: recipient, tx: tx)
        }

        #expect(db.read { tx in manager.fetchName(for: recipient, tx: tx) } == nil)
    }

    @Test
    func testSaveStripsWhitespace() {
        let recipient = insertRecipient()

        db.write { tx in
            manager.saveName(givenName: "  Shared ", familyName: " ", for: recipient, tx: tx)
        }

        let name = db.read { tx in manager.fetchName(for: recipient, tx: tx) }
        #expect(name?.givenName == "Shared")
        #expect(name?.familyName == nil)
    }

    @Test
    func testSaveStoresNameThisClientCannotRender() {
        let recipient = insertRecipient()
        let tooLongForThisClient = String(repeating: "a", count: 30)

        db.write { tx in
            manager.saveName(givenName: tooLongForThisClient, familyName: nil, for: recipient, tx: tx)
        }

        #expect(ProfileName(givenName: tooLongForThisClient, familyName: nil) == nil)
        #expect(db.read { tx in manager.fetchName(for: recipient, tx: tx) }?.givenName == tooLongForThisClient)
    }
}
