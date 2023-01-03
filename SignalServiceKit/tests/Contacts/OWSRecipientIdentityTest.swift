//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest
import GRDB

@testable import SignalServiceKit

class OWSRecipientIdentityTest: SSKBaseTestSwift {
    private lazy var localAddress = CommonGenerator.address()
    private lazy var aliceAddress = CommonGenerator.address()
    private lazy var bobAddress = CommonGenerator.address()
    private lazy var charlieAddress = CommonGenerator.address()
    private var recipients: [SignalServiceAddress] {
        [aliceAddress, bobAddress, charlieAddress, localAddress]
    }
    private var groupThread: TSGroupThread!
    private var identityKeys = [SignalServiceAddress: Data]()

    private func identityKey(_ address: SignalServiceAddress) -> Data {
        if let value = identityKeys[address] {
            return value
        }
        let data = Randomness.generateRandomBytes(Int32(kStoredIdentityKeyLength))
        identityKeys[address] = data
        return data
    }

    private func createFakeGroup() throws {
        // Create local account.
        tsAccountManager.registerForTests(withLocalNumber: localAddress.phoneNumber!,
                                          uuid: localAddress.uuid!)
        // Create recipients.
        write { transaction in
            for recipient in self.recipients {
                SignalRecipient.fetchOrCreate(for: recipient, trustLevel: .high, transaction: transaction)
                    .markAsRegistered(transaction: transaction)
            }
        }
        // Create identities for our recipients.
        for recipient in recipients {
            OWSIdentityManager.shared.saveRemoteIdentity(identityKey(recipient),
                                                         address: recipient)
        }

        // Create a group with our recipients plus us.
        self.groupThread = try! GroupManager.createGroupForTests(members: recipients,
                                                                 name: "Test Group")
    }

    override func setUp() {
        super.setUp()
        try! createFakeGroup()
    }

    func testNoneVerified() throws {
        XCTAssertTrue(Self.identityManager.groupContainsUnverifiedMember(groupThread.uniqueId))
    }

    func testAllVerified() throws {
        for recipient in recipients {
            OWSIdentityManager.shared.setVerificationState(.verified,
                                                           identityKey: identityKey(recipient),
                                                           address: recipient,
                                                           isUserInitiatedChange: true)
        }
        XCTAssertFalse(Self.identityManager.groupContainsUnverifiedMember(groupThread.uniqueId))
    }

    func testSomeVerified() throws {
        let recipient = recipients[0]
        OWSIdentityManager.shared.setVerificationState(.verified,
                                                       identityKey: identityKey(recipient),
                                                       address: recipient,
                                                       isUserInitiatedChange: true)
        XCTAssertTrue(Self.identityManager.groupContainsUnverifiedMember(groupThread.uniqueId))
    }

    func testSomeNoLongerVerified() throws {
        // Verify everyone
        for recipient in recipients {
            OWSIdentityManager.shared.setVerificationState(.verified,
                                                           identityKey: identityKey(recipient),
                                                           address: recipient,
                                                           isUserInitiatedChange: true)
        }
        // Make Alice and Bob no-longer-verified.
        let deverifiedAddresses = [aliceAddress, bobAddress]
        for recipient in deverifiedAddresses {
            OWSIdentityManager.shared.setVerificationState(.noLongerVerified,
                                                           identityKey: identityKey(recipient),
                                                           address: recipient,
                                                           isUserInitiatedChange: false)
        }
        XCTAssertTrue(Self.identityManager.groupContainsUnverifiedMember(groupThread.uniqueId))

        // Check that the list of no-longer-verified addresses is just Alice and Bob.
        read { transaction in
            let noLongerVerifiedAddresses =
            OWSRecipientIdentity.noLongerVerifiedAddresses(inGroup: self.groupThread.uniqueId,
                                                           limit: 2,
                                                           transaction: transaction)
            XCTAssertEqual(Set(noLongerVerifiedAddresses), Set(deverifiedAddresses))
        }
    }

    func testNoLongerVerifiedLimit() throws {
        for recipient in recipients {
            OWSIdentityManager.shared.setVerificationState(.noLongerVerified,
                                                           identityKey: identityKey(recipient),
                                                           address: recipient,
                                                           isUserInitiatedChange: false)
        }
        // All recipients are no longer verified. Check that the limit is respected.
        for limit in 1..<recipients.count {
            read { transaction in
                let noLongerVerifiedAddresses =
                OWSRecipientIdentity.noLongerVerifiedAddresses(inGroup: self.groupThread.uniqueId,
                                                               limit: limit,
                                                               transaction: transaction)
                XCTAssertEqual(noLongerVerifiedAddresses.count, limit)
            }
        }
    }

    func testLocalAddressIgnoredForVerifiedCheck() {
        // Verify everyone except me.
        for recipient in recipients {
            if recipient == localAddress {
                continue
            }
            OWSIdentityManager.shared.setVerificationState(.verified,
                                                           identityKey: identityKey(recipient),
                                                           address: recipient,
                                                           isUserInitiatedChange: true)
        }
        XCTAssertFalse(Self.identityManager.groupContainsUnverifiedMember(groupThread.uniqueId))
    }
}
