//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import Signal

class CVMessageMappingTest: SignalBaseTest {

    var thread: TSThread!
    var mapping: CVMessageMapping!
    var messageFactory: IncomingMessageFactory!

    override func setUp() {
        super.setUp()
        let thread = ContactThreadFactory().create()
        self.thread = thread
        self.mapping = CVMessageMapping(thread: thread)
        self.messageFactory = IncomingMessageFactory()
        messageFactory.threadCreator = { _ in return thread }
    }

    func test_loadInitialMessagePage_empty() throws {
        try read { transaction in
            try self.mapping.loadInitialMessagePage(focusMessageId: nil,
                                                    reusableInteractions: [:],
                                                    deletedInteractionIds: [],
                                                    transaction: transaction)
        }

        XCTAssertEqual([], mapping.loadedInteractions)
    }

    func test_loadInitialMessagePage_nonempty() throws {
        let initialMessages = messageFactory.create(count: 5)
        try read { transaction in
            try self.mapping.loadInitialMessagePage(focusMessageId: nil,
                                                    reusableInteractions: [:],
                                                    deletedInteractionIds: [],
                                                    transaction: transaction)
        }
        XCTAssertEqual(5, mapping.loadedInteractions.count)
        XCTAssertEqual(initialMessages.map { $0.uniqueId }, mapping.loadedInteractions.map { $0.uniqueId })
    }

    func test_reloadInteractions_deletes() throws {
        let initialMessages = messageFactory.create(count: 5)

        try read { transaction in
            try self.mapping.loadInitialMessagePage(focusMessageId: nil,
                                                    reusableInteractions: [:],
                                                    deletedInteractionIds: [],
                                                    transaction: transaction)
        }

        let removedMessages = [initialMessages[0], initialMessages[2]]
        write { transaction in
            for message in removedMessages {
                message.anyRemove(transaction: transaction)
            }
        }
        XCTAssertEqual(initialMessages.map { $0.uniqueId }, mapping.loadedInteractions.map { $0.uniqueId })

        let remainingMessages = [initialMessages[1], initialMessages[3], initialMessages[4]]
        let deletedInteractionIds: Set<String> = Set(removedMessages.map { $0.uniqueId })
        try read { transaction in
            return try self.mapping.loadSameLocation(reusableInteractions: [:],
                                                       deletedInteractionIds: deletedInteractionIds,
                                                       transaction: transaction)
        }
        XCTAssertEqual(remainingMessages.map { $0.uniqueId }, mapping.loadedInteractions.map { $0.uniqueId })
    }

    func test_reloadInteractions_inserts() throws {
        let initialMessages = messageFactory.create(count: 2)
        try read { transaction in
            try self.mapping.loadInitialMessagePage(focusMessageId: nil,
                                                    reusableInteractions: [:],
                                                    deletedInteractionIds: [],
                                                    transaction: transaction)
        }

        let insertedMessages = messageFactory.create(count: 3)
        try read { transaction in
            return try self.mapping.loadSameLocation(reusableInteractions: [:],
                                                       deletedInteractionIds: [],
                                                       transaction: transaction)
        }
        XCTAssertEqual((initialMessages + insertedMessages).map { $0.uniqueId }, mapping.loadedInteractions.map { $0.uniqueId })
    }

    func test_reloadInteractions_updates() throws {
        let initialMessages = messageFactory.create(count: 5)
        try read { transaction in
            try self.mapping.loadInitialMessagePage(focusMessageId: nil,
                                                    reusableInteractions: [:],
                                                    deletedInteractionIds: [],
                                                    transaction: transaction)
        }

        let updatedMessages = [initialMessages[1], initialMessages[2]]

        write { transaction in
            for message in updatedMessages {
                // This write is actually not necessary for the test to succeed, since we're manually
                // passing in `updatedInteractionIds` rather than observing db changes in this unit test,
                // "marking as read" here only documents an example of what we mean by "updated".
                message.debugonly_markAsReadNow(transaction: transaction)
            }
        }

        try read { transaction in
            return try self.mapping.loadSameLocation(reusableInteractions: [:],
                                                       deletedInteractionIds: [],
                                                       transaction: transaction)
        }
        XCTAssertEqual(initialMessages.map { $0.uniqueId }, mapping.loadedInteractions.map { $0.uniqueId })
    }

    func test_reloadInteractions_mixed_updates() throws {
        let initialMessages = messageFactory.create(count: 4)
        try read { transaction in
            try self.mapping.loadInitialMessagePage(focusMessageId: nil,
                                                    reusableInteractions: [:],
                                                    deletedInteractionIds: [],
                                                    transaction: transaction)
        }

        let removedMessages = [initialMessages[0], initialMessages[3]]
        let updatedMessages = [initialMessages[1], initialMessages[2]]
        let insertedMessage: TSIncomingMessage = write { transaction in
            for message in removedMessages {
                message.anyRemove(transaction: transaction)
            }
            for message in updatedMessages {
                // This write is actually not necessary for the test to succeed, since we're manually
                // passing in `updatedInteractionIds` rather than observing db changes in this unit test,
                // "marking as read" here only documents an example of what we mean by "updated".
                message.debugonly_markAsReadNow(transaction: transaction)
            }
            return self.messageFactory.create(transaction: transaction)
        }

        let deletedInteractionIds: Set<String> = Set(removedMessages.map { $0.uniqueId })
        try read { transaction in
            return try self.mapping.loadSameLocation(reusableInteractions: [:],
                                                       deletedInteractionIds: deletedInteractionIds,
                                                       transaction: transaction)
        }

        let remainingMessages = [initialMessages[1], initialMessages[2], insertedMessage]
        XCTAssertEqual(remainingMessages.map { $0.uniqueId }, mapping.loadedInteractions.map { $0.uniqueId })
    }

    func test_reloadInteractions_removeAll() throws {
        let initialMessages = messageFactory.create(count: 5)
        try read { transaction in
            try self.mapping.loadInitialMessagePage(focusMessageId: nil,
                                                    reusableInteractions: [:],
                                                    deletedInteractionIds: [],
                                                    transaction: transaction)
        }

        XCTAssert(!mapping.canLoadNewer)
        XCTAssert(!mapping.canLoadOlder)

        write { transaction in
            for message in initialMessages {
                message.anyRemove(transaction: transaction)
            }
        }

        let removedIds = Set(initialMessages.map { $0.uniqueId })
        try read { transaction in
            return try self.mapping.loadSameLocation(reusableInteractions: [:],
                                                       deletedInteractionIds: removedIds,
                                                       transaction: transaction)
        }

        XCTAssertEqual([], mapping.loadedInteractions)
    }

    func test_reloadInteractions_fix_crash() throws {
        let initialLoadCount = mapping.initialLoadCount

        let initialMessages: [TSIncomingMessage] = write { transaction in
            // create more messages than the initial load window can fit
            let createdMessages = self.messageFactory.create(count: UInt(initialLoadCount + 1), transaction: transaction)

            // mark as read so that we initially load the bottom of the conversation
            for message in createdMessages {
                message.debugonly_markAsReadNow(transaction: transaction)
            }

            return createdMessages
        }

        try read { transaction in
            try self.mapping.loadInitialMessagePage(focusMessageId: nil,
                                                    reusableInteractions: [:],
                                                    deletedInteractionIds: [],
                                                    transaction: transaction)
        }
        let initiallyLoadedInteractions = mapping.loadedInteractions
        XCTAssertEqual(initialLoadCount, initiallyLoadedInteractions.count)
        XCTAssert(!mapping.canLoadNewer)
        XCTAssert(mapping.canLoadOlder)

        write { transaction in
            for message in initialMessages {
                message.anyRemove(transaction: transaction)
            }
        }

        let removedIds = Set(initialMessages.map { $0.uniqueId })
        try read { transaction in
            return try self.mapping.loadSameLocation(reusableInteractions: [:],
                                                       deletedInteractionIds: removedIds,
                                                       transaction: transaction)
        }

        XCTAssertEqual([], mapping.loadedInteractions)
    }

    func test_loadAroundEdge() throws {
        let initialMessages: [TSIncomingMessage] = write { transaction in
            // create more messages than the initial load window can fit
            let createdMessages = self.messageFactory.create(count: UInt(self.mapping.initialLoadCount * 2), transaction: transaction)

            // mark as read so that we initially load the bottom of the conversation
            for message in createdMessages {
                message.debugonly_markAsReadNow(transaction: transaction)
            }

            return createdMessages
        }

        for message in initialMessages {
            self.mapping = CVMessageMapping(thread: thread)
            try read { transaction in
                try self.mapping.loadInitialMessagePage(focusMessageId: nil,
                                                        reusableInteractions: [:],
                                                        deletedInteractionIds: [],
                                                        transaction: transaction)
                try self.mapping.loadMessagePage(aroundInteractionId: message.uniqueId,
                                                 reusableInteractions: [:],
                                                 deletedInteractionIds: [],
                                                 transaction: transaction)
            }
            guard (mapping.loadedInteractions.map { $0.uniqueId }.contains(message.uniqueId)) else {
                XCTFail("message not loaded: \(message)")
                return
            }
        }
    }

    func testTotalDeletion() throws {

        // Insert batch 1.
        let batch1 = messageFactory.create(count: 5)

        try read { transaction in
            try self.mapping.loadInitialMessagePage(focusMessageId: nil,
                                                    reusableInteractions: [:],
                                                    deletedInteractionIds: [],
                                                    transaction: transaction)
        }
        XCTAssertEqual(batch1.map { $0.uniqueId }, mapping.loadedInteractions.map { $0.uniqueId })

        // Remove batch 1.
        var deletedInteractionIds = Set<String>()
        write { transaction in
            for message in batch1 {
                message.anyRemove(transaction: transaction)
                deletedInteractionIds.insert(message.uniqueId)
            }
        }

        try read { transaction in
            return try self.mapping.loadSameLocation(reusableInteractions: [:],
                                                     deletedInteractionIds: deletedInteractionIds,
                                                     transaction: transaction)
        }
        deletedInteractionIds.removeAll()

        XCTAssertTrue(mapping.loadedInteractions.isEmpty)

        // Insert batch 2.
        let batch2 = messageFactory.create(count: 5)

        try read { transaction in
            return try self.mapping.loadSameLocation(reusableInteractions: [:],
                                                     deletedInteractionIds: deletedInteractionIds,
                                                     transaction: transaction)
        }
        XCTAssertEqual(batch2.map { $0.uniqueId }, mapping.loadedInteractions.map { $0.uniqueId })

        // Remove batch 2, insert batch 3.
        write { transaction in
            for message in batch2 {
                message.anyRemove(transaction: transaction)
                deletedInteractionIds.insert(message.uniqueId)
            }
        }
        let batch3 = messageFactory.create(count: 5)

        try read { transaction in
            return try self.mapping.loadSameLocation(reusableInteractions: [:],
                                                     deletedInteractionIds: deletedInteractionIds,
                                                     transaction: transaction)
        }
        deletedInteractionIds.removeAll()

        XCTAssertEqual(batch3.map { $0.uniqueId }, mapping.loadedInteractions.map { $0.uniqueId })
    }

    func testDeletionAndLoadOlder() throws {

        let batch1read = messageFactory.create(count: 100)
        write { transaction in
            for message in batch1read {
                // This write is actually not necessary for the test to succeed, since we're manually
                // passing in `updatedInteractionIds` rather than observing db changes in this unit test,
                // "marking as read" here only documents an example of what we mean by "updated".
                message.debugonly_markAsReadNow(transaction: transaction)
            }
        }
        let batch1unread = messageFactory.create(count: 100)
        var currentInteractions = batch1read + batch1unread
        var deletedInteractionIds = Set<String>()

        try read { transaction in
            try self.mapping.loadInitialMessagePage(focusMessageId: nil,
                                                    reusableInteractions: [:],
                                                    deletedInteractionIds: [],
                                                    transaction: transaction)
        }
        // Make sure the load window is pretty small.
        let loadWindowCount1 = mapping.loadedInteractions.count
        XCTAssertTrue(loadWindowCount1 < 50)

        // Remove the first, middle and last interactions.
        // This will break "sort index" continuity and make things interesting.
        let batch2 = [currentInteractions.first!, currentInteractions[currentInteractions.count / 2], currentInteractions.last!]
        write { transaction in
            for message in batch2 {
                message.anyRemove(transaction: transaction)
                deletedInteractionIds.insert(message.uniqueId)
                currentInteractions = currentInteractions.filter { interaction in
                    interaction.uniqueId != message.uniqueId
                }
            }
        }

        try read { transaction in
            return try self.mapping.loadOlderMessagePage(reusableInteractions: [:],
                                                         deletedInteractionIds: deletedInteractionIds,
                                                         transaction: transaction)
        }
        deletedInteractionIds.removeAll()

        let loadWindowCount2 = mapping.loadedInteractions.count
        XCTAssertTrue(loadWindowCount1 < loadWindowCount2)
        XCTAssertTrue(loadWindowCount2 < 100)

        // Remove the first, middle and last interactions.
        // This will break "sort index" continuity and make things interesting.
        let batch3 = [currentInteractions.first!, currentInteractions[currentInteractions.count / 2], currentInteractions.last!]
        write { transaction in
            for message in batch3 {
                message.anyRemove(transaction: transaction)
                deletedInteractionIds.insert(message.uniqueId)
                currentInteractions = currentInteractions.filter { interaction in
                    interaction.uniqueId != message.uniqueId
                }
            }
        }

        try read { transaction in
            return try self.mapping.loadOlderMessagePage(reusableInteractions: [:],
                                                         deletedInteractionIds: deletedInteractionIds,
                                                         transaction: transaction)
        }
        deletedInteractionIds.removeAll()

        let loadWindowCount3 = mapping.loadedInteractions.count
        XCTAssertTrue(loadWindowCount2 < loadWindowCount3)
        XCTAssertTrue(loadWindowCount3 < 150)
    }

    func testDeletionAndLoadNewer() throws {

        let batch1 = messageFactory.create(count: 200)
        var currentInteractions = batch1
        var deletedInteractionIds = Set<String>()

        try read { transaction in
            try self.mapping.loadInitialMessagePage(focusMessageId: nil,
                                                    reusableInteractions: [:],
                                                    deletedInteractionIds: [],
                                                    transaction: transaction)
        }
        // Make sure the load window is pretty small.
        let loadWindowCount1 = mapping.loadedInteractions.count
        XCTAssertTrue(loadWindowCount1 < 50)

        // Remove the first, middle and last interactions.
        // This will break "sort index" continuity and make things interesting.
        let batch2 = [currentInteractions.first!, currentInteractions[currentInteractions.count / 2], currentInteractions.last!]
        write { transaction in
            for message in batch2 {
                message.anyRemove(transaction: transaction)
                deletedInteractionIds.insert(message.uniqueId)
                currentInteractions = currentInteractions.filter { interaction in
                    interaction.uniqueId != message.uniqueId
                }
            }
        }

        try read { transaction in
            return try self.mapping.loadNewerMessagePage(reusableInteractions: [:],
                                                         deletedInteractionIds: deletedInteractionIds,
                                                         transaction: transaction)
        }
        deletedInteractionIds.removeAll()

        let loadWindowCount2 = mapping.loadedInteractions.count
        XCTAssertTrue(loadWindowCount1 < loadWindowCount2)
        XCTAssertTrue(loadWindowCount2 < 100)

        // Remove the first, middle and last interactions.
        // This will break "sort index" continuity and make things interesting.
        let batch3 = [currentInteractions.first!, currentInteractions[currentInteractions.count / 2], currentInteractions.last!]
        write { transaction in
            for message in batch3 {
                message.anyRemove(transaction: transaction)
                deletedInteractionIds.insert(message.uniqueId)
                currentInteractions = currentInteractions.filter { interaction in
                    interaction.uniqueId != message.uniqueId
                }
            }
        }

        try read { transaction in
            return try self.mapping.loadNewerMessagePage(reusableInteractions: [:],
                                                         deletedInteractionIds: deletedInteractionIds,
                                                         transaction: transaction)
        }
        deletedInteractionIds.removeAll()

        let loadWindowCount3 = mapping.loadedInteractions.count
        XCTAssertTrue(loadWindowCount2 < loadWindowCount3)
        XCTAssertTrue(loadWindowCount3 < 150)
    }
}
