//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest
@testable import SignalServiceKit

class InteractionFinderTest: SSKBaseTest {

    func testBuildUniqueIdCursorForConversationView() {
        let thread = TSContactThread(contactAddress: SignalServiceAddress(phoneNumber: "+13213334444"))
        var messages = [TSOutgoingMessage]()
        self.write { transaction in
            thread.anyInsert(transaction: transaction)
            for idx in 1...5 {
                let message = TSOutgoingMessage(in: thread, messageBody: "message \(idx)")
                message.anyInsert(transaction: transaction)
                messages.append(message)
            }
        }

        let uniqueIds = messages.map { $0.uniqueId }
        let rowIds = messages.map { $0.sqliteRowId! }

        func drain(_ filter: InteractionFinder.RowIdFilter, tx: DBReadTransaction) -> [String] {
            var cursor = InteractionFinder(threadUniqueId: thread.uniqueId)
                .buildUniqueIdCursorForConversationView(rowIdFilter: filter, tx: tx)
            var results = [String]()
            while let uniqueId = cursor.next() {
                results.append(uniqueId)
            }
            return results
        }

        self.read { transaction in
            // These filters must yield uniqueIds newest first.
            XCTAssertEqual(drain(.newest, tx: transaction), Array(uniqueIds.reversed()))
            XCTAssertEqual(drain(.atOrBefore(rowIds[2]), tx: transaction), [uniqueIds[2], uniqueIds[1], uniqueIds[0]])
            XCTAssertEqual(drain(.before(rowIds[2]), tx: transaction), [uniqueIds[1], uniqueIds[0]])
            // These filters must yield uniqueIds oldest first.
            XCTAssertEqual(drain(.after(rowIds[2]), tx: transaction), [uniqueIds[3], uniqueIds[4]])
            XCTAssertEqual(drain(.range(rowIds[1]...rowIds[3]), tx: transaction), [uniqueIds[1], uniqueIds[2], uniqueIds[3]])
        }
    }

    func testUnreadInArchiveIsIgnored() {
        func makeThread(withUnreadMessages unreadCount: UInt, transaction: DBWriteTransaction) -> TSContactThread {
            let thread = ContactThreadFactory().create(transaction: transaction)

            if unreadCount > 0 {
                let messageFactory = IncomingMessageFactory()
                messageFactory.threadCreator = { _ in return thread }
                _ = messageFactory.create(count: unreadCount, transaction: transaction)
            }

            return thread
        }

        let unarchivedCount = UInt(10)
        let archivedCount = UInt(3)

        write { transaction in
            _ = makeThread(withUnreadMessages: unarchivedCount, transaction: transaction)

            let archivedWithMessages = makeThread(withUnreadMessages: archivedCount, transaction: transaction)
            ThreadAssociatedData
                .fetchOrDefault(for: archivedWithMessages, transaction: transaction)
                .updateWith(isArchived: true, updateStorageService: false, transaction: transaction)
        }

        // Unread count should be just the unarchived threads

        read { transaction in
            let unreadCount = InteractionFinder.unreadCountInAllThreads(transaction: transaction)
            XCTAssertEqual(unarchivedCount, unreadCount)
        }
    }
}

// MARK: -

private extension TSOutgoingMessage {
    convenience init(in thread: TSThread, messageBody: String) {
        let builder: TSOutgoingMessageBuilder = .withDefaultValues(
            thread: thread,
            messageBody: AttachmentContentValidatorMock.mockValidatedBody(messageBody),
        )
        self.init(outgoingMessageWith: builder, recipientAddressStates: [:])
    }
}
