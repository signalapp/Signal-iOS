//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import XCTest
@testable import Signal

class ConversationMessageMappingTest: SignalBaseTest {

    var thread: TSThread!
    var mapping: ConversationMessageMapping!
    var messageFactory: IncomingMessageFactory!

    override func setUp() {
        super.setUp()
        let thread = ContactThreadFactory().create()
        self.thread = thread
        self.mapping = ConversationMessageMapping(thread: thread)
        self.messageFactory = IncomingMessageFactory()
        messageFactory.threadCreator = { _ in return thread }
    }

    func test_loadInitialMessagePage_empty() throws {
        try read { transaction in
            try self.mapping.loadInitialMessagePage(focusMessageId: nil, transaction: transaction)
        }

        XCTAssertEqual([], mapping.loadedInteractions)
    }

    func test_loadInitialMessagePage_nonempty() throws {
        let initialMessages = messageFactory.create(count: 5)
        try read { transaction in
            try self.mapping.loadInitialMessagePage(focusMessageId: nil, transaction: transaction)
        }
        XCTAssertEqual(5, mapping.loadedInteractions.count)
        XCTAssertEqual(initialMessages.map { $0.uniqueId }, mapping.loadedInteractions.map { $0.uniqueId })
    }

    func test_updateAndCalculateDiff_deletes() throws {
        let initialMessages = messageFactory.create(count: 5)
        try read { transaction in
            try self.mapping.loadInitialMessagePage(focusMessageId: nil, transaction: transaction)
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
        let diff: ConversationMessageMapping.ConversationMessageMappingDiff = try read { transaction in
            return try self.mapping.updateAndCalculateDiff(updatedInteractionIds: deletedInteractionIds, transaction: transaction)
        }
        XCTAssertEqual(remainingMessages.map { $0.uniqueId }, mapping.loadedInteractions.map { $0.uniqueId })

        XCTAssertEqual([], diff.addedItemIds)
        XCTAssertEqual([], diff.updatedItemIds)
        XCTAssertEqual(deletedInteractionIds, diff.removedItemIds)
    }

    func test_updateAndCalculateDiff_inserts() throws {
        let initialMessages = messageFactory.create(count: 2)
        try read { transaction in
            try self.mapping.loadInitialMessagePage(focusMessageId: nil, transaction: transaction)
        }

        let insertedMessages = messageFactory.create(count: 3)
        let insertedIds = Set(insertedMessages.map { $0.uniqueId})
        let diff: ConversationMessageMapping.ConversationMessageMappingDiff = try read { transaction in
            return try self.mapping.updateAndCalculateDiff(updatedInteractionIds: insertedIds,
                                                           transaction: transaction)
        }
        XCTAssertEqual((initialMessages + insertedMessages).map { $0.uniqueId }, mapping.loadedInteractions.map { $0.uniqueId })

        XCTAssertEqual(insertedIds, diff.addedItemIds)
        XCTAssertEqual([], diff.updatedItemIds)
        XCTAssertEqual([], diff.removedItemIds)
    }

    func test_updateAndCalculateDiff_updates() throws {
        let initialMessages = messageFactory.create(count: 5)
        try read { transaction in
            try self.mapping.loadInitialMessagePage(focusMessageId: nil, transaction: transaction)
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

        let updatedIds = Set(updatedMessages.map { $0.uniqueId })
        let diff: ConversationMessageMapping.ConversationMessageMappingDiff = try read { transaction in
            return try self.mapping.updateAndCalculateDiff(updatedInteractionIds: updatedIds,
                                                           transaction: transaction)
        }
        XCTAssertEqual(initialMessages.map { $0.uniqueId }, mapping.loadedInteractions.map { $0.uniqueId })

        XCTAssertEqual([], diff.addedItemIds)
        XCTAssertEqual(updatedIds, diff.updatedItemIds)
        XCTAssertEqual([], diff.removedItemIds)
    }

    func test_updateAndCalculateDiff_mixed_updates() throws {
        let initialMessages = messageFactory.create(count: 4)
        try read { transaction in
            try self.mapping.loadInitialMessagePage(focusMessageId: nil, transaction: transaction)
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

        let updatedIds = Set((updatedMessages + removedMessages + [insertedMessage]).map { $0.uniqueId })
        let diff: ConversationMessageMapping.ConversationMessageMappingDiff = try read { transaction in
            return try self.mapping.updateAndCalculateDiff(updatedInteractionIds: updatedIds,
                                                           transaction: transaction)
        }

        let remainingMessages = [initialMessages[1], initialMessages[2], insertedMessage]
        XCTAssertEqual(remainingMessages.map { $0.uniqueId }, mapping.loadedInteractions.map { $0.uniqueId })

        XCTAssertEqual([insertedMessage.uniqueId], diff.addedItemIds)
        XCTAssertEqual(Set(updatedMessages.map { $0.uniqueId }), diff.updatedItemIds)
        XCTAssertEqual(Set(removedMessages.map { $0.uniqueId }), diff.removedItemIds)
    }

    func test_updateAndCalculateDiff_removeAll() throws {
        let initialMessages = messageFactory.create(count: 5)
        try read { transaction in
            try self.mapping.loadInitialMessagePage(focusMessageId: nil, transaction: transaction)
        }

        XCTAssert(!mapping.canLoadNewer)
        XCTAssert(!mapping.canLoadOlder)

        write { transaction in
            for message in initialMessages {
                message.anyRemove(transaction: transaction)
            }
        }

        let removedIds = Set(initialMessages.map { $0.uniqueId })
        let diff: ConversationMessageMapping.ConversationMessageMappingDiff = try read { transaction in
            return try self.mapping.updateAndCalculateDiff(updatedInteractionIds: removedIds,
                                                           transaction: transaction)
        }

        XCTAssertEqual([], mapping.loadedInteractions)

        XCTAssertEqual([], diff.addedItemIds)
        XCTAssertEqual([], diff.updatedItemIds)
        XCTAssertEqual(removedIds, diff.removedItemIds)
    }

    func test_updateAndCalculateDiff_fix_crash() throws {
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
            try self.mapping.loadInitialMessagePage(focusMessageId: nil, transaction: transaction)
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
        let diff: ConversationMessageMapping.ConversationMessageMappingDiff = try read { transaction in
            return try self.mapping.updateAndCalculateDiff(updatedInteractionIds: removedIds,
                                                           transaction: transaction)
        }

        XCTAssertEqual([], mapping.loadedInteractions)

        XCTAssertEqual([], diff.addedItemIds)
        XCTAssertEqual([], diff.updatedItemIds)
        XCTAssertEqual(Set(initiallyLoadedInteractions.map { $0.uniqueId }), diff.removedItemIds)
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
            self.mapping = ConversationMessageMapping(thread: thread)
            try read { transaction in
                try self.mapping.loadInitialMessagePage(focusMessageId: nil, transaction: transaction)
                try self.mapping.loadMessagePage(aroundInteractionId: message.uniqueId, transaction: transaction)
            }
            guard (mapping.loadedInteractions.map { $0.uniqueId }.contains(message.uniqueId)) else {
                XCTFail("message not loaded: \(message)")
                return
            }
        }
    }
}
