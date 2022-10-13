//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalServiceKit

class DeliveryReceiptContextTests: SSKBaseTestSwift {
    func testExecutesDifferentMessages() throws {
        let aliceRecipient = SignalServiceAddress(phoneNumber: "+12345678900")
        var timestamp: UInt64?
        write { transaction in
            let aliceContactThread = TSContactThread.getOrCreateThread(withContactAddress: aliceRecipient, transaction: transaction)
            let helloAlice = TSOutgoingMessage(in: aliceContactThread, messageBody: "Hello Alice", attachmentId: nil)
            helloAlice.anyInsert(transaction: transaction)
            timestamp = helloAlice.timestamp
        }
        XCTAssertNotNil(timestamp)
        write { transaction in
            var messages = [TSOutgoingMessage]()
            BatchingDeliveryReceiptContext.withDeferredUpdates(transaction: transaction) { context in
                let message = context.messages(timestamp!, transaction: transaction)[0]
                context.addUpdate(message: message, transaction: transaction) { m in
                    messages.append(m)
                }
            }
            XCTAssertEqual(messages.count, 2)
            XCTAssertFalse(messages[0] === messages[1])
        }

    }
}
