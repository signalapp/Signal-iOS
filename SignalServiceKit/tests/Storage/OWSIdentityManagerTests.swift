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
                localIdentifiers: .forUnitTests,
                tx: tx.asV2Write
            )
        }
    }

    func testNewEmptyKey() throws {
        let newKey = Randomness.generateRandomBytes(32)
        let aci = Aci.randomForTesting()
        try write { transaction in
            _ = OWSAccountIdFinder.ensureRecipientId(for: aci, tx: transaction)
            XCTAssert(try identityManager.isTrustedIdentityKey(
                newKey,
                serviceId: aci,
                direction: .outgoing,
                tx: transaction.asV2Read
            ).get())
            XCTAssert(try identityManager.isTrustedIdentityKey(
                newKey,
                serviceId: aci,
                direction: .incoming,
                tx: transaction.asV2Read
            ).get())
        }
    }

    func testAlreadyRegisteredKey() throws {
        let newKey = Randomness.generateRandomBytes(32)
        let aci = Aci.randomForTesting()
        try write { transaction in
            identityManager.saveIdentityKey(newKey, for: aci, tx: transaction.asV2Write)
            XCTAssert(try identityManager.isTrustedIdentityKey(
                newKey,
                serviceId: aci,
                direction: .outgoing,
                tx: transaction.asV2Read
            ).get())
            XCTAssert(try identityManager.isTrustedIdentityKey(
                newKey,
                serviceId: aci,
                direction: .incoming,
                tx: transaction.asV2Read
            ).get())
        }
    }

    func testChangedKey() throws {
        let originalKey = Randomness.generateRandomBytes(32)
        let aci = Aci.randomForTesting()
        let address = SignalServiceAddress(aci)
        try write { transaction in
            identityManager.saveIdentityKey(originalKey, for: aci, tx: transaction.asV2Write)

            XCTAssert(try identityManager.isTrustedIdentityKey(
                originalKey,
                serviceId: aci,
                direction: .outgoing,
                tx: transaction.asV2Read
            ).get())
            XCTAssert(try identityManager.isTrustedIdentityKey(
                originalKey,
                serviceId: aci,
                direction: .incoming,
                tx: transaction.asV2Read
            ).get())

            let otherKey = Randomness.generateRandomBytes(32)

            XCTAssertFalse(try identityManager.isTrustedIdentityKey(
                otherKey,
                serviceId: aci,
                direction: .outgoing,
                tx: transaction.asV2Read
            ).get())
            XCTAssert(try identityManager.isTrustedIdentityKey(
                otherKey,
                serviceId: aci,
                direction: .incoming,
                tx: transaction.asV2Read
            ).get())
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
