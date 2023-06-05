//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import Signal
@testable import SignalServiceKit

class MessageLoaderTest: XCTestCase {
    private var batchFetcher: MockBatchFetcher!
    private var interactionFetcher: MockInteractionFetcher!
    private var messageLoader: MessageLoader!
    private var mockDB: MockDB!

    private class MockBatchFetcher: MessageLoaderBatchFetcher {
        var interactions = [TSInteraction]()
        func fetchUniqueIds(filter: RowIdFilter, excludingPlaceholders excludePlaceholders: Bool, limit: Int, tx: DBReadTransaction) throws -> [String] {
            switch filter {
            case .newest:
                return Array(interactions.lazy.suffix(limit).map { $0.uniqueId })
            case .after(let rowId):
                return Array(interactions.lazy.filter { $0.grdbId!.int64Value > rowId }.prefix(limit).map { $0.uniqueId })
            case .before(let rowId):
                return Array(interactions.lazy.filter { $0.grdbId!.int64Value < rowId }.suffix(limit).map { $0.uniqueId })
            case .range(let rowIds):
                return Array(interactions.lazy.filter { rowIds.contains($0.grdbId!.int64Value) }.map { $0.uniqueId })
            }
        }
    }

    private class MockInteractionFetcher: MessageLoaderInteractionFetcher {
        var interactions = [TSInteraction]()
        func fetchInteractions(for uniqueIds: [String], tx: DBReadTransaction) -> [String: TSInteraction] {
            return Dictionary(
                uniqueKeysWithValues: interactions.lazy.filter { uniqueIds.contains($0.uniqueId) }.map { ($0.uniqueId, $0) }
            )
        }
    }

    override func setUp() {
        super.setUp()

        batchFetcher = MockBatchFetcher()
        interactionFetcher = MockInteractionFetcher()
        messageLoader = MessageLoader(
            batchFetcher: batchFetcher,
            interactionFetchers: [interactionFetcher]
        )
        mockDB = MockDB()
    }

    private func createInteractions(_ count: Int64) -> [TSInteraction] {
        return ((1 as Int64)...count).map { rowId in
            TSInteraction(grdbId: rowId, uniqueId: UUID().uuidString, receivedAtTimestamp: 0, sortId: 0, timestamp: 0, uniqueThreadId: "")
        }
    }

    private func setInteractions(_ interactions: [TSInteraction]) {
        batchFetcher.interactions = interactions
        interactionFetcher.interactions = interactions
    }

    func test_loadInitialMessagePage_empty() throws {
        try mockDB.read { tx in
            try self.messageLoader.loadInitialMessagePage(
                focusMessageId: nil,
                reusableInteractions: [:],
                deletedInteractionIds: [],
                tx: tx
            )
        }
        XCTAssertEqual(messageLoader.loadedInteractions, [])
    }

    func test_loadInitialMessagePage_nonempty() throws {
        let initialMessages = createInteractions(5)
        setInteractions(initialMessages)
        try mockDB.read { tx in
            try self.messageLoader.loadInitialMessagePage(
                focusMessageId: nil,
                reusableInteractions: [:],
                deletedInteractionIds: [],
                tx: tx
            )
        }
        XCTAssertEqual(messageLoader.loadedInteractions.count, 5)
        XCTAssertEqual(initialMessages.map { $0.uniqueId }, messageLoader.loadedInteractions.map { $0.uniqueId })
    }

    func test_reloadInteractions_deletes() throws {
        let initialMessages = createInteractions(5)
        setInteractions(initialMessages)

        try mockDB.read { tx in
            try self.messageLoader.loadInitialMessagePage(
                focusMessageId: nil,
                reusableInteractions: [:],
                deletedInteractionIds: [],
                tx: tx
            )
        }

        let remainingMessages = [initialMessages[1], initialMessages[3], initialMessages[4]]
        setInteractions(remainingMessages)

        XCTAssertEqual(initialMessages.map { $0.uniqueId }, messageLoader.loadedInteractions.map { $0.uniqueId })

        let deletedInteractionIds: Set<String> = Set([initialMessages[0], initialMessages[2]].map { $0.uniqueId })
        try mockDB.read { tx in
            return try self.messageLoader.loadSameLocation(
                reusableInteractions: [:],
                deletedInteractionIds: deletedInteractionIds,
                tx: tx
            )
        }
        XCTAssertEqual(remainingMessages.map { $0.uniqueId }, messageLoader.loadedInteractions.map { $0.uniqueId })
    }

    func test_reloadInteractions_inserts() throws {
        let allMessages = createInteractions(5)

        setInteractions(Array(allMessages.prefix(2)))
        try mockDB.read { tx in
            try self.messageLoader.loadInitialMessagePage(
                focusMessageId: nil,
                reusableInteractions: [:],
                deletedInteractionIds: [],
                tx: tx
            )
        }

        setInteractions(allMessages)
        try mockDB.read { tx in
            return try self.messageLoader.loadSameLocation(
                reusableInteractions: [:],
                deletedInteractionIds: [],
                tx: tx
            )
        }

        XCTAssertEqual(allMessages.map { $0.uniqueId }, messageLoader.loadedInteractions.map { $0.uniqueId })
    }

    func test_reloadInteractions_insertsAndDeletes() throws {
        let allMessages = createInteractions(5)
        let initialMessages = Array(allMessages.prefix(4))

        setInteractions(initialMessages)
        try mockDB.read { tx in
            try self.messageLoader.loadInitialMessagePage(
                focusMessageId: nil,
                reusableInteractions: [:],
                deletedInteractionIds: [],
                tx: tx
            )
        }

        let remainingMessages = [allMessages[1], allMessages[2], allMessages[4]]
        setInteractions(remainingMessages)

        let deletedInteractionIds: Set<String> = Set([allMessages[0], allMessages[3]].map { $0.uniqueId })
        try mockDB.read { tx in
            return try self.messageLoader.loadSameLocation(
                reusableInteractions: [:],
                deletedInteractionIds: deletedInteractionIds,
                tx: tx
            )
        }

        XCTAssertEqual(remainingMessages.map { $0.uniqueId }, messageLoader.loadedInteractions.map { $0.uniqueId })
    }

    func test_reloadInteractions_removeAll() throws {
        let initialMessages = createInteractions(5)
        setInteractions(initialMessages)

        try mockDB.read { tx in
            try self.messageLoader.loadInitialMessagePage(
                focusMessageId: nil,
                reusableInteractions: [:],
                deletedInteractionIds: [],
                tx: tx
            )
        }

        XCTAssert(!messageLoader.canLoadNewer)
        XCTAssert(!messageLoader.canLoadOlder)

        setInteractions([])

        let removedIds = Set(initialMessages.map { $0.uniqueId })
        try mockDB.read { tx in
            return try self.messageLoader.loadSameLocation(
                reusableInteractions: [:],
                deletedInteractionIds: removedIds,
                tx: tx
            )
        }

        XCTAssertEqual(messageLoader.loadedInteractions, [])
    }

    func test_reloadInteractions_fix_crash() throws {
        // Create more messages than are part of the first batch.
        let initialMessages = createInteractions(400)
        setInteractions(initialMessages)

        try mockDB.read { tx in
            try self.messageLoader.loadInitialMessagePage(
                focusMessageId: nil,
                reusableInteractions: [:],
                deletedInteractionIds: [],
                tx: tx
            )
        }

        XCTAssertLessThan(messageLoader.loadedInteractions.count, initialMessages.count)
        XCTAssert(!messageLoader.canLoadNewer)
        XCTAssert(messageLoader.canLoadOlder)

        setInteractions([])

        let removedIds = Set(initialMessages.map { $0.uniqueId })
        try mockDB.read { tx in
            return try self.messageLoader.loadSameLocation(
                reusableInteractions: [:],
                deletedInteractionIds: removedIds,
                tx: tx
            )
        }

        XCTAssertEqual(messageLoader.loadedInteractions, [])
    }

    func test_loadAroundEdge() throws {
        // Create more messages than are part of the first batch.
        let initialMessages = createInteractions(100)
        setInteractions(initialMessages)

        // For each message, load the end of the chat, and then jump to that
        // message. (This would be similar to opening the chat and tapping a reply
        // to jump earlier in the history.)
        for idx in stride(from: initialMessages.startIndex, to: initialMessages.endIndex, by: 10) {
            let message = initialMessages[idx]
            let messageLoader = MessageLoader(batchFetcher: batchFetcher, interactionFetchers: [interactionFetcher])
            try mockDB.read { tx in
                try messageLoader.loadInitialMessagePage(
                    focusMessageId: nil,
                    reusableInteractions: [:],
                    deletedInteractionIds: [],
                    tx: tx
                )
                XCTAssertLessThan(messageLoader.loadedInteractions.count, initialMessages.count)
                try messageLoader.loadMessagePage(
                    aroundInteractionId: message.uniqueId,
                    reusableInteractions: [:],
                    deletedInteractionIds: [],
                    tx: tx
                )
            }
            XCTAssertNotNil(messageLoader.loadedInteractions.map { $0.uniqueId }.firstIndex(of: message.uniqueId))
        }
    }

    func testTotalDeletion() throws {
        let allMessages = createInteractions(15)

        let batch1 = Array(allMessages[0..<5])
        let batch2 = Array(allMessages[5..<10])
        let batch3 = Array(allMessages[10..<15])

        setInteractions(batch1)
        try mockDB.read { tx in
            try self.messageLoader.loadInitialMessagePage(
                focusMessageId: nil,
                reusableInteractions: [:],
                deletedInteractionIds: [],
                tx: tx
            )
        }
        XCTAssertEqual(batch1.map { $0.uniqueId }, messageLoader.loadedInteractions.map { $0.uniqueId })

        setInteractions([])
        try mockDB.read { tx in
            return try self.messageLoader.loadSameLocation(
                reusableInteractions: [:],
                deletedInteractionIds: Set(batch1.map { $0.uniqueId }),
                tx: tx
            )
        }
        XCTAssertEqual(messageLoader.loadedInteractions, [])

        setInteractions(batch2)
        try mockDB.read { tx in
            return try self.messageLoader.loadSameLocation(
                reusableInteractions: [:],
                deletedInteractionIds: [],
                tx: tx
            )
        }
        XCTAssertEqual(batch2.map { $0.uniqueId }, messageLoader.loadedInteractions.map { $0.uniqueId })

        setInteractions(batch3)
        try mockDB.read { tx in
            return try self.messageLoader.loadSameLocation(
                reusableInteractions: [:],
                deletedInteractionIds: Set(batch2.map { $0.uniqueId }),
                tx: tx
            )
        }

        XCTAssertEqual(batch3.map { $0.uniqueId }, messageLoader.loadedInteractions.map { $0.uniqueId })
    }

    func testDeletionAndLoadOlder() throws {
        var messages = createInteractions(200)

        setInteractions(messages)
        try mockDB.read { tx in
            try self.messageLoader.loadInitialMessagePage(
                focusMessageId: messages[100].uniqueId,  // pretend this is the first unread message
                reusableInteractions: [:],
                deletedInteractionIds: [],
                tx: tx
            )
        }

        // Make sure the load window is pretty small.
        let loadCount1 = messageLoader.loadedInteractions.count
        XCTAssertLessThan(loadCount1, 50)

        // Remove the first, middle and last interactions.
        // This will break "sort index" continuity and make things interesting.
        let removedInteractions1 = [
            messages.remove(at: (messages.startIndex + messages.endIndex) / 2),
            messages.remove(at: messages.endIndex - 1),
            messages.remove(at: messages.startIndex)
        ]
        setInteractions(messages)
        try mockDB.read { tx in
            return try self.messageLoader.loadOlderMessagePage(
                reusableInteractions: [:],
                deletedInteractionIds: Set(removedInteractions1.map { $0.uniqueId }),
                tx: tx
            )
        }

        let loadCount2 = messageLoader.loadedInteractions.count
        XCTAssertLessThan(loadCount1, loadCount2)
        XCTAssertLessThan(loadCount2, 100)

        // Remove the first, middle and last interactions.
        // This will break "sort index" continuity and make things interesting.
        let removedInteractions2 = [
            messages.remove(at: (messages.startIndex + messages.endIndex) / 2),
            messages.remove(at: messages.endIndex - 1),
            messages.remove(at: messages.startIndex)
        ]
        setInteractions(messages)

        try mockDB.read { tx in
            return try self.messageLoader.loadOlderMessagePage(
                reusableInteractions: [:],
                deletedInteractionIds: Set(removedInteractions2.map { $0.uniqueId }),
                tx: tx
            )
        }

        let loadCount3 = messageLoader.loadedInteractions.count
        XCTAssertLessThan(loadCount2, loadCount3)
        XCTAssertLessThan(loadCount3, 150)
    }

    func testDeletionAndLoadNewer() throws {
        var messages = createInteractions(200)

        setInteractions(messages)
        try mockDB.read { tx in
            try self.messageLoader.loadInitialMessagePage(
                focusMessageId: messages[100].uniqueId,  // pretend this is the first unread message
                reusableInteractions: [:],
                deletedInteractionIds: [],
                tx: tx
            )
        }

        // Make sure the load window is pretty small.
        let loadCount1 = messageLoader.loadedInteractions.count
        XCTAssertLessThan(loadCount1, 50)

        // Remove the first, middle and last interactions.
        // This will break "sort index" continuity and make things interesting.
        let removedInteractions1 = [
            messages.remove(at: (messages.startIndex + messages.endIndex) / 2),
            messages.remove(at: messages.endIndex - 1),
            messages.remove(at: messages.startIndex)
        ]
        setInteractions(messages)
        try mockDB.read { tx in
            return try self.messageLoader.loadNewerMessagePage(
                reusableInteractions: [:],
                deletedInteractionIds: Set(removedInteractions1.map { $0.uniqueId }),
                tx: tx
            )
        }

        let loadCount2 = messageLoader.loadedInteractions.count
        XCTAssertLessThan(loadCount1, loadCount2)
        XCTAssertLessThan(loadCount2, 100)

        // Remove the first, middle and last interactions.
        // This will break "sort index" continuity and make things interesting.
        let removedInteractions2 = [
            messages.remove(at: (messages.startIndex + messages.endIndex) / 2),
            messages.remove(at: messages.endIndex - 1),
            messages.remove(at: messages.startIndex)
        ]
        setInteractions(messages)

        try mockDB.read { tx in
            return try self.messageLoader.loadNewerMessagePage(
                reusableInteractions: [:],
                deletedInteractionIds: Set(removedInteractions2.map { $0.uniqueId }),
                tx: tx
            )
        }

        let loadCount3 = messageLoader.loadedInteractions.count
        XCTAssertLessThan(loadCount2, loadCount3)
        XCTAssertLessThan(loadCount3, 150)
    }
}
