//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest
@testable import SignalServiceKit

class InteractionFinderTest: SSKBaseTest {
    func testInteractions() {
        let address1 = SignalServiceAddress(phoneNumber: "+fake-id")
        // Threads
        let contactThread1 = TSContactThread(contactAddress: SignalServiceAddress(phoneNumber: "+13213334444"))
        let contactThread2 = TSContactThread(contactAddress: SignalServiceAddress(phoneNumber: "+13213334445"))
        // Messages
        let outgoingMessage1 = TSOutgoingMessage(in: contactThread1, messageBody: "good heavens")
        let outgoingMessage2 = TSOutgoingMessage(in: contactThread2, messageBody: "land's sakes")
        let outgoingMessage3 = TSOutgoingMessage(in: contactThread2, messageBody: "oh my word")
        let errorMessage1: TSErrorMessage = .nonblockingIdentityChange(
            thread: contactThread1,
            address: address1,
            wasIdentityVerified: false
        )
        let errorMessage2: TSErrorMessage = .failedDecryption(
            thread: contactThread1,
            timestamp: 0,
            sender: nil
        )
        // Non-message interactions
        let missedCall = TSCall(callType: .incomingMissed,
                                offerType: .audio,
                                thread: contactThread1,
                                sentAtTimestamp: NSDate.ows_millisecondTimeStamp())

        let finder1 = InteractionFinder(threadUniqueId: contactThread1.uniqueId)
        let finder2 = InteractionFinder(threadUniqueId: contactThread2.uniqueId)
        self.read { transaction in
            XCTAssertEqual(0, try! finder1.fetchUniqueIdsForConversationView(rowIdFilter: .newest, limit: 100, tx: transaction).count)
            XCTAssertEqual(0, try! finder2.fetchUniqueIdsForConversationView(rowIdFilter: .newest, limit: 100, tx: transaction).count)
        }

        self.write { transaction in
            // Threads
            contactThread1.anyInsert(transaction: transaction)
            contactThread2.anyInsert(transaction: transaction)
            // Messages
            outgoingMessage1.anyInsert(transaction: transaction)
            outgoingMessage2.anyInsert(transaction: transaction)
            outgoingMessage3.anyInsert(transaction: transaction)
            errorMessage1.anyInsert(transaction: transaction)
            errorMessage2.anyInsert(transaction: transaction)
            // Non-message interactions
            missedCall.anyInsert(transaction: transaction)
        }

        self.read { transaction in
            XCTAssertEqual(4, try! finder1.fetchUniqueIdsForConversationView(rowIdFilter: .newest, limit: 100, tx: transaction).count)
            XCTAssertEqual(2, try! finder2.fetchUniqueIdsForConversationView(rowIdFilter: .newest, limit: 100, tx: transaction).count)
        }
    }

    func testUnreadInArchiveIsIgnored() {
        func makeThread(withUnreadMessages unreadCount: UInt, transaction: SDSAnyWriteTransaction) -> TSContactThread {
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
        let builder: TSOutgoingMessageBuilder = .withDefaultValues(thread: thread, messageBody: messageBody)
        self.init(outgoingMessageWith: builder, recipientAddressStates: [:])
    }
}
