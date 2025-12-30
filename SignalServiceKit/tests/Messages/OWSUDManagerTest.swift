//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import XCTest
@testable import SignalServiceKit

class OWSUDManagerTest: SSKBaseTest {

    private var udManagerImpl: OWSUDManagerImpl {
        return SSKEnvironment.shared.udManagerRef as! OWSUDManagerImpl
    }

    // MARK: - Setup/Teardown

    private let localIdentifiers: LocalIdentifiers = .forUnitTests

    override func setUp() {
        super.setUp()

        SSKEnvironment.shared.databaseStorageRef.write { tx in
            (DependenciesBridge.shared.registrationStateChangeManager as! RegistrationStateChangeManagerImpl).registerForTests(
                localIdentifiers: localIdentifiers,
                tx: tx,
            )
        }

        let profileManager = SSKEnvironment.shared.profileManagerRef as! OWSFakeProfileManager
        profileManager.fakeUserProfiles = [
            localIdentifiers.aciAddress: OWSUserProfile(address: .localUser, profileKey: Aes256Key.generateRandom()),
        ]
    }

    // MARK: - Tests

    func testMode_noProfileKey() {
        XCTAssert(DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered)

        // Ensure UD is enabled by setting our own access level to enabled.
        write { tx in
            udManagerImpl.setUnidentifiedAccessMode(.enabled, for: localIdentifiers.aci, tx: tx)
        }

        let bobRecipientAci = Aci.randomForTesting()

        write { tx in
            let udAccess = udManagerImpl.udAccess(for: bobRecipientAci, tx: tx)!
            XCTAssertEqual(.unknown, udAccess.mode)
            XCTAssertEqual(udAccess.key.keyData, SMKUDAccessKey.zeroedKey.keyData)
        }

        write { tx in
            udManagerImpl.setUnidentifiedAccessMode(.unknown, for: bobRecipientAci, tx: tx)
            let udAccess = udManagerImpl.udAccess(for: bobRecipientAci, tx: tx)!
            XCTAssertEqual(.unknown, udAccess.mode)
            XCTAssertEqual(udAccess.key.keyData, SMKUDAccessKey.zeroedKey.keyData)
        }

        write { tx in
            udManagerImpl.setUnidentifiedAccessMode(.disabled, for: bobRecipientAci, tx: tx)
            let udAccess = udManagerImpl.udAccess(for: bobRecipientAci, tx: tx)
            XCTAssertNil(udAccess)
        }

        write { tx in
            udManagerImpl.setUnidentifiedAccessMode(.enabled, for: bobRecipientAci, tx: tx)
            let udAccess = udManagerImpl.udAccess(for: bobRecipientAci, tx: tx)
            XCTAssertNil(udAccess)
        }

        write { tx in
            // Bob should work in unrestricted mode, even if he doesn't have a profile key.
            udManagerImpl.setUnidentifiedAccessMode(.unrestricted, for: bobRecipientAci, tx: tx)
            let udAccess = udManagerImpl.udAccess(for: bobRecipientAci, tx: tx)!
            XCTAssertEqual(.unrestricted, udAccess.mode)
            XCTAssertEqual(udAccess.key.keyData, SMKUDAccessKey.zeroedKey.keyData)
        }
    }

    func testMode_withProfileKey() {
        XCTAssert(DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered)
        guard let localAddress = DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.aciAddress else {
            XCTFail("localAddress was unexpectedly nil")
            return
        }
        XCTAssert(localAddress.isValid)

        // Ensure UD is enabled by setting our own access level to enabled.
        write { tx in
            udManagerImpl.setUnidentifiedAccessMode(.enabled, for: localIdentifiers.aci, tx: tx)
        }

        let profileManager = SSKEnvironment.shared.profileManagerRef as! OWSFakeProfileManager

        let bobRecipientAci = Aci.randomForTesting()
        profileManager.fakeUserProfiles![SignalServiceAddress(bobRecipientAci)] = OWSUserProfile(address: .otherUser(SignalServiceAddress(bobRecipientAci)), profileKey: Aes256Key.generateRandom())

        write { tx in
            let udAccess = udManagerImpl.udAccess(for: bobRecipientAci, tx: tx)!
            XCTAssertEqual(.unknown, udAccess.mode)
            XCTAssertNotEqual(udAccess.key.keyData, SMKUDAccessKey.zeroedKey.keyData)
        }

        write { tx in
            udManagerImpl.setUnidentifiedAccessMode(.unknown, for: bobRecipientAci, tx: tx)
            let udAccess = udManagerImpl.udAccess(for: bobRecipientAci, tx: tx)!
            XCTAssertEqual(.unknown, udAccess.mode)
            XCTAssertNotEqual(udAccess.key.keyData, SMKUDAccessKey.zeroedKey.keyData)
        }

        write { tx in
            udManagerImpl.setUnidentifiedAccessMode(.disabled, for: bobRecipientAci, tx: tx)
            let udAccess = udManagerImpl.udAccess(for: bobRecipientAci, tx: tx)
            XCTAssertNil(udAccess)
        }

        write { tx in
            udManagerImpl.setUnidentifiedAccessMode(.enabled, for: bobRecipientAci, tx: tx)
            let udAccess = udManagerImpl.udAccess(for: bobRecipientAci, tx: tx)!
            XCTAssertEqual(.enabled, udAccess.mode)
            XCTAssertNotEqual(udAccess.key.keyData, SMKUDAccessKey.zeroedKey.keyData)
        }

        write { tx in
            udManagerImpl.setUnidentifiedAccessMode(.unrestricted, for: bobRecipientAci, tx: tx)
            let udAccess = udManagerImpl.udAccess(for: bobRecipientAci, tx: tx)!
            XCTAssertEqual(.unrestricted, udAccess.mode)
            XCTAssertEqual(udAccess.key.keyData, SMKUDAccessKey.zeroedKey.keyData)
        }
    }
}
