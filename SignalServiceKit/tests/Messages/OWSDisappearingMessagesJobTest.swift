//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
import SignalServiceKit

final class OWSDisappearingMessagesJobTest: SSKBaseTestSwift {
    private func message(
        withBody body: String,
        expiresInSeconds: UInt32,
        expireStartedAt: UInt64
    ) -> TSMessage {
        let localAddress = SignalServiceAddress(uuid: UUID())
        let thread = TSContactThread.getOrCreateThread(contactAddress: localAddress)
        let messageBuilder = TSIncomingMessageBuilder.incomingMessageBuilder(
            thread: thread,
            messageBody: body
        )
        messageBuilder.timestamp = 1234
        messageBuilder.expiresInSeconds = expiresInSeconds
        messageBuilder.expireStartedAt = expireStartedAt
        return messageBuilder.build()
    }

    func testRemoveAnyExpiredMessage() {
        let now = Date.ows_millisecondTimestamp()
        let expiredMessage1 = message(
            withBody: "expired message 1",
            expiresInSeconds: 1,
            expireStartedAt: now - 20_000
        )
        let expiredMessage2 = message(
            withBody: "expired message 2",
            expiresInSeconds: 2,
            expireStartedAt: now - 2001
        )
        let notYetExpiredMessage = message(
            withBody: "not yet expired",
            expiresInSeconds: 20,
            expireStartedAt: now - 10_000
        )
        let messageThatDoesntExpire = message(
            withBody: "message that doesn't expire",
            expiresInSeconds: 0,
            expireStartedAt: 0
        )

        write { transaction in
            expiredMessage1.anyInsert(transaction: transaction)
            expiredMessage2.anyInsert(transaction: transaction)
            notYetExpiredMessage.anyInsert(transaction: transaction)
            messageThatDoesntExpire.anyInsert(transaction: transaction)
        }

        let job = OWSDisappearingMessagesJob.shared

        read { transaction in
            let messageCount = TSMessage.anyCount(transaction: transaction)
            XCTAssertEqual(messageCount, 4, "Test is not set up correctly")
        }

        job.syncPassForTests()

        read { transaction in
            let messageCount = TSMessage.anyCount(transaction: transaction)
            XCTAssertEqual(messageCount, 2)
        }
    }
}
