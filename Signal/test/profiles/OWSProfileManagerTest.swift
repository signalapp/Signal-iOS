//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import Signal
@testable import SignalMessaging
@testable import SignalServiceKit

class OWSProfileManagerTest: SignalBaseTest {
    private lazy var localAddress = CommonGenerator.address()

    override func setUp() {
        super.setUp()
        // Create local account.
        tsAccountManager.registerForTests(withLocalNumber: localAddress.phoneNumber!,
                                          uuid: localAddress.uuid!)
    }

    private func add(username: String, transaction: SDSAnyWriteTransaction) -> OWSUserProfile {
        let profile = OWSUserProfile(address: SignalServiceAddress(uuid: UUID()))
        profile.update(username: username,
                       isStoriesCapable: true,
                       canReceiveGiftBadges: true,
                       userProfileWriter: .tests,
                       transaction: transaction)
        return profile
    }

    func testGetUsernames() {
        let profileManager = OWSProfileManager(databaseStorage: databaseStorage)
        var addresses: [SignalServiceAddress] = []
        write { transaction in
            for username in ["alice", "bob"] {
                let profile = self.add(username: username, transaction: transaction)
                addresses.append(profile.address)
            }
        }
        read { transaction in
            let bogus = SignalServiceAddress(uuid: UUID())
            let actual = profileManager.usernames(forAddresses: addresses + [bogus], transaction: transaction).map {
                $0.stringOrNil
            }
            let expected = ["alice", "bob", nil]
            XCTAssertEqual(actual, expected)
        }
    }

    func testGetUsername() {
        let profileManager = OWSProfileManager(databaseStorage: databaseStorage)
        var address: SignalServiceAddress!
        write { transaction in
            let profile = self.add(username: "alice", transaction: transaction)
            address = profile.address
        }
        read { transaction in
            let actual = profileManager.username(for: address, transaction: transaction).map {
                $0.stringOrNil
            }
            let expected = "alice"
            XCTAssertEqual(actual, expected)
        }
    }

    func testGetUsername_Fail() {
        let profileManager = OWSProfileManager(databaseStorage: databaseStorage)
        read { transaction in
            let address = SignalServiceAddress(uuid: UUID())
            let maybeUsername = profileManager.username(for: address, transaction: transaction)
            XCTAssertNil(maybeUsername)
        }
    }
}
