//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalCoreKit
import XCTest

@testable import SignalServiceKit

final class DisappearingMessageFinderTest: SSKBaseTestSwift {
    private var finder = DisappearingMessagesFinder()
    private var now: UInt64 = 0

    override func setUp() {
        super.setUp()
        finder = DisappearingMessagesFinder()
        now = Date.ows_millisecondTimestamp()
    }

    func localAddress() -> SignalServiceAddress {
        SignalServiceAddress(phoneNumber: "+12225550123")
    }

    private lazy var otherAddress = SignalServiceAddress(serviceId: Aci.randomForTesting(), phoneNumber: "+13335550198")

    func thread(with transaction: SDSAnyWriteTransaction) -> TSThread {
        TSContactThread.getOrCreateThread(
            withContactAddress: otherAddress,
            transaction: transaction
        )
    }

    @discardableResult
    func incomingMessage(
        withBody body: String,
        expiresInSeconds: UInt32,
        expireStartedAt: UInt64,
        markAsRead: Bool = false
    ) -> TSIncomingMessage {
        write { transaction -> TSIncomingMessage in
            // It only makes sense to "mark as read" if expiration hasn't started,
            // since we don't start expiration for unread incoming messages.
            owsAssert(!markAsRead || expireStartedAt == 0)

            let thread = self.thread(with: transaction)

            let incomingMessageBuilder = TSIncomingMessageBuilder(thread: thread, messageBody: body)
            incomingMessageBuilder.timestamp = 1
            incomingMessageBuilder.authorAci = AciObjC(otherAddress.aci!)
            incomingMessageBuilder.expiresInSeconds = expiresInSeconds
            let message = incomingMessageBuilder.build()
            message.anyInsert(transaction: transaction)

            if expireStartedAt > 0 {
                message.markAsRead(
                    atTimestamp: expireStartedAt,
                    thread: thread,
                    circumstance: .onLinkedDevice,
                    shouldClearNotifications: true,
                    transaction: transaction
                )
            } else if markAsRead {
                message.markAsRead(
                    atTimestamp: now - 1000,
                    thread: thread,
                    circumstance: .onLinkedDevice,
                    shouldClearNotifications: true,
                    transaction: transaction
                )
            }

            return message
        }
    }

    @discardableResult
    func outgoingMessage(
        withBody body: String,
        expiresInSeconds: UInt32,
        expireStartedAt: UInt64
    ) -> TSOutgoingMessage {
        write { transaction in
            let thread = self.thread(with: transaction)

            let messageBuilder = TSOutgoingMessageBuilder(thread: thread, messageBody: body)
            messageBuilder.expiresInSeconds = expiresInSeconds
            messageBuilder.expireStartedAt = expireStartedAt

            let message = messageBuilder.build(transaction: transaction)
            message.anyInsert(transaction: transaction)
            return message
        }
    }

    func testExpiredMessages() {
        let expiredMessage1 = incomingMessage(
            withBody: "expiredMessage1",
            expiresInSeconds: 2,
            expireStartedAt: now - 2001
        )
        let expiredMessage2 = incomingMessage(
            withBody: "expiredMessage2",
            expiresInSeconds: 1,
            expireStartedAt: now - 20000
        )

        incomingMessage(
            withBody: "notYetExpiredMessage",
            expiresInSeconds: 20,
            expireStartedAt: now - 10000
        )
        incomingMessage(
            withBody: "unreadExpiringMessage",
            expiresInSeconds: 10,
            expireStartedAt: 0
        )
        incomingMessage(
            withBody: "unexpiringMessage",
            expiresInSeconds: 0,
            expireStartedAt: 0
        )
        incomingMessage(
            withBody: "unexpiringMessage2",
            expiresInSeconds: 0,
            expireStartedAt: 0
        )

        var actualMessageIds = Set<String>()
        read { transaction in
            for message in finder.fetchExpiredMessages(transaction: transaction) {
                actualMessageIds.insert(message.uniqueId)
            }
        }

        let expectedMessageIds = Set<String>([expiredMessage1.uniqueId, expiredMessage2.uniqueId])
        XCTAssertEqual(expectedMessageIds, actualMessageIds)
    }

    func testUnstartedExpiredMessagesForThread() {
        let expiredIncomingMessage = incomingMessage(
            withBody: "incoming expiredMessage",
            expiresInSeconds: 2,
            expireStartedAt: now - 2001
        )
        let notYetExpiredIncomingMessage = incomingMessage(
            withBody: "incoming notYetExpiredMessage",
            expiresInSeconds: 20,
            expireStartedAt: now - 10000
        )
        let unreadExpiringIncomingMessage = incomingMessage(
            withBody: "incoming unreadExpiringMessage",
            expiresInSeconds: 10,
            expireStartedAt: 0
        )
        let readExpiringIncomingMessage = incomingMessage(
            withBody: "incoming readExpiringMessage",
            expiresInSeconds: 10,
            expireStartedAt: 0,
            markAsRead: true
        )
        let unExpiringIncomingMessage = incomingMessage(
            withBody: "incoming unexpiringMessage",
            expiresInSeconds: 0,
            expireStartedAt: 0
        )
        let unExpiringIncomingMessage2 = incomingMessage(
            withBody: "incoming unexpiringMessage2",
            expiresInSeconds: 0,
            expireStartedAt: 0
        )

        let expiredOutgoingMessage = outgoingMessage(
            withBody: "outgoing expiredMessage",
            expiresInSeconds: 2,
            expireStartedAt: now - 2001
        )
        let notYetExpiredOutgoingMessage = outgoingMessage(
            withBody: "outgoing notYetExpiredMessage",
            expiresInSeconds: 20,
            expireStartedAt: now - 10000
        )
        let expiringUnsentOutgoingMessage = outgoingMessage(
            withBody: "expiringUnsentOutgoingMessage",
            expiresInSeconds: 10,
            expireStartedAt: 0
        )
        let expiringSentOutgoingMessage = outgoingMessage(
            withBody: "expiringSentOutgoingMessage",
            expiresInSeconds: 10,
            expireStartedAt: 0
        )
        let expiringDeliveredOutgoingMessage = outgoingMessage(
            withBody: "expiringDeliveredOutgoingMessage",
            expiresInSeconds: 10,
            expireStartedAt: 0
        )
        let expiringDeliveredAndReadOutgoingMessage = outgoingMessage(
            withBody: "expiringDeliveredAndReadOutgoingMessage",
            expiresInSeconds: 10,
            expireStartedAt: 0
        )
        let unExpiringOutgoingMessage = outgoingMessage(
            withBody: "outgoing unexpiringMessage",
            expiresInSeconds: 0,
            expireStartedAt: 0
        )
        let unExpiringOutgoingMessage2 = outgoingMessage(
            withBody: "outgoing unexpiringMessage2",
            expiresInSeconds: 0,
            expireStartedAt: 0
        )

        write { transaction in
            // Mark outgoing message as "sent", "delivered" or "delivered and read" using production methods.
            expiringSentOutgoingMessage.update(
                withSentRecipient: otherAddress.serviceIdObjC!,
                wasSentByUD: false,
                transaction: transaction
            )
            expiringDeliveredOutgoingMessage.update(
                withDeliveredRecipient: otherAddress,
                deviceId: 0,
                deliveryTimestamp: Date.ows_millisecondTimestamp(),
                context: PassthroughDeliveryReceiptContext(),
                tx: transaction
            )
            let nowMs = Date.ows_millisecondTimestamp()
            expiringDeliveredAndReadOutgoingMessage.update(
                withReadRecipient: otherAddress,
                deviceId: 0,
                readTimestamp: nowMs,
                tx: transaction
            )
        }

        let shouldBeExpiringMessages: [TSMessage] = [
            expiredIncomingMessage,
            notYetExpiredIncomingMessage,
            readExpiringIncomingMessage,
            expiringSentOutgoingMessage,
            expiringDeliveredOutgoingMessage,
            expiringDeliveredAndReadOutgoingMessage,
            expiredOutgoingMessage,
            notYetExpiredOutgoingMessage
        ]
        let shouldNotBeExpiringMessages: [TSMessage] = [
            unreadExpiringIncomingMessage,
            unExpiringIncomingMessage,
            unExpiringIncomingMessage2,
            expiringUnsentOutgoingMessage,
            unExpiringOutgoingMessage,
            unExpiringOutgoingMessage2
        ]

        write { transaction in
            for oldMessage in shouldBeExpiringMessages {
                let messageId = oldMessage.uniqueId
                let shouldBeExpiring = true
                let message = TSMessage.anyFetch(uniqueId: messageId, transaction: transaction) as? TSMessage
                let logTag = "\(messageId) \(oldMessage.body ?? "nil")"
                guard let message else {
                    XCTFail("Missing message: \(logTag)")
                    continue
                }
                XCTAssertEqual(shouldBeExpiring, message.shouldStartExpireTimer(), logTag)
                XCTAssertEqual(shouldBeExpiring, message.storedShouldStartExpireTimer, logTag)
                XCTAssertTrue(message.expiresAt > 0, logTag)
            }

            for oldMessage in shouldNotBeExpiringMessages {
                let messageId = oldMessage.uniqueId
                let shouldBeExpiring = false
                let message = TSMessage.anyFetch(uniqueId: messageId, transaction: transaction) as? TSMessage
                let logTag = "\(messageId) \(oldMessage.body ?? "nil")"
                guard let message else {
                    XCTFail("Missing message: \(logTag)")
                    continue
                }
                XCTAssertEqual(shouldBeExpiring, message.shouldStartExpireTimer(), logTag)
                XCTAssertEqual(shouldBeExpiring, message.storedShouldStartExpireTimer, logTag)
                XCTAssertEqual(message.expiresAt, 0, logTag)
            }

            let unstartedExpiringMessages = self.finder.fetchUnstartedExpiringMessages(
                in: self.thread(with: transaction),
                transaction: transaction
            )
            XCTAssert(unstartedExpiringMessages.isEmpty)
        }
    }

    func nextExpirationTimestamp() -> UInt64? {
        var result: UInt64?
        read { transaction in
            result = finder.nextExpirationTimestamp(transaction: transaction)
        }
        return result
    }

    func testNextExpirationTimestampNilWhenNoExpiringMessages() {
        // Sanity check.
        XCTAssertNil(nextExpirationTimestamp())

        incomingMessage(
            withBody: "unexpiringMessage",
            expiresInSeconds: 0,
            expireStartedAt: 0
        )
        XCTAssertNil(nextExpirationTimestamp())
    }

    func testNextExpirationTimestampNotNilWithUpcomingExpiringMessages() {
        incomingMessage(
            withBody: "soonToExpireMessage",
            expiresInSeconds: 10,
            expireStartedAt: now - 9000
        )

        XCTAssertNotNil(nextExpirationTimestamp())
        XCTAssertEqual(now + 1000, nextExpirationTimestamp() ?? 0)

        // expired message should take precedence
        incomingMessage(
            withBody: "expiredMessage",
            expiresInSeconds: 10,
            expireStartedAt: now - 11000
        )
        XCTAssertNotNil(nextExpirationTimestamp())
        XCTAssertEqual(now - 1000, nextExpirationTimestamp() ?? 0)
    }
}
