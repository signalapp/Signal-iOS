//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import XCTest
@testable import SignalServiceKit

class OWSReceiptsForSenderMessageTest: SSKBaseTestSwift {
    func testIsUrgent() throws {
        write { transaction in
            let thread = TSContactThread.getOrCreateThread(
                withContactAddress: SignalServiceAddress(phoneNumber: "+12223334444"),
                transaction: transaction
            )

            let receiptSet = MessageReceiptSet()
            receiptSet.insert(timestamp: 123)
            receiptSet.insert(timestamp: 456)

            let fns = [
                OWSReceiptsForSenderMessage.deliveryReceiptsForSenderMessage,
                // TODO: For unknown reasons, `readReceiptsForSenderMessage` is not available here.
                // We should fix this, but we couldn't figure out how.
                // OWSReceiptsForSenderMessage.readReceiptsForSenderMessage,
                OWSReceiptsForSenderMessage.viewedReceiptsForSenderMessage
            ]

            for fn in fns {
                let receiptsMessage = fn(thread, receiptSet, transaction)
                XCTAssertFalse(receiptsMessage.isUrgent)
            }
        }
    }
}
