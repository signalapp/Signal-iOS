//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

class UserProfileTest: SignalBaseTest {
    private lazy var localAddress = CommonGenerator.address()

    override func setUp() {
        super.setUp()
        // Create local account.
        tsAccountManager.registerForTests(withLocalNumber: localAddress.phoneNumber!,
                                          uuid: localAddress.uuid!)
    }

    func testUserProfileForAci() {
        let aci = Aci.randomForTesting()
        let address = SignalServiceAddress(aci)
        write { transaction in
            OWSUserProfile(address: address).anyInsert(transaction: transaction)
        }
        read { transaction in
            let actual = OWSUserProfile.getFor(address, transaction: transaction)
            XCTAssertEqual(actual?.recipientUUID, aci.serviceIdUppercaseString)
        }
        read { transaction in
            let actual = OWSUserProfile.getFor(SignalServiceAddress.randomForTesting(), transaction: transaction)
            XCTAssertNil(actual)
        }
    }

    func testUserProfileForPni() throws {
        guard FeatureFlags.phoneNumberIdentifiers else {
            throw XCTSkip("Can't run this test until `SignalServiceAddress`es can be constructed by default with a PNI.")
        }

        let pni = Pni.randomForTesting()
        let address = SignalServiceAddress(pni)
        write { transaction in
            OWSUserProfile(address: address).anyInsert(transaction: transaction)
        }
        read { transaction in
            let actual = OWSUserProfile.getFor(address, transaction: transaction)
            XCTAssertEqual(actual?.recipientUUID, pni.serviceIdUppercaseString)
        }
        read { transaction in
            let actual = OWSUserProfile.getFor(SignalServiceAddress.randomForTesting(), transaction: transaction)
            XCTAssertNil(actual)
        }
    }

    func testUserProfilesForServiceIds() {
        let addresses = [SignalServiceAddress.randomForTesting(),
                         SignalServiceAddress.randomForTesting()]
        let profiles = addresses.map { OWSUserProfile(address: $0) }
        write { transaction in
            for profile in profiles {
                profile.anyInsert(transaction: transaction)
            }
        }
        read { transaction in
            let bogusAddresses = [SignalServiceAddress.randomForTesting()]
            let actual = SignalServiceKit.OWSUserProfile.getFor(keys: addresses + bogusAddresses,
                                                                transaction: transaction)
            let expected = profiles + [nil]
            XCTAssertEqual(actual.map { $0?.recipientUUID },
                           expected.map { $0?.recipientUUID })
        }
    }

    func testUserProfileForPhoneNumber() {
        let address = SignalServiceAddress(phoneNumber: "+17035550000")
        write { transaction in
            OWSUserProfile(address: address).anyInsert(transaction: transaction)
        }
        read { transaction in
            let actual = OWSUserProfile.getFor(address, transaction: transaction)
            XCTAssertEqual(actual?.recipientPhoneNumber, "+17035550000")
        }
        read { transaction in
            let actual = OWSUserProfile.getFor(SignalServiceAddress(phoneNumber: "+17035550001"), transaction: transaction)
            XCTAssertNil(actual)
        }
    }

    func testUserProfilesForPhoneNumbers() {
        let addresses = [SignalServiceAddress(phoneNumber: "+17035550000"),
                         SignalServiceAddress(phoneNumber: "+17035550001")]
        let profiles = addresses.map { OWSUserProfile(address: $0) }
        write { transaction in
            for profile in profiles {
                profile.anyInsert(transaction: transaction)
            }
        }
        read { transaction in
            let bogusAddresses = [SignalServiceAddress(phoneNumber: "+17035550002")]
            let actual = SignalServiceKit.OWSUserProfile.getFor(keys: addresses + bogusAddresses,
                                                                transaction: transaction)
            let expected = profiles + [nil]
            XCTAssertEqual(actual.map { $0?.recipientPhoneNumber },
                           expected.map { $0?.recipientPhoneNumber })
        }
    }
}
