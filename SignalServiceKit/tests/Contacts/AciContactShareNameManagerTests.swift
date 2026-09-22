//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import Testing

@testable import SignalServiceKit

struct AciContactShareNameManagerTests {
    private let db = InMemoryDB()
    private let searchableNameIndexer: SearchableNameIndexerImpl
    private let manager: AciContactShareNameManagerImpl

    init() {
        let aciContactShareNameStore = AciContactShareNameStore()
        self.searchableNameIndexer = SearchableNameIndexerImpl(
            threadStore: ThreadStoreImpl(),
            signalAccountStore: SignalAccountStoreImpl(),
            userProfileStore: UserProfileStoreImpl(),
            signalRecipientStore: RecipientDatabaseTable(),
            usernameLookupRecordStore: UsernameLookupRecordStore(),
            nicknameRecordStore: NicknameRecordStoreImpl(),
            aciContactShareNameStore: aciContactShareNameStore,
        )
        self.manager = AciContactShareNameManagerImpl(
            aciContactShareNameStore: aciContactShareNameStore,
            searchableNameIndexer: searchableNameIndexer,
        )
    }

    private func insertRecipient() -> SignalRecipient {
        return db.write { tx in
            try! SignalRecipient.insertRecord(aci: .randomForTesting(), phoneNumber: nil, tx: tx)
        }
    }

    private func searchForNames(_ searchText: String) -> [SignalRecipient.RowId] {
        var recipientRowIDs = [SignalRecipient.RowId]()
        db.read { tx in
            try? searchableNameIndexer.search(for: searchText, maxResults: 10, tx: tx) { indexableName in
                if let aciContactShareName = indexableName as? AciContactShareName {
                    recipientRowIDs.append(aciContactShareName.recipientRowID)
                }
            }
        }
        return recipientRowIDs
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

    @Test
    func testSavedNameIsSearchable() {
        let recipient = insertRecipient()

        db.write { tx in
            manager.saveName(givenName: "Bob", familyName: nil, for: recipient, tx: tx)
        }

        #expect(searchForNames("Bob") == [recipient.id])
    }

    @Test
    func testSaveOverwritesSearchIndexEntry() {
        let recipient = insertRecipient()

        db.write { tx in
            manager.saveName(givenName: "Bob", familyName: nil, for: recipient, tx: tx)
            manager.saveName(givenName: "Robert", familyName: nil, for: recipient, tx: tx)
        }

        #expect(searchForNames("Robert") == [recipient.id])
        #expect(searchForNames("Bob").isEmpty)
    }

    @Test
    func testDeleteRemovesSearchIndexEntry() {
        let recipient = insertRecipient()

        db.write { tx in
            manager.saveName(givenName: "Bob", familyName: nil, for: recipient, tx: tx)
            manager.deleteName(for: recipient, tx: tx)
        }

        #expect(searchForNames("Bob").isEmpty)
    }
}
