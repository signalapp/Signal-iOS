//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalServiceKit

class TSMessageTest: SSKBaseTest {
    private var thread: TSThread!

    override func setUp() {
        super.setUp()

        self.thread = TSContactThread.getOrCreateThread(contactAddress: SignalServiceAddress(phoneNumber: "fake-thread-id"))
    }

    func testExpiresAtWithoutStartedTimer() {
        let builder = TSOutgoingMessageBuilder.outgoingMessageBuilder(
            thread: self.thread,
            messageBody: AttachmentContentValidatorMock.mockValidatedBody("foo"),
        )
        builder.timestamp = 1
        builder.expiresInSeconds = 100

        let message = SSKEnvironment.shared.databaseStorageRef.read { builder.build(transaction: $0) }
        XCTAssertEqual(0, message.expiresAt)
    }

    func testExpiresAtWithStartedTimer() {
        let now = Date.ows_millisecondTimestamp()
        let expirationSeconds: UInt32 = 10

        let builder = TSOutgoingMessageBuilder.outgoingMessageBuilder(
            thread: self.thread,
            messageBody: AttachmentContentValidatorMock.mockValidatedBody("foo"),
        )
        builder.timestamp = 1
        builder.expiresInSeconds = expirationSeconds
        builder.expireStartedAt = now

        let message = SSKEnvironment.shared.databaseStorageRef.read { builder.build(transaction: $0) }
        XCTAssertEqual(now + UInt64(expirationSeconds * 1000), message.expiresAt)
    }

    func testCanBeRemotelyDeleted() {
        let now = Date.ows_millisecondTimestamp()

        do {
            let builder = TSOutgoingMessageBuilder.outgoingMessageBuilder(thread: self.thread)
            builder.timestamp = now - UInt64.minuteInMs
            let message = SSKEnvironment.shared.databaseStorageRef.read { builder.build(transaction: $0) }

            XCTAssert(message.canBeRemotelyDeleted)
        }

        do {
            let builder: TSIncomingMessageBuilder = .withDefaultValues(thread: self.thread)
            builder.timestamp = now - UInt64.minuteInMs
            let message = builder.build()

            XCTAssertFalse(message.canBeRemotelyDeleted)
        }

        do {
            let builder = TSOutgoingMessageBuilder.outgoingMessageBuilder(thread: self.thread)
            builder.timestamp = now - UInt64.minuteInMs
            let message = SSKEnvironment.shared.databaseStorageRef.read { builder.build(transaction: $0) }
            SSKEnvironment.shared.databaseStorageRef.write { transaction in
                message.anyInsert(transaction: transaction)
                message.updateWithRemotelyDeletedAndRemoveRenderableContent(with: transaction)
            }

            XCTAssertFalse(message.canBeRemotelyDeleted)
        }

        do {
            let builder = TSOutgoingMessageBuilder.outgoingMessageBuilder(thread: self.thread)
            builder.timestamp = now - UInt64.minuteInMs
            builder.giftBadge = OWSGiftBadge(redemptionCredential: Data())
            let message = SSKEnvironment.shared.databaseStorageRef.read { builder.build(transaction: $0) }

            XCTAssertFalse(message.canBeRemotelyDeleted)
        }

        do {
            let builder = TSOutgoingMessageBuilder.outgoingMessageBuilder(thread: self.thread)
            builder.timestamp = now + UInt64.minuteInMs
            let message = SSKEnvironment.shared.databaseStorageRef.read { builder.build(transaction: $0) }

            XCTAssertTrue(message.canBeRemotelyDeleted)
        }

        do {
            let builder = TSOutgoingMessageBuilder.outgoingMessageBuilder(thread: self.thread)
            builder.timestamp = now + (25 * UInt64.hourInMs)
            let message = SSKEnvironment.shared.databaseStorageRef.read { builder.build(transaction: $0) }

            XCTAssertTrue(message.canBeRemotelyDeleted)
        }

        do {
            let builder = TSOutgoingMessageBuilder.outgoingMessageBuilder(thread: self.thread)
            builder.timestamp = now - (25 * UInt64.hourInMs)
            let message = SSKEnvironment.shared.databaseStorageRef.read { builder.build(transaction: $0) }

            XCTAssertFalse(message.canBeRemotelyDeleted)
        }
    }
}
