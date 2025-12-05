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
            threadStore: MockThreadStore()
        )
    }

    private func createIncomingMessage(
        with thread: TSThread,
        customizeBlock: ((TSIncomingMessageBuilder) -> Void)
    ) -> TSIncomingMessage {
        let messageBuilder: TSIncomingMessageBuilder = .withDefaultValues(
            thread: thread
        )
        customizeBlock(messageBuilder)
        let targetMessage = messageBuilder.build()
        return targetMessage
    }

    private func insertMessage(thread: TSThread) -> (interactionId: Int64, threadId: Int64) {
        db.write { tx in
            let db = tx.database

            let messageBuilder: TSIncomingMessageBuilder = .withDefaultValues(
                thread: thread
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
                tx: tx
            )
        }

        db.read { tx in
            let pinnedMessages = pinnedMessageManager.fetchPinnedMessagesForThread(threadId: threadId, tx: tx)
            #expect(pinnedMessages.count == 1)
            #expect(pinnedMessages.first!.grdbId?.int64Value == interactionId2)
        }
    }
}
