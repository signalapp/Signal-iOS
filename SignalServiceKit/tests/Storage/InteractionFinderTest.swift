//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import XCTest
@testable import SignalServiceKit

class InteractionFinderTest: SSKBaseTestSwift {

    // MARK: - Dependencies

    var storageCoordinator: StorageCoordinator {
        return SSKEnvironment.shared.storageCoordinator
    }

    // MARK: -

    override func setUp() {
        super.setUp()

        storageCoordinator.useGRDBForTests()
    }

    func specialMessageCount(threadId: String, transaction: SDSAnyReadTransaction) -> UInt {
        var count: UInt = 0
        let interactionFinder = InteractionFinder(threadUniqueId: threadId)
        interactionFinder.enumerateSpecialMessages(transaction: transaction) { (_, _) in
            count += 1
        }
        return count
    }

    func envelopeForThread(thread: TSContactThread) -> SSKProtoEnvelope {
        let timestamp = NSDate.ows_millisecondTimeStamp()
        let source = thread.contactAddress

        let builder = SSKProtoEnvelope.builder(timestamp: timestamp)
        builder.setType(.ciphertext)
        if let phoneNumber = source.phoneNumber {
            builder.setSourceE164(phoneNumber)
        }
        if let uuidString = source.uuidString {
            builder.setSourceUuid(uuidString)
        }
        builder.setSourceDevice(1)
        return try! builder.build()
    }

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
                                             albumMessageId: nil,
                                             shouldAlwaysPad: true)
        let attachmentData2 = Randomness.generateRandomBytes(2048)
        let attachment2 = TSAttachmentStream(contentType: OWSMimeTypeImagePdf,
                                             byteCount: UInt32(attachmentData2.count),
                                             sourceFilename: "some.df", caption: nil, albumMessageId: nil,
                                             shouldAlwaysPad: true)
        // Messages
        let outgoingMessage1 = TSOutgoingMessage(in: contactThread1, messageBody: "good heavens", attachmentId: attachment1.uniqueId)
        let outgoingMessage2 = TSOutgoingMessage(in: contactThread2, messageBody: "land's sakes", attachmentId: attachment2.uniqueId)
        let outgoingMessage3 = TSOutgoingMessage(in: contactThread2, messageBody: "oh my word", attachmentId: nil)
        let errorMessage1 = TSErrorMessage.nonblockingIdentityChange(in: contactThread1, address: address1)
        let errorMessage2 = TSErrorMessage(timestamp: NSDate.ows_millisecondTimeStamp(),
                                           in: contactThread1,
                                           failedMessageType: .groupCreationFailed)

        self.read { transaction in
            XCTAssertEqual(0, self.specialMessageCount(threadId: contactThread1.uniqueId, transaction: transaction))
            XCTAssertEqual(0, self.specialMessageCount(threadId: contactThread2.uniqueId, transaction: transaction))
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

            let envelope = self.envelopeForThread(thread: contactThread1)
            let errorMessage3 = TSInvalidIdentityKeyReceivingErrorMessage.untrustedKey(with: envelope,
                                                                                       with: transaction)!
            errorMessage3.anyInsert(transaction: transaction)
        }

        self.read { transaction in
            XCTAssertEqual(2, self.specialMessageCount(threadId: contactThread1.uniqueId, transaction: transaction))
            XCTAssertEqual(0, self.specialMessageCount(threadId: contactThread2.uniqueId, transaction: transaction))
        }
    }
}
