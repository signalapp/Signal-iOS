//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
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
            isArchivedObsolete: false,
            isMarkedUnreadObsolete: false,
            lastDraftInteractionRowId: lastDraftInteractionRowId,
            lastDraftUpdateTimestamp: lastDraftUpdateTimestamp,
            lastInteractionRowId: lastInteractionRowID,
            lastSentStoryTimestamp: nil,
            mentionNotificationMode: .default,
            messageDraft: draft,
            messageDraftBodyRanges: nil,
            mutedUntilTimestampObsolete: 0,
            shouldThreadBeVisible: true,
            storyViewMode: .default,
            contactUUID: nil,
            contactPhoneNumber: nil,
        )
    }

    func buildThreadAssociatedData(
        uniqueID: String,
        isMarkedUnread: Bool,
        isArchived: Bool,
    ) -> ThreadAssociatedData {
        return ThreadAssociatedData(
            threadUniqueId: uniqueID,
            isArchived: isArchived,
            isMarkedUnread: isMarkedUnread,
            mutedUntilTimestamp: 0,
            audioPlaybackRate: 1,
        )
    }

    func newDraftGoesToTop(chatListType: ChatListType) throws {
        try db.write { transaction in
            let database = transaction.database

            // New draft.
            try buildThreadRecord(
                uniqueID: "UUID1",
                draft: "test draft",
                lastInteractionRowID: 0,
                lastDraftInteractionRowId: 1,
                lastDraftUpdateTimestamp: 1,
            ).insert(database)

            try buildThreadAssociatedData(
                uniqueID: "UUID1",
                isMarkedUnread: chatListType == .unread,
                isArchived: chatListType == .archive,
            ).insert(database)

            // Non-draft that has more recent lastInteractionRowID.
            try buildThreadRecord(
                uniqueID: "UUID2",
                draft: nil,
                lastInteractionRowID: 1,
                lastDraftInteractionRowId: 0,
                lastDraftUpdateTimestamp: 0,
            ).insert(database)

            try buildThreadAssociatedData(
                uniqueID: "UUID2",
                isMarkedUnread: chatListType == .unread,
                isArchived: chatListType == .archive,
            ).insert(database)
        }

        switch chatListType {
        case .inbox, .unread:
            try db.read { transaction in
                let messages = try threadFinder.visibleInboxThreadIds(transaction: transaction)
                XCTAssertEqual(messages.count, 2)
                XCTAssertTrue(messages.first == "UUID1", "First message should be the draft")
            }
        case .archive:
            try db.read { transaction in
                let messages = try threadFinder.visibleArchivedThreadIds(transaction: transaction)
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
                draft: "test draft",
                lastInteractionRowID: 3,
                lastDraftInteractionRowId: 1,
                lastDraftUpdateTimestamp: 1,
            ).insert(database)

            try buildThreadAssociatedData(
                uniqueID: "UUID1",
                isMarkedUnread: chatListType == .unread,
                isArchived: chatListType == .archive,
            ).insert(database)

            // Non-draft that has less recent lastInteractionRowID.
            try buildThreadRecord(
                uniqueID: "UUID2",
                draft: nil,
                lastInteractionRowID: 2,
                lastDraftInteractionRowId: 0,
                lastDraftUpdateTimestamp: 0,
            ).insert(database)

            try buildThreadAssociatedData(
                uniqueID: "UUID2",
                isMarkedUnread: chatListType == .unread,
                isArchived: chatListType == .archive,
            ).insert(database)
        }

        switch chatListType {
        case .inbox, .unread:
            try db.read { transaction in
                let threads = try threadFinder.visibleInboxThreadIds(transaction: transaction)
                XCTAssertEqual(threads.count, 2)
                XCTAssertTrue(threads.first == "UUID1", "First thread should be the draft thread, even though the draft is not the most recent activity")
            }
        case .archive:
            try db.read { transaction in
                let threads = try threadFinder.visibleArchivedThreadIds(transaction: transaction)
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
                draft: "test draft",
                lastInteractionRowID: 2,
                lastDraftInteractionRowId: 2,
                lastDraftUpdateTimestamp: 1,
            ).insert(database)

            try buildThreadAssociatedData(
                uniqueID: "UUID1",
                isMarkedUnread: chatListType == .unread,
                isArchived: chatListType == .archive,
            ).insert(database)

            // Thread 2, has a more recent draft based on timestamp.
            try buildThreadRecord(
                uniqueID: "UUID2",
                draft: "test draft",
                lastInteractionRowID: 1,
                lastDraftInteractionRowId: 2,
                lastDraftUpdateTimestamp: 2,
            ).insert(database)

            try buildThreadAssociatedData(
                uniqueID: "UUID2",
                isMarkedUnread: chatListType == .unread,
                isArchived: chatListType == .archive,
            ).insert(database)
        }

        switch chatListType {
        case .inbox, .unread:
            try db.read { transaction in
                let threads = try threadFinder.visibleInboxThreadIds(transaction: transaction)
                XCTAssertEqual(threads.count, 2)
                XCTAssertTrue(threads.first == "UUID2", "First thread should be the one with latest timestamp")
            }
        case .archive:
            try db.read { transaction in
                let threads = try threadFinder.visibleArchivedThreadIds(transaction: transaction)
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
                draft: "test draft",
                lastInteractionRowID: 1,
                lastDraftInteractionRowId: 2,
                lastDraftUpdateTimestamp: 100,
            ).insert(database)

            try buildThreadAssociatedData(
                uniqueID: "UUID1",
                isMarkedUnread: chatListType == .unread,
                isArchived: chatListType == .archive,
            ).insert(database)

            // Non-draft that has less recent lastInteractionRowID.
            try buildThreadRecord(
                uniqueID: "UUID2",
                draft: nil,
                lastInteractionRowID: 3,
                lastDraftInteractionRowId: 0,
                lastDraftUpdateTimestamp: 0,
            ).insert(database)

            try buildThreadAssociatedData(
                uniqueID: "UUID2",
                isMarkedUnread: chatListType == .unread,
                isArchived: chatListType == .archive,
            ).insert(database)
        }

        switch chatListType {
        case .inbox, .unread:
            try db.read { transaction in
                let threads = try threadFinder.visibleInboxThreadIds(transaction: transaction)
                XCTAssertEqual(threads.count, 2)
                XCTAssertTrue(threads.first == "UUID2", "First thread should be most recent thread, the non-draft")
            }
        case .archive:
            try db.read { transaction in
                let threads = try threadFinder.visibleArchivedThreadIds(transaction: transaction)
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
