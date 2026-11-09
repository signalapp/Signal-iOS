//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import Testing

@testable import SignalServiceKit

struct StorageServiceChatFolderRecordUpdaterTest {
    private let inMemoryDB = InMemoryDB()
    private let store = ChatFolderStore()
    private let recipientDatabaseTable = RecipientDatabaseTable()
    private let manager: ChatFolderManager
    private let updater: StorageServiceChatFolderRecordUpdater

    init() {
        let recipientFetcher = RecipientFetcher(
            recipientDatabaseTable: recipientDatabaseTable,
            searchableNameIndexer: MockSearchableNameIndexer(),
        )
        self.manager = ChatFolderManager(
            chatFolderStore: store,
            recipientDatabaseTable: recipientDatabaseTable,
            recipientFetcher: recipientFetcher,
            storageServiceManager: FakeStorageServiceManager(),
            threadStore: ThreadStoreImpl(),
        )
        self.updater = StorageServiceChatFolderRecordUpdater(
            chatFolderStore: store,
            recipientDatabaseTable: recipientDatabaseTable,
            recipientFetcher: recipientFetcher,
        )
        // The app creates this at launch.
        inMemoryDB.write { _ = store.fetchOrInsertAllChatsRecord(tx: $0) }
    }

    static func record(
        id: UUID = UUID(),
        folderType: StorageServiceProtoChatFolderRecordFolderType = .custom,
        name: String? = "Work",
        position: UInt32 = 1,
        showOnlyUnread: Bool = false,
        includedAcis: [Aci] = [],
        includedRecipients: [StorageServiceProtoRecipient] = [],
        includedGroupMasterKeys: [Data] = [],
        excludedGroupMasterKeys: [Data] = [],
        deletedAtTimestampMs: UInt64 = 0,
    ) -> StorageServiceProtoChatFolderRecord {
        var builder = StorageServiceProtoChatFolderRecord.builder()
        builder.setId(id.data)
        if let name {
            builder.setName(name)
        }
        builder.setPosition(position)
        builder.setShowOnlyUnread(showOnlyUnread)
        builder.setShowMutedChats(true)
        // All chats always includes everything.
        builder.setIncludeAllIndividualChats(folderType == .all)
        builder.setIncludeAllGroupChats(folderType == .all)
        builder.setFolderType(folderType)
        builder.setDeletedAtTimestampMs(deletedAtTimestampMs)
        builder.setIncludedRecipients(includedAcis.map { aci in
            var contactBuilder = StorageServiceProtoRecipientContact.builder()
            contactBuilder.setServiceIDBinary(aci.serviceIdBinary)
            var recipientBuilder = StorageServiceProtoRecipient.builder()
            recipientBuilder.setIdentifier(.contact(contactBuilder.buildInfallibly()))
            return recipientBuilder.buildInfallibly()
        } + includedRecipients + includedGroupMasterKeys.map { groupRecipient(masterKey: $0) })
        builder.setExcludedRecipients(excludedGroupMasterKeys.map { groupRecipient(masterKey: $0) })
        return builder.buildInfallibly()
    }

    private static func groupRecipient(masterKey: Data) -> StorageServiceProtoRecipient {
        var recipientBuilder = StorageServiceProtoRecipient.builder()
        recipientBuilder.setIdentifier(.groupMasterKey(masterKey))
        return recipientBuilder.buildInfallibly()
    }

    private func record(
        id: UUID = UUID(),
        folderType: StorageServiceProtoChatFolderRecordFolderType = .custom,
        name: String? = "Work",
        position: UInt32 = 1,
        showOnlyUnread: Bool = false,
        includedGroupMasterKeys: [Data] = [],
        excludedGroupMasterKeys: [Data] = [],
        deletedAtTimestampMs: UInt64 = 0,
    ) -> StorageServiceProtoChatFolderRecord {
        return Self.record(
            id: id,
            folderType: folderType,
            name: name,
            position: position,
            showOnlyUnread: showOnlyUnread,
            includedGroupMasterKeys: includedGroupMasterKeys,
            excludedGroupMasterKeys: excludedGroupMasterKeys,
            deletedAtTimestampMs: deletedAtTimestampMs,
        )
    }

    private func merge(_ record: StorageServiceProtoChatFolderRecord) -> StorageServiceMergeResult<UUID> {
        return inMemoryDB.write { updater.mergeRecord(record, transaction: $0) }
    }

    private func build(_ id: UUID) -> StorageServiceProtoChatFolderRecord? {
        return inMemoryDB.read { updater.buildRecord(for: id, unknownFields: nil, transaction: $0) }
    }

    private func fetch(_ id: UUID) -> ChatFolderRecord? {
        return inMemoryDB.read { store.fetchRecord(chatFolderId: id, tx: $0) }
    }

    private func fetchFolder(_ id: UUID) -> ChatFolder? {
        return inMemoryDB.read { manager.fetch(chatFolderId: id, tx: $0) }
    }

    private func memberships(_ id: UUID) -> [ChatFolderChatRecord.Chat: ChatFolder.MembershipType] {
        return inMemoryDB.read { tx in
            guard let folderRowId = store.fetchRecord(chatFolderId: id, tx: tx)?.id else {
                return [:]
            }
            var result = [ChatFolderChatRecord.Chat: ChatFolder.MembershipType]()
            for membership in store.fetchMemberships(folderRowId: folderRowId, tx: tx) {
                result[membership.chat] = membership.membershipType
            }
            return result
        }
    }

    private func insertCustomFolder(
        name: String = "Family",
        position: UInt32 = 2,
        showOnlyUnread: Bool = false,
        includeAllGroupChats: Bool = false,
    ) -> ChatFolderRecord {
        return inMemoryDB.write { tx in
            store.insertCustomFolderRecord(
                chatFolderId: UUID(),
                name: name,
                position: position,
                showOnlyUnread: showOnlyUnread,
                showMutedChats: true,
                includeAllIndividualChats: false,
                includeAllGroupChats: includeAllGroupChats,
                deletedAtTimestampMs: 0,
                tx: tx,
            )
        }
    }

    private func insertRecipient(aci: Aci? = nil, phoneNumber: String? = nil, pni: Pni? = nil) -> SignalRecipient {
        return inMemoryDB.write { tx in
            try! SignalRecipient.insertRecord(aci: aci, phoneNumber: phoneNumber.map { E164($0)! }, pni: pni, tx: tx)
        }
    }

    private func setMembership(_ chat: ChatFolderChatRecord.Chat, folder: ChatFolderRecord) {
        inMemoryDB.write { store.setMembership(.included, chat: chat, folderRowId: folder.id, tx: $0) }
    }

    private func includedContacts(_ built: StorageServiceProtoChatFolderRecord) -> [StorageServiceProtoRecipientContact] {
        return built.includedRecipients.compactMap { recipient in
            guard case .contact(let contact)? = recipient.identifier else {
                return nil
            }
            return contact
        }
    }

    private func groupMasterKeys(_ recipients: [StorageServiceProtoRecipient]) -> [Data] {
        return recipients.compactMap { recipient in
            guard case .groupMasterKey(let masterKey)? = recipient.identifier else {
                return nil
            }
            return masterKey
        }
    }

    // MARK: -

    @Test
    func testBuildRecordRoundTripsSettings() throws {
        let folder = insertCustomFolder(name: "Family", position: 2, showOnlyUnread: true, includeAllGroupChats: true)

        let id = folder.chatFolderId
        let built = try #require(build(id))
        #expect(built.id == id.data)
        #expect(built.name == "Family")
        #expect(built.position == 2)
        #expect(built.folderType == .custom)
        #expect(built.showOnlyUnread)
        #expect(built.showMutedChats)
        #expect(!built.includeAllIndividualChats)
        #expect(built.includeAllGroupChats)
        #expect(built.includedRecipients.isEmpty)
    }

    @Test
    func testUnrestoredGroupIsKeptUntilItsThreadExists() throws {
        let id = UUID()
        let masterKey = Randomness.generateRandomBytes(32)
        let groupId = try GroupV2ContextInfo.deriveFrom(masterKeyData: masterKey).groupId

        _ = merge(record(id: id, includedGroupMasterKeys: [masterKey]))
        #expect(fetchFolder(id)?.includedThreadRowIds == [])

        // The group goes back up with the folder even before it's restored.
        let built = try #require(build(id))
        guard case .groupMasterKey(let builtMasterKey)? = built.includedRecipients.first?.identifier else {
            Issue.record("Expected a group")
            return
        }
        #expect(builtMasterKey == masterKey)

        // Once the group's thread exists, it's in the folder.
        let threadRowId = try inMemoryDB.write { tx in
            let groupThread = TSGroupThread.forUnitTest(groupId: groupId.serialize())
            try groupThread.insert(tx.database)
            let threadRowId = try #require(groupThread.sqliteRowId)
            var groupRecord = try #require(GroupStore().fetchGroup(forGroupId: groupId, tx: tx))
            groupRecord.setThreadId(threadRowId, tx: tx)
            return threadRowId
        }
        #expect(fetchFolder(id)?.includedThreadRowIds == [threadRowId])
    }

    @Test
    func testUnrestoredExcludedGroupIsKept() throws {
        let id = UUID()
        let masterKey = Randomness.generateRandomBytes(32)

        _ = merge(record(id: id, excludedGroupMasterKeys: [masterKey]))

        let built = try #require(build(id))
        #expect(groupMasterKeys(built.includedRecipients) == [])
        #expect(groupMasterKeys(built.excludedRecipients) == [masterKey])
    }

    @Test
    func testGroupInBothListsIsExcluded() throws {
        let id = UUID()
        let masterKey = Randomness.generateRandomBytes(32)

        _ = merge(record(id: id, includedGroupMasterKeys: [masterKey], excludedGroupMasterKeys: [masterKey]))

        let built = try #require(build(id))
        #expect(groupMasterKeys(built.includedRecipients) == [])
        #expect(groupMasterKeys(built.excludedRecipients) == [masterKey])
    }

    @Test
    func testRemoteAllChatsFolderIdIsAdopted() throws {
        let localAllChats = try #require(inMemoryDB.read { store.fetchRecordForAllChatsFolder(tx: $0) })
        let remoteId = UUID()

        let result = merge(record(id: remoteId, folderType: .all, name: nil, position: 3))
        // The record stored under the old id gets deleted.
        guard case .merged(needsUpdate: false, remoteId, localAllChats.chatFolderId) = result else {
            Issue.record("Expected a merge")
            return
        }

        let allChats = try #require(inMemoryDB.read { store.fetchRecordForAllChatsFolder(tx: $0) })
        #expect(allChats.id == localAllChats.id)
        #expect(allChats.chatFolderId == remoteId)
        #expect(allChats.position == 3)
        #expect(fetch(localAllChats.chatFolderId) == nil)
    }

    @Test
    func testRemoteAllChatsSyncsAsIs() throws {
        let allChats = try #require(inMemoryDB.read { store.fetchRecordForAllChatsFolder(tx: $0) })
        let id = allChats.chatFolderId
        let masterKey = Randomness.generateRandomBytes(32)

        let result = merge(record(
            id: id,
            folderType: .all,
            name: nil,
            position: 3,
            showOnlyUnread: true,
            includedGroupMasterKeys: [masterKey],
        ))
        guard case .merged(needsUpdate: false, id, nil) = result else {
            Issue.record("Expected a merge")
            return
        }
        let merged = try #require(inMemoryDB.read { store.fetchRecordForAllChatsFolder(tx: $0) })
        #expect(merged.position == 3)
        #expect(merged.showOnlyUnread)
        let built = try #require(build(id))
        #expect(groupMasterKeys(built.includedRecipients) == [masterKey])
    }

    @Test
    func testRemoteAllChatsDeletionIsOverwritten() throws {
        let allChats = try #require(inMemoryDB.read { store.fetchRecordForAllChatsFolder(tx: $0) })
        let id = allChats.chatFolderId

        let result = merge(record(
            id: id,
            folderType: .all,
            name: nil,
            position: .max,
            showOnlyUnread: true,
            deletedAtTimestampMs: 100,
        ))
        // Our live All Chats is uploaded over the deleted one, and none of the
        // deleted record's fields are applied.
        guard case .merged(needsUpdate: true, id, nil) = result else {
            Issue.record("Expected a merge")
            return
        }
        let merged = try #require(inMemoryDB.read { store.fetchRecordForAllChatsFolder(tx: $0) })
        #expect(merged == allChats)
        let built = try #require(build(id))
        #expect(built.deletedAtTimestampMs == 0)
    }

    @Test
    func testRemoteAllChatsDeletionWithANewIdIsOverwritten() throws {
        let localAllChats = try #require(inMemoryDB.read { store.fetchRecordForAllChatsFolder(tx: $0) })
        let remoteId = UUID()

        let result = merge(record(id: remoteId, folderType: .all, name: nil, position: .max, deletedAtTimestampMs: 100))
        // The id is adopted, our live All Chats is uploaded under it, and the
        // record stored under the old id gets deleted.
        guard case .merged(needsUpdate: true, remoteId, localAllChats.chatFolderId) = result else {
            Issue.record("Expected a merge")
            return
        }
        let allChats = try #require(inMemoryDB.read { store.fetchRecordForAllChatsFolder(tx: $0) })
        #expect(allChats.chatFolderId == remoteId)
        #expect(allChats.position == localAllChats.position)
        #expect(!allChats.isDeleted)
        #expect(try #require(build(remoteId)).deletedAtTimestampMs == 0)
    }

    @Test
    func testRemoteAllChatsRecordDoesNotChangeACustomFolderType() throws {
        let folder = insertCustomFolder(name: "Work", position: 1)
        let id = folder.chatFolderId

        guard case .merged(needsUpdate: false, id, _) = merge(record(id: id, folderType: .all, name: nil, position: 3)) else {
            Issue.record("Expected a merge")
            return
        }
        let fetched = try #require(fetch(id))
        #expect(fetched.folderType == .custom)
        #expect(fetched.position == 3)
        let allChats = try #require(inMemoryDB.read { store.fetchRecordForAllChatsFolder(tx: $0) })
        #expect(allChats.chatFolderId != folder.chatFolderId)
    }

    @Test
    func testDeletionTakesPrecedence() {
        let id = UUID()
        _ = merge(record(id: id))

        // A remote deletion deletes the local folder.
        _ = merge(record(id: id, position: .max, deletedAtTimestampMs: 200))
        #expect(fetch(id)?.deletedAtTimestampMs == 200)

        // A live remote folder doesn't undo the local deletion, and our
        // deletion is uploaded over it.
        guard case .merged(needsUpdate: true, _, _) = merge(record(id: id)) else {
            Issue.record("Expected a merge")
            return
        }
        #expect(fetch(id)?.isDeleted == true)

        // A later remote deletion loses to ours, which is uploaded over it.
        guard case .merged(needsUpdate: true, _, _) = merge(record(id: id, position: .max, deletedAtTimestampMs: 300)) else {
            Issue.record("Expected a merge")
            return
        }
        #expect(fetch(id)?.deletedAtTimestampMs == 200)

        // The same deletion is already in sync.
        guard case .merged(needsUpdate: false, _, _) = merge(record(id: id, position: .max, deletedAtTimestampMs: 200)) else {
            Issue.record("Expected a merge")
            return
        }
        #expect(fetch(id)?.deletedAtTimestampMs == 200)

        // An earlier remote deletion wins.
        guard case .merged(needsUpdate: false, _, _) = merge(record(id: id, position: .max, deletedAtTimestampMs: 100)) else {
            Issue.record("Expected a merge")
            return
        }
        #expect(fetch(id)?.deletedAtTimestampMs == 100)
    }

    @Test
    func testRemoteDeletionKeepsLocalNameAndSettings() throws {
        let id = insertCustomFolder(name: "Family", position: 2, showOnlyUnread: true).chatFolderId

        _ = merge(record(id: id, name: nil, position: .max, deletedAtTimestampMs: 100))

        let deleted = try #require(fetch(id))
        #expect(deleted.deletedAtTimestampMs == 100)
        #expect(deleted.name == "Family")
        #expect(deleted.showOnlyUnread)
    }

    @Test
    func testRemoteDeletionOfUnknownFolderIsRemembered() {
        let id = UUID()
        _ = merge(record(id: id, position: .max, deletedAtTimestampMs: 100))
        #expect(fetch(id)?.deletedAtTimestampMs == 100)
    }

    @Test
    func testDeletionTimestampsRoundTripExactly() throws {
        for timestampMs: UInt64 in [1, 2, 999, 1_000, 2_188_924_454_535, 1 << 50] {
            let id = UUID()
            _ = merge(record(id: id, position: .max, deletedAtTimestampMs: timestampMs))
            #expect(try #require(build(id)).deletedAtTimestampMs == timestampMs)
        }
    }

    @Test
    func testHugeDeletionTimestampIsClamped() throws {
        let id = UUID()
        _ = merge(record(id: id, position: .max, deletedAtTimestampMs: .max))
        #expect(fetch(id)?.deletedAtTimestampMs == .max)
        #expect(fetch(id)?.isDeleted == true)
        #expect(try #require(build(id)).deletedAtTimestampMs == UInt64(Int64.max))
        // It isn't cleaned up early
        #expect(inMemoryDB.read { store.fetchRecords(deletedBefore: Date(), tx: $0) }.isEmpty)
    }

    @Test
    func testUnnamedFoldersAreKept() {
        let id = UUID()
        guard case .merged(needsUpdate: false, id, _) = merge(record(id: id, name: nil)) else {
            Issue.record("Expected a merge")
            return
        }
        #expect(fetch(id)?.name == "")

        let deletedId = UUID()
        _ = merge(record(id: deletedId, name: nil, position: .max, deletedAtTimestampMs: 100))
        #expect(fetch(deletedId)?.deletedAtTimestampMs == 100)
    }

    @Test
    func testInvalidRecords() {
        func isInvalid(_ result: StorageServiceMergeResult<UUID>) -> Bool {
            if case .invalid = result { true } else { false }
        }

        var missingId = StorageServiceProtoChatFolderRecord.builder()
        missingId.setName("Work")
        missingId.setFolderType(.custom)
        #expect(isInvalid(merge(missingId.buildInfallibly())))

        for idLength: UInt in [15, 17] {
            var badId = StorageServiceProtoChatFolderRecord.builder()
            badId.setId(Randomness.generateRandomBytes(idLength))
            badId.setName("Work")
            badId.setFolderType(.custom)
            #expect(isInvalid(merge(badId.buildInfallibly())))
        }

        #expect(isInvalid(merge(record(folderType: .unknown))))
    }

    // MARK: - Contact members

    @Test
    func testMergeInsertsFolderWithMembers() throws {
        let id = UUID()
        let aci = Aci.randomForTesting()

        guard case .merged(needsUpdate: false, id, _) = merge(Self.record(id: id, includedAcis: [aci])) else {
            Issue.record("Expected a merge")
            return
        }

        let recipient = try #require(inMemoryDB.read { recipientDatabaseTable.fetchRecipient(serviceId: aci, transaction: $0) })
        #expect(memberships(id) == [.contact(recipientRowId: recipient.id): .included])
    }

    @Test
    func testBuildRecordEncodesContactMembers() throws {
        let aci = Aci.randomForTesting()
        let folder = insertCustomFolder()
        setMembership(.contact(recipientRowId: insertRecipient(aci: aci).id), folder: folder)

        let id = folder.chatFolderId
        let built = try #require(build(id))
        let contact = try #require(includedContacts(built).first)
        #expect(contact.serviceIDBinary == aci.serviceIdBinary)
        #expect(!contact.hasE164)
    }

    @Test
    func testMergedPniMemberSurvivesBuildingTheFolderAgain() throws {
        let id = UUID()
        let pni = Pni.randomForTesting()
        var contactBuilder = StorageServiceProtoRecipientContact.builder()
        contactBuilder.setServiceIDBinary(pni.serviceIdBinary)
        contactBuilder.setE164("+16505550100")
        var recipientBuilder = StorageServiceProtoRecipient.builder()
        recipientBuilder.setIdentifier(.contact(contactBuilder.buildInfallibly()))

        // Nothing on this device knows the contact yet.
        guard case .merged = merge(Self.record(id: id, includedRecipients: [recipientBuilder.buildInfallibly()])) else {
            Issue.record("Expected a merge")
            return
        }

        let built = try #require(build(id))
        let contact = try #require(includedContacts(built).first)
        #expect(contact.serviceIDBinary == pni.serviceIdBinary)
    }

    @Test
    func testBuildRecordEncodesServiceIdWithPhoneNumberAndLeavesOutPhoneOnlyContacts() throws {
        let pni = Pni.randomForTesting()
        let phoneNumber = "+16505550100"
        let folder = insertCustomFolder()
        setMembership(.contact(recipientRowId: insertRecipient(phoneNumber: phoneNumber, pni: pni).id), folder: folder)
        setMembership(.contact(recipientRowId: insertRecipient(phoneNumber: "+16505550101").id), folder: folder)

        let id = folder.chatFolderId
        let built = try #require(build(id))
        #expect(built.includedRecipients.count == 1)
        let contact = try #require(includedContacts(built).first)
        #expect(contact.serviceIDBinary == pni.serviceIdBinary)
        #expect(contact.e164 == phoneNumber)
    }
}
