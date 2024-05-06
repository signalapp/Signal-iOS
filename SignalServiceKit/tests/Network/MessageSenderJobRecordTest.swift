//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest
@testable import SignalServiceKit

class SSKMessageSenderJobRecordTest: SSKBaseTest {

    func test_savedVisibleMessage() {
        let message = OutgoingMessageFactory().create()
        self.read { transaction in
            let jobRecord = try! MessageSenderJobRecord(
                persistedMessage: .init(
                    rowId: 0,
                    message: message
                ),
                isHighPriority: false,
                transaction: transaction
            )

            switch jobRecord.messageType {
            case .persisted:
                break
            case .transient, .editMessage, .none:
                XCTFail("Incorrect message type")
            }
            XCTAssertNotNil(jobRecord.threadId)
        }
    }

    func test_invisibleMessage() {
        let message = OutgoingMessageFactory().buildDeliveryReceipt()
        self.read { transaction in
            let jobRecord = MessageSenderJobRecord(
                transientMessage: message,
                isHighPriority: false
            )

            switch jobRecord.messageType {
            case .transient:
                break
            case .persisted, .editMessage, .none:
                XCTFail("Incorrect message type")
            }
            XCTAssertNotNil(jobRecord.threadId)
        }
    }
}
