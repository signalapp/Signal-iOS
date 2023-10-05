//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

class OWSIdentityManagerTests: SSKBaseTestSwift {
    private var identityManager: OWSIdentityManager { DependenciesBridge.shared.identityManager }

    override func setUp() {
        super.setUp()
        databaseStorage.write { tx in
            (DependenciesBridge.shared.registrationStateChangeManager as! RegistrationStateChangeManagerImpl).registerForTests(
                localIdentifiers: .init(
                    aci: .init(fromUUID: UUID()),
                    pni: nil,
                    e164: .init("+13235551234")!
                ),
                tx: tx.asV2Write
            )
        }
    }

    func testNewEmptyKey() {
        let newKey = Randomness.generateRandomBytes(32)
        let address = SignalServiceAddress(phoneNumber: "+12223334444")
        write { transaction in
            _ = OWSAccountIdFinder.ensureAccountId(forAddress: address, transaction: transaction)
            XCTAssert(identityManager.isTrustedIdentityKey(
                newKey,
                address: address,
                direction: .outgoing,
                untrustedThreshold: OWSIdentityManagerImpl.Constants.minimumUntrustedThreshold,
                tx: transaction.asV2Read
            ))
            XCTAssert(identityManager.isTrustedIdentityKey(
                newKey,
                address: address,
                direction: .incoming,
                untrustedThreshold: OWSIdentityManagerImpl.Constants.minimumUntrustedThreshold,
                tx: transaction.asV2Read
            ))
        }
    }

    func testAlreadyRegisteredKey() {
        let newKey = Randomness.generateRandomBytes(32)
        let aci = Aci.randomForTesting()
        let address = SignalServiceAddress(aci)
        write { transaction in
            identityManager.saveIdentityKey(newKey, for: aci, tx: transaction.asV2Write)
            XCTAssert(identityManager.isTrustedIdentityKey(
                newKey,
                address: address,
                direction: .outgoing,
                untrustedThreshold: OWSIdentityManagerImpl.Constants.minimumUntrustedThreshold,
                tx: transaction.asV2Read
            ))
            XCTAssert(identityManager.isTrustedIdentityKey(
                newKey,
                address: address,
                direction: .incoming,
                untrustedThreshold: OWSIdentityManagerImpl.Constants.minimumUntrustedThreshold,
                tx: transaction.asV2Read
            ))
        }
    }

    func testChangedKey() {
        let originalKey = Randomness.generateRandomBytes(32)
        let aci = Aci.randomForTesting()
        let address = SignalServiceAddress(aci)
        write { transaction in
            identityManager.saveIdentityKey(originalKey, for: aci, tx: transaction.asV2Write)

            XCTAssert(identityManager.isTrustedIdentityKey(
                originalKey,
                address: address,
                direction: .outgoing,
                untrustedThreshold: OWSIdentityManagerImpl.Constants.minimumUntrustedThreshold,
                tx: transaction.asV2Read
            ))
            XCTAssert(identityManager.isTrustedIdentityKey(
                originalKey,
                address: address,
                direction: .incoming,
                untrustedThreshold: OWSIdentityManagerImpl.Constants.minimumUntrustedThreshold,
                tx: transaction.asV2Read
            ))

            let otherKey = Randomness.generateRandomBytes(32)

            XCTAssertFalse(identityManager.isTrustedIdentityKey(
                otherKey,
                address: address,
                direction: .outgoing,
                untrustedThreshold: OWSIdentityManagerImpl.Constants.minimumUntrustedThreshold,
                tx: transaction.asV2Read
            ))
            XCTAssert(identityManager.isTrustedIdentityKey(
                otherKey,
                address: address,
                direction: .incoming,
                untrustedThreshold: OWSIdentityManagerImpl.Constants.minimumUntrustedThreshold,
                tx: transaction.asV2Read
            ))
        }
    }

    func testIdentityKey() {
        let identityManager = DependenciesBridge.shared.identityManager

        let newKey = identityManager.generateAndPersistNewIdentityKey(for: .aci)
        XCTAssertEqual(newKey.publicKey.count, 32)

        let pniKey = identityManager.generateAndPersistNewIdentityKey(for: .pni)
        XCTAssertEqual(pniKey.publicKey.count, 32)
        XCTAssertNotEqual(pniKey.privateKey, newKey.privateKey)

        let fetchedKey = databaseStorage.read { tx in identityManager.identityKeyPair(for: .aci, tx: tx.asV2Read)! }
        XCTAssertEqual(newKey.privateKey, fetchedKey.privateKey)

        let fetchedPniKey = databaseStorage.read { tx in identityManager.identityKeyPair(for: .pni, tx: tx.asV2Read)! }
        XCTAssertEqual(pniKey.privateKey, fetchedPniKey.privateKey)
    }

    func testShouldSharePhoneNumber() {
        let aliceAci = Aci.randomForTesting()
        let bobAci = Aci.randomForTesting()

        write { transaction in
            // {}
            XCTAssertFalse(identityManager.shouldSharePhoneNumber(with: aliceAci, tx: transaction.asV2Write))
            XCTAssertFalse(identityManager.shouldSharePhoneNumber(with: bobAci, tx: transaction.asV2Write))

            // {Alice}
            identityManager.setShouldSharePhoneNumber(with: aliceAci, tx: transaction.asV2Write)
            XCTAssertTrue(identityManager.shouldSharePhoneNumber(with: aliceAci, tx: transaction.asV2Write))
            XCTAssertFalse(identityManager.shouldSharePhoneNumber(with: bobAci, tx: transaction.asV2Write))

            // {Alice}; redundant set shouldn't change anything.
            identityManager.setShouldSharePhoneNumber(with: aliceAci, tx: transaction.asV2Write)
            XCTAssertTrue(identityManager.shouldSharePhoneNumber(with: aliceAci, tx: transaction.asV2Write))
            XCTAssertFalse(identityManager.shouldSharePhoneNumber(with: bobAci, tx: transaction.asV2Write))

            // {Alice, Bob}
            identityManager.setShouldSharePhoneNumber(with: bobAci, tx: transaction.asV2Write)
            XCTAssertTrue(identityManager.shouldSharePhoneNumber(with: aliceAci, tx: transaction.asV2Write))
            XCTAssertTrue(identityManager.shouldSharePhoneNumber(with: bobAci, tx: transaction.asV2Write))

            // {Bob}
            identityManager.clearShouldSharePhoneNumber(with: aliceAci, tx: transaction.asV2Write)
            XCTAssertFalse(identityManager.shouldSharePhoneNumber(with: aliceAci, tx: transaction.asV2Write))
            XCTAssertTrue(identityManager.shouldSharePhoneNumber(with: bobAci, tx: transaction.asV2Write))

            // {Bob}; redundant clear shouldn't change anything.
            identityManager.clearShouldSharePhoneNumber(with: aliceAci, tx: transaction.asV2Write)
            XCTAssertFalse(identityManager.shouldSharePhoneNumber(with: aliceAci, tx: transaction.asV2Write))
            XCTAssertTrue(identityManager.shouldSharePhoneNumber(with: bobAci, tx: transaction.asV2Write))

            // {Alice, Bob}
            identityManager.setShouldSharePhoneNumber(with: aliceAci, tx: transaction.asV2Write)
            // {}
            identityManager.clearShouldSharePhoneNumberForEveryone(tx: transaction.asV2Write)
            XCTAssertFalse(identityManager.shouldSharePhoneNumber(with: aliceAci, tx: transaction.asV2Write))
            XCTAssertFalse(identityManager.shouldSharePhoneNumber(with: bobAci, tx: transaction.asV2Write))
        }
    }
}
