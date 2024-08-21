//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import XCTest

@testable import SignalServiceKit

class BlockingManagerTests: SSKBaseTest {
    // Some tests will use this to simulate the state as seen by another process
    private var otherBlockingManager: BlockingManager!

    override func setUp() {
        super.setUp()
        otherBlockingManager = BlockingManager(blockedRecipientStore: BlockedRecipientStoreImpl())
    }

    override func tearDown() {
        super.tearDown()
        BlockingManager.TestingFlags.optimisticallyCommitSyncToken = false
    }

    func testAddBlockedAddress() {
        // Setup
        let generatedAddress = SignalServiceAddress.randomForTesting()
        let generatedThread = ContactThreadFactory().create()

        // Test
        expectation(forNotification: BlockingManager.blockListDidChange, object: nil)
        databaseStorage.write { writeTx in
            _ = otherBlockingManager.blockedAddresses(transaction: writeTx)
            blockingManager.addBlockedThread(generatedThread, blockMode: .localShouldNotLeaveGroups, transaction: writeTx)
            blockingManager.addBlockedAddress(generatedAddress, blockMode: .localShouldNotLeaveGroups, transaction: writeTx)
        }

        // Verify
        databaseStorage.read { readTx in
            // First, query the whole set of blocked addresses:
            let allFetchedBlockedAddresses = blockingManager.blockedAddresses(transaction: readTx)
            let allExpectedBlockedAddresses = [generatedAddress, generatedThread.contactAddress]
            XCTAssertEqual(Set(allFetchedBlockedAddresses), Set(allExpectedBlockedAddresses))

            XCTAssertTrue(blockingManager.isAddressBlocked(generatedAddress, transaction: readTx))
            XCTAssertTrue(blockingManager.isAddressBlocked(generatedThread.contactAddress, transaction: readTx))
            XCTAssertTrue(blockingManager.isThreadBlocked(generatedThread, transaction: readTx))

            // Since this was a local change, we expect to need a sync message
            XCTAssertTrue(blockingManager._testingOnly_needsSyncMessage(readTx))

            // Reload the remote state and ensure it sees the up-to-date block list.
            XCTAssertEqual(Set(allFetchedBlockedAddresses), Set(otherBlockingManager.blockedAddresses(transaction: readTx)))
        }
        waitForExpectations(timeout: 3)
    }

    func testRemoveBlockedAddress() {
        // Setup
        let blockedContact = SignalServiceAddress.randomForTesting()
        let unblockedContact = SignalServiceAddress.randomForTesting()
        let blockedThread = ContactThreadFactory().create()
        let unblockedThread = ContactThreadFactory().create()
        databaseStorage.write {
            blockingManager.addBlockedAddress(blockedContact, blockMode: .localShouldLeaveGroups, transaction: $0)
            blockingManager.addBlockedAddress(blockedContact, blockMode: .localShouldLeaveGroups, transaction: $0)
            blockingManager.addBlockedThread(blockedThread, blockMode: .localShouldLeaveGroups, transaction: $0)
            blockingManager.addBlockedThread(unblockedThread, blockMode: .localShouldLeaveGroups, transaction: $0)
            _ = otherBlockingManager.blockedAddresses(transaction: $0)
            blockingManager._testingOnly_clearNeedsSyncMessage($0)
        }

        // Test
        databaseStorage.write {
            blockingManager.removeBlockedAddress(unblockedContact, wasLocallyInitiated: true, transaction: $0)
            blockingManager.removeBlockedThread(unblockedThread, wasLocallyInitiated: true, transaction: $0)
        }

        // Verify
        databaseStorage.read { readTx in
            XCTAssertTrue(blockingManager.isAddressBlocked(blockedContact, transaction: readTx))
            XCTAssertTrue(blockingManager.isThreadBlocked(blockedThread, transaction: readTx))
            XCTAssertFalse(blockingManager.isAddressBlocked(unblockedContact, transaction: readTx))
            XCTAssertFalse(blockingManager.isThreadBlocked(unblockedThread, transaction: readTx))

            // Since this was a local change, we expect to need a sync message
            XCTAssertTrue(blockingManager._testingOnly_needsSyncMessage(readTx))

            // Reload the remote state and ensure it sees the up-to-date block list.
            let otherBlockedAddresses = otherBlockingManager.blockedAddresses(transaction: readTx)
            let expectedBlockedAddresses = [blockedContact, blockedThread.contactAddress]
            XCTAssertEqual(Set(otherBlockedAddresses), Set(expectedBlockedAddresses))
        }
    }

    func testIncomingSyncMessage() {
        // Setup
        let noLongerBlockedAci = Aci.randomForTesting()
        let noLongerBlockedPhoneNumber = E164("+17635550100")!
        let noLongerBlockedGroupId = TSGroupModel.generateRandomV1GroupId()

        let stillBlockedAci = Aci.randomForTesting()
        let stillBlockedPhoneNumber = E164("+17635550101")!
        let stillBlockedGroupId = TSGroupModel.generateRandomV1GroupId()

        let newlyBlockedAci = Aci.randomForTesting()
        let newlyBlockedPhoneNumber = E164("+17635550101")!
        let newlyBlockedGroupId = TSGroupModel.generateRandomV1GroupId()

        databaseStorage.write { tx in
            blockingManager.addBlockedAddress(
                SignalServiceAddress(noLongerBlockedAci),
                blockMode: .localShouldNotLeaveGroups,
                transaction: tx
            )
            blockingManager.addBlockedAddress(
                SignalServiceAddress(noLongerBlockedPhoneNumber),
                blockMode: .localShouldNotLeaveGroups,
                transaction: tx
            )
            blockingManager.addBlockedGroup(
                groupId: noLongerBlockedGroupId,
                blockMode: .localShouldNotLeaveGroups,
                transaction: tx
            )

            blockingManager.addBlockedAddress(
                SignalServiceAddress(stillBlockedAci),
                blockMode: .localShouldNotLeaveGroups,
                transaction: tx
            )
            blockingManager.addBlockedAddress(
                SignalServiceAddress(stillBlockedPhoneNumber),
                blockMode: .localShouldNotLeaveGroups,
                transaction: tx
            )
            blockingManager.addBlockedGroup(
                groupId: stillBlockedGroupId,
                blockMode: .localShouldNotLeaveGroups,
                transaction: tx
            )
            _ = otherBlockingManager.blockedAddresses(transaction: tx)
        }

        // Test
        databaseStorage.write { tx in
            blockingManager.processIncomingSync(
                blockedPhoneNumbers: Set([stillBlockedPhoneNumber, newlyBlockedPhoneNumber].map(\.stringValue)),
                blockedAcis: [stillBlockedAci, newlyBlockedAci],
                blockedGroupIds: [stillBlockedGroupId, newlyBlockedGroupId],
                tx: tx
            )
        }

        // Verify
        databaseStorage.read { readTx in
            // First, our incoming sync message should've cleared our "NeedsSync" flag
            XCTAssertFalse(blockingManager._testingOnly_needsSyncMessage(readTx))

            // Verify our victims aren't blocked anymore
            XCTAssertFalse(blockingManager.isAddressBlocked(SignalServiceAddress(noLongerBlockedAci), transaction: readTx))
            XCTAssertFalse(blockingManager.isAddressBlocked(SignalServiceAddress(noLongerBlockedPhoneNumber), transaction: readTx))
            XCTAssertFalse(blockingManager.isGroupIdBlocked(noLongerBlockedGroupId, transaction: readTx))

            XCTAssertTrue(blockingManager.isAddressBlocked(SignalServiceAddress(stillBlockedAci), transaction: readTx))
            XCTAssertTrue(blockingManager.isAddressBlocked(SignalServiceAddress(stillBlockedPhoneNumber), transaction: readTx))
            XCTAssertTrue(blockingManager.isGroupIdBlocked(stillBlockedGroupId, transaction: readTx))

            XCTAssertTrue(blockingManager.isAddressBlocked(SignalServiceAddress(newlyBlockedAci), transaction: readTx))
            XCTAssertTrue(blockingManager.isAddressBlocked(SignalServiceAddress(newlyBlockedPhoneNumber), transaction: readTx))
            XCTAssertTrue(blockingManager.isGroupIdBlocked(newlyBlockedGroupId, transaction: readTx))

            // Finally, verify that any remote state agrees
            let otherBlockedAddresses = otherBlockingManager.blockedAddresses(transaction: readTx)
            let expectedBlockedAddresses = [
                SignalServiceAddress(stillBlockedAci),
                SignalServiceAddress(stillBlockedPhoneNumber),
                SignalServiceAddress(newlyBlockedAci),
                SignalServiceAddress(newlyBlockedPhoneNumber),
            ]
            XCTAssertEqual(Set(otherBlockedAddresses), Set(expectedBlockedAddresses))
            let otherBlockedGroupIds = otherBlockingManager.blockedGroupModels(transaction: readTx).map(\.groupId)
            let expectedBlockedGroupIds = [
                stillBlockedGroupId,
                newlyBlockedGroupId,
            ]
            XCTAssertEqual(Set(otherBlockedGroupIds), Set(expectedBlockedGroupIds))
        }
    }

    func testSendSyncMessage() {
        // Setup
        // ensure local client has necessary "registered" state
        let identityManager = DependenciesBridge.shared.identityManager
        identityManager.generateAndPersistNewIdentityKey(for: .aci)
        Self.databaseStorage.write { tx in
            (DependenciesBridge.shared.registrationStateChangeManager as! RegistrationStateChangeManagerImpl).registerForTests(
                localIdentifiers: .forUnitTests,
                tx: tx.asV2Write
            )
        }
        BlockingManager.TestingFlags.optimisticallyCommitSyncToken = true

        // Test
        expectation(forNotification: BlockingManager.blockListDidChange, object: nil)
        let neededSyncMessage = databaseStorage.write { writeTx -> Bool in
            blockingManager.addBlockedAddress(SignalServiceAddress.randomForTesting(), blockMode: .localShouldLeaveGroups, transaction: writeTx)
            return blockingManager._testingOnly_needsSyncMessage(writeTx)
        }
        waitForExpectations(timeout: 3)

        // Verify
        databaseStorage.read {
            XCTAssertTrue(neededSyncMessage)
            XCTAssertFalse(blockingManager._testingOnly_needsSyncMessage($0))
        }
    }
}
