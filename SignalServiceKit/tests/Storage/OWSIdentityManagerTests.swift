//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

class OWSIdentityManagerTests: SSKBaseTest {
    private var identityManager: OWSIdentityManagerImpl { DependenciesBridge.shared.identityManager as! OWSIdentityManagerImpl }

    override func setUp() {
        super.setUp()
        SSKEnvironment.shared.databaseStorageRef.write { tx in
            (DependenciesBridge.shared.registrationStateChangeManager as! RegistrationStateChangeManagerImpl).registerForTests(
                localIdentifiers: .forUnitTests,
                tx: tx.asV2Write
            )
        }
    }

    func testNewEmptyKey() throws {
        let newKey = IdentityKeyPair.generate().identityKey
        let aci = Aci.randomForTesting()
        try write { transaction in
            _ = DependenciesBridge.shared.recipientIdFinder.ensureRecipientUniqueId(for: aci, tx: transaction.asV2Write)
            XCTAssert(try identityManager.isTrustedIdentityKey(
                newKey,
                serviceId: aci,
                direction: .outgoing,
                tx: transaction.asV2Read
            ))
            XCTAssert(try identityManager.isTrustedIdentityKey(
                newKey,
                serviceId: aci,
                direction: .incoming,
                tx: transaction.asV2Read
            ))
        }
    }

    func testAlreadyRegisteredKey() throws {
        let newKey = IdentityKeyPair.generate().identityKey
        let aci = Aci.randomForTesting()
        try write { transaction in
            identityManager.saveIdentityKey(newKey, for: aci, tx: transaction.asV2Write)
            XCTAssert(try identityManager.isTrustedIdentityKey(
                newKey,
                serviceId: aci,
                direction: .outgoing,
                tx: transaction.asV2Read
            ))
            XCTAssert(try identityManager.isTrustedIdentityKey(
                newKey,
                serviceId: aci,
                direction: .incoming,
                tx: transaction.asV2Read
            ))
        }
    }

    func testChangedKey() throws {
        let originalKey = IdentityKeyPair.generate().identityKey
        let aci = Aci.randomForTesting()
        try write { transaction in
            identityManager.saveIdentityKey(originalKey, for: aci, tx: transaction.asV2Write)

            XCTAssert(try identityManager.isTrustedIdentityKey(
                originalKey,
                serviceId: aci,
                direction: .outgoing,
                tx: transaction.asV2Read
            ))
            XCTAssert(try identityManager.isTrustedIdentityKey(
                originalKey,
                serviceId: aci,
                direction: .incoming,
                tx: transaction.asV2Read
            ))

            let otherKey = IdentityKeyPair.generate().identityKey

            XCTAssertThrowsError(try identityManager.isTrustedIdentityKey(
                otherKey,
                serviceId: aci,
                direction: .outgoing,
                tx: transaction.asV2Read
            ), "", { error in
                switch error {
                case IdentityManagerError.identityKeyMismatchForOutgoingMessage:
                    // This is fine.
                    break
                default:
                    XCTFail("Threw the wrong type of error.")
                }
            })
            XCTAssert(try identityManager.isTrustedIdentityKey(
                otherKey,
                serviceId: aci,
                direction: .incoming,
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

        let fetchedKey = SSKEnvironment.shared.databaseStorageRef.read { tx in identityManager.identityKeyPair(for: .aci, tx: tx.asV2Read)! }
        XCTAssertEqual(newKey.privateKey, fetchedKey.privateKey)

        let fetchedPniKey = SSKEnvironment.shared.databaseStorageRef.read { tx in identityManager.identityKeyPair(for: .pni, tx: tx.asV2Read)! }
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
