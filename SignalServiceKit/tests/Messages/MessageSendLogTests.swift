//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import SignalServiceKit
import XCTest
import GRDB

class MessageSendLogTests: SSKBaseTestSwift {
    func testStoreAndRetrieveValidPayload() {
        databaseStorage.write { writeTx in
            // Create and save the message payload
            let newMessage = createOutgoingMessage(transaction: writeTx)
            let payloadData = CommonGenerator.sentence.data(using: .utf8)!
            let payloadIndex = MessageSendLog.recordPayload(payloadData, forMessageBeingSent: newMessage, transaction: writeTx) as! Int64

            // "Send" the message to a recipient
            let recipientAddress = CommonGenerator.address()
            let deviceId = Int64.random(in: 0..<100)
            MessageSendLog.recordPendingDelivery(
                payloadId: payloadIndex,
                recipientUuid: recipientAddress.uuid!,
                recipientDeviceId: deviceId,
                message: newMessage,
                transaction: writeTx)

            // Re-fetch the payload
            let fetchedPayload = MessageSendLog.fetchPayload(
                address: recipientAddress,
                deviceId: deviceId,
                timestamp: newMessage.timestamp,
                transaction: writeTx)!

            XCTAssertEqual(fetchedPayload.contentHint, .implicit)
            XCTAssertEqual(fetchedPayload.plaintextContent, payloadData)
            XCTAssertEqual(fetchedPayload.uniqueThreadId, newMessage.uniqueThreadId)
        }
    }

    func testStoreAndRetrievePayloadForInvalidRecipient() {
        databaseStorage.write { writeTx in
            // Create and save the message payload
            let newMessage = createOutgoingMessage(transaction: writeTx)
            let payloadData = CommonGenerator.sentence.data(using: .utf8)!
            let payloadIndex = MessageSendLog.recordPayload(payloadData, forMessageBeingSent: newMessage, transaction: writeTx) as! Int64

            // "Send" the message to one recipient
            let recipientAddress = CommonGenerator.address()
            let deviceId = Int64.random(in: 0..<100)
            MessageSendLog.recordPendingDelivery(
                payloadId: payloadIndex,
                recipientUuid: recipientAddress.uuid!,
                recipientDeviceId: deviceId,
                message: newMessage,
                transaction: writeTx)

            // Expect no results when re-fetching the payload with a different deviceId
            XCTAssertNil(MessageSendLog.fetchPayload(
                address: recipientAddress,
                deviceId: deviceId+1,
                timestamp: newMessage.timestamp,
                transaction: writeTx))

            // Expect no results when re-fetching the payload with a different address
            XCTAssertNil(MessageSendLog.fetchPayload(
                            address: CommonGenerator.address(),
                            deviceId: deviceId,
                            timestamp: newMessage.timestamp,
                            transaction: writeTx))
        }
    }

    func testStoreAndRetrievePayloadForDeliveredRecipient() {
        databaseStorage.write { writeTx in
            // Create and save the message payload
            let newMessage = createOutgoingMessage(transaction: writeTx)
            let payloadData = CommonGenerator.sentence.data(using: .utf8)!
            let payloadIndex = MessageSendLog.recordPayload(payloadData, forMessageBeingSent: newMessage, transaction: writeTx) as! Int64

            // "Send" the message to two devices
            let recipientAddress = CommonGenerator.address()
            for deviceId: Int64 in [0, 1] {
                MessageSendLog.recordPendingDelivery(
                    payloadId: payloadIndex,
                    recipientUuid: recipientAddress.uuid!,
                    recipientDeviceId: deviceId,
                    message: newMessage,
                    transaction: writeTx)
            }

            // Mark the payload as "delivered" to the first device
            MessageSendLog.recordSuccessfulDelivery(
                timestamp: newMessage.timestamp,
                recipientUuid: recipientAddress.uuid!,
                recipientDeviceId: 0,
                transaction: writeTx)

            // Expect no results when re-fetching the payload for the first device
            XCTAssertNil(MessageSendLog.fetchPayload(
                            address: recipientAddress,
                            deviceId: 0,
                            timestamp: newMessage.timestamp,
                            transaction: writeTx))

            // Expect some results when re-fetching the payload for the second device
            XCTAssertNotNil(MessageSendLog.fetchPayload(
                                address: recipientAddress,
                                deviceId: 1,
                                timestamp: newMessage.timestamp,
                                transaction: writeTx))
        }
    }

    func testStoreAndRetrieveExpiredPayload() {
        databaseStorage.write { writeTx in
            // Create and save the message payload. Outgoing message date is long ago
            let newMessage = createOutgoingMessage(date: Date(timeIntervalSince1970: 10000), transaction: writeTx)
            let payloadData = CommonGenerator.sentence.data(using: .utf8)!
            let payloadIndex = MessageSendLog.recordPayload(payloadData, forMessageBeingSent: newMessage, transaction: writeTx) as! Int64

            // "Send" the message to a recipient
            let recipientAddress = CommonGenerator.address()
            let deviceId = Int64.random(in: 0..<100)
            MessageSendLog.recordPendingDelivery(
                payloadId: payloadIndex,
                recipientUuid: recipientAddress.uuid!,
                recipientDeviceId: deviceId,
                message: newMessage,
                transaction: writeTx)

            // Expect no results when re-fetching the payload since it's expired
            XCTAssertNil(MessageSendLog.fetchPayload(
                            address: recipientAddress,
                            deviceId: deviceId,
                            timestamp: newMessage.timestamp,
                            transaction: writeTx))
        }
    }

    func testFinalDeliveryRemovesPayload() {
        databaseStorage.write { writeTx in
            // Create and save the message payload
            let newMessage = createOutgoingMessage(transaction: writeTx)
            let payloadData = CommonGenerator.sentence.data(using: .utf8)!
            let payloadIndex = MessageSendLog.recordPayload(payloadData, forMessageBeingSent: newMessage, transaction: writeTx) as! Int64

            // "Send" the message to one recipient, two devices
            let recipientAddress = CommonGenerator.address()
            for deviceId: Int64 in [0, 1] {
                MessageSendLog.recordPendingDelivery(
                    payloadId: payloadIndex,
                    recipientUuid: recipientAddress.uuid!,
                    recipientDeviceId: deviceId,
                    message: newMessage,
                    transaction: writeTx)
            }
            MessageSendLog.sendComplete(message: newMessage, transaction: writeTx)

            // Deliver to first device
            MessageSendLog.recordSuccessfulDelivery(
                timestamp: newMessage.timestamp,
                recipientUuid: recipientAddress.uuid!,
                recipientDeviceId: 0,
                transaction: writeTx)

            // Verify the payload still exists
            XCTAssertTrue(isPayloadAlive(index: payloadIndex, transaction: writeTx))

            // Deliver to second device
            MessageSendLog.recordSuccessfulDelivery(
                timestamp: newMessage.timestamp,
                recipientUuid: recipientAddress.uuid!,
                recipientDeviceId: 1,
                transaction: writeTx)

            // Verify the payload was deleted
            XCTAssertFalse(isPayloadAlive(index: payloadIndex, transaction: writeTx))
        }
    }

    func testReceiveDeliveryBeforeSendFinished() {
        databaseStorage.write { writeTx in
            // Create and save the message payload
            let newMessage = createOutgoingMessage(transaction: writeTx)
            let payloadData = CommonGenerator.sentence.data(using: .utf8)!
            let payloadIndex = MessageSendLog.recordPayload(payloadData, forMessageBeingSent: newMessage, transaction: writeTx) as! Int64

            let recipientAddress = CommonGenerator.address()

            // "Send" the message to one device. It acks delivery
            MessageSendLog.recordPendingDelivery(
                payloadId: payloadIndex,
                recipientUuid: recipientAddress.uuid!,
                recipientDeviceId: 0,
                message: newMessage,
                transaction: writeTx)
            MessageSendLog.recordSuccessfulDelivery(
                timestamp: newMessage.timestamp,
                recipientUuid: recipientAddress.uuid!,
                recipientDeviceId: 0,
                transaction: writeTx)

            // Verify the payload still exists since we haven't finished sending
            XCTAssertTrue(isPayloadAlive(index: payloadIndex, transaction: writeTx))

            // "Send" the message to two more devices. Mark send as complete
            for deviceId: Int64 in [1, 2] {
                MessageSendLog.recordPendingDelivery(
                    payloadId: payloadIndex,
                    recipientUuid: recipientAddress.uuid!,
                    recipientDeviceId: deviceId,
                    message: newMessage,
                    transaction: writeTx)
            }
            MessageSendLog.sendComplete(message: newMessage, transaction: writeTx)

            // Deliver to second device
            MessageSendLog.recordSuccessfulDelivery(
                timestamp: newMessage.timestamp,
                recipientUuid: recipientAddress.uuid!,
                recipientDeviceId: 1,
                transaction: writeTx)

            // Verify the payload still exists
            XCTAssertTrue(isPayloadAlive(index: payloadIndex, transaction: writeTx))

            // Deliver to third device
            MessageSendLog.recordSuccessfulDelivery(
                timestamp: newMessage.timestamp,
                recipientUuid: recipientAddress.uuid!,
                recipientDeviceId: 2,
                transaction: writeTx)

            // Verify the payload was deleted
            XCTAssertFalse(isPayloadAlive(index: payloadIndex, transaction: writeTx))
        }
    }

    func testPartialFailureReusesPayloadEntry() {
        databaseStorage.write { writeTx in
            // Create and save the message payload
            let newMessage = createOutgoingMessage(transaction: writeTx)
            let payloadData = CommonGenerator.sentence.data(using: .utf8)!
            let initialPayloadId = MessageSendLog.recordPayload(payloadData, forMessageBeingSent: newMessage, transaction: writeTx) as! Int64

            let recipientAddress = CommonGenerator.address()

            // "Send" the message to one device. Complete send but don't mark as delivered.
            MessageSendLog.recordPendingDelivery(
                payloadId: initialPayloadId,
                recipientUuid: recipientAddress.uuid!,
                recipientDeviceId: 0,
                message: newMessage,
                transaction: writeTx)
            MessageSendLog.sendComplete(message: newMessage, transaction: writeTx)

            // Simulate a "retry" of a failed send. Try a fresh insert of the payload data
            // Then send to another device and complete the send.
            let retryPayloadId = MessageSendLog.recordPayload(
                payloadData,
                forMessageBeingSent: newMessage,
                transaction: writeTx) as! Int64
            MessageSendLog.recordPendingDelivery(
                payloadId: initialPayloadId,
                recipientUuid: recipientAddress.uuid!,
                recipientDeviceId: 1,
                message: newMessage,
                transaction: writeTx)
            MessageSendLog.sendComplete(message: newMessage, transaction: writeTx)

            // Both payloadIds should be the same. The payload is still alive.
            XCTAssertEqual(initialPayloadId, retryPayloadId)
            XCTAssertTrue(isPayloadAlive(index: initialPayloadId, transaction: writeTx))

            // Deliver to first device
            MessageSendLog.recordSuccessfulDelivery(
                timestamp: newMessage.timestamp,
                recipientUuid: recipientAddress.uuid!,
                recipientDeviceId: 0,
                transaction: writeTx)

            // Verify the payload still exists
            XCTAssertTrue(isPayloadAlive(index: initialPayloadId, transaction: writeTx))

            // Deliver to second device
            MessageSendLog.recordSuccessfulDelivery(
                timestamp: newMessage.timestamp,
                recipientUuid: recipientAddress.uuid!,
                recipientDeviceId: 1,
                transaction: writeTx)

            // Verify the payload was deleted
            XCTAssertFalse(isPayloadAlive(index: initialPayloadId, transaction: writeTx))
        }
    }

    func testRetryPartialFailureAfterAllInitialRecipientsAcked() {
        databaseStorage.write { writeTx in
            // Create and save the message payload
            let newMessage = createOutgoingMessage(transaction: writeTx)
            let payloadData = CommonGenerator.sentence.data(using: .utf8)!
            let recipientAddress = CommonGenerator.address()

            // Record + Send + Deliver + Complete (Deliver and Complete can happen in either order)
            let initialPayloadId = MessageSendLog.recordPayload(
                payloadData,
                forMessageBeingSent: newMessage,
                transaction: writeTx) as! Int64
            MessageSendLog.recordPendingDelivery(
                payloadId: initialPayloadId,
                recipientUuid: recipientAddress.uuid!,
                recipientDeviceId: 0,
                message: newMessage,
                transaction: writeTx)
            MessageSendLog.recordSuccessfulDelivery(
                timestamp: newMessage.timestamp,
                recipientUuid: recipientAddress.uuid!,
                recipientDeviceId: 0,
                transaction: writeTx)
            MessageSendLog.sendComplete(message: newMessage, transaction: writeTx)

            // Verify payload is deleted:
            XCTAssertFalse(isPayloadAlive(index: initialPayloadId, transaction: writeTx))

            // Record + Send + Complete + Deliver (Deliver and Complete can happen in either order)
            let secondPayloadId = MessageSendLog.recordPayload(
                payloadData,
                forMessageBeingSent: newMessage,
                transaction: writeTx) as! Int64
            MessageSendLog.recordPendingDelivery(
                payloadId: secondPayloadId,
                recipientUuid: recipientAddress.uuid!,
                recipientDeviceId: 1,
                message: newMessage,
                transaction: writeTx)
            MessageSendLog.sendComplete(message: newMessage, transaction: writeTx)
            MessageSendLog.recordSuccessfulDelivery(
                timestamp: newMessage.timestamp,
                recipientUuid: recipientAddress.uuid!,
                recipientDeviceId: 1,
                transaction: writeTx)

            // Verify payload is deleted:
            XCTAssertFalse(isPayloadAlive(index: secondPayloadId, transaction: writeTx))
            // Verify the ID was not reusued
            XCTAssertNotEqual(initialPayloadId, secondPayloadId)
        }
    }

    // Test disabled since it exercises an owsFailDebug()
    // Works correctly if assertions are disabled and the test is enabled.
    func testPlaintextMismatchFails() throws {
        databaseStorage.write { writeTx in
            // Create and save the message payload
            let newMessage = createOutgoingMessage(transaction: writeTx)
            let payloadData = CommonGenerator.sentence.data(using: .utf8)!

            let initialPayloadId = MessageSendLog.recordPayload(
                payloadData,
                forMessageBeingSent: newMessage,
                transaction: writeTx)

            let secondPayloadId = MessageSendLog.recordPayload(
                payloadData + Data([1]),    // append a byte so the payload doesn't match
                forMessageBeingSent: newMessage,
                transaction: writeTx)

            XCTAssertNotNil(initialPayloadId)
            XCTAssertNil(secondPayloadId)
        }
    }

    func testDeleteMessageWithOnePayload() {
        databaseStorage.write { writeTx in
            // Create and save the message payload
            let newMessage = createOutgoingMessage(transaction: writeTx)
            let payloadData = CommonGenerator.sentence.data(using: .utf8)!
            let payloadIndex = MessageSendLog.recordPayload(payloadData, forMessageBeingSent: newMessage, transaction: writeTx) as! Int64

            // "Send" the message to a recipient
            let recipientAddress = CommonGenerator.address()
            let deviceId = Int64.random(in: 0..<100)
            MessageSendLog.recordPendingDelivery(
                payloadId: payloadIndex,
                recipientUuid: recipientAddress.uuid!,
                recipientDeviceId: deviceId,
                message: newMessage,
                transaction: writeTx)

            // Delete the message
            MessageSendLog.deleteAllPayloadsForInteraction(newMessage, transaction: writeTx)

            // Verify the corresponding payload was deleted
            XCTAssertFalse(isPayloadAlive(index: payloadIndex, transaction: writeTx))
        }
    }

    func testDeleteMessageWithManyPayloads() {
        databaseStorage.write { writeTx in
            // Create and save several message payloads
            let message1 = createOutgoingMessage(transaction: writeTx)
            let data1 = CommonGenerator.sentence.data(using: .utf8)!
            let index1 = MessageSendLog.recordPayload(data1, forMessageBeingSent: message1, transaction: writeTx) as! Int64
            let message2 = createOutgoingMessage(transaction: writeTx)
            let data2 = CommonGenerator.sentence.data(using: .utf8)!
            let index2 = MessageSendLog.recordPayload(data2, forMessageBeingSent: message2, transaction: writeTx) as! Int64

            let readReceiptMessage = createOutgoingMessage(relatedMessageIds: [message1.uniqueId, message2.uniqueId], transaction: writeTx)
            let data3 = CommonGenerator.sentence.data(using: .utf8)!
            let index3 = MessageSendLog.recordPayload(data3, forMessageBeingSent: readReceiptMessage, transaction: writeTx) as! Int64

            // "Send" the messages to a recipient
            let recipientAddress = CommonGenerator.address()
            let deviceId = Int64.random(in: 0..<100)
            for index in [index1, index2, index3] {
                MessageSendLog.recordPendingDelivery(
                    payloadId: index,
                    recipientUuid: recipientAddress.uuid!,
                    recipientDeviceId: deviceId,
                    message: message1,
                    transaction: writeTx)
            }

            // Delete message1.
            MessageSendLog.deleteAllPayloadsForInteraction(message1, transaction: writeTx)

            // We expect that the read receipt message is deleted because it relates to the deleted message
            // We expect message2's payload to stick around, because none of its content is dependent on message1
            XCTAssertFalse(isPayloadAlive(index: index1, transaction: writeTx))
            XCTAssertTrue(isPayloadAlive(index: index2, transaction: writeTx))
            XCTAssertFalse(isPayloadAlive(index: index3, transaction: writeTx))
        }
    }

    func testCleanupExpiredPayloads() {
        databaseStorage.write { writeTx in
            let oldMessage = createOutgoingMessage(date: Date(timeIntervalSince1970: 1000), transaction: writeTx)
            let oldData = CommonGenerator.sentence.data(using: .utf8)!
            let oldIndex = MessageSendLog.recordPayload(oldData, forMessageBeingSent: oldMessage, transaction: writeTx) as! Int64
            let newMessage = createOutgoingMessage(transaction: writeTx)
            let newData = CommonGenerator.sentence.data(using: .utf8)!
            let newIndex = MessageSendLog.recordPayload(newData, forMessageBeingSent: newMessage, transaction: writeTx) as! Int64

            // Verify both messages exist
            XCTAssertTrue(isPayloadAlive(index: oldIndex, transaction: writeTx))
            XCTAssertTrue(isPayloadAlive(index: newIndex, transaction: writeTx))

            // Kick off cleanup
            MessageSendLog.test_forceCleanupStaleEntries(transaction: writeTx)

            // Verify only the old message was deleted
            XCTAssertFalse(isPayloadAlive(index: oldIndex, transaction: writeTx))
            XCTAssertTrue(isPayloadAlive(index: newIndex, transaction: writeTx))
        }
    }

    func testTimestampMismatch() {
        // IOS-1762: Greyson reported an issue where a resent message would have a timestamp mismatch on the outside vs
        // inside of the envelope. In his case, the outside had a timestamp of 1629210680139 versus the inside
        // which had 1629210680140.
        //
        // Casting back and forth from Date/TimeInterval and millisecond timestamps would lead to float math
        // incorrectly coercing to the wrong timestamp. In this case, constructing a Date from that millisecond
        // timestamp would result in a time interval of 1629210680.1399999. Reconverting back to a timestamp and
        // we get 1629210680139.
        databaseStorage.write { writeTx in
            let originalTimestamp: UInt64 = 1629210680140
            let originalDate = Date(millisecondsSince1970: originalTimestamp)
            XCTAssertEqual(originalDate.ows_millisecondsSince1970, originalTimestamp)

            let address = CommonGenerator.address()
            let message = createOutgoingMessage(date: originalDate, transaction: writeTx)
            let data = CommonGenerator.sentence.data(using: .utf8)!
            XCTAssertEqual(message.timestamp, originalTimestamp)

            let index = MessageSendLog.recordPayload(data, forMessageBeingSent: message, transaction: writeTx)!.int64Value
            MessageSendLog.recordPendingDelivery(payloadId: index, recipientUuid: address.uuid!, recipientDeviceId: 1, message: message, transaction: writeTx)

            let fetchedPayload = MessageSendLog.test_fetchPayload(
                address: address,
                deviceId: 1,
                timestamp: originalTimestamp,
                allowExpired: true,
                transaction: writeTx)
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
