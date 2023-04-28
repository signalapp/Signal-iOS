//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest
@testable import SignalServiceKit

class SSKMessageSenderJobRecordTest: SSKBaseTestSwift {

    func test_savedVisibleMessage() {
        let message = OutgoingMessageFactory().create()
        self.read { transaction in
            let jobRecord = try! MessageSenderJobRecord(
                message: message,
                removeMessageAfterSending: false,
                isHighPriority: false,
                label: MessageSenderJobQueue.jobRecordLabel,
                transaction: transaction
            )

            XCTAssertNotNil(jobRecord.messageId)
            XCTAssertNotNil(jobRecord.threadId)
            XCTAssertNil(jobRecord.invisibleMessage)
        }
    }

    func test_unsavedVisibleMessage() {
        self.write { transaction in
            let message = OutgoingMessageFactory().build(transaction: transaction)

            do {
                _ = try MessageSenderJobRecord(
                    message: message,
                    removeMessageAfterSending: false,
                    isHighPriority: false,
                    label: MessageSenderJobQueue.jobRecordLabel,
                    transaction: transaction
                )

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
            let jobRecord = try! MessageSenderJobRecord(
                message: message,
                removeMessageAfterSending: false,
                isHighPriority: false,
                label: MessageSenderJobQueue.jobRecordLabel,
                transaction: transaction
            )

            XCTAssertNil(jobRecord.messageId)
            XCTAssertNotNil(jobRecord.threadId)
            XCTAssertNotNil(jobRecord.invisibleMessage)
        }
    }
}
