//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import XCTest
import SignalServiceKit

class OWSViewOnceMessageReadSyncMessageTest: SSKBaseTestSwift {
    override func setUp() {
        super.setUp()
        tsAccountManager.registerForTests(withLocalNumber: "+12225550101", uuid: UUID(), pni: UUID())
    }

    private func getViewOnceSyncMessage() -> OWSViewOnceMessageReadSyncMessage {
        write { transaction in
            let senderAddress = SignalServiceAddress(phoneNumber: "+12225550102")

            let thread = TSContactThread.getOrCreateThread(
                withContactAddress: senderAddress,
                transaction: transaction
            )

            let viewOnceMessage: TSOutgoingMessage = {
                let builder = TSOutgoingMessageBuilder.outgoingMessageBuilder(
                    thread: thread,
                    messageBody: nil
                )
                builder.timestamp = 100
                return builder.build(transaction: transaction)
            }()

            return OWSViewOnceMessageReadSyncMessage(
                thread: thread,
                senderAddress: senderAddress,
                message: viewOnceMessage,
                readTimestamp: 1234,
                transaction: transaction
            )
        }
    }

    func testIsUrgent() throws {
        XCTAssertFalse(getViewOnceSyncMessage().isUrgent)
    }
}
