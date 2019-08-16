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
        self.yapRead { transaction in
            let jobRecord = try! SSKMessageSenderJobRecord(message: message,
                                                           removeMessageAfterSending: false,
                                                           label: MessageSenderJobQueue.jobRecordLabel,
                                                           transaction: transaction.asAnyRead)
            XCTAssertNotNil(jobRecord.messageId)
            XCTAssertNotNil(jobRecord.threadId)
            XCTAssertNil(jobRecord.invisibleMessage)
        }
    }

    func test_unsavedVisibleMessage() {
        var message: TSOutgoingMessage!
        self.yapWrite { transaction in
            message = OutgoingMessageFactory().build(transaction: transaction.asAnyWrite)

            do {
                _ = try SSKMessageSenderJobRecord(message: message, removeMessageAfterSending: false, label: MessageSenderJobQueue.jobRecordLabel, transaction: transaction.asAnyRead)
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
        self.yapRead { transaction in
            let jobRecord = try! SSKMessageSenderJobRecord(message: message,
                                                           removeMessageAfterSending: false,
                                                           label: MessageSenderJobQueue.jobRecordLabel,
                                                           transaction: transaction.asAnyRead)
            XCTAssertNil(jobRecord.messageId)
            XCTAssertNotNil(jobRecord.threadId)
            XCTAssertNotNil(jobRecord.invisibleMessage)
        }
    }
}
