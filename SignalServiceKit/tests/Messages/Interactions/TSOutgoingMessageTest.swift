//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

@testable import SignalServiceKit
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

    func testNoPniSignatureByDefault() {
        write { transaction in
            let otherAddress = SignalServiceAddress(uuid: UUID(), phoneNumber: "+12223334444")
            let thread = TSContactThread.getOrCreateThread(withContactAddress: otherAddress, transaction: transaction)
            let messageBuilder = TSOutgoingMessageBuilder.outgoingMessageBuilder(thread: thread, messageBody: nil)
            messageBuilder.timestamp = 100
            let message = messageBuilder.build()
            let messageData = message.buildPlainTextData(thread, transaction: transaction)!
            let content = try! SSKProtoContent(serializedData: messageData)
            XCTAssertNil(content.pniSignatureMessage)
        }
    }

    func testPniSignatureWhenNeeded() {
        tsAccountManager.registerForTests(withLocalNumber: "+17775550101", uuid: UUID(), pni: UUID())
        let aciKey = identityManager.generateNewIdentityKey(for: .aci)
        let pniKey = identityManager.generateNewIdentityKey(for: .pni)

        write { transaction in
            let otherAddress = SignalServiceAddress(uuid: UUID(), phoneNumber: "+12223334444")
            identityManager.setShouldSharePhoneNumber(with: otherAddress, transaction: transaction)

            let thread = TSContactThread.getOrCreateThread(withContactAddress: otherAddress, transaction: transaction)
            let messageBuilder = TSOutgoingMessageBuilder.outgoingMessageBuilder(thread: thread, messageBody: nil)
            messageBuilder.timestamp = 100
            let message = messageBuilder.build()
            let messageData = message.buildPlainTextData(thread, transaction: transaction)!
            let content = try! SSKProtoContent(serializedData: messageData)

            let messagePni = content.pniSignatureMessage!.pni
            XCTAssertEqual(messagePni, tsAccountManager.localPni!.data)
            XCTAssert(try! pniKey.identityKeyPair.identityKey.verifyAlternateIdentity(
                aciKey.identityKeyPair.identityKey,
                signature: content.pniSignatureMessage!.signature!))
        }
    }
}
