//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

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

    func testUserProfileForUUID() {
        let uuid = UUID()
        let address = SignalServiceAddress(uuid: uuid)
        write { transaction in
            OWSUserProfile(address: address).anyInsert(transaction: transaction)
        }
        read { transaction in
            let actual = OWSUserProfile.getFor(address, transaction: transaction)
            XCTAssertEqual(actual?.recipientUUID, uuid.uuidString)
        }
        read { transaction in
            let actual = OWSUserProfile.getFor(SignalServiceAddress(uuid: UUID()), transaction: transaction)
            XCTAssertNil(actual)
        }
    }

    func testUserProfilesForUUIDs() {
        let addresses = [SignalServiceAddress(uuid: UUID()),
                         SignalServiceAddress(uuid: UUID())]
        let profiles = addresses.map { OWSUserProfile(address: $0) }
        write { transaction in
            for profile in profiles {
                profile.anyInsert(transaction: transaction)
            }
        }
        read { transaction in
            let bogusAddresses = [SignalServiceAddress(uuid: UUID())]
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
