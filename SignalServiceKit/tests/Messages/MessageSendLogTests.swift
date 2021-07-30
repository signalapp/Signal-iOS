//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

@testable import SignalServiceKit
import XCTest
import GRDB

class MessageSendLogTests: SSKBaseTestSwift {

    override func setUp() {
        super.setUp()
    }

    override func tearDown() {
        super.tearDown()
    }

    func testStoreAndRetrieveValidPayload() {
        databaseStorage.write { writeTx in
            // Create and save the message payload
            let newMessage = createOutgoingMessage(transaction: writeTx)
            let payloadData = CommonGenerator.sentence.data(using: .utf8)!
            let payloadIndex = MessageSendLog.recordPayload(payloadData, for: newMessage, transaction: writeTx) as! Int64

            // "Send" the message to a recipient
            let recipientAddress = CommonGenerator.address()
            let deviceId = Int64.random(in: 0..<100)
            MessageSendLog.recordPendingDelivery(
                payloadId: payloadIndex,
                recipientUuid: recipientAddress.uuid!,
                recipientDeviceId: deviceId,
                transaction: writeTx)

            // Re-fetch the payload
            let fetchedPayload = MessageSendLog.fetchPayload(
                address: recipientAddress,
                deviceId: deviceId,
                timestamp: Date(millisecondsSince1970: newMessage.timestamp),
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
            let payloadIndex = MessageSendLog.recordPayload(payloadData, for: newMessage, transaction: writeTx) as! Int64

            // "Send" the message to one recipient
            let recipientAddress = CommonGenerator.address()
            let deviceId = Int64.random(in: 0..<100)
            MessageSendLog.recordPendingDelivery(
                payloadId: payloadIndex,
                recipientUuid: recipientAddress.uuid!,
                recipientDeviceId: deviceId,
                transaction: writeTx)

            // Expect no results when re-fetching the payload with a different deviceId
            XCTAssertNil(MessageSendLog.fetchPayload(
                address: recipientAddress,
                deviceId: deviceId+1,
                timestamp: Date(millisecondsSince1970: newMessage.timestamp),
                transaction: writeTx))

            // Expect no results when re-fetching the payload with a different address
            XCTAssertNil(MessageSendLog.fetchPayload(
                            address: CommonGenerator.address(),
                            deviceId: deviceId,
                            timestamp: Date(millisecondsSince1970: newMessage.timestamp),
                            transaction: writeTx))
        }
    }

    func testStoreAndRetrievePayloadForDeliveredRecipient() {
        databaseStorage.write { writeTx in
            // Create and save the message payload
            let newMessage = createOutgoingMessage(transaction: writeTx)
            let payloadData = CommonGenerator.sentence.data(using: .utf8)!
            let payloadIndex = MessageSendLog.recordPayload(payloadData, for: newMessage, transaction: writeTx) as! Int64

            // "Send" the message to two devices
            let recipientAddress = CommonGenerator.address()
            for deviceId: Int64 in [0,1] {
                MessageSendLog.recordPendingDelivery(
                    payloadId: payloadIndex,
                    recipientUuid: recipientAddress.uuid!,
                    recipientDeviceId: deviceId,
                    transaction: writeTx)
            }

            // Mark the payload as "delivered" to the first device
            MessageSendLog.recordSuccessfulDelivery(
                timestamp: Date(millisecondsSince1970: newMessage.timestamp),
                recipientUuid: recipientAddress.uuid!,
                recipientDeviceId: 0,
                transaction: writeTx)

            // Expect no results when re-fetching the payload for the first device
            XCTAssertNil(MessageSendLog.fetchPayload(
                            address: recipientAddress,
                            deviceId: 0,
                            timestamp: Date(millisecondsSince1970: newMessage.timestamp),
                            transaction: writeTx))

            // Expect some results when re-fetching the payload for the first device
            XCTAssertNotNil(MessageSendLog.fetchPayload(
                                address: recipientAddress,
                                deviceId: 1,
                                timestamp: Date(millisecondsSince1970: newMessage.timestamp),
                                transaction: writeTx))
        }
    }

    func testStoreAndRetrieveExpiredPayload() {
        databaseStorage.write { writeTx in
            // Create and save the message payload. Outgoing message date is long ago
            let newMessage = createOutgoingMessage(date: Date(timeIntervalSince1970: 10000), transaction: writeTx)
            let payloadData = CommonGenerator.sentence.data(using: .utf8)!
            let payloadIndex = MessageSendLog.recordPayload(payloadData, for: newMessage, transaction: writeTx) as! Int64

            // "Send" the message to a recipient
            let recipientAddress = CommonGenerator.address()
            let deviceId = Int64.random(in: 0..<100)
            MessageSendLog.recordPendingDelivery(
                payloadId: payloadIndex,
                recipientUuid: recipientAddress.uuid!,
                recipientDeviceId: deviceId,
                transaction: writeTx)

            // Expect no results when re-fetching the payload since it's expired
            XCTAssertNil(MessageSendLog.fetchPayload(
                            address: recipientAddress,
                            deviceId: deviceId,
                            timestamp: Date(millisecondsSince1970: newMessage.timestamp),
                            transaction: writeTx))
        }
    }

    func testFinalDeliveryRemovesPayload() {
        databaseStorage.write { writeTx in
            // Create and save the message payload
            let newMessage = createOutgoingMessage(transaction: writeTx)
            let payloadData = CommonGenerator.sentence.data(using: .utf8)!
            let payloadIndex = MessageSendLog.recordPayload(payloadData, for: newMessage, transaction: writeTx) as! Int64

            // "Send" the message to one recipient, two devices
            let recipientAddress = CommonGenerator.address()
            for deviceId: Int64 in [0, 1] {
                MessageSendLog.recordPendingDelivery(
                    payloadId: payloadIndex,
                    recipientUuid: recipientAddress.uuid!,
                    recipientDeviceId: deviceId,
                    transaction: writeTx)
            }

            // Deliver to first device
            MessageSendLog.recordSuccessfulDelivery(
                timestamp: Date(millisecondsSince1970: newMessage.timestamp),
                recipientUuid: recipientAddress.uuid!,
                recipientDeviceId: 0,
                transaction: writeTx)

            // Verify the payload still exists
            XCTAssertTrue(isPayloadAlive(index: payloadIndex, transaction: writeTx))

            // Deliver to second device
            MessageSendLog.recordSuccessfulDelivery(
                timestamp: Date(millisecondsSince1970: newMessage.timestamp),
                recipientUuid: recipientAddress.uuid!,
                recipientDeviceId: 1,
                transaction: writeTx)

            // Verify the payload was deleted
            XCTAssertFalse(isPayloadAlive(index: payloadIndex, transaction: writeTx))
        }
    }

    func testDeleteMessageWithOnePayload() {
        databaseStorage.write { writeTx in
            // Create and save the message payload
            let newMessage = createOutgoingMessage(transaction: writeTx)
            let payloadData = CommonGenerator.sentence.data(using: .utf8)!
            let payloadIndex = MessageSendLog.recordPayload(payloadData, for: newMessage, transaction: writeTx) as! Int64

            // "Send" the message to a recipient
            let recipientAddress = CommonGenerator.address()
            let deviceId = Int64.random(in: 0..<100)
            MessageSendLog.recordPendingDelivery(
                payloadId: payloadIndex,
                recipientUuid: recipientAddress.uuid!,
                recipientDeviceId: deviceId,
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
            let index1 = MessageSendLog.recordPayload(data1, for: message1, transaction: writeTx) as! Int64
            let message2 = createOutgoingMessage(transaction: writeTx)
            let data2 = CommonGenerator.sentence.data(using: .utf8)!
            let index2 = MessageSendLog.recordPayload(data2, for: message2, transaction: writeTx) as! Int64

            let readReceiptMessage = createOutgoingMessage(relatedMessageIds: [message1.uniqueId, message2.uniqueId], transaction: writeTx)
            let data3 = CommonGenerator.sentence.data(using: .utf8)!
            let index3 = MessageSendLog.recordPayload(data3, for: readReceiptMessage, transaction: writeTx) as! Int64

            // "Send" the messages to a recipient
            let recipientAddress = CommonGenerator.address()
            let deviceId = Int64.random(in: 0..<100)
            for index in [index1, index2, index3] {
                MessageSendLog.recordPendingDelivery(
                    payloadId: index,
                    recipientUuid: recipientAddress.uuid!,
                    recipientDeviceId: deviceId,
                    transaction: writeTx)
            }

            // Delete message1.
            MessageSendLog.deleteAllPayloadsForInteraction(message1, transaction: writeTx)

            // We expect that the read receipt message is deleted because it relates to the deleted mesage
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
            let oldIndex = MessageSendLog.recordPayload(oldData, for: oldMessage, transaction: writeTx) as! Int64
            let newMessage = createOutgoingMessage(transaction: writeTx)
            let newData = CommonGenerator.sentence.data(using: .utf8)!
            let newIndex = MessageSendLog.recordPayload(newData, for: newMessage, transaction: writeTx) as! Int64

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

    // MARK: - Helpers

    class MSLTestMessage: TSOutgoingMessage {
        override init(outgoingMessageWithBuilder outgoingMessageBuilder: TSOutgoingMessageBuilder) {
            super.init(outgoingMessageWithBuilder: outgoingMessageBuilder)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        required init(dictionary dictionaryValue: [String : Any]!) throws {
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
        let testMessage = MSLTestMessage(outgoingMessageWithBuilder: builder)
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
