//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import Signal
@testable import SignalServiceKit

class DeletedForMeMessageTest: SignalBaseTest {
    func testInsertRemotelyDeletedMessage() {
        let interactionDeleteManager = DependenciesBridge.shared.interactionDeleteManager
        let lastVisibleInteractionStore = DependenciesBridge.shared.lastVisibleInteractionStore

        write { tx in
            let otherAddress = SignalServiceAddress(phoneNumber: "+12223334444")
            let thread = TSContactThread.getOrCreateThread(withContactAddress: otherAddress, transaction: tx)

            func insertMessage(timestamp: UInt64) -> TSOutgoingMessage {
                let builder = TSOutgoingMessageBuilder.outgoingMessageBuilder(thread: thread, messageBody: nil)
                builder.timestamp = timestamp
                let message = builder.build(transaction: tx)
                message.anyInsert(transaction: tx)
                return message
            }

            func fetchThread() -> TSThread {
                return TSThread.anyFetch(uniqueId: thread.uniqueId, transaction: tx)!
            }

            let deletedMessage = insertMessage(timestamp: 100)
            let otherMessage = insertMessage(timestamp: 200)
            let deletedForMeMessage = DeletedForMeMessage(
                rowId: deletedMessage.sqliteRowId!,
                uniqueId: deletedMessage.uniqueId,
                timestamp: deletedMessage.timestamp,
                receivedAtTimestamp: deletedMessage.receivedAtTimestamp,
                expiresInSeconds: 0,
                expireStartedAt: 0,
                storyAuthorAci: nil,
                storyTimestamp: nil,
            )
            interactionDeleteManager.delete(
                interactions: [deletedMessage],
                sideEffects: .custom(),
                tx: tx,
            )

            fetchThread().updateWith(
                isArchived: true,
                isMarkedUnread: true,
                updateStorageService: false,
                transaction: tx,
            )
            let lastVisibleInteraction = LastVisibleInteractionStore.LastVisibleInteraction(
                sortId: otherMessage.sortId,
                onScreenPercentage: 1,
            )
            lastVisibleInteractionStore.setLastVisibleInteraction(
                lastVisibleInteraction,
                for: thread,
                tx: tx,
            )

            _ = TSInteraction.insertRemotelyDeletedMessage(
                deletedForMeMessage: deletedForMeMessage,
                thread: fetchThread(),
                tx: tx,
            )

            let fetchedMessage = TSInteraction.anyFetch(
                uniqueId: deletedMessage.uniqueId,
                transaction: tx,
            ) as? TSOutgoingMessage
            XCTAssertEqual(fetchedMessage?.sqliteRowId, deletedForMeMessage.rowId)
            XCTAssertEqual(fetchedMessage?.sortId, UInt64(deletedForMeMessage.rowId))
            XCTAssertEqual(fetchedMessage?.timestamp, 100)
            XCTAssertEqual(fetchedMessage?.wasRemotelyDeleted, true)

            XCTAssertTrue(fetchThread().isArchived)
            XCTAssertTrue(fetchThread().isMarkedUnread)
            XCTAssertEqual(
                lastVisibleInteractionStore.lastVisibleInteraction(for: thread, tx: tx),
                lastVisibleInteraction,
            )

            // Inserting a message normally does change these, so the
            // assertions above are meaningful.
            _ = insertMessage(timestamp: 300)
            XCTAssertFalse(fetchThread().isArchived)
            XCTAssertFalse(fetchThread().isMarkedUnread)
            XCTAssertNil(lastVisibleInteractionStore.lastVisibleInteraction(for: thread, tx: tx))
        }
    }
}
