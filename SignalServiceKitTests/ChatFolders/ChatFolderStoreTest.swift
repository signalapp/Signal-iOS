//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import LibSignalClient
import Testing

@testable import SignalServiceKit

final class ChatFolderStoreTest {
    private let inMemoryDB = InMemoryDB()
    private let store = ChatFolderStore()

    init() {
        // The app creates this at launch.
        inMemoryDB.write { _ = store.fetchOrInsertAllChatsRecord(tx: $0) }
    }

    // MARK: - Helpers

    private var recipientNicknames = [String: SignalRecipient.RowId]()

    /// A real recipient, for membership foreign keys
    private func contact(_ nickname: String) -> ChatFolderChatRecord.Chat {
        if let existing = recipientNicknames[nickname] {
            return .contact(recipientRowId: existing)
        }
        let recipient = inMemoryDB.write { tx in
            try! SignalRecipient.insertRecord(aci: Aci.randomForTesting(), tx: tx)
        }
        recipientNicknames[nickname] = recipient.id
        return .contact(recipientRowId: recipient.id)
    }

    private func recipientRowId(_ chat: ChatFolderChatRecord.Chat) -> SignalRecipient.RowId {
        guard case .contact(let recipientRowId) = chat else {
            fatalError("not a contact")
        }
        return recipientRowId
    }

    @discardableResult
    private func insertFolder(
        name: String,
        position: UInt32,
        showOnlyUnread: Bool = false,
        showMutedChats: Bool = true,
        includeAllIndividualChats: Bool = false,
        includeAllGroupChats: Bool = false,
    ) -> ChatFolderRecord {
        return inMemoryDB.write { tx in
            store.insertCustomFolderRecord(
                chatFolderId: UUID(),
                name: name,
                position: position,
                showOnlyUnread: showOnlyUnread,
                showMutedChats: showMutedChats,
                includeAllIndividualChats: includeAllIndividualChats,
                includeAllGroupChats: includeAllGroupChats,
                deletedAtTimestampMs: 0,
                tx: tx,
            )
        }
    }

    private func insertGroup() -> ChatFolderChatRecord.Chat {
        let group = inMemoryDB.write { tx in
            GroupRecord.insertRecord(
                groupId: Randomness.generateRandomBytes(32),
                threadId: nil,
                masterKey: nil,
                refreshedAt: Date(),
                tx: tx,
            )
        }
        return .group(groupRowId: group.rowId)
    }

    private func setMembership(
        _ membershipType: ChatFolder.MembershipType,
        _ chat: ChatFolderChatRecord.Chat,
        in folder: ChatFolderRecord,
    ) {
        inMemoryDB.write { tx in
            store.setMembership(membershipType, chat: chat, folderRowId: folder.id, tx: tx)
        }
    }

    private func memberships(_ folder: ChatFolderRecord) -> [ChatFolderChatRecord.Chat: ChatFolder.MembershipType] {
        let memberships = inMemoryDB.read { store.fetchMemberships(folderRowId: folder.id, tx: $0) }
        return Dictionary(uniqueKeysWithValues: memberships.map { ($0.chat, $0.membershipType) })
    }

    private func membershipRowCount() -> Int {
        return inMemoryDB.read { tx in
            try! Int.fetchOne(tx.database, sql: "SELECT COUNT(*) FROM ChatFolderChat")!
        }
    }

    private func expectViolation(
        _ expected: ResultCode,
        sourceLocation: SourceLocation = #_sourceLocation,
        _ block: () throws -> Void,
    ) {
        let error = #expect(throws: DatabaseError.self, sourceLocation: sourceLocation, performing: block)
        #expect(error?.extendedResultCode == expected, sourceLocation: sourceLocation)
    }

    // MARK: - Schema

    @Test
    func testMembershipQueriesUseTheirIndexes() {
        func plan(_ sql: String) -> String {
            return inMemoryDB.read { tx in
                let rows = try! Row.fetchAll(tx.database, sql: "EXPLAIN QUERY PLAN \(sql)")
                return rows.map { "\($0["detail"] ?? "")" }.joined(separator: " | ")
            }
        }

        // Keyed on the folder: loading or replacing a folder's memberships, and
        // the foreign key cascade when a folder row is deleted.
        #expect(
            plan("SELECT * FROM ChatFolderChat WHERE chatFolderRowId = 1")
                .contains("index_ChatFolderChat_on_chatFolderRowId (chatFolderRowId=?)"),
        )
        #expect(
            plan("DELETE FROM ChatFolder WHERE id = 1")
                .contains("index_ChatFolderChat_on_chatFolderRowId (chatFolderRowId=?)"),
        )

        // Keyed on the recipient and folder: the merge's existing lookup.
        #expect(
            plan("SELECT * FROM ChatFolderChat WHERE chatFolderRowId = 1 AND recipientRowId = 1")
                .contains("index_ChatFolderChat_on_recipientRowId_and_chatFolderRowId (recipientRowId=? AND chatFolderRowId=?)"),
        )

        // Keyed on the recipient alone: the merge, and the foreign key cascade
        // when a recipient row is deleted.
        #expect(
            plan("SELECT * FROM ChatFolderChat WHERE recipientRowId = 1")
                .contains("index_ChatFolderChat_on_recipientRowId_and_chatFolderRowId (recipientRowId=?)"),
        )
        #expect(
            plan("DELETE FROM model_SignalRecipient WHERE id = 1")
                .contains("index_ChatFolderChat_on_recipientRowId_and_chatFolderRowId (recipientRowId=?)"),
        )

        // Keyed on the group alone: the foreign key cascade when a group row
        // is deleted.
        #expect(
            plan("DELETE FROM GroupRecord WHERE rowId = 1")
                .contains("index_ChatFolderChat_on_groupRowId_and_chatFolderRowId (groupRowId=?)"),
        )
    }

    // MARK: - Round tripping

    @Test
    func testInsertAndFetchRoundTrip() {
        let inserted = insertFolder(
            name: "Work 💼",
            position: 1,
            showOnlyUnread: true,
            showMutedChats: false,
            includeAllGroupChats: true,
        )
        let fetched = inMemoryDB.read { store.fetchRecord(chatFolderId: inserted.chatFolderId, tx: $0) }
        #expect(fetched == inserted)
    }

    @Test
    func testChatFolderIdIsStoredAsUUIDBytes() throws {
        let inserted = insertFolder(name: "Work", position: 1)

        let storedId = try inMemoryDB.read { tx in
            try Data.fetchOne(
                tx.database,
                sql: "SELECT chatFolderId FROM ChatFolder WHERE id = ?",
                arguments: [inserted.id],
            )
        }
        #expect(storedId == inserted.chatFolderId.data)
    }

    @Test
    func testChatFolderIdIsUnique() {
        let existing = insertFolder(name: "Work", position: 1)

        inMemoryDB.write { tx in
            expectViolation(.SQLITE_CONSTRAINT_UNIQUE) {
                _ = try ChatFolderRecord.insertRecord(
                    chatFolderId: existing.chatFolderId,
                    folderType: .custom,
                    name: "Also Work",
                    position: 2,
                    showOnlyUnread: false,
                    showMutedChats: true,
                    includeAllIndividualChats: false,
                    includeAllGroupChats: false,
                    deletedAtTimestampMs: 0,
                    tx: tx,
                )
            }
        }
    }

    @Test
    func testASecondAllChatsFolderCannotBePersisted() {
        inMemoryDB.write { tx in
            expectViolation(.SQLITE_CONSTRAINT_UNIQUE) {
                _ = try ChatFolderRecord.insertRecord(
                    chatFolderId: UUID(),
                    folderType: .all,
                    name: "",
                    position: 7,
                    showOnlyUnread: false,
                    showMutedChats: true,
                    includeAllIndividualChats: true,
                    includeAllGroupChats: true,
                    deletedAtTimestampMs: 0,
                    tx: tx,
                )
            }
        }
        let records = inMemoryDB.read { store.fetchAllRecords(tx: $0) }
        #expect(records.count == 1)
    }

    // MARK: - Ordering and current-ness

    @Test
    func testFetchDisplayableRecordsIsOrderedAndExcludesTombstones() {
        insertFolder(name: "Third", position: 30)
        insertFolder(name: "First", position: 10)
        let second = insertFolder(name: "Second", position: 20)

        inMemoryDB.write { tx in
            store.markDeleted(chatFolderId: second.chatFolderId, deletedAtTimestampMs: 1000, tx: tx)
        }

        let records = inMemoryDB.read { store.fetchDisplayableRecords(tx: $0) }
        #expect(records.map(\.name) == ["", "First", "Third"])
        #expect(records.map(\.position) == [0, 10, 30])
    }

    @Test
    func testFetchOrInsertAllChatsRecordRecreatesAMissingFolder() throws {
        let seeded = try #require(inMemoryDB.read { store.fetchRecordForAllChatsFolder(tx: $0) })
        #expect(inMemoryDB.write { store.fetchOrInsertAllChatsRecord(tx: $0) } == seeded)

        inMemoryDB.write { tx in
            try! tx.database.execute(sql: #"DELETE FROM "ChatFolder""#)
        }
        let recreated = inMemoryDB.write { store.fetchOrInsertAllChatsRecord(tx: $0) }
        #expect(recreated.folderType == .all)
        #expect(recreated.chatFolderId != seeded.chatFolderId)
        #expect(inMemoryDB.read { store.fetchRecordForAllChatsFolder(tx: $0) } == recreated)
    }

    @Test
    func testFoldersWithTheSamePositionSortTheSameOnEveryDevice() {
        let chatFolderIds = [UUID(), UUID()]
        func names(insertionOrder: [Int]) -> [String] {
            let otherDB = InMemoryDB()
            otherDB.write { tx in
                for index in insertionOrder {
                    _ = store.insertCustomFolderRecord(
                        chatFolderId: chatFolderIds[index],
                        name: "Folder \(index)",
                        position: 1,
                        showOnlyUnread: false,
                        showMutedChats: true,
                        includeAllIndividualChats: false,
                        includeAllGroupChats: false,
                        deletedAtTimestampMs: 0,
                        tx: tx,
                    )
                }
            }
            return otherDB.read { store.fetchDisplayableRecords(tx: $0).map(\.name) }
        }

        #expect(names(insertionOrder: [0, 1]) == names(insertionOrder: [1, 0]))
    }

    // MARK: - Membership

    @Test
    func testSetMembershipUpsertsRatherThanDuplicating() {
        let folder = insertFolder(name: "Work", position: 1)
        let chats = [contact("alice"), insertGroup()]

        for chat in chats {
            setMembership(.included, chat, in: folder)
            // "Remove from folder" flips included to excluded; it must not add a row.
            setMembership(.excluded, chat, in: folder)
        }

        #expect(memberships(folder) == [chats[0]: .excluded, chats[1]: .excluded])
        #expect(membershipRowCount() == chats.count)
    }

    @Test
    func testTheSameChatCanBeInSeveralFolders() {
        let work = insertFolder(name: "Work", position: 1)
        let family = insertFolder(name: "Family", position: 2)
        let chats = [contact("alice"), insertGroup()]

        for folder in [work, family] {
            for chat in chats {
                setMembership(.included, chat, in: folder)
            }
        }

        for folder in [work, family] {
            #expect(memberships(folder) == [chats[0]: .included, chats[1]: .included])
        }
    }

    @Test
    func testRemoveMembershipOnlyRemovesThatChat() {
        let work = insertFolder(name: "Work", position: 1)
        let family = insertFolder(name: "Family", position: 2)
        let chats = [contact("alice"), insertGroup()]
        for folder in [work, family] {
            for chat in chats {
                setMembership(.included, chat, in: folder)
            }
        }

        for (index, chat) in chats.enumerated() {
            inMemoryDB.write { tx in
                store.removeMembership(chat: chat, folderRowId: work.id, tx: tx)
            }
            let remaining = chats[(index + 1)...]
            #expect(memberships(work) == Dictionary(uniqueKeysWithValues: remaining.map { ($0, .included) }))
        }
        #expect(memberships(family) == [chats[0]: .included, chats[1]: .included])
    }

    @Test
    func testReplaceMembershipsDropsWhateverWasThereBefore() {
        let folder = insertFolder(name: "Work", position: 1)
        setMembership(.included, contact("stale"), in: folder)
        setMembership(.excluded, insertGroup(), in: folder)
        let fresh = contact("fresh")

        inMemoryDB.write { tx in
            store.replaceMemberships(
                folderRowId: folder.id,
                includedChats: [fresh],
                excludedChats: [],
                tx: tx,
            )
        }

        #expect(memberships(folder) == [fresh: .included])
    }

    @Test
    func testReplaceMembershipsWithEmptySetsClearsEverything() {
        let folder = insertFolder(name: "Work", position: 1)
        setMembership(.included, contact("stale"), in: folder)

        inMemoryDB.write { tx in
            store.replaceMemberships(folderRowId: folder.id, includedChats: [], excludedChats: [], tx: tx)
        }

        #expect(membershipRowCount() == 0)
    }

    @Test
    func testReplaceMembershipsResolvesChatInBothSetsAsExcluded() {
        let folder = insertFolder(name: "Work", position: 1)
        let a = contact("a")
        let contested = contact("contested")
        let c = contact("c")

        inMemoryDB.write { tx in
            store.replaceMemberships(
                folderRowId: folder.id,
                includedChats: [a, contested],
                excludedChats: [contested, c],
                tx: tx,
            )
        }

        #expect(memberships(folder) == [a: .included, contested: .excluded, c: .excluded])
    }

    // MARK: - Deletion

    @Test
    func testMarkDeletedTombstonesAndDropsMembership() throws {
        let folder = insertFolder(name: "Work", position: 1)
        setMembership(.included, contact("alice"), in: folder)
        setMembership(.included, insertGroup(), in: folder)

        inMemoryDB.write { tx in
            store.markDeleted(chatFolderId: folder.chatFolderId, deletedAtTimestampMs: 12345, tx: tx)
        }

        let tombstone = try #require(inMemoryDB.read { store.fetchRecord(chatFolderId: folder.chatFolderId, tx: $0) })
        #expect(tombstone.isDeleted)
        #expect(tombstone.deletedAtTimestampMs == 12345)
        #expect(tombstone.position == ChatFolderRecord.deletedPosition)
        #expect(membershipRowCount() == 0)
    }

    // MARK: - Recipient merging

    @Test
    func testMergeRecipientPrefersTheSurvivingRecipientsMembership() {
        let a = insertFolder(name: "A", position: 1)
        let b = insertFolder(name: "B", position: 2)
        let c = insertFolder(name: "C", position: 3)
        let surviving = contact("surviving")
        let losing = contact("losing")

        setMembership(.included, surviving, in: a)
        setMembership(.excluded, losing, in: a)

        setMembership(.included, losing, in: b)
        setMembership(.excluded, surviving, in: b)

        setMembership(.excluded, losing, in: c)

        let affected = inMemoryDB.write { tx in
            store.mergeRecipient(recipientRowId(losing), into: recipientRowId(surviving), tx: tx)
        }

        #expect(affected == [a.chatFolderId, b.chatFolderId, c.chatFolderId])
        #expect(memberships(a) == [surviving: .included])
        #expect(memberships(b) == [surviving: .excluded])
        #expect(memberships(c) == [surviving: .excluded])
    }

    @Test
    func testMergeRecipientLeavesOtherChatsAlone() {
        let folder = insertFolder(name: "Work", position: 1)
        let group = insertGroup()
        let losing = contact("losing")
        let surviving = contact("surviving")
        setMembership(.included, losing, in: folder)
        setMembership(.included, group, in: folder)

        inMemoryDB.write { tx in
            _ = store.mergeRecipient(recipientRowId(losing), into: recipientRowId(surviving), tx: tx)
        }

        #expect(memberships(folder) == [surviving: .included, group: .included])
    }

    @Test
    func testMergeRecipientIntoItselfIsANoOp() {
        let folder = insertFolder(name: "Work", position: 1)
        let same = contact("same")
        setMembership(.included, same, in: folder)

        let affected = inMemoryDB.write { tx in
            store.mergeRecipient(recipientRowId(same), into: recipientRowId(same), tx: tx)
        }

        #expect(affected.isEmpty)
        #expect(memberships(folder) == [same: .included])
    }

    // MARK: - Cascade

    @Test
    func testHardDeletingAFolderCascadesToMembership() {
        let folder = insertFolder(name: "Work", position: 1)
        setMembership(.included, contact("alice"), in: folder)
        setMembership(.included, insertGroup(), in: folder)

        inMemoryDB.write { tx in
            try! tx.database.execute(
                sql: #"DELETE FROM "ChatFolder" WHERE "id" = ?"#,
                arguments: [folder.id],
            )
        }

        #expect(membershipRowCount() == 0)
    }

    @Test
    func testDeletingARecipientCascadesToMembership() {
        let folder = insertFolder(name: "Work", position: 1)
        let doomed = contact("doomed")
        let survivor = contact("survivor")
        setMembership(.included, doomed, in: folder)
        setMembership(.included, survivor, in: folder)

        inMemoryDB.write { tx in
            try! tx.database.execute(
                sql: #"DELETE FROM "model_SignalRecipient" WHERE "id" = ?"#,
                arguments: [recipientRowId(doomed)],
            )
        }

        #expect(memberships(folder) == [survivor: .included])
    }

    @Test
    func testDeletingAGroupCascadesToMembership() {
        let folder = insertFolder(name: "Work", position: 1)
        let group = insertGroup()
        setMembership(.included, group, in: folder)
        guard case .group(let groupRowId) = group else {
            fatalError("not a group")
        }

        inMemoryDB.write { tx in
            try! tx.database.execute(
                sql: #"DELETE FROM "GroupRecord" WHERE "rowId" = ?"#,
                arguments: [groupRowId],
            )
        }

        #expect(membershipRowCount() == 0)
    }

    // MARK: - Constraints

    @Test
    func testMembershipForAnUnknownRecipientOrGroupIsRejected() {
        let folder = insertFolder(name: "Work", position: 1)
        inMemoryDB.write { tx in
            for chat: ChatFolderChatRecord.Chat in [.contact(recipientRowId: 999_999), .group(groupRowId: 999_999)] {
                let record = ChatFolderChatRecord(
                    chatFolderRowId: folder.id,
                    chat: chat,
                    membershipType: .included,
                )
                expectViolation(.SQLITE_CONSTRAINT_FOREIGNKEY) {
                    try record.insert(tx.database)
                }
            }
        }
    }

    @Test
    func testMembershipMustReferenceExactlyOneChat() {
        let folder = insertFolder(name: "Work", position: 1)
        let aliceRowId = recipientRowId(contact("alice"))
        guard case .group(let groupRowId) = insertGroup() else {
            fatalError("not a group")
        }
        let invalidColumns: [(Int64?, Int64?)] = [
            (nil, nil),
            (aliceRowId, groupRowId),
        ]
        inMemoryDB.write { tx in
            for (recipientRowId, groupRowId) in invalidColumns {
                expectViolation(.SQLITE_CONSTRAINT_CHECK) {
                    try tx.database.execute(
                        sql: """
                        INSERT INTO ChatFolderChat (chatFolderRowId, recipientRowId, groupRowId, membershipType)
                        VALUES (?, ?, ?, 0)
                        """,
                        arguments: [folder.id, recipientRowId, groupRowId],
                    )
                }
            }
        }
        #expect(membershipRowCount() == 0)
    }
}
