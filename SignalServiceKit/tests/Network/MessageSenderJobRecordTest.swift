//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import XCTest
@testable import SignalServiceKit

let kMessageSenderJobRecordLabel = "MessageSender"
class SSKMessageSenderJobRecordTest: SSKBaseTestSwift {

    func test_savedVisibleMessage() {
        let message = OutgoingMessageFactory().create()
        let jobRecord = try! SSKMessageSenderJobRecord(message: message, removeMessageAfterSending: false, label: MessageSenderJobQueue.jobRecordLabel)
        XCTAssertNotNil(jobRecord.messageId)
        XCTAssertNotNil(jobRecord.threadId)
        XCTAssertNil(jobRecord.invisibleMessage)
    }

    func test_unsavedVisibleMessage() {
        var message: TSOutgoingMessage!
        self.yapWrite { transaction in
            message = OutgoingMessageFactory().build(transaction: transaction)
        }
        message.uniqueId = nil

        do {
            _ = try SSKMessageSenderJobRecord(message: message, removeMessageAfterSending: false, label: MessageSenderJobQueue.jobRecordLabel)
            XCTFail("Should error")
        } catch JobRecordError.assertionError {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func test_invisibleMessage() {
        let message = OutgoingMessageFactory().buildDeliveryReceipt()

        let jobRecord = try! SSKMessageSenderJobRecord(message: message, removeMessageAfterSending: false, label: MessageSenderJobQueue.jobRecordLabel)
        XCTAssertNil(jobRecord.messageId)
        XCTAssertNotNil(jobRecord.threadId)
        XCTAssertNotNil(jobRecord.invisibleMessage)
    }
}
