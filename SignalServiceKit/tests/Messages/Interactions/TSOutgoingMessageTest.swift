//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

@testable import SignalServiceKit
import XCTest

class TSOutgoingMessageTest: SSKBaseTestSwift {
    override func setUp() {
        super.setUp()
        tsAccountManager.registerForTests(withLocalNumber: "+17775550101", uuid: UUID(), pni: UUID())
        _ = identityManager.generateNewIdentityKey(for: .aci)
        _ = identityManager.generateNewIdentityKey(for: .pni)
    }

    func testIsUrgent() {
        write { transaction in
            let otherAddress = SignalServiceAddress(phoneNumber: "+12223334444")
            let thread = TSContactThread.getOrCreateThread(withContactAddress: otherAddress, transaction: transaction)
            let messageBuilder = TSOutgoingMessageBuilder.outgoingMessageBuilder(thread: thread, messageBody: nil)
            messageBuilder.timestamp = 100
            let message = messageBuilder.build(transaction: transaction)

            XCTAssertTrue(message.isUrgent)
        }
    }

    func testShouldNotStartExpireTimerWithMessageThatDoesNotExpire() {
        write { transaction in
            let otherAddress = SignalServiceAddress(phoneNumber: "+12223334444")
            let thread = TSContactThread.getOrCreateThread(withContactAddress: otherAddress, transaction: transaction)
            let messageBuilder = TSOutgoingMessageBuilder.outgoingMessageBuilder(thread: thread, messageBody: nil)
            messageBuilder.timestamp = 100
            let message = messageBuilder.build(transaction: transaction)

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
            let message = messageBuilder.build(transaction: transaction)

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
            let message = messageBuilder.build(transaction: transaction)

            message.updateAllUnsentRecipientsAsSending(transaction: transaction)

            XCTAssertFalse(message.shouldStartExpireTimer())
        }
    }

    func testNoPniSignatureByDefault() {
        write { transaction in
            let otherAddress = SignalServiceAddress(uuid: UUID(), phoneNumber: "+12223334444")
            let thread = TSContactThread.getOrCreateThread(withContactAddress: otherAddress, transaction: transaction)
            let messageBuilder = TSOutgoingMessageBuilder.outgoingMessageBuilder(thread: thread, messageBody: nil)
            messageBuilder.timestamp = 100
            let message = messageBuilder.build(transaction: transaction)
            let messageData = message.buildPlainTextData(thread, transaction: transaction)!
            let content = try! SSKProtoContent(serializedData: messageData)
            XCTAssertNil(content.pniSignatureMessage)
        }
    }

    func testPniSignatureWhenNeeded() {
        write { transaction in
            let otherAddress = SignalServiceAddress(uuid: UUID(), phoneNumber: "+12223334444")
            identityManager.setShouldSharePhoneNumber(with: otherAddress, transaction: transaction)

            let thread = TSContactThread.getOrCreateThread(withContactAddress: otherAddress, transaction: transaction)
            let messageBuilder = TSOutgoingMessageBuilder.outgoingMessageBuilder(thread: thread, messageBody: nil)
            messageBuilder.timestamp = 100
            let message = messageBuilder.build(transaction: transaction)
            let messageData = message.buildPlainTextData(thread, transaction: transaction)!
            let content = try! SSKProtoContent(serializedData: messageData)

            let messagePni = content.pniSignatureMessage!.pni
            XCTAssertEqual(messagePni, tsAccountManager.localPni!.data)

            let aciKeyPair = identityManager.identityKeyPair(for: .aci, transaction: transaction)!.identityKeyPair
            let pniKeyPair = identityManager.identityKeyPair(for: .pni, transaction: transaction)!.identityKeyPair
            XCTAssert(try! pniKeyPair.identityKey.verifyAlternateIdentity(
                aciKeyPair.identityKey,
                signature: content.pniSignatureMessage!.signature!))
        }
    }

    func testReceiptClearsSharePhoneNumber() {
        write { transaction in
            let otherAddress = SignalServiceAddress(uuid: UUID(), phoneNumber: "+12223334444")
            identityManager.setShouldSharePhoneNumber(with: otherAddress, transaction: transaction)

            let thread = TSContactThread.getOrCreateThread(withContactAddress: otherAddress, transaction: transaction)
            let messageBuilder = TSOutgoingMessageBuilder.outgoingMessageBuilder(thread: thread, messageBody: nil)
            messageBuilder.timestamp = Date.ows_millisecondTimestamp()
            let message = messageBuilder.build(transaction: transaction)
            let messageData = message.buildPlainTextData(thread, transaction: transaction)!

            message.update(withSentRecipient: otherAddress, wasSentByUD: true, transaction: transaction)

            let payloadId = MessageSendLog.recordPayload(messageData, forMessageBeingSent: message, transaction: transaction) as! Int64
            MessageSendLog.recordPendingDelivery(payloadId: payloadId,
                                                 recipientUuid: otherAddress.uuid!,
                                                 recipientDeviceId: 1,
                                                 message: message,
                                                 transaction: transaction)

            // Nothing changed yet...
            XCTAssert(identityManager.shouldSharePhoneNumber(with: otherAddress, transaction: transaction))

            message.update(withDeliveredRecipient: otherAddress,
                           recipientDeviceId: 1,
                           deliveryTimestamp: NSDate.ows_millisecondTimeStamp(),
                           context: PassthroughDeliveryReceiptContext(),
                           transaction: transaction)

            XCTAssertFalse(identityManager.shouldSharePhoneNumber(with: otherAddress, transaction: transaction))
        }
    }

    func testReceiptClearsSharePhoneNumberOnlyOnLastDevice() {
        write { transaction in
            let otherAddress = SignalServiceAddress(uuid: UUID(), phoneNumber: "+12223334444")
            identityManager.setShouldSharePhoneNumber(with: otherAddress, transaction: transaction)

            let thread = TSContactThread.getOrCreateThread(withContactAddress: otherAddress, transaction: transaction)
            let messageBuilder = TSOutgoingMessageBuilder.outgoingMessageBuilder(thread: thread, messageBody: nil)
            messageBuilder.timestamp = Date.ows_millisecondTimestamp()
            let message = messageBuilder.build(transaction: transaction)
            let messageData = message.buildPlainTextData(thread, transaction: transaction)!

            message.update(withSentRecipient: otherAddress, wasSentByUD: true, transaction: transaction)

            let payloadId = MessageSendLog.recordPayload(messageData, forMessageBeingSent: message, transaction: transaction) as! Int64
            MessageSendLog.recordPendingDelivery(payloadId: payloadId,
                                                 recipientUuid: otherAddress.uuid!,
                                                 recipientDeviceId: 1,
                                                 message: message,
                                                 transaction: transaction)
            MessageSendLog.recordPendingDelivery(payloadId: payloadId,
                                                 recipientUuid: otherAddress.uuid!,
                                                 recipientDeviceId: 2,
                                                 message: message,
                                                 transaction: transaction)

            // Nothing changed yet...
            XCTAssert(identityManager.shouldSharePhoneNumber(with: otherAddress, transaction: transaction))

            message.update(withDeliveredRecipient: otherAddress,
                           recipientDeviceId: 1,
                           deliveryTimestamp: NSDate.ows_millisecondTimeStamp(),
                           context: PassthroughDeliveryReceiptContext(),
                           transaction: transaction)

            // Still waiting on device #2!
            XCTAssert(identityManager.shouldSharePhoneNumber(with: otherAddress, transaction: transaction))

            message.update(withDeliveredRecipient: otherAddress,
                           recipientDeviceId: 2,
                           deliveryTimestamp: NSDate.ows_millisecondTimeStamp(),
                           context: PassthroughDeliveryReceiptContext(),
                           transaction: transaction)

            // There we go.
            XCTAssertFalse(identityManager.shouldSharePhoneNumber(with: otherAddress, transaction: transaction))
        }
    }

    func testReceiptDoesNotClearSharePhoneNumberIfNotSealedSender() {
        write { transaction in
            let otherAddress = SignalServiceAddress(uuid: UUID(), phoneNumber: "+12223334444")
            identityManager.setShouldSharePhoneNumber(with: otherAddress, transaction: transaction)

            let thread = TSContactThread.getOrCreateThread(withContactAddress: otherAddress, transaction: transaction)
            let messageBuilder = TSOutgoingMessageBuilder.outgoingMessageBuilder(thread: thread, messageBody: nil)
            messageBuilder.timestamp = Date.ows_millisecondTimestamp()
            let message = messageBuilder.build(transaction: transaction)
            let messageData = message.buildPlainTextData(thread, transaction: transaction)!

            message.update(withSentRecipient: otherAddress, wasSentByUD: false, transaction: transaction)

            let payloadId = MessageSendLog.recordPayload(messageData, forMessageBeingSent: message, transaction: transaction) as! Int64
            MessageSendLog.recordPendingDelivery(payloadId: payloadId,
                                                 recipientUuid: otherAddress.uuid!,
                                                 recipientDeviceId: 1,
                                                 message: message,
                                                 transaction: transaction)

            // Nothing changed yet...
            XCTAssert(identityManager.shouldSharePhoneNumber(with: otherAddress, transaction: transaction))

            message.update(withDeliveredRecipient: otherAddress,
                           recipientDeviceId: 1,
                           deliveryTimestamp: NSDate.ows_millisecondTimeStamp(),
                           context: PassthroughDeliveryReceiptContext(),
                           transaction: transaction)

            // Still not changed!
            XCTAssert(identityManager.shouldSharePhoneNumber(with: otherAddress, transaction: transaction))
        }
    }

    func testReceiptDoesNotClearSharePhoneNumberIfNoPniSignature() {
        write { transaction in
            let otherAddress = SignalServiceAddress(uuid: UUID(), phoneNumber: "+12223334444")

            let thread = TSContactThread.getOrCreateThread(withContactAddress: otherAddress, transaction: transaction)
            let messageBuilder = TSOutgoingMessageBuilder.outgoingMessageBuilder(thread: thread, messageBody: nil)
            messageBuilder.timestamp = Date.ows_millisecondTimestamp()
            let message = messageBuilder.build(transaction: transaction)
            let messageData = message.buildPlainTextData(thread, transaction: transaction)!

            message.update(withSentRecipient: otherAddress, wasSentByUD: true, transaction: transaction)

            let payloadId = MessageSendLog.recordPayload(messageData, forMessageBeingSent: message, transaction: transaction) as! Int64
            MessageSendLog.recordPendingDelivery(payloadId: payloadId,
                                                 recipientUuid: otherAddress.uuid!,
                                                 recipientDeviceId: 1,
                                                 message: message,
                                                 transaction: transaction)

            // If we set it now...
            XCTAssertFalse(identityManager.shouldSharePhoneNumber(with: otherAddress, transaction: transaction))
            identityManager.setShouldSharePhoneNumber(with: otherAddress, transaction: transaction)

            message.update(withDeliveredRecipient: otherAddress,
                           recipientDeviceId: 1,
                           deliveryTimestamp: NSDate.ows_millisecondTimeStamp(),
                           context: PassthroughDeliveryReceiptContext(),
                           transaction: transaction)

            // ...it should stay active.
            XCTAssert(identityManager.shouldSharePhoneNumber(with: otherAddress, transaction: transaction))
        }
    }

    func testReceiptDoesNotClearSharePhoneNumberIfPniHasChanged() {
        let otherAddress = SignalServiceAddress(uuid: UUID(), phoneNumber: "+12223334444")
        var message: TSOutgoingMessage!

        write { transaction in
            identityManager.setShouldSharePhoneNumber(with: otherAddress, transaction: transaction)

            let thread = TSContactThread.getOrCreateThread(withContactAddress: otherAddress, transaction: transaction)
            let messageBuilder = TSOutgoingMessageBuilder.outgoingMessageBuilder(thread: thread, messageBody: nil)
            messageBuilder.timestamp = Date.ows_millisecondTimestamp()
            message = messageBuilder.build(transaction: transaction)
            let messageData = message.buildPlainTextData(thread, transaction: transaction)!

            message.update(withSentRecipient: otherAddress, wasSentByUD: true, transaction: transaction)

            let payloadId = MessageSendLog.recordPayload(messageData, forMessageBeingSent: message, transaction: transaction) as! Int64
            MessageSendLog.recordPendingDelivery(payloadId: payloadId,
                                                 recipientUuid: otherAddress.uuid!,
                                                 recipientDeviceId: 1,
                                                 message: message,
                                                 transaction: transaction)
        }

        // Change our PNI, using registerForTests(...) instead of updateLocalPhoneNumber(...) because the latter kicks
        // off a request to check with the server.
        tsAccountManager.registerForTests(withLocalNumber: "+17775550199",
                                          uuid: tsAccountManager.localUuid!,
                                          pni: UUID())

        write { transaction in
            // Changing your number resets this setting.
            XCTAssertFalse(identityManager.shouldSharePhoneNumber(with: otherAddress, transaction: transaction))
            identityManager.setShouldSharePhoneNumber(with: otherAddress, transaction: transaction)

            message.update(withDeliveredRecipient: otherAddress,
                           recipientDeviceId: 1,
                           deliveryTimestamp: NSDate.ows_millisecondTimeStamp(),
                           context: PassthroughDeliveryReceiptContext(),
                           transaction: transaction)

            // Still on, because our PNI changed!
            XCTAssert(identityManager.shouldSharePhoneNumber(with: otherAddress, transaction: transaction))
        }
    }
}
