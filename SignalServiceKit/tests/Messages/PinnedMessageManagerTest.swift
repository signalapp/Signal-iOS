//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Testing

@testable import LibSignalClient
@testable import SignalServiceKit

@MainActor
struct PinnedMessageManagerTest {
    private let db = InMemoryDB()
    private let pinnedMessageManager: PinnedMessageManager

    init() throws {
        pinnedMessageManager = PinnedMessageManager(
            disappearingMessagesConfigurationStore: MockDisappearingMessagesConfigurationStore(),
            interactionStore: MockInteractionStore(),
            accountManager: MockTSAccountManager(),
            db: db,
            threadStore: MockThreadStore(),
            dateProvider: Date.provider,
            expirationJob: PinnedMessageExpirationJob(dateProvider: { Date() }, db: db),
        )
    }

    private func createIncomingMessage(
        with thread: TSThread,
        customizeBlock: (TSIncomingMessageBuilder) -> Void,
    ) -> TSIncomingMessage {
        let messageBuilder: TSIncomingMessageBuilder = .withDefaultValues(
            thread: thread,
        )
        customizeBlock(messageBuilder)
        let targetMessage = messageBuilder.build()
        return targetMessage
    }

    private func insertMessage(thread: TSThread) -> (interactionId: Int64, threadId: Int64) {
        db.write { tx in
            let db = tx.database

            let messageBuilder: TSIncomingMessageBuilder = .withDefaultValues(
                thread: thread,
            )
            let targetMessage = messageBuilder.build()
            try! targetMessage.asRecord().insert(db)

            return (targetMessage.grdbId!.int64Value, thread.grdbId!.int64Value)
        }
    }

    @Test
    func testFetchPinnedMessagesForThread() throws {
        let thread = db.write { tx in
            let thread = TSThread()
            try! thread.asRecord().insert(tx.database)
            return thread
        }

        let (_, threadId) = insertMessage(thread: thread)
        let (interactionId2, _) = insertMessage(thread: thread)

        try db.write { tx in
            _ = try PinnedMessageRecord.insertRecord(
                interactionId: interactionId2,
                threadId: threadId,
                sentTimestamp: NSDate.ows_millisecondTimeStamp(),
                receivedTimestamp: NSDate.ows_millisecondTimeStamp(),
                tx: tx,
            )
        }

        db.read { tx in
            let pinnedMessages = pinnedMessageManager.fetchPinnedMessagesForThread(threadId: threadId, tx: tx)
            #expect(pinnedMessages.count == 1)
            #expect(pinnedMessages.first!.grdbId?.int64Value == interactionId2)
        }
    }

    @Test
    func testSortedPinnedMessages() throws {
        let thread = db.write { tx in
            let thread = TSThread()
            try! thread.asRecord().insert(tx.database)
            return thread
        }

        let (olderPinnedMessage, threadId) = insertMessage(thread: thread)
        let (newerPinnedMessage, _) = insertMessage(thread: thread)

        let olderTimestamp = Date().ows_millisecondsSince1970.advanced(by: -1000)
        let newerTimestamp = Date().ows_millisecondsSince1970

        try db.write { tx in
            _ = try PinnedMessageRecord.insertRecord(
                interactionId: olderPinnedMessage,
                threadId: threadId,
                sentTimestamp: olderTimestamp,
                receivedTimestamp: olderTimestamp,
                tx: tx,
            )

            _ = try PinnedMessageRecord.insertRecord(
                interactionId: newerPinnedMessage,
                threadId: threadId,
                sentTimestamp: newerTimestamp,
                receivedTimestamp: newerTimestamp,
                tx: tx,
            )
        }

        db.read { tx in
            let pinnedMessages = pinnedMessageManager.fetchPinnedMessagesForThread(threadId: threadId, tx: tx)
            #expect(pinnedMessages.count == 2)
            #expect(pinnedMessages.first!.grdbId?.int64Value == newerPinnedMessage, "More recently pinned message should be first")
            #expect(pinnedMessages.last!.grdbId?.int64Value == olderPinnedMessage)
        }
    }
}
