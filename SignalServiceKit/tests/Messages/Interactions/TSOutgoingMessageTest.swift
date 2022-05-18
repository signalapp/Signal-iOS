//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import SignalServiceKit
import XCTest

class TSOutgoingMessageTest: SSKBaseTestSwift {

    func testShouldNotStartExpireTimerWithMessageThatDoesNotExpire() {
        write { transaction in
            let otherAddress = SignalServiceAddress(phoneNumber: "+12223334444")
            let thread = TSContactThread.getOrCreateThread(withContactAddress: otherAddress, transaction: transaction)
            let messageBuilder = TSOutgoingMessageBuilder.outgoingMessageBuilder(thread: thread, messageBody: nil)
            messageBuilder.timestamp = 100
            let message = messageBuilder.build()

            XCTAssertFalse(message.shouldStartExpireTimer())

            message.update(withSentRecipient: otherAddress, wasSentByUD: false, transaction: transaction)

            XCTAssertFalse(message.shouldStartExpireTimer())
        }
    }

    func testShouldStartExpireTimerWithSentMessage() {
        write { transaction in
            let otherAddress = SignalServiceAddress(phoneNumber: "+12223334444")
            let thread = TSContactThread.getOrCreateThread(withContactAddress: otherAddress, transaction: transaction)
            let messageBuilder = TSOutgoingMessageBuilder.outgoingMessageBuilder(thread: thread, messageBody: nil)
            messageBuilder.timestamp = 100
            messageBuilder.expiresInSeconds = 10
            let message = messageBuilder.build()

            XCTAssertFalse(message.shouldStartExpireTimer())

            message.update(withSentRecipient: otherAddress, wasSentByUD: false, transaction: transaction)

            XCTAssertTrue(message.shouldStartExpireTimer())
        }
    }

    func testShouldNotStartExpireTimerWithAttemptingOutMessage() {
        write { transaction in
            let otherAddress = SignalServiceAddress(phoneNumber: "+12223334444")
            let thread = TSContactThread.getOrCreateThread(withContactAddress: otherAddress, transaction: transaction)
            let messageBuilder = TSOutgoingMessageBuilder.outgoingMessageBuilder(thread: thread, messageBody: nil)
            messageBuilder.timestamp = 100
            messageBuilder.expiresInSeconds = 10
            let message = messageBuilder.build()

            message.updateAllUnsentRecipientsAsSending(transaction: transaction)

            XCTAssertFalse(message.shouldStartExpireTimer())
        }
    }
}
