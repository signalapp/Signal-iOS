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
        self.read { transaction in
            let jobRecord = try! SSKMessageSenderJobRecord(message: message,
                                                           removeMessageAfterSending: false,
                                                           label: MessageSenderJobQueue.jobRecordLabel,
                                                           transaction: transaction)
            XCTAssertNotNil(jobRecord.messageId)
            XCTAssertNotNil(jobRecord.threadId)
            XCTAssertNil(jobRecord.invisibleMessage)
        }
    }

    func test_unsavedVisibleMessage() {
        self.write { transaction in
            let message = OutgoingMessageFactory().build(transaction: transaction)

            do {
                _ = try SSKMessageSenderJobRecord(message: message, removeMessageAfterSending: false, label: MessageSenderJobQueue.jobRecordLabel, transaction: transaction)
                XCTFail("Should error")
            } catch JobRecordError.assertionError {
                // expected
            } catch {
                XCTFail("unexpected error: \(error)")
            }
        }
    }

    func test_invisibleMessage() {
        let message = OutgoingMessageFactory().buildDeliveryReceipt()
        self.read { transaction in
            let jobRecord = try! SSKMessageSenderJobRecord(message: message,
                                                           removeMessageAfterSending: false,
                                                           label: MessageSenderJobQueue.jobRecordLabel,
                                                           transaction: transaction)
            XCTAssertNil(jobRecord.messageId)
            XCTAssertNotNil(jobRecord.threadId)
            XCTAssertNotNil(jobRecord.invisibleMessage)
        }
    }
}
