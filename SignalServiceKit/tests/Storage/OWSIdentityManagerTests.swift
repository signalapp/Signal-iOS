//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import SignalServiceKit
import XCTest

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
            identityManager.saveRemoteIdentity(newKey, address: address, transaction: transaction)
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
            identityManager.saveRemoteIdentity(originalKey, address: address, transaction: transaction)

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
        let newKey = identityManager.generateNewIdentityKey(for: .aci)
        XCTAssertEqual(newKey.publicKey.count, 32)

        let pniKey = identityManager.generateNewIdentityKey(for: .pni)
        XCTAssertEqual(pniKey.publicKey.count, 32)
        XCTAssertNotEqual(pniKey.privateKey, newKey.privateKey)

        let fetchedKey = identityManager.identityKeyPair(for: .aci)!
        XCTAssertEqual(newKey.privateKey, fetchedKey.privateKey)

        let fetchedPniKey = identityManager.identityKeyPair(for: .pni)!
        XCTAssertEqual(pniKey.privateKey, fetchedPniKey.privateKey)
    }

}
