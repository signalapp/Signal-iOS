//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest
@testable import SignalServiceKit

class InteractionFinderTest: SSKBaseTestSwift {
    func testInteractions() {
        let address1 = SignalServiceAddress(phoneNumber: "+fake-id")
        // Threads
        let contactThread1 = TSContactThread(contactAddress: SignalServiceAddress(phoneNumber: "+13213334444"))
        let contactThread2 = TSContactThread(contactAddress: SignalServiceAddress(phoneNumber: "+13213334445"))
        // Attachments
        let attachmentData1 = Randomness.generateRandomBytes(1024)
        let attachment1 = TSAttachmentStream(contentType: OWSMimeTypeImageGif,
                                             byteCount: UInt32(attachmentData1.count),
                                             sourceFilename: "some.gif",
                                             caption: nil,
                                             albumMessageId: nil)
        let attachmentData2 = Randomness.generateRandomBytes(2048)
        let attachment2 = TSAttachmentStream(contentType: OWSMimeTypePdf,
                                             byteCount: UInt32(attachmentData2.count),
                                             sourceFilename: "some.df", caption: nil, albumMessageId: nil)
        // Messages
        let outgoingMessage1 = TSOutgoingMessage(in: contactThread1, messageBody: "good heavens", attachmentId: attachment1.uniqueId)
        let outgoingMessage2 = TSOutgoingMessage(in: contactThread2, messageBody: "land's sakes", attachmentId: attachment2.uniqueId)
        let outgoingMessage3 = TSOutgoingMessage(in: contactThread2, messageBody: "oh my word", attachmentId: nil)
        let errorMessage1 = TSErrorMessage.nonblockingIdentityChange(in: contactThread1,
                                                                     address: address1,
                                                                     wasIdentityVerified: false)
        let errorMessage2 = TSErrorMessageBuilder(thread: contactThread1,
                                                  errorType: .groupCreationFailed).build()
        // Non-message interactions
        let missedCall = TSCall(callType: .incomingMissed,
                                offerType: .audio,
                                thread: contactThread1,
                                sentAtTimestamp: NSDate.ows_millisecondTimeStamp())

        let finder1 = InteractionFinder(threadUniqueId: contactThread1.uniqueId)
        let finder2 = InteractionFinder(threadUniqueId: contactThread2.uniqueId)
        self.read { transaction in
            XCTAssertEqual(0, finder1.count(transaction: transaction))
            XCTAssertEqual(0, finder2.count(transaction: transaction))
        }

        self.write { transaction in
            // Threads
            contactThread1.anyInsert(transaction: transaction)
            contactThread2.anyInsert(transaction: transaction)
            // Attachments
            attachment1.anyInsert(transaction: transaction)
            attachment2.anyInsert(transaction: transaction)
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
            XCTAssertEqual(4, finder1.count(transaction: transaction))
            XCTAssertEqual(2, finder2.count(transaction: transaction))
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
            let unreadCount = InteractionFinder.unreadCountInAllThreads(transaction: transaction.unwrapGrdbRead)
            XCTAssertEqual(unarchivedCount, unreadCount)
        }
    }
}
