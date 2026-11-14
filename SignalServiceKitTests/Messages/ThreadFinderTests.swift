//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import LibSignalClient
import Testing
import XCTest

@testable import SignalServiceKit

class ThreadFinderTests: XCTestCase {
    private var db = InMemoryDB()
    private let threadFinder = ThreadFinder()

    enum ChatListType: CaseIterable {
        case inbox
        case unread
        case archive
    }

    func buildThreadRecord(
        uniqueID: String,
        isArchived: Bool,
        isMarkedUnread: Bool,
        draft: String?,
        lastInteractionRowID: UInt64,
        lastDraftInteractionRowId: UInt64,
        lastDraftUpdateTimestamp: UInt64,
    ) -> TSContactThread {
        return TSContactThread(
            id: nil,
            uniqueId: uniqueID,
            creationDate: Date.now,
            editTargetTimestamp: nil,
            isArchived: isArchived,
            isMarkedUnread: isMarkedUnread,
            lastDraftInteractionRowId: lastDraftInteractionRowId,
            lastDraftUpdateTimestamp: lastDraftUpdateTimestamp,
            lastInteractionRowId: lastInteractionRowID,
            lastSentStoryTimestamp: nil,
            shouldNotifyForMentionsWhenMutedLegacy: true,
            shouldNotifyForMentionsWhenMuted: nil,
            shouldNotifyForRepliesWhenMuted: nil,
            shouldNotifyForCallsWhenMuted: nil,
            shouldNotifyForUnreadRemindersWhenMuted: nil,
            messageDraft: draft,
            messageDraftBodyRanges: nil,
            mutedUntilTimestamp: 0,
            shouldThreadBeVisible: true,
            storyViewMode: .default,
            audioPlaybackRate: 1,
            contactUUID: nil,
            contactPhoneNumber: nil,
        )
    }

    func testUnreadFilter() throws {
        let authorAci = Aci.randomForTesting()

        try db.write { transaction in
            let fixtures: [(
                uniqueId: String,
                lastInteractionRowId: UInt64,
                isMarkedUnread: Bool,
                isArchived: Bool,
                interactionIsRead: Bool?,
            )] = [
                ("marked-unread", 5, true, false, true),
                ("unread-interaction", 4, false, false, false),
                ("read", 3, false, false, true),
                ("required-visible", 2, false, false, true),
                ("archived-unread", 1, true, true, false),
            ]

            for fixture in fixtures {
                let thread = buildThreadRecord(
                    uniqueID: fixture.uniqueId,
                    isArchived: fixture.isArchived,
                    isMarkedUnread: fixture.isMarkedUnread,
                    draft: nil,
                    lastInteractionRowID: fixture.lastInteractionRowId,
                    lastDraftInteractionRowId: 0,
                    lastDraftUpdateTimestamp: 0,
                )
                try thread.insert(transaction.database)

                if let interactionIsRead = fixture.interactionIsRead {
                    let message = TSIncomingMessageBuilder.withDefaultValues(
                        thread: thread,
                        timestamp: fixture.lastInteractionRowId,
                        receivedAtTimestamp: fixture.lastInteractionRowId,
                        authorAci: authorAci,
                        read: interactionIsRead,
                    ).build()
                    try message.asRecord().insert(transaction.database)
                }
            }
        }

        db.read { transaction in
            let threadUniqueIds = threadFinder.visibleInboxThreadUniqueIds(
                filteredBy: .unread,
                requiredVisibleThreadIds: ["required-visible"],
                transaction: transaction,
            )
            XCTAssertEqual(threadUniqueIds, ["marked-unread", "unread-interaction", "required-visible"])
        }
    }

    func newDraftGoesToTop(chatListType: ChatListType) throws {
        try db.write { transaction in
            let database = transaction.database

            // New draft.
            try buildThreadRecord(
                uniqueID: "UUID1",
                isArchived: chatListType == .archive,
                isMarkedUnread: chatListType == .unread,
                draft: "test draft",
                lastInteractionRowID: 0,
                lastDraftInteractionRowId: 1,
                lastDraftUpdateTimestamp: 1,
            ).insert(database)

            // Non-draft that has more recent lastInteractionRowID.
            try buildThreadRecord(
                uniqueID: "UUID2",
                isArchived: chatListType == .archive,
                isMarkedUnread: chatListType == .unread,
                draft: nil,
                lastInteractionRowID: 1,
                lastDraftInteractionRowId: 0,
                lastDraftUpdateTimestamp: 0,
            ).insert(database)
        }

        switch chatListType {
        case .inbox, .unread:
            db.read { transaction in
                let messages = threadFinder.visibleInboxThreadUniqueIds(transaction: transaction)
                XCTAssertEqual(messages.count, 2)
                XCTAssertTrue(messages.first == "UUID1", "First message should be the draft")
            }
        case .archive:
            db.read { transaction in
                let messages = threadFinder.visibleArchivedThreadUniqueIds(transaction: transaction)
                XCTAssertEqual(messages.count, 2)
                XCTAssertTrue(messages.first == "UUID1", "First message should be the draft")
            }
        }
    }

    func testNewDraftGoesToTop_inbox() throws {
        try newDraftGoesToTop(chatListType: .inbox)
    }

    func testNewDraftGoesToTop_unread() throws {
        try newDraftGoesToTop(chatListType: .unread)
    }

    func testNewDraftGoesToTop_archive() throws {
        try newDraftGoesToTop(chatListType: .archive)
    }

    func ignoreDraftRowIdThatIsNotMostRecent(chatListType: ChatListType) throws {
        try db.write { transaction in
            let database = transaction.database

            // New draft that is not the latest activity on the thread.
            try buildThreadRecord(
                uniqueID: "UUID1",
                isArchived: chatListType == .archive,
                isMarkedUnread: chatListType == .unread,
                draft: "test draft",
                lastInteractionRowID: 3,
                lastDraftInteractionRowId: 1,
                lastDraftUpdateTimestamp: 1,
            ).insert(database)

            // Non-draft that has less recent lastInteractionRowID.
            try buildThreadRecord(
                uniqueID: "UUID2",
                isArchived: chatListType == .archive,
                isMarkedUnread: chatListType == .unread,
                draft: nil,
                lastInteractionRowID: 2,
                lastDraftInteractionRowId: 0,
                lastDraftUpdateTimestamp: 0,
            ).insert(database)
        }

        switch chatListType {
        case .inbox, .unread:
            db.read { transaction in
                let threads = threadFinder.visibleInboxThreadUniqueIds(transaction: transaction)
                XCTAssertEqual(threads.count, 2)
                XCTAssertTrue(threads.first == "UUID1", "First thread should be the draft thread, even though the draft is not the most recent activity")
            }
        case .archive:
            db.read { transaction in
                let threads = threadFinder.visibleArchivedThreadUniqueIds(transaction: transaction)
                XCTAssertEqual(threads.count, 2)
                XCTAssertTrue(threads.first == "UUID1", "First thread should be the draft thread, even though the draft is not the most recent activity")
            }
        }
    }

    func testIgnoreDraftRowIdThatIsNotMostRecent_inbox() throws {
        try ignoreDraftRowIdThatIsNotMostRecent(chatListType: .inbox)
    }

    func testIgnoreDraftRowIdThatIsNotMostRecent_unread() throws {
        try ignoreDraftRowIdThatIsNotMostRecent(chatListType: .unread)
    }

    func testIgnoreDraftRowIdThatIsNotMostRecent_archive() throws {
        try ignoreDraftRowIdThatIsNotMostRecent(chatListType: .archive)
    }

    func sameDraftRowIdFallsBackToTimestamp(chatListType: ChatListType) throws {
        try db.write { transaction in
            let database = transaction.database

            // Thread 1, has a draft after latest TSInteraction, but less recent than UUID2.
            try buildThreadRecord(
                uniqueID: "UUID1",
                isArchived: chatListType == .archive,
                isMarkedUnread: chatListType == .unread,
                draft: "test draft",
                lastInteractionRowID: 2,
                lastDraftInteractionRowId: 2,
                lastDraftUpdateTimestamp: 1,
            ).insert(database)

            // Thread 2, has a more recent draft based on timestamp.
            try buildThreadRecord(
                uniqueID: "UUID2",
                isArchived: chatListType == .archive,
                isMarkedUnread: chatListType == .unread,
                draft: "test draft",
                lastInteractionRowID: 1,
                lastDraftInteractionRowId: 2,
                lastDraftUpdateTimestamp: 2,
            ).insert(database)
        }

        switch chatListType {
        case .inbox, .unread:
            db.read { transaction in
                let threads = threadFinder.visibleInboxThreadUniqueIds(transaction: transaction)
                XCTAssertEqual(threads.count, 2)
                XCTAssertTrue(threads.first == "UUID2", "First thread should be the one with latest timestamp")
            }
        case .archive:
            db.read { transaction in
                let threads = threadFinder.visibleArchivedThreadUniqueIds(transaction: transaction)
                XCTAssertEqual(threads.count, 2)
                XCTAssertTrue(threads.first == "UUID2", "First thread should be the one with latest timestamp")
            }
        }
    }

    func testSameDraftRowIdFallsBackToTimestamp_inbox() throws {
        try sameDraftRowIdFallsBackToTimestamp(chatListType: .inbox)
    }

    func testSameDraftRowIdFallsBackToTimestamp_unread() throws {
        try sameDraftRowIdFallsBackToTimestamp(chatListType: .unread)
    }

    func testSameDraftRowIdFallsBackToTimestamp_archive() throws {
        try sameDraftRowIdFallsBackToTimestamp(chatListType: .archive)
    }

    func draftNotMostRecent(chatListType: ChatListType) throws {
        try db.write { transaction in
            let database = transaction.database

            // New draft that is not the latest activity on the thread.
            try buildThreadRecord(
                uniqueID: "UUID1",
                isArchived: chatListType == .archive,
                isMarkedUnread: chatListType == .unread,
                draft: "test draft",
                lastInteractionRowID: 1,
                lastDraftInteractionRowId: 2,
                lastDraftUpdateTimestamp: 100,
            ).insert(database)

            // Non-draft that has less recent lastInteractionRowID.
            try buildThreadRecord(
                uniqueID: "UUID2",
                isArchived: chatListType == .archive,
                isMarkedUnread: chatListType == .unread,
                draft: nil,
                lastInteractionRowID: 3,
                lastDraftInteractionRowId: 0,
                lastDraftUpdateTimestamp: 0,
            ).insert(database)
        }

        switch chatListType {
        case .inbox, .unread:
            db.read { transaction in
                let threads = threadFinder.visibleInboxThreadUniqueIds(transaction: transaction)
                XCTAssertEqual(threads.count, 2)
                XCTAssertTrue(threads.first == "UUID2", "First thread should be most recent thread, the non-draft")
            }
        case .archive:
            db.read { transaction in
                let threads = threadFinder.visibleArchivedThreadUniqueIds(transaction: transaction)
                XCTAssertEqual(threads.count, 2)
                XCTAssertTrue(threads.first == "UUID2", "First thread should be most recent thread, the non-draft")
            }
        }
    }

    func testDraftNotMostRecent_inbox() throws {
        try draftNotMostRecent(chatListType: .inbox)
    }

    func testDraftNotMostRecent_unread() throws {
        try draftNotMostRecent(chatListType: .unread)
    }

    func testDraftNotMostRecent_archive() throws {
        try draftNotMostRecent(chatListType: .archive)
    }
}

// MARK: - Chat folders

struct ThreadFinderChatFolderTests {
    private let db = InMemoryDB()
    private let threadFinder = ThreadFinder()

    private func contactThread() -> TSThread {
        return TSContactThread(contactAddress: .isolatedRandomForTesting())
    }

    /// Inserts a visible group thread.
    @discardableResult
    private func insertGroupThread(
        lastInteractionRowId: UInt64,
        mutedUntilTimestamp: UInt64 = 0,
    ) throws -> TSThread {
        return try insert(
            TSGroupThread.forUnitTest(groupId: Randomness.generateRandomBytes(kGroupIdLengthV2)),
            lastInteractionRowId: lastInteractionRowId,
            mutedUntilTimestamp: mutedUntilTimestamp,
        )
    }

    private func releaseNotesThread() -> TSThread {
        return TSReleaseNotesThread(uniqueId: UUID().uuidString)
    }

    /// Inserts a visible thread. Chat list order is by `lastInteractionRowId`,
    /// highest first.
    @discardableResult
    private func insert(
        _ thread: TSThread,
        lastInteractionRowId: UInt64,
        isArchived: Bool = false,
        isMarkedUnread: Bool = false,
        mutedUntilTimestamp: UInt64 = 0,
    ) throws -> TSThread {
        thread.id = nil
        thread.shouldThreadBeVisible = true
        thread.lastInteractionRowId = lastInteractionRowId
        thread.isArchived = isArchived
        thread.isMarkedUnread = isMarkedUnread
        thread.mutedUntilTimestamp = mutedUntilTimestamp
        try db.write { tx in
            try thread.insert(tx.database)
        }
        return thread
    }

    private func insertIncomingMessage(in thread: TSThread, read: Bool) throws {
        try db.write { tx in
            let message = TSIncomingMessageBuilder.withDefaultValues(
                thread: thread,
                timestamp: thread.lastInteractionRowId,
                receivedAtTimestamp: thread.lastInteractionRowId,
                authorAci: Aci.randomForTesting(),
                read: read,
            ).build()
            try message.asRecord().insert(tx.database)
        }
    }

    private func chatFolder(
        folderType: ChatFolderRecord.FolderType = .custom,
        showOnlyUnread: Bool = false,
        showMutedChats: Bool = true,
        includeAllIndividualChats: Bool = false,
        includeAllGroupChats: Bool = false,
        included: [TSThread] = [],
        excluded: [TSThread] = [],
    ) -> ChatFolder {
        let chatFolderStore = ChatFolderStore()
        let record = db.write { tx in
            switch folderType {
            case .all:
                // Override the real All Chats record in memory without saving, so tests can pass contradictory
                // settings to the query and verify that All Chats ignores them.
                var record = chatFolderStore.fetchOrInsertAllChatsRecord(tx: tx)
                record.showOnlyUnread = showOnlyUnread
                record.showMutedChats = showMutedChats
                record.includeAllIndividualChats = includeAllIndividualChats
                record.includeAllGroupChats = includeAllGroupChats
                return record
            case .custom:
                return chatFolderStore.insertCustomFolderRecord(
                    chatFolderId: UUID(),
                    name: "Folder",
                    position: 1,
                    showOnlyUnread: showOnlyUnread,
                    showMutedChats: showMutedChats,
                    includeAllIndividualChats: includeAllIndividualChats,
                    includeAllGroupChats: includeAllGroupChats,
                    deletedAtTimestampMs: 0,
                    tx: tx,
                )
            }
        }
        return ChatFolder(
            record: record,
            includedThreadRowIds: Set(included.map { $0.sqliteRowId! }),
            excludedThreadRowIds: Set(excluded.map { $0.sqliteRowId! }),
        )
    }

    private func visibleInboxThreadUniqueIds(
        filteredBy inboxFilter: InboxFilter = .unfiltered,
        chatFolder: ChatFolder?,
        requiredVisibleThreadIds: Set<String> = [],
    ) -> [String] {
        return db.read { tx in
            threadFinder.visibleInboxThreadUniqueIds(
                filteredBy: inboxFilter,
                chatFolder: chatFolder,
                requiredVisibleThreadIds: requiredVisibleThreadIds,
                transaction: tx,
            )
        }
    }

    @Test
    func testChatFolderExplicitMembership() throws {
        let first = try insert(contactThread(), lastInteractionRowId: 4)
        let second = try insertGroupThread(lastInteractionRowId: 3)
        let notIncluded = try insert(contactThread(), lastInteractionRowId: 2)
        let archived = try insert(contactThread(), lastInteractionRowId: 1, isArchived: true)

        #expect(
            visibleInboxThreadUniqueIds(chatFolder: nil)
                == [first, second, notIncluded].map(\.uniqueId),
        )

        let folder = chatFolder(included: [first, second, archived])
        #expect(
            visibleInboxThreadUniqueIds(chatFolder: folder)
                == [first, second].map(\.uniqueId),
        )
    }

    @Test
    func testChatFolderIncludeAllIndividualChats() throws {
        let contact = try insert(contactThread(), lastInteractionRowId: 5)
        let includedGroup = try insertGroupThread(lastInteractionRowId: 4)
        try insertGroupThread(lastInteractionRowId: 3)
        let releaseNotes = try insert(releaseNotesThread(), lastInteractionRowId: 2)
        let excludedContact = try insert(contactThread(), lastInteractionRowId: 1)

        let folder = chatFolder(
            includeAllIndividualChats: true,
            included: [includedGroup],
            excluded: [excludedContact],
        )
        #expect(
            visibleInboxThreadUniqueIds(chatFolder: folder)
                == [contact, includedGroup, releaseNotes].map(\.uniqueId),
        )
    }

    @Test
    func testChatFolderIncludeAllGroupChats() throws {
        let includedContact = try insert(contactThread(), lastInteractionRowId: 5)
        let group = try insertGroupThread(lastInteractionRowId: 4)
        try insert(contactThread(), lastInteractionRowId: 3)
        try insert(releaseNotesThread(), lastInteractionRowId: 2)
        let excludedGroup = try insertGroupThread(lastInteractionRowId: 1)

        let folder = chatFolder(
            includeAllGroupChats: true,
            included: [includedContact],
            excluded: [excludedGroup],
        )
        #expect(
            visibleInboxThreadUniqueIds(chatFolder: folder)
                == [includedContact, group].map(\.uniqueId),
        )
    }

    @Test
    func testChatFolderHidesMutedChats() throws {
        let mutedForever = try insert(contactThread(), lastInteractionRowId: 4, mutedUntilTimestamp: TSThread.alwaysMutedTimestamp)
        let mutedUntilLater = try insertGroupThread(lastInteractionRowId: 3, mutedUntilTimestamp: Date.ows_millisecondTimestamp() + UInt64.hourInMs)
        let muteExpired = try insert(contactThread(), lastInteractionRowId: 2, mutedUntilTimestamp: 1)
        let notMuted = try insertGroupThread(lastInteractionRowId: 1)

        let allThreads = [mutedForever, mutedUntilLater, muteExpired, notMuted]

        let showingMuted = chatFolder(showMutedChats: true, included: allThreads)
        #expect(
            visibleInboxThreadUniqueIds(chatFolder: showingMuted)
                == allThreads.map(\.uniqueId),
        )

        let hidingMuted = chatFolder(showMutedChats: false, included: allThreads)
        #expect(
            visibleInboxThreadUniqueIds(chatFolder: hidingMuted)
                == [muteExpired, notMuted].map(\.uniqueId),
        )
    }

    @Test
    func testChatFolderShowOnlyUnread() throws {
        let markedUnread = try insert(contactThread(), lastInteractionRowId: 5, isMarkedUnread: true)
        let unreadMessage = try insertGroupThread(lastInteractionRowId: 4)
        try insertIncomingMessage(in: unreadMessage, read: false)
        let readMessage = try insert(contactThread(), lastInteractionRowId: 3)
        try insertIncomingMessage(in: readMessage, read: true)
        let requiredVisible = try insert(contactThread(), lastInteractionRowId: 2)
        let unreadOutsideFolder = try insert(contactThread(), lastInteractionRowId: 1, isMarkedUnread: true)

        let folder = chatFolder(
            showOnlyUnread: true,
            included: [markedUnread, unreadMessage, readMessage, requiredVisible],
        )
        #expect(
            visibleInboxThreadUniqueIds(chatFolder: folder, requiredVisibleThreadIds: [requiredVisible.uniqueId])
                == [markedUnread, unreadMessage, requiredVisible].map(\.uniqueId),
        )

        // The inbox unread filter narrows a folder the same way.
        let allChatsInFolder = chatFolder(included: [markedUnread, unreadMessage, readMessage])
        #expect(
            visibleInboxThreadUniqueIds(filteredBy: .unread, chatFolder: allChatsInFolder)
                == [markedUnread, unreadMessage].map(\.uniqueId),
        )

        #expect(
            visibleInboxThreadUniqueIds(filteredBy: .unread, chatFolder: nil)
                == [markedUnread, unreadMessage, unreadOutsideFolder].map(\.uniqueId),
        )
    }

    @Test
    func testAllChatsFolderIgnoresFolderSettings() throws {
        let contact = try insert(contactThread(), lastInteractionRowId: 4)
        try insertIncomingMessage(in: contact, read: true)
        let mutedGroup = try insertGroupThread(lastInteractionRowId: 3, mutedUntilTimestamp: TSThread.alwaysMutedTimestamp)
        let releaseNotes = try insert(releaseNotesThread(), lastInteractionRowId: 2)
        let excluded = try insert(contactThread(), lastInteractionRowId: 1)

        let allChats = chatFolder(
            folderType: .all,
            showOnlyUnread: true,
            showMutedChats: false,
            includeAllIndividualChats: false,
            includeAllGroupChats: false,
            excluded: [excluded],
        )
        #expect(
            visibleInboxThreadUniqueIds(chatFolder: allChats)
                == [contact, mutedGroup, releaseNotes, excluded].map(\.uniqueId),
        )
        #expect(
            visibleInboxThreadUniqueIds(chatFolder: allChats)
                == visibleInboxThreadUniqueIds(chatFolder: nil),
        )
    }

    // MARK: - Query plans

    /// Returns the query plan of each statement the inbox fetch executes.
    private func inboxQueryPlans(
        filteredBy inboxFilter: InboxFilter,
        chatFolder: ChatFolder?,
    ) throws -> [[String]] {
        return try db.read { tx in
            var statements = [String]()
            tx.database.trace(options: .statement) { event in
                if case .statement(let statement) = event {
                    statements.append(statement.sql)
                }
            }
            _ = threadFinder.visibleInboxThreadUniqueIds(
                filteredBy: inboxFilter,
                chatFolder: chatFolder,
                requiredVisibleThreadIds: ["required-visible"],
                transaction: tx,
            )
            tx.database.trace(options: [])

            return try statements.map { sql in
                try Row.fetchAll(tx.database, sql: "EXPLAIN QUERY PLAN \(sql)").map { row -> String in row["detail"] }
            }
        }
    }

    enum InboxQuery: CaseIterable {
        case inbox
        case unread
        case allChatsFolder
        case customFolder
        case unreadCustomFolder
    }

    @Test(arguments: InboxQuery.allCases)
    func testInboxQueryUsesIndexes(_ query: InboxQuery) throws {
        let threadSearch = "SEARCH model_TSThread USING INDEX index_thread_on_shouldThreadBeVisible (shouldThreadBeVisible=?)"
        let unreadSearch = "SEARCH model_TSInteraction USING INDEX index_model_TSInteraction_UnreadMessages (read=? AND uniqueThreadId=?)"

        let (inboxFilter, folder, expectedSearches): (InboxFilter, ChatFolder?, [String]) = switch query {
        case .inbox:
            (.unfiltered, nil, [threadSearch])
        case .unread:
            (.unread, nil, [threadSearch, unreadSearch])
        case .allChatsFolder:
            (.unfiltered, chatFolder(folderType: .all), [threadSearch])
        case .customFolder:
            (.unfiltered, chatFolder(), [threadSearch])
        case .unreadCustomFolder:
            (.unfiltered, chatFolder(showOnlyUnread: true), [threadSearch, unreadSearch])
        }

        let plans = try inboxQueryPlans(filteredBy: inboxFilter, chatFolder: folder)
        #expect(plans.count == 1)

        for plan in plans {
            #expect(plan.filter { $0.hasPrefix("SCAN") } == [], "\(plan)")
            for search in expectedSearches {
                #expect(plan.contains(search), "Missing \(search): \(plan)")
            }
        }
    }
}
