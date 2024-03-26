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
                isHighPriority: false,
                transaction: transaction
            )

            switch jobRecord.messageType {
            case .persisted:
                break
            case .transient, .none:
                XCTFail("Incorrect message type")
            }
            XCTAssertNotNil(jobRecord.threadId)
        }
    }

    func test_unsavedVisibleMessage() {
        self.write { transaction in
            let message = OutgoingMessageFactory().build(transaction: transaction)

            do {
                _ = try MessageSenderJobRecord(
                    message: message,
                    isHighPriority: false,
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
                isHighPriority: false,
                transaction: transaction
            )

            switch jobRecord.messageType {
            case .transient:
                break
            case .persisted, .none:
                XCTFail("Incorrect message type")
            }
            XCTAssertNotNil(jobRecord.threadId)
        }
    }
}
