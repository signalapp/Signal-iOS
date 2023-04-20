//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest
import GRDB

@testable import SignalServiceKit

class OWSRecipientIdentityTest: SSKBaseTestSwift {
    private lazy var localServiceId = ServiceId(UUID())
    private lazy var aliceServiceId = ServiceId(UUID())
    private lazy var bobServiceId = ServiceId(UUID())
    private lazy var charlieServiceId = ServiceId(UUID())
    private var recipients: [ServiceId] {
        [aliceServiceId, bobServiceId, charlieServiceId, localServiceId]
    }
    private var groupThread: TSGroupThread!
    private var identityKeys = [ServiceId: Data]()

    private func identityKey(_ serviceId: ServiceId) -> Data {
        if let value = identityKeys[serviceId] {
            return value
        }
        let data = Randomness.generateRandomBytes(Int32(kStoredIdentityKeyLength))
        identityKeys[serviceId] = data
        return data
    }

    private func createFakeGroup() throws {
        // Create local account.
        tsAccountManager.registerForTests(
            withLocalNumber: "+16505550100",
            uuid: localServiceId.uuidValue
        )
        // Create recipients.
        write { tx in
            let recipientFetcher = DependenciesBridge.shared.recipientFetcher
            for recipient in self.recipients {
                recipientFetcher.fetchOrCreate(serviceId: recipient, tx: tx.asV2Write).markAsRegistered(transaction: tx)
            }
        }
        // Create identities for our recipients.
        for recipient in recipients {
            OWSIdentityManager.shared.saveRemoteIdentity(
                identityKey(recipient),
                address: SignalServiceAddress(recipient)
            )
        }

        // Create a group with our recipients plus us.
        self.groupThread = try! GroupManager.createGroupForTests(
            members: recipients.map { SignalServiceAddress($0) },
            name: "Test Group"
        )
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
            OWSIdentityManager.shared.setVerificationState(
                .verified,
                identityKey: identityKey(recipient),
                address: SignalServiceAddress(recipient),
                isUserInitiatedChange: true
            )
        }
        XCTAssertFalse(Self.identityManager.groupContainsUnverifiedMember(groupThread.uniqueId))
    }

    func testSomeVerified() throws {
        let recipient = recipients[0]
        OWSIdentityManager.shared.setVerificationState(
            .verified,
            identityKey: identityKey(recipient),
            address: SignalServiceAddress(recipient),
            isUserInitiatedChange: true
        )
        XCTAssertTrue(Self.identityManager.groupContainsUnverifiedMember(groupThread.uniqueId))
    }

    func testSomeNoLongerVerified() throws {
        // Verify everyone
        for recipient in recipients {
            OWSIdentityManager.shared.setVerificationState(
                .verified,
                identityKey: identityKey(recipient),
                address: SignalServiceAddress(recipient),
                isUserInitiatedChange: true
            )
        }
        // Make Alice and Bob no-longer-verified.
        let deverifiedServiceIds = [aliceServiceId, bobServiceId]
        for recipient in deverifiedServiceIds {
            OWSIdentityManager.shared.setVerificationState(
                .noLongerVerified,
                identityKey: identityKey(recipient),
                address: SignalServiceAddress(recipient),
                isUserInitiatedChange: false
            )
        }
        XCTAssertTrue(Self.identityManager.groupContainsUnverifiedMember(groupThread.uniqueId))

        // Check that the list of no-longer-verified addresses is just Alice and Bob.
        read { transaction in
            let noLongerVerifiedAddresses = OWSRecipientIdentity.noLongerVerifiedAddresses(
                inGroup: self.groupThread.uniqueId,
                limit: 2,
                transaction: transaction
            )
            XCTAssertEqual(Set(noLongerVerifiedAddresses), Set(deverifiedServiceIds.map { SignalServiceAddress($0) }))
        }
    }

    func testNoLongerVerifiedLimit() throws {
        for recipient in recipients {
            OWSIdentityManager.shared.setVerificationState(
                .noLongerVerified,
                identityKey: identityKey(recipient),
                address: SignalServiceAddress(recipient),
                isUserInitiatedChange: false
            )
        }
        // All recipients are no longer verified. Check that the limit is respected.
        for limit in 1..<recipients.count {
            read { transaction in
                let noLongerVerifiedAddresses = OWSRecipientIdentity.noLongerVerifiedAddresses(
                    inGroup: self.groupThread.uniqueId,
                    limit: limit,
                    transaction: transaction
                )
                XCTAssertEqual(noLongerVerifiedAddresses.count, limit)
            }
        }
    }

    func testLocalAddressIgnoredForVerifiedCheck() {
        // Verify everyone except me.
        for recipient in recipients {
            if recipient == localServiceId {
                continue
            }
            OWSIdentityManager.shared.setVerificationState(
                .verified,
                identityKey: identityKey(recipient),
                address: SignalServiceAddress(recipient),
                isUserInitiatedChange: true
            )
        }
        XCTAssertFalse(Self.identityManager.groupContainsUnverifiedMember(groupThread.uniqueId))
    }
}
