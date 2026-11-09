//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import LibSignalClient
import Testing

@testable import SignalServiceKit

final class ChatFolderManagerTest {
    private let inMemoryDB = InMemoryDB()
    private let store = ChatFolderStore()
    private let threadStore = MockThreadStore()
    private let storageServiceManager = ChatFolderRecordingStorageServiceManager()
    private let manager: ChatFolderManager

    init() {
        let recipientDatabaseTable = RecipientDatabaseTable()
        manager = ChatFolderManager(
            chatFolderStore: store,
            recipientDatabaseTable: recipientDatabaseTable,
            recipientFetcher: RecipientFetcher(
                recipientDatabaseTable: recipientDatabaseTable,
                searchableNameIndexer: MockSearchableNameIndexer(),
            ),
            storageServiceManager: storageServiceManager,
            threadStore: threadStore,
        )
    }

    // MARK: - Helpers

    private func insertFolder() -> ChatFolderRecord {
        return inMemoryDB.write { tx in
            store.insertCustomFolderRecord(
                chatFolderId: UUID(),
                name: "Work",
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

    private func insertRecipient(_ aci: Aci = .randomForTesting()) -> SignalRecipient {
        return inMemoryDB.write { tx in
            try! SignalRecipient.insertRecord(aci: aci, tx: tx)
        }
    }

    private func insertContactThread(_ aci: Aci) -> TSContactThread {
        let thread = TSContactThread(contactAddress: .isolatedForTesting(serviceId: aci))
        threadStore.insertThread(thread)
        return thread
    }

    /// Group threads are resolved through `GroupRecord.threadId`, which is a
    /// foreign key, so they need a real row. Their IDs are kept clear of the
    /// mock thread store's.
    private var nextGroupThreadRowId: Int64 = 1000
    private func insertGroupThreadRow() -> Int64 {
        let thread = TSThread(uniqueId: UUID().uuidString)
        thread.id = nextGroupThreadRowId
        nextGroupThreadRowId += 1
        inMemoryDB.write { tx in
            try! thread.insert(tx.database)
        }
        return thread.id!
    }

    private func insertGroup(groupId: Data = Randomness.generateRandomBytes(32), threadRowId: Int64?) -> GroupRecord {
        return inMemoryDB.write { tx in
            GroupRecord.insertRecord(
                groupId: groupId,
                threadId: threadRowId,
                masterKey: nil,
                refreshedAt: Date(),
                tx: tx,
            )
        }
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

    private func fetch(_ folder: ChatFolderRecord) -> ChatFolder {
        return inMemoryDB.read { manager.fetch(chatFolderId: folder.chatFolderId, tx: $0)! }
    }

    private func memberships(_ folder: ChatFolderRecord) -> [ChatFolderChatRecord.Chat: ChatFolder.MembershipType] {
        let memberships = inMemoryDB.read { store.fetchMemberships(folderRowId: folder.id, tx: $0) }
        return Dictionary(uniqueKeysWithValues: memberships.map { ($0.chat, $0.membershipType) })
    }

    // MARK: - Reading

    @Test
    func testFetchResolvesEachKindOfChatToItsThread() {
        let folder = insertFolder()
        let recipient = insertRecipient()
        let contactThread = insertContactThread(recipient.aci!)
        let groupThreadRowId = insertGroupThreadRow()
        let group = insertGroup(threadRowId: groupThreadRowId)

        setMembership(.included, .contact(recipientRowId: recipient.id), in: folder)
        setMembership(.excluded, .group(groupRowId: group.rowId), in: folder)

        let hydrated = fetch(folder)
        #expect(hydrated.includedThreadRowIds == [contactThread.sqliteRowId!])
        #expect(hydrated.excludedThreadRowIds == [groupThreadRowId])
    }

    @Test
    func testChatsAppearOnceTheirThreadsExist() {
        let folder = insertFolder()
        let recipient = insertRecipient()
        var group = insertGroup(threadRowId: nil)

        setMembership(.included, .contact(recipientRowId: recipient.id), in: folder)
        setMembership(.included, .group(groupRowId: group.rowId), in: folder)
        #expect(fetch(folder).includedThreadRowIds == [])

        let contactThread = insertContactThread(recipient.aci!)
        let groupThreadRowId = insertGroupThreadRow()
        inMemoryDB.write { tx in
            group.setThreadId(groupThreadRowId, tx: tx)
        }

        #expect(fetch(folder).includedThreadRowIds == [contactThread.sqliteRowId!, groupThreadRowId])
    }

    @Test
    func testGroupMembershipOutlivesItsThread() {
        let folder = insertFolder()
        let groupThreadRowId = insertGroupThreadRow()
        let group = insertGroup(threadRowId: groupThreadRowId)
        setMembership(.included, .group(groupRowId: group.rowId), in: folder)

        inMemoryDB.write { tx in
            try! tx.database.execute(
                sql: #"DELETE FROM "model_TSThread" WHERE "id" = ?"#,
                arguments: [groupThreadRowId],
            )
        }

        #expect(fetch(folder).includedThreadRowIds == [])
        #expect(memberships(folder) == [.group(groupRowId: group.rowId): .included])
    }

    // MARK: - Writing

    @Test
    func testSetMembershipStoresEachKindOfThreadByWhatIdentifiesIt() {
        let folder = insertFolder()
        let recipient = insertRecipient()
        let contactThread = insertContactThread(recipient.aci!)
        let groupId = Randomness.generateRandomBytes(32)
        let group = insertGroup(groupId: groupId, threadRowId: nil)
        let groupThread = TSGroupThread.forUnitTest(groupId: groupId)

        inMemoryDB.write { tx in
            manager.setMembership(.included, thread: contactThread, folderRowId: folder.id, tx: tx)
            manager.setMembership(.excluded, thread: groupThread, folderRowId: folder.id, tx: tx)
        }

        #expect(memberships(folder) == [
            .contact(recipientRowId: recipient.id): .included,
            .group(groupRowId: group.rowId): .excluded,
        ])
    }

    @Test
    func testSetMembershipCreatesAMissingRecipient() throws {
        let folder = insertFolder()
        let aci = Aci.randomForTesting()
        let contactThread = insertContactThread(aci)

        inMemoryDB.write { tx in
            manager.setMembership(.included, thread: contactThread, folderRowId: folder.id, tx: tx)
        }

        let recipient = try #require(inMemoryDB.read { RecipientDatabaseTable().fetchRecipient(serviceId: aci, transaction: $0) })
        #expect(memberships(folder) == [.contact(recipientRowId: recipient.id): .included])
    }

    @Test
    func testUpdateMembershipsOnlyTouchesTheGivenThreads() {
        let folder = insertFolder()
        let threadless = insertRecipient()
        let unrestoredGroup = insertGroup(threadRowId: nil)
        let removed = insertRecipient()
        let removedThread = insertContactThread(removed.aci!)
        let added = insertRecipient()
        let addedThread = insertContactThread(added.aci!)
        let flipped = insertRecipient()
        let flippedThread = insertContactThread(flipped.aci!)

        setMembership(.excluded, .contact(recipientRowId: threadless.id), in: folder)
        setMembership(.included, .group(groupRowId: unrestoredGroup.rowId), in: folder)
        setMembership(.included, .contact(recipientRowId: removed.id), in: folder)
        setMembership(.included, .contact(recipientRowId: flipped.id), in: folder)

        // A thread created while the folder was being edited wasn't shown, so
        // its membership is kept.
        _ = insertContactThread(threadless.aci!)

        inMemoryDB.write { tx in
            manager.updateMemberships(
                folderRowId: folder.id,
                includedThreadRowIds: [addedThread.sqliteRowId!],
                excludedThreadRowIds: [flippedThread.sqliteRowId!],
                removedThreadRowIds: [removedThread.sqliteRowId!],
                tx: tx,
            )
        }

        #expect(memberships(folder) == [
            .contact(recipientRowId: threadless.id): .excluded,
            .group(groupRowId: unrestoredGroup.rowId): .included,
            .contact(recipientRowId: added.id): .included,
            .contact(recipientRowId: flipped.id): .excluded,
        ])
    }

    @Test
    func testUpdateMembershipsStoresAThreadInBothSetsAsExcluded() {
        let folder = insertFolder()
        let recipient = insertRecipient()
        let contactThread = insertContactThread(recipient.aci!)
        let groupId = Randomness.generateRandomBytes(32)
        let group = insertGroup(groupId: groupId, threadRowId: nil)
        let groupThread = TSGroupThread.forUnitTest(groupId: groupId)
        threadStore.insertThread(groupThread)
        let threadRowIds: Set = [contactThread.sqliteRowId!, groupThread.sqliteRowId!]

        inMemoryDB.write { tx in
            manager.updateMemberships(
                folderRowId: folder.id,
                includedThreadRowIds: threadRowIds,
                excludedThreadRowIds: threadRowIds,
                removedThreadRowIds: [],
                tx: tx,
            )
        }

        #expect(memberships(folder) == [
            .contact(recipientRowId: recipient.id): .excluded,
            .group(groupRowId: group.rowId): .excluded,
        ])
    }

    @Test
    func testUpdateMembershipsRemovesEachKindOfThread() {
        let folder = insertFolder()
        let recipient = insertRecipient()
        let contactThread = insertContactThread(recipient.aci!)
        let groupId = Randomness.generateRandomBytes(32)
        let group = insertGroup(groupId: groupId, threadRowId: nil)
        let groupThread = TSGroupThread.forUnitTest(groupId: groupId)
        threadStore.insertThread(groupThread)

        setMembership(.included, .contact(recipientRowId: recipient.id), in: folder)
        setMembership(.excluded, .group(groupRowId: group.rowId), in: folder)

        inMemoryDB.write { tx in
            manager.updateMemberships(
                folderRowId: folder.id,
                includedThreadRowIds: [],
                excludedThreadRowIds: [],
                removedThreadRowIds: [contactThread.sqliteRowId!, groupThread.sqliteRowId!],
                tx: tx,
            )
        }

        #expect(memberships(folder) == [:])
    }

    @Test
    func testRemovingAThreadDoesNotCreateARecipient() {
        let folder = insertFolder()
        let aci = Aci.randomForTesting()
        let contactThread = insertContactThread(aci)

        inMemoryDB.write { tx in
            manager.updateMemberships(
                folderRowId: folder.id,
                includedThreadRowIds: [],
                excludedThreadRowIds: [],
                removedThreadRowIds: [contactThread.sqliteRowId!],
                tx: tx,
            )
        }

        #expect(inMemoryDB.read { RecipientDatabaseTable().fetchRecipient(serviceId: aci, transaction: $0) } == nil)
    }

    // MARK: - All chats

    @Test
    func testLaunchCreatesExactlyOneAllChatsFolder() throws {
        #expect(inMemoryDB.read { store.fetchAllRecords(tx: $0) }.isEmpty)

        manager.createAllChatsFolderIfNeeded(db: inMemoryDB)
        manager.createAllChatsFolderIfNeeded(db: inMemoryDB)

        let records = inMemoryDB.read { store.fetchAllRecords(tx: $0) }
        #expect(records.count == 1)

        let allChats = try #require(records.first)
        #expect(allChats.folderType == .all)
        #expect(allChats.name == "")
        #expect(allChats.position == 0)
        #expect(allChats.includeAllIndividualChats)
        #expect(allChats.includeAllGroupChats)
        #expect(allChats.showMutedChats)
        #expect(!allChats.showOnlyUnread)
        #expect(!allChats.isDeleted)
    }

    @Test
    func testCreatingAllChatsUploadsIt() throws {
        manager.createAllChatsFolderIfNeeded(db: inMemoryDB)

        let allChats = try #require(inMemoryDB.read { store.fetchRecordForAllChatsFolder(tx: $0) })
        #expect(storageServiceManager.chatFolderIds == [allChats.chatFolderId])
    }

    @Test
    func testExistingAllChatsIsNotUploadedAgain() {
        inMemoryDB.write { tx in
            _ = store.fetchOrInsertAllChatsRecord(tx: tx)
        }

        manager.createAllChatsFolderIfNeeded(db: inMemoryDB)

        #expect(storageServiceManager.chatFolderIds.isEmpty)
    }
}

private class ChatFolderRecordingStorageServiceManager: FakeStorageServiceManager {
    var chatFolderIds = Set<UUID>()

    override func recordPendingUpdates(chatFolderIds: some Collection<UUID>) {
        self.chatFolderIds.formUnion(chatFolderIds)
    }
}
