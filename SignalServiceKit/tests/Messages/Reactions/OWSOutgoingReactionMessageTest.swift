//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
import SignalServiceKit

class OWSOutgoingReactionMessageTest: SSKBaseTestSwift {
    private lazy var reactionMessage: OWSOutgoingReactionMessage = {
        write { transaction in
            let thread = TSContactThread.getOrCreateThread(
                withContactAddress: SignalServiceAddress(phoneNumber: "+12223334444"),
                transaction: transaction
            )

            let messageBuilder = TSOutgoingMessageBuilder.outgoingMessageBuilder(thread: thread, messageBody: nil)
            messageBuilder.timestamp = 100
            let message = messageBuilder.build(transaction: transaction)

            return OWSOutgoingReactionMessage(
                thread: thread,
                message: message,
                emoji: "🔮",
                isRemoving: false,
                expiresInSeconds: 1234,
                transaction: transaction
            )
        }
    }()

    func testIsUrgent() throws {
        XCTAssertTrue(reactionMessage.isUrgent)
    }

    func testShouldBeSaved() throws {
        // Reactions should be saved, but their outgoing messages are not. For example,
        // if I react with 🔮, we save that reaction, but we don't save the message that
        // tells everyone about that reaction.
        XCTAssertFalse(reactionMessage.shouldBeSaved)
    }
}
