//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import XCTest

@testable import SignalServiceKit

class SignalRecipientTest: SSKBaseTestSwift {
    var tsAccountManager: TSAccountManager {
         return SSKEnvironment.shared.tsAccountManager
     }

    lazy var localAddress = CommonGenerator.address()

    override func setUp() {
        super.setUp()

        tsAccountManager.registerForTests(withLocalNumber: localAddress.phoneNumber!, uuid: localAddress.uuid!)
    }

    func testSelfRecipientWithExistingRecord() {
        write { transaction in
            SignalRecipient.mark(asRegisteredAndGet: self.localAddress, trustLevel: .high, transaction: transaction)

            XCTAssertTrue(SignalRecipient.isRegisteredRecipient(self.localAddress, transaction: transaction))
        }
    }

    func testRecipientWithExistingRecord() {
        let recipient = CommonGenerator.address()
        write { transaction in
            SignalRecipient.mark(asRegisteredAndGet: recipient, trustLevel: .high, transaction: transaction)

            XCTAssertTrue(SignalRecipient.isRegisteredRecipient(recipient, transaction: transaction))
        }
    }

    // MARK: - Low Trust

    func testLowTrustPhoneNumberOnly() {
        // Phone number only recipients are recorded
        let recipient = CommonGenerator.address(hasUUID: false)
        write { transaction in
            SignalRecipient.mark(asRegisteredAndGet: recipient, trustLevel: .low, transaction: transaction)

            XCTAssertTrue(SignalRecipient.isRegisteredRecipient(recipient, transaction: transaction))
        }
    }

    func testLowTrustUUIDOnly() {
        // UUID only recipients are recorded
        let recipient = CommonGenerator.address(hasPhoneNumber: false)
        write { transaction in
            SignalRecipient.mark(asRegisteredAndGet: recipient, trustLevel: .low, transaction: transaction)

            XCTAssertTrue(SignalRecipient.isRegisteredRecipient(recipient, transaction: transaction))
        }
    }

    func testLowTrustFullyQualified() {
        // Fully qualified addresses only record their UUID

        let recipientAddress = CommonGenerator.address()
        let recipientAddressWithoutUUID = SignalServiceAddress(phoneNumber: recipientAddress.phoneNumber!)

        XCTAssertNil(recipientAddressWithoutUUID.uuid)

        write { transaction in
            let recipient = SignalRecipient.mark(
                asRegisteredAndGet: recipientAddress,
                trustLevel: .low,
                transaction: transaction
            )

            // The impartial address is *not* automatically filled
            // after marking the complete address as registered.
            XCTAssertNil(recipientAddressWithoutUUID.uuid)

            XCTAssertTrue(SignalRecipient.isRegisteredRecipient(
                recipientAddress,
                transaction: transaction
            ))
            XCTAssertFalse(SignalRecipient.isRegisteredRecipient(
                recipientAddressWithoutUUID,
                transaction: transaction
            ))

            XCTAssertEqual(recipient.recipientUUID, recipientAddress.uuidString)
            XCTAssertNil(recipient.recipientPhoneNumber)
        }
    }

    // MARK: - High Trust

    func testHighTrustPhoneNumberOnly() {
        // Phone number only recipients are recorded
        let recipient = CommonGenerator.address(hasUUID: false)
        write { transaction in
            SignalRecipient.mark(asRegisteredAndGet: recipient, trustLevel: .high, transaction: transaction)

            XCTAssertTrue(SignalRecipient.isRegisteredRecipient(recipient, transaction: transaction))
        }
    }

    func testHighTrustUUIDOnly() {
        // UUID only recipients are recorded
        let recipient = CommonGenerator.address(hasPhoneNumber: false)
        write { transaction in
            SignalRecipient.mark(asRegisteredAndGet: recipient, trustLevel: .high, transaction: transaction)

            XCTAssertTrue(SignalRecipient.isRegisteredRecipient(recipient, transaction: transaction))
        }
    }

    func testHighTrustFullyQualified() {
        // Fully qualified addresses are recorded in their entirety

        let recipientAddress = CommonGenerator.address()
        let recipientAddressWithoutUUID = SignalServiceAddress(phoneNumber: recipientAddress.phoneNumber!)

        XCTAssertNil(recipientAddressWithoutUUID.uuid)

        write { transaction in
            let recipient = SignalRecipient.mark(
                asRegisteredAndGet: recipientAddress,
                trustLevel: .high,
                transaction: transaction
            )

            // The impartial address is automatically filled
            // after marking the complete address as registered.
            XCTAssertEqual(recipientAddressWithoutUUID.uuid, recipientAddress.uuid)

            XCTAssertTrue(SignalRecipient.isRegisteredRecipient(
                recipientAddress,
                transaction: transaction
            ))
            XCTAssertTrue(SignalRecipient.isRegisteredRecipient(
                recipientAddressWithoutUUID,
                transaction: transaction
            ))

            XCTAssertEqual(recipient.recipientUUID, recipientAddress.uuidString)
            XCTAssertEqual(recipient.recipientPhoneNumber, recipientAddress.phoneNumber)
        }
    }

    func testHighTrustMergeWithInvestedPhoneNumber() {
        // If there is a UUID only contact and a phone number only contact,
        // and then we later find out they are the same user we must merge
        // the two recipients together.
        let uuidOnlyAddress = CommonGenerator.address(hasPhoneNumber: false)
        let phoneNumberOnlyAddress = CommonGenerator.address(hasUUID: false)
        let address = SignalServiceAddress(uuid: uuidOnlyAddress.uuid!, phoneNumber: phoneNumberOnlyAddress.phoneNumber!)

        write { transaction in
            let uuidRecipient = SignalRecipient.mark(
                asRegisteredAndGet: uuidOnlyAddress,
                trustLevel: .high,
                transaction: transaction
            )

            let phoneNumberRecipient = SignalRecipient.mark(
                asRegisteredAndGet: phoneNumberOnlyAddress,
                trustLevel: .high,
                transaction: transaction
            )

            let mergedRecipient = SignalRecipient.mark(
                asRegisteredAndGet: address,
                trustLevel: .high,
                transaction: transaction
            )

            // TODO: test this more thoroughly. right now just confirming we prefer
            // the UUID recipient when no other info is available

            XCTAssertEqual(mergedRecipient.uniqueId, uuidRecipient.uniqueId)
        }
    }

    func testHighTrustPhoneNumberChange() {
        let oldAddress = CommonGenerator.address()

        write { transaction in
            let oldThread = TSContactThread.getOrCreateThread(
                withContactAddress: oldAddress,
                transaction: transaction
            )

            let messageBuilder = TSIncomingMessageBuilder(
                thread: oldThread,
                authorAddress: oldAddress,
                messageBody: "Test 123"
            )
            let oldMessage = messageBuilder.build()
            oldMessage.anyInsert(transaction: transaction)

            let oldProfile = OWSUserProfile.getOrBuild(
                for: oldAddress,
                transaction: transaction
            )
            // TODO: It's weird to me that getOrBuild doesn't
            // save the profile if it builds it. Maybe this is
            // a bug?
            oldProfile.anyInsert(transaction: transaction)

            let oldAccount = SignalAccount(address: oldAddress)
            oldAccount.anyInsert(transaction: transaction)

            SignalRecipient.mark(
                asRegisteredAndGet: oldAddress,
                trustLevel: .high,
                transaction: transaction
            )

            let newAddress = SignalServiceAddress(uuid: oldAddress.uuid!, phoneNumber: CommonGenerator.e164())

            SignalRecipient.mark(
                asRegisteredAndGet: newAddress,
                trustLevel: .high,
                transaction: transaction
            )

            let newThread = TSContactThread.getOrCreateThread(
                withContactAddress: newAddress,
                transaction: transaction
            )
            let newMessage = TSIncomingMessage.anyFetchIncomingMessage(
                uniqueId: oldMessage.uniqueId,
                transaction: transaction
            )!
            let newProfile = OWSUserProfile.getOrBuild(
                for: newAddress,
                transaction: transaction
            )
            let newAccount = SignalAccount.anyFetch(
                uniqueId: oldAccount.uniqueId,
                transaction: transaction
            )!

            // We maintain the same thread, profile, interactions, etc.
            // after the phone number change. They are updated to reflect
            // the new address.
            XCTAssertEqual(oldAddress.phoneNumber, newAddress.phoneNumber)
            XCTAssertEqual(oldAddress.uuid, newAddress.uuid)

            XCTAssertEqual(oldThread.uniqueId, newThread.uniqueId)
            XCTAssertNotEqual(oldThread.contactPhoneNumber, newThread.contactPhoneNumber)
            XCTAssertEqual(newAddress, newThread.contactAddress)

            XCTAssertEqual(oldMessage.uniqueId, newMessage.uniqueId)
            XCTAssertNotEqual(oldMessage.authorPhoneNumber, newMessage.authorPhoneNumber)
            XCTAssertEqual(newAddress, newMessage.authorAddress)

            XCTAssertEqual(oldProfile.uniqueId, newProfile.uniqueId)
            XCTAssertNotEqual(oldProfile.recipientPhoneNumber, newProfile.recipientPhoneNumber)
            XCTAssertEqual(newAddress, newProfile.address)

            XCTAssertEqual(oldAccount.uniqueId, newAccount.uniqueId)
            XCTAssertNotEqual(oldAccount.recipientPhoneNumber, newAccount.recipientPhoneNumber)
            XCTAssertEqual(newAddress, newAccount.recipientAddress)
        }
    }

    func testHighTrustUUIDChange() {
        let oldAddress = CommonGenerator.address()

        write { transaction in
            let oldThread = TSContactThread.getOrCreateThread(
                withContactAddress: oldAddress,
                transaction: transaction
            )

            let messageBuilder = TSIncomingMessageBuilder(
                thread: oldThread,
                authorAddress: oldAddress,
                messageBody: "Test 123"
            )
            let oldMessage = messageBuilder.build()
            oldMessage.anyInsert(transaction: transaction)

            let oldProfile = OWSUserProfile.getOrBuild(
                for: oldAddress,
                transaction: transaction
            )
            // TODO: It's weird to me that getOrBuild doesn't
            // save the profile if it builds it. Maybe this is
            // a bug?
            oldProfile.anyInsert(transaction: transaction)

            let oldAccount = SignalAccount(address: oldAddress)
            oldAccount.anyInsert(transaction: transaction)

            SignalRecipient.mark(
                asRegisteredAndGet: oldAddress,
                trustLevel: .high,
                transaction: transaction
            )

            let newAddress = SignalServiceAddress(uuid: UUID(), phoneNumber: oldAddress.phoneNumber!)

            SignalRecipient.mark(
                asRegisteredAndGet: newAddress,
                trustLevel: .high,
                transaction: transaction
            )

            let newThread = TSContactThread.getOrCreateThread(
                withContactAddress: newAddress,
                transaction: transaction
            )
            let newMessage = TSIncomingMessage.anyFetchIncomingMessage(
                uniqueId: oldMessage.uniqueId,
                transaction: transaction
            )!
            let newProfile = OWSUserProfile.getOrBuild(
                for: newAddress,
                transaction: transaction
            )
            let newAccount = SignalAccount.anyFetch(
                uniqueId: oldAccount.uniqueId,
                transaction: transaction
            )!

            // When the UUID changes, we treat it as a new account. Old data
            // should remain associated with the old UUID, but have the phone
            // number stripped.
            XCTAssertNil(oldAddress.phoneNumber)
            XCTAssertNotEqual(oldAddress.phoneNumber, newAddress.phoneNumber)
            XCTAssertNotEqual(oldAddress.uuid, newAddress.uuid)

            oldThread.anyReload(transaction: transaction)
            XCTAssertNotEqual(oldThread.uniqueId, newThread.uniqueId)
            XCTAssertNil(oldThread.contactPhoneNumber)
            XCTAssertEqual(newAddress, newThread.contactAddress)
            XCTAssertNotEqual(newAddress, oldThread.contactAddress)

            XCTAssertEqual(oldMessage.uniqueId, newMessage.uniqueId)
            XCTAssertNil(newMessage.authorPhoneNumber)
            XCTAssertNotEqual(newAddress, newMessage.authorAddress)

            oldProfile.anyReload(transaction: transaction)
            XCTAssertNotEqual(oldProfile.uniqueId, newProfile.uniqueId)
            XCTAssertNil(oldProfile.recipientPhoneNumber)
            XCTAssertEqual(newAddress, newProfile.address)
            XCTAssertNotEqual(newAddress, oldProfile.address)

            XCTAssertEqual(oldAccount.uniqueId, newAccount.uniqueId)
            XCTAssertNil(newAccount.recipientPhoneNumber)
            XCTAssertNotEqual(newAddress, newAccount.recipientAddress)
        }
    }
}
