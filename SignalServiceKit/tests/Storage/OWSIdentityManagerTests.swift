//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

class OWSIdentityManagerTests: SSKBaseTestSwift {
    override func setUp() {
        super.setUp()
        tsAccountManager.registerForTests(withLocalNumber: "+13235551234", uuid: UUID())
    }

    func testNewEmptyKey() {
        let newKey = Randomness.generateRandomBytes(32)
        let address = SignalServiceAddress(phoneNumber: "+12223334444")
        write { transaction in
            _ = OWSAccountIdFinder.ensureAccountId(forAddress: address, transaction: transaction)
            XCTAssert(identityManager.isTrustedIdentityKey(newKey,
                                                           address: address,
                                                           direction: .outgoing,
                                                           transaction: transaction))
            XCTAssert(identityManager.isTrustedIdentityKey(newKey,
                                                           address: address,
                                                           direction: .incoming,
                                                           transaction: transaction))
        }
    }

    func testAlreadyRegisteredKey() {
        let newKey = Randomness.generateRandomBytes(32)
        let address = SignalServiceAddress(phoneNumber: "+12223334444")
        write { transaction in
            identityManager.saveRemoteIdentity(
                newKey,
                address: address,
                transaction: transaction
            )
            XCTAssert(identityManager.isTrustedIdentityKey(newKey,
                                                           address: address,
                                                           direction: .outgoing,
                                                           transaction: transaction))
            XCTAssert(identityManager.isTrustedIdentityKey(newKey,
                                                           address: address,
                                                           direction: .incoming,
                                                           transaction: transaction))
        }
    }

    func testChangedKey() {
        let originalKey = Randomness.generateRandomBytes(32)
        let address = SignalServiceAddress(phoneNumber: "+12223334444")
        write { transaction in
            identityManager.saveRemoteIdentity(
                originalKey,
                address: address,
                transaction: transaction
            )

            XCTAssert(identityManager.isTrustedIdentityKey(originalKey,
                                                           address: address,
                                                           direction: .outgoing,
                                                           transaction: transaction))
            XCTAssert(identityManager.isTrustedIdentityKey(originalKey,
                                                           address: address,
                                                           direction: .incoming,
                                                           transaction: transaction))

            let otherKey = Randomness.generateRandomBytes(32)

            XCTAssertFalse(identityManager.isTrustedIdentityKey(otherKey,
                                                                address: address,
                                                                direction: .outgoing,
                                                                transaction: transaction))
            XCTAssert(identityManager.isTrustedIdentityKey(otherKey,
                                                           address: address,
                                                           direction: .incoming,
                                                           transaction: transaction))
        }
    }

    func testIdentityKey() {
        let newKey = identityManager.generateAndPersistNewIdentityKey(for: .aci)
        XCTAssertEqual(newKey.publicKey.count, 32)

        let pniKey = identityManager.generateAndPersistNewIdentityKey(for: .pni)
        XCTAssertEqual(pniKey.publicKey.count, 32)
        XCTAssertNotEqual(pniKey.privateKey, newKey.privateKey)

        let fetchedKey = identityManager.identityKeyPair(for: .aci)!
        XCTAssertEqual(newKey.privateKey, fetchedKey.privateKey)

        let fetchedPniKey = identityManager.identityKeyPair(for: .pni)!
        XCTAssertEqual(pniKey.privateKey, fetchedPniKey.privateKey)
    }

    func testShouldSharePhoneNumber() {
        let aliceAddress = SignalServiceAddress(serviceId: FutureAci.randomForTesting(), phoneNumber: "+12223334444")
        let bobAddress = SignalServiceAddress(serviceId: FutureAci.randomForTesting(), phoneNumber: "+17775556666")

        write { transaction in
            // {}
            XCTAssertFalse(identityManager.shouldSharePhoneNumber(with: aliceAddress, transaction: transaction))
            XCTAssertFalse(identityManager.shouldSharePhoneNumber(with: bobAddress, transaction: transaction))

            // {Alice}
            identityManager.setShouldSharePhoneNumber(with: aliceAddress, transaction: transaction)
            XCTAssertTrue(identityManager.shouldSharePhoneNumber(with: aliceAddress, transaction: transaction))
            XCTAssertFalse(identityManager.shouldSharePhoneNumber(with: bobAddress, transaction: transaction))

            // {Alice}; redundant set shouldn't change anything.
            identityManager.setShouldSharePhoneNumber(with: aliceAddress, transaction: transaction)
            XCTAssertTrue(identityManager.shouldSharePhoneNumber(with: aliceAddress, transaction: transaction))
            XCTAssertFalse(identityManager.shouldSharePhoneNumber(with: bobAddress, transaction: transaction))

            // {Alice, Bob}
            identityManager.setShouldSharePhoneNumber(with: bobAddress, transaction: transaction)
            XCTAssertTrue(identityManager.shouldSharePhoneNumber(with: aliceAddress, transaction: transaction))
            XCTAssertTrue(identityManager.shouldSharePhoneNumber(with: bobAddress, transaction: transaction))

            // {Bob}
            identityManager.clearShouldSharePhoneNumber(with: aliceAddress, transaction: transaction)
            XCTAssertFalse(identityManager.shouldSharePhoneNumber(with: aliceAddress, transaction: transaction))
            XCTAssertTrue(identityManager.shouldSharePhoneNumber(with: bobAddress, transaction: transaction))

            // {Bob}; redundant clear shouldn't change anything.
            identityManager.clearShouldSharePhoneNumber(with: aliceAddress, transaction: transaction)
            XCTAssertFalse(identityManager.shouldSharePhoneNumber(with: aliceAddress, transaction: transaction))
            XCTAssertTrue(identityManager.shouldSharePhoneNumber(with: bobAddress, transaction: transaction))

            // {Alice, Bob}
            identityManager.setShouldSharePhoneNumber(with: aliceAddress, transaction: transaction)
            // {}
            identityManager.clearShouldSharePhoneNumberForEveryone(transaction: transaction)
            XCTAssertFalse(identityManager.shouldSharePhoneNumber(with: aliceAddress, transaction: transaction))
            XCTAssertFalse(identityManager.shouldSharePhoneNumber(with: bobAddress, transaction: transaction))
        }
    }
}
