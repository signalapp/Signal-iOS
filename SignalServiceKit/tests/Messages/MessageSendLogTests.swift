//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import LibSignalClient
import XCTest

@testable import SignalServiceKit

class MessageSendLogTests: SSKBaseTestSwift {
    private var messageSendLog: MessageSendLog { SSKEnvironment.shared.messageSendLogRef }

    func testStoreAndRetrieveValidPayload() throws {
        try databaseStorage.write { writeTx in
            // Create and save the message payload
            let newMessage = createOutgoingMessage(transaction: writeTx)
            let payloadData = CommonGenerator.sentence.data(using: .utf8)!
            let payloadId = try XCTUnwrap(messageSendLog.recordPayload(payloadData, for: newMessage, tx: writeTx))

            // "Send" the message to a recipient
            let serviceId = Aci.randomForTesting()
            let deviceId = UInt32.random(in: 0..<100)
            messageSendLog.recordPendingDelivery(
                payloadId: payloadId,
                recipientAci: serviceId,
                recipientDeviceId: deviceId,
                message: newMessage,
                tx: writeTx
            )

            // Re-fetch the payload
            let fetchedPayload = messageSendLog.fetchPayload(
                recipientAci: serviceId,
                recipientDeviceId: deviceId,
                timestamp: newMessage.timestamp,
                tx: writeTx
            )!

            XCTAssertEqual(fetchedPayload.contentHint, .implicit)
            XCTAssertEqual(fetchedPayload.plaintextContent, payloadData)
            XCTAssertEqual(fetchedPayload.uniqueThreadId, newMessage.uniqueThreadId)
        }
    }

    func testStoreAndRetrievePayloadForInvalidRecipient() throws {
        try databaseStorage.write { writeTx in
            // Create and save the message payload
            let newMessage = createOutgoingMessage(transaction: writeTx)
            let payloadData = CommonGenerator.sentence.data(using: .utf8)!
            let payloadId = try XCTUnwrap(messageSendLog.recordPayload(payloadData, for: newMessage, tx: writeTx))

            // "Send" the message to one recipient
            let serviceId = Aci.randomForTesting()
            let deviceId = UInt32.random(in: 0..<100)
            messageSendLog.recordPendingDelivery(
                payloadId: payloadId,
                recipientAci: serviceId,
                recipientDeviceId: deviceId,
                message: newMessage,
                tx: writeTx
            )

            // Expect no results when re-fetching the payload with a different deviceId
            XCTAssertNil(messageSendLog.fetchPayload(
                recipientAci: serviceId,
                recipientDeviceId: deviceId+1,
                timestamp: newMessage.timestamp,
                tx: writeTx
            ))

            // Expect no results when re-fetching the payload with a different address
            XCTAssertNil(messageSendLog.fetchPayload(
                recipientAci: Aci.randomForTesting(),
                recipientDeviceId: deviceId,
                timestamp: newMessage.timestamp,
                tx: writeTx
            ))
        }
    }

    func testStoreAndRetrievePayloadForDeliveredRecipient() throws {
        try databaseStorage.write { writeTx in
            // Create and save the message payload
            let newMessage = createOutgoingMessage(transaction: writeTx)
            let payloadData = CommonGenerator.sentence.data(using: .utf8)!
            let payloadId = try XCTUnwrap(messageSendLog.recordPayload(payloadData, for: newMessage, tx: writeTx))

            // "Send" the message to two devices
            let serviceId = Aci.randomForTesting()
            for deviceId: UInt32 in [0, 1] {
                messageSendLog.recordPendingDelivery(
                    payloadId: payloadId,
                    recipientAci: serviceId,
                    recipientDeviceId: deviceId,
                    message: newMessage,
                    tx: writeTx
                )
            }

            // Mark the payload as "delivered" to the first device
            messageSendLog.recordSuccessfulDelivery(
                message: newMessage,
                recipientAci: serviceId,
                recipientDeviceId: 0,
                tx: writeTx
            )

            // Expect no results when re-fetching the payload for the first device
            XCTAssertNil(messageSendLog.fetchPayload(
                recipientAci: serviceId,
                recipientDeviceId: 0,
                timestamp: newMessage.timestamp,
                tx: writeTx
            ))

            // Expect some results when re-fetching the payload for the second device
            XCTAssertNotNil(messageSendLog.fetchPayload(
                recipientAci: serviceId,
                recipientDeviceId: 1,
                timestamp: newMessage.timestamp,
                tx: writeTx
            ))
        }
    }

    func testStoreAndRetrieveExpiredPayload() throws {
        try databaseStorage.write { writeTx in
            // Create and save the message payload. Outgoing message date is long ago
            let newMessage = createOutgoingMessage(date: Date(timeIntervalSince1970: 10000), transaction: writeTx)
            let payloadData = CommonGenerator.sentence.data(using: .utf8)!
            let payloadId = try XCTUnwrap(messageSendLog.recordPayload(payloadData, for: newMessage, tx: writeTx))

            // "Send" the message to a recipient
            let serviceId = Aci.randomForTesting()
            let deviceId = UInt32.random(in: 0..<100)
            messageSendLog.recordPendingDelivery(
                payloadId: payloadId,
                recipientAci: serviceId,
                recipientDeviceId: deviceId,
                message: newMessage,
                tx: writeTx
            )

            // Expect no results when re-fetching the payload since it's expired
            XCTAssertNil(messageSendLog.fetchPayload(
                recipientAci: serviceId,
                recipientDeviceId: deviceId,
                timestamp: newMessage.timestamp,
                tx: writeTx
            ))
        }
    }

    func testFinalDeliveryRemovesPayload() throws {
        try databaseStorage.write { writeTx in
            // Create and save the message payload
            let newMessage = createOutgoingMessage(transaction: writeTx)
            let payloadData = CommonGenerator.sentence.data(using: .utf8)!
            let payloadId = try XCTUnwrap(messageSendLog.recordPayload(payloadData, for: newMessage, tx: writeTx))

            // "Send" the message to one recipient, two devices
            let serviceId = Aci.randomForTesting()
            for deviceId: UInt32 in [0, 1] {
                messageSendLog.recordPendingDelivery(
                    payloadId: payloadId,
                    recipientAci: serviceId,
                    recipientDeviceId: deviceId,
                    message: newMessage,
                    tx: writeTx
                )
            }
            messageSendLog.sendComplete(message: newMessage, tx: writeTx)

            // Deliver to first device
            messageSendLog.recordSuccessfulDelivery(
                message: newMessage,
                recipientAci: serviceId,
                recipientDeviceId: 0,
                tx: writeTx
            )

            // Verify the payload still exists
            XCTAssertTrue(isPayloadAlive(index: payloadId, transaction: writeTx))

            // Deliver to second device
            messageSendLog.recordSuccessfulDelivery(
                message: newMessage,
                recipientAci: serviceId,
                recipientDeviceId: 1,
                tx: writeTx
            )

            // Verify the payload was deleted
            XCTAssertFalse(isPayloadAlive(index: payloadId, transaction: writeTx))
        }
    }

    func testReceiveDeliveryBeforeSendFinished() throws {
        try databaseStorage.write { writeTx in
            // Create and save the message payload
            let newMessage = createOutgoingMessage(transaction: writeTx)
            let payloadData = CommonGenerator.sentence.data(using: .utf8)!
            let payloadId = try XCTUnwrap(messageSendLog.recordPayload(payloadData, for: newMessage, tx: writeTx))

            let serviceId = Aci.randomForTesting()

            // "Send" the message to one device. It acks delivery
            messageSendLog.recordPendingDelivery(
                payloadId: payloadId,
                recipientAci: serviceId,
                recipientDeviceId: 0,
                message: newMessage,
                tx: writeTx
            )
            messageSendLog.recordSuccessfulDelivery(
                message: newMessage,
                recipientAci: serviceId,
                recipientDeviceId: 0,
                tx: writeTx
            )

            // Verify the payload still exists since we haven't finished sending
            XCTAssertTrue(isPayloadAlive(index: payloadId, transaction: writeTx))

            // "Send" the message to two more devices. Mark send as complete
            for deviceId: UInt32 in [1, 2] {
                messageSendLog.recordPendingDelivery(
                    payloadId: payloadId,
                    recipientAci: serviceId,
                    recipientDeviceId: deviceId,
                    message: newMessage,
                    tx: writeTx
                )
            }
            messageSendLog.sendComplete(message: newMessage, tx: writeTx)

            // Deliver to second device
            messageSendLog.recordSuccessfulDelivery(
                message: newMessage,
                recipientAci: serviceId,
                recipientDeviceId: 1,
                tx: writeTx
            )

            // Verify the payload still exists
            XCTAssertTrue(isPayloadAlive(index: payloadId, transaction: writeTx))

            // Deliver to third device
            messageSendLog.recordSuccessfulDelivery(
                message: newMessage,
                recipientAci: serviceId,
                recipientDeviceId: 2,
                tx: writeTx
            )

            // Verify the payload was deleted
            XCTAssertFalse(isPayloadAlive(index: payloadId, transaction: writeTx))
        }
    }

    func testPartialFailureReusesPayloadEntry() throws {
        try databaseStorage.write { writeTx in
            // Create and save the message payload
            let newMessage = createOutgoingMessage(transaction: writeTx)
            let payloadData = CommonGenerator.sentence.data(using: .utf8)!
            let initialPayloadId = try XCTUnwrap(messageSendLog.recordPayload(payloadData, for: newMessage, tx: writeTx))

            let serviceId = Aci.randomForTesting()

            // "Send" the message to one device. Complete send but don't mark as delivered.
            messageSendLog.recordPendingDelivery(
                payloadId: initialPayloadId,
                recipientAci: serviceId,
                recipientDeviceId: 0,
                message: newMessage,
                tx: writeTx
            )
            messageSendLog.sendComplete(message: newMessage, tx: writeTx)

            // Simulate a "retry" of a failed send. Try a fresh insert of the payload data
            // Then send to another device and complete the send.
            let retryPayloadId = try XCTUnwrap(messageSendLog.recordPayload(payloadData, for: newMessage, tx: writeTx))
            messageSendLog.recordPendingDelivery(
                payloadId: initialPayloadId,
                recipientAci: serviceId,
                recipientDeviceId: 1,
                message: newMessage,
                tx: writeTx
            )
            messageSendLog.sendComplete(message: newMessage, tx: writeTx)

            // Both payloadIds should be the same. The payload is still alive.
            XCTAssertEqual(initialPayloadId, retryPayloadId)
            XCTAssertTrue(isPayloadAlive(index: initialPayloadId, transaction: writeTx))

            // Deliver to first device
            messageSendLog.recordSuccessfulDelivery(
                message: newMessage,
                recipientAci: serviceId,
                recipientDeviceId: 0,
                tx: writeTx
            )

            // Verify the payload still exists
            XCTAssertTrue(isPayloadAlive(index: initialPayloadId, transaction: writeTx))

            // Deliver to second device
            messageSendLog.recordSuccessfulDelivery(
                message: newMessage,
                recipientAci: serviceId,
                recipientDeviceId: 1,
                tx: writeTx
            )

            // Verify the payload was deleted
            XCTAssertFalse(isPayloadAlive(index: initialPayloadId, transaction: writeTx))
        }
    }

    func testRetryPartialFailureAfterAllInitialRecipientsAcked() throws {
        try databaseStorage.write { writeTx in
            // Create and save the message payload
            let newMessage = createOutgoingMessage(transaction: writeTx)
            let payloadData = CommonGenerator.sentence.data(using: .utf8)!
            let serviceId = Aci.randomForTesting()

            // Record + Send + Deliver + Complete (Deliver and Complete can happen in either order)
            let initialPayloadId = try XCTUnwrap(messageSendLog.recordPayload(payloadData, for: newMessage, tx: writeTx))
            messageSendLog.recordPendingDelivery(
                payloadId: initialPayloadId,
                recipientAci: serviceId,
                recipientDeviceId: 0,
                message: newMessage,
                tx: writeTx
            )
            messageSendLog.recordSuccessfulDelivery(
                message: newMessage,
                recipientAci: serviceId,
                recipientDeviceId: 0,
                tx: writeTx
            )
            messageSendLog.sendComplete(message: newMessage, tx: writeTx)

            // Verify payload is deleted:
            XCTAssertFalse(isPayloadAlive(index: initialPayloadId, transaction: writeTx))

            // Record + Send + Complete + Deliver (Deliver and Complete can happen in either order)
            let secondPayloadId = try XCTUnwrap(messageSendLog.recordPayload(payloadData, for: newMessage, tx: writeTx))
            messageSendLog.recordPendingDelivery(
                payloadId: secondPayloadId,
                recipientAci: serviceId,
                recipientDeviceId: 1,
                message: newMessage,
                tx: writeTx
            )
            messageSendLog.sendComplete(message: newMessage, tx: writeTx)
            messageSendLog.recordSuccessfulDelivery(
                message: newMessage,
                recipientAci: serviceId,
                recipientDeviceId: 1,
                tx: writeTx
            )

            // Verify payload is deleted:
            XCTAssertFalse(isPayloadAlive(index: secondPayloadId, transaction: writeTx))
            // Verify the ID was not reusued
            XCTAssertNotEqual(initialPayloadId, secondPayloadId)
        }
    }

    // Test disabled since it exercises an owsFailDebug()
    // Works correctly if assertions are disabled and the test is enabled.
    func testPlaintextMismatchFails() throws {
        try databaseStorage.write { writeTx in
            // Create and save the message payload
            let newMessage = createOutgoingMessage(transaction: writeTx)
            let payloadData = CommonGenerator.sentence.data(using: .utf8)!

            let initialPayloadId = try XCTUnwrap(messageSendLog.recordPayload(payloadData, for: newMessage, tx: writeTx))

            // append a byte so the payload doesn't match 
            let secondPayloadId = try XCTUnwrap(messageSendLog.recordPayload(payloadData + Data([1]), for: newMessage, tx: writeTx))

            XCTAssertNotNil(initialPayloadId)
            XCTAssertNil(secondPayloadId)
        }
    }

    func testDeleteMessageWithOnePayload() throws {
        try databaseStorage.write { writeTx in
            // Create and save the message payload
            let newMessage = createOutgoingMessage(transaction: writeTx)
            let payloadData = CommonGenerator.sentence.data(using: .utf8)!
            let payloadId = try XCTUnwrap(messageSendLog.recordPayload(payloadData, for: newMessage, tx: writeTx))

            // "Send" the message to a recipient
            let serviceId = Aci.randomForTesting()
            let deviceId = UInt32.random(in: 0..<100)
            messageSendLog.recordPendingDelivery(
                payloadId: payloadId,
                recipientAci: serviceId,
                recipientDeviceId: deviceId,
                message: newMessage,
                tx: writeTx
            )

            // Delete the message
            messageSendLog.deleteAllPayloadsForInteraction(newMessage, tx: writeTx)

            // Verify the corresponding payload was deleted
            XCTAssertFalse(isPayloadAlive(index: payloadId, transaction: writeTx))
        }
    }

    func testDeleteMessageWithManyPayloads() throws {
        try databaseStorage.write { writeTx in
            // Create and save several message payloads
            let message1 = createOutgoingMessage(transaction: writeTx)
            let data1 = CommonGenerator.sentence.data(using: .utf8)!
            let index1 = try XCTUnwrap(messageSendLog.recordPayload(data1, for: message1, tx: writeTx))
            let message2 = createOutgoingMessage(transaction: writeTx)
            let data2 = CommonGenerator.sentence.data(using: .utf8)!
            let index2 = try XCTUnwrap(messageSendLog.recordPayload(data2, for: message2, tx: writeTx))

            let readReceiptMessage = createOutgoingMessage(relatedMessageIds: [message1.uniqueId, message2.uniqueId], transaction: writeTx)
            let data3 = CommonGenerator.sentence.data(using: .utf8)!
            let index3 = try XCTUnwrap(messageSendLog.recordPayload(data3, for: readReceiptMessage, tx: writeTx))

            // "Send" the messages to a recipient
            let serviceId = Aci.randomForTesting()
            let deviceId = UInt32.random(in: 0..<100)
            for index in [index1, index2, index3] {
                messageSendLog.recordPendingDelivery(
                    payloadId: index,
                    recipientAci: serviceId,
                    recipientDeviceId: deviceId,
                    message: message1,
                    tx: writeTx
                )
            }

            // Delete message1.
            messageSendLog.deleteAllPayloadsForInteraction(message1, tx: writeTx)

            // We expect that the read receipt message is deleted because it relates to the deleted message
            // We expect message2's payload to stick around, because none of its content is dependent on message1
            XCTAssertFalse(isPayloadAlive(index: index1, transaction: writeTx))
            XCTAssertTrue(isPayloadAlive(index: index2, transaction: writeTx))
            XCTAssertFalse(isPayloadAlive(index: index3, transaction: writeTx))
        }
    }

    func testCleanupExpiredPayloads() throws {
        let (oldId, newId) = try databaseStorage.write { writeTx in
            let oldMessage = createOutgoingMessage(date: Date(timeIntervalSince1970: 1000), transaction: writeTx)
            let oldData = CommonGenerator.sentence.data(using: .utf8)!
            let oldId = try XCTUnwrap(messageSendLog.recordPayload(oldData, for: oldMessage, tx: writeTx))
            let newMessage = createOutgoingMessage(transaction: writeTx)
            let newData = CommonGenerator.sentence.data(using: .utf8)!
            let newId = try XCTUnwrap(messageSendLog.recordPayload(newData, for: newMessage, tx: writeTx))

            // Verify both messages exist
            XCTAssertTrue(isPayloadAlive(index: oldId, transaction: writeTx))
            XCTAssertTrue(isPayloadAlive(index: newId, transaction: writeTx))

            return (oldId, newId)
        }

        // Kick off cleanup
        let testScheduler = TestScheduler()
        messageSendLog.schedulePeriodicCleanup(on: testScheduler)
        testScheduler.tick()

        databaseStorage.write { writeTx in
            // Verify only the old message was deleted
            XCTAssertFalse(isPayloadAlive(index: oldId, transaction: writeTx))
            XCTAssertTrue(isPayloadAlive(index: newId, transaction: writeTx))
        }
    }

    func testTimestampMismatch() throws {
        // IOS-1762: Greyson reported an issue where a resent message would have a timestamp mismatch on the outside vs
        // inside of the envelope. In his case, the outside had a timestamp of 1629210680139 versus the inside
        // which had 1629210680140.
        //
        // Casting back and forth from Date/TimeInterval and millisecond timestamps would lead to float math
        // incorrectly coercing to the wrong timestamp. In this case, constructing a Date from that millisecond
        // timestamp would result in a time interval of 1629210680.1399999. Reconverting back to a timestamp and
        // we get 1629210680139.
        try databaseStorage.write { writeTx in
            let messageSendLog = MessageSendLog(
                databaseStorage: databaseStorage,
                dateProvider: { Date(timeIntervalSince1970: 1629270000) }
            )

            let originalTimestamp: UInt64 = 1629210680140
            let originalDate = Date(millisecondsSince1970: originalTimestamp)
            XCTAssertEqual(originalDate.ows_millisecondsSince1970, originalTimestamp)

            let serviceId = Aci.randomForTesting()
            let message = createOutgoingMessage(date: originalDate, transaction: writeTx)
            let data = CommonGenerator.sentence.data(using: .utf8)!
            XCTAssertEqual(message.timestamp, originalTimestamp)

            let index = try XCTUnwrap(messageSendLog.recordPayload(data, for: message, tx: writeTx))
            messageSendLog.recordPendingDelivery(payloadId: index, recipientAci: serviceId, recipientDeviceId: 1, message: message, tx: writeTx)

            let fetchedPayload = messageSendLog.fetchPayload(
                recipientAci: serviceId,
                recipientDeviceId: 1,
                timestamp: originalTimestamp,
                tx: writeTx
            )
            XCTAssertEqual(fetchedPayload?.sentTimestamp, originalTimestamp)
        }
    }

    // MARK: - Helpers

    class MSLTestMessage: TSOutgoingMessage {
        override init(outgoingMessageWithBuilder outgoingMessageBuilder: TSOutgoingMessageBuilder, transaction: SDSAnyReadTransaction) {
            super.init(outgoingMessageWithBuilder: outgoingMessageBuilder, transaction: transaction)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        required init(dictionary dictionaryValue: [String: Any]!) throws {
            fatalError("init(dictionary:) has not been implemented")
        }

        var _contentHint: SealedSenderContentHint = .resendable
        override var contentHint: SealedSenderContentHint { _contentHint }

        var _relatedMessageIds: [String] = []
        override var relatedUniqueIds: Set<String> { Set(_relatedMessageIds) }
    }

    func createOutgoingMessage(
        date: Date? = nil,
        contentHint: SealedSenderContentHint = .implicit,
        relatedMessageIds: [String] = [],
        transaction writeTx: SDSAnyWriteTransaction
    ) -> TSOutgoingMessage {

        let resolvedDate = date ?? {
            let newDate = Date()
            usleep(2000)    // If we're taking the timestamp of Now, wait a bit to avoid collisions
            return newDate
        }()

        let builder = TSOutgoingMessageBuilder(thread: ContactThreadFactory().create(transaction: writeTx),
                                               timestamp: resolvedDate.ows_millisecondsSince1970)
        let testMessage = MSLTestMessage(outgoingMessageWithBuilder: builder, transaction: writeTx)
        testMessage._contentHint = contentHint
        testMessage._relatedMessageIds = [testMessage.uniqueId] + relatedMessageIds
        return testMessage
    }

    func isPayloadAlive(index: Int64, transaction writeTx: SDSAnyWriteTransaction) -> Bool {
        let count = try! MessageSendLog.Payload
            .filter(Column("payloadId") == index)
            .fetchCount(writeTx.unwrapGrdbWrite.database)
        return count > 0
    }
}
