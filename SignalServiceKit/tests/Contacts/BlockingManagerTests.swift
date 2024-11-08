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
        otherBlockingManager = BlockingManager(
            appReadiness: AppReadinessMock(),
            blockedRecipientStore: BlockedRecipientStoreImpl()
        )
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
        SSKEnvironment.shared.databaseStorageRef.write { writeTx in
            _ = otherBlockingManager.blockedAddresses(transaction: writeTx)
            SSKEnvironment.shared.blockingManagerRef.addBlockedThread(generatedThread, blockMode: .localShouldNotLeaveGroups, transaction: writeTx)
            SSKEnvironment.shared.blockingManagerRef.addBlockedAddress(generatedAddress, blockMode: .localShouldNotLeaveGroups, transaction: writeTx)
        }

        // Verify
        SSKEnvironment.shared.databaseStorageRef.read { readTx in
            // First, query the whole set of blocked addresses:
            let allFetchedBlockedAddresses = SSKEnvironment.shared.blockingManagerRef.blockedAddresses(transaction: readTx)
            let allExpectedBlockedAddresses = [generatedAddress, generatedThread.contactAddress]
            XCTAssertEqual(Set(allFetchedBlockedAddresses), Set(allExpectedBlockedAddresses))

            XCTAssertTrue(SSKEnvironment.shared.blockingManagerRef.isAddressBlocked(generatedAddress, transaction: readTx))
            XCTAssertTrue(SSKEnvironment.shared.blockingManagerRef.isAddressBlocked(generatedThread.contactAddress, transaction: readTx))
            XCTAssertTrue(SSKEnvironment.shared.blockingManagerRef.isThreadBlocked(generatedThread, transaction: readTx))

            // Since this was a local change, we expect to need a sync message
            XCTAssertTrue(SSKEnvironment.shared.blockingManagerRef._testingOnly_needsSyncMessage(readTx))

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
        SSKEnvironment.shared.databaseStorageRef.write {
            SSKEnvironment.shared.blockingManagerRef.addBlockedAddress(blockedContact, blockMode: .localShouldLeaveGroups, transaction: $0)
            SSKEnvironment.shared.blockingManagerRef.addBlockedAddress(blockedContact, blockMode: .localShouldLeaveGroups, transaction: $0)
            SSKEnvironment.shared.blockingManagerRef.addBlockedThread(blockedThread, blockMode: .localShouldLeaveGroups, transaction: $0)
            SSKEnvironment.shared.blockingManagerRef.addBlockedThread(unblockedThread, blockMode: .localShouldLeaveGroups, transaction: $0)
            _ = otherBlockingManager.blockedAddresses(transaction: $0)
            SSKEnvironment.shared.blockingManagerRef._testingOnly_clearNeedsSyncMessage($0)
        }

        // Test
        SSKEnvironment.shared.databaseStorageRef.write {
            SSKEnvironment.shared.blockingManagerRef.removeBlockedAddress(unblockedContact, wasLocallyInitiated: true, transaction: $0)
            SSKEnvironment.shared.blockingManagerRef.removeBlockedThread(unblockedThread, wasLocallyInitiated: true, transaction: $0)
        }

        // Verify
        SSKEnvironment.shared.databaseStorageRef.read { readTx in
            XCTAssertTrue(SSKEnvironment.shared.blockingManagerRef.isAddressBlocked(blockedContact, transaction: readTx))
            XCTAssertTrue(SSKEnvironment.shared.blockingManagerRef.isThreadBlocked(blockedThread, transaction: readTx))
            XCTAssertFalse(SSKEnvironment.shared.blockingManagerRef.isAddressBlocked(unblockedContact, transaction: readTx))
            XCTAssertFalse(SSKEnvironment.shared.blockingManagerRef.isThreadBlocked(unblockedThread, transaction: readTx))

            // Since this was a local change, we expect to need a sync message
            XCTAssertTrue(SSKEnvironment.shared.blockingManagerRef._testingOnly_needsSyncMessage(readTx))

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
        let noLongerBlockedGroupId = TSGroupModel.generateRandomGroupId(.V2)

        let stillBlockedAci = Aci.randomForTesting()
        let stillBlockedPhoneNumber = E164("+17635550101")!
        let stillBlockedGroupId = TSGroupModel.generateRandomGroupId(.V2)

        let newlyBlockedAci = Aci.randomForTesting()
        let newlyBlockedPhoneNumber = E164("+17635550101")!
        let newlyBlockedGroupId = TSGroupModel.generateRandomGroupId(.V2)

        SSKEnvironment.shared.databaseStorageRef.write { tx in
            SSKEnvironment.shared.blockingManagerRef.addBlockedAddress(
                SignalServiceAddress(noLongerBlockedAci),
                blockMode: .localShouldNotLeaveGroups,
                transaction: tx
            )
            SSKEnvironment.shared.blockingManagerRef.addBlockedAddress(
                SignalServiceAddress(noLongerBlockedPhoneNumber),
                blockMode: .localShouldNotLeaveGroups,
                transaction: tx
            )
            SSKEnvironment.shared.blockingManagerRef.addBlockedGroup(
                groupId: noLongerBlockedGroupId,
                blockMode: .localShouldNotLeaveGroups,
                transaction: tx
            )

            SSKEnvironment.shared.blockingManagerRef.addBlockedAddress(
                SignalServiceAddress(stillBlockedAci),
                blockMode: .localShouldNotLeaveGroups,
                transaction: tx
            )
            SSKEnvironment.shared.blockingManagerRef.addBlockedAddress(
                SignalServiceAddress(stillBlockedPhoneNumber),
                blockMode: .localShouldNotLeaveGroups,
                transaction: tx
            )
            SSKEnvironment.shared.blockingManagerRef.addBlockedGroup(
                groupId: stillBlockedGroupId,
                blockMode: .localShouldNotLeaveGroups,
                transaction: tx
            )
            _ = otherBlockingManager.blockedAddresses(transaction: tx)
        }

        // Test
        SSKEnvironment.shared.databaseStorageRef.write { tx in
            SSKEnvironment.shared.blockingManagerRef.processIncomingSync(
                blockedPhoneNumbers: Set([stillBlockedPhoneNumber, newlyBlockedPhoneNumber].map(\.stringValue)),
                blockedAcis: [stillBlockedAci, newlyBlockedAci],
                blockedGroupIds: [stillBlockedGroupId, newlyBlockedGroupId],
                tx: tx
            )
        }

        // Verify
        SSKEnvironment.shared.databaseStorageRef.read { readTx in
            // First, our incoming sync message should've cleared our "NeedsSync" flag
            XCTAssertFalse(SSKEnvironment.shared.blockingManagerRef._testingOnly_needsSyncMessage(readTx))

            // Verify our victims aren't blocked anymore
            XCTAssertFalse(SSKEnvironment.shared.blockingManagerRef.isAddressBlocked(SignalServiceAddress(noLongerBlockedAci), transaction: readTx))
            XCTAssertFalse(SSKEnvironment.shared.blockingManagerRef.isAddressBlocked(SignalServiceAddress(noLongerBlockedPhoneNumber), transaction: readTx))
            XCTAssertFalse(SSKEnvironment.shared.blockingManagerRef.isGroupIdBlocked(noLongerBlockedGroupId, transaction: readTx))

            XCTAssertTrue(SSKEnvironment.shared.blockingManagerRef.isAddressBlocked(SignalServiceAddress(stillBlockedAci), transaction: readTx))
            XCTAssertTrue(SSKEnvironment.shared.blockingManagerRef.isAddressBlocked(SignalServiceAddress(stillBlockedPhoneNumber), transaction: readTx))
            XCTAssertTrue(SSKEnvironment.shared.blockingManagerRef.isGroupIdBlocked(stillBlockedGroupId, transaction: readTx))

            XCTAssertTrue(SSKEnvironment.shared.blockingManagerRef.isAddressBlocked(SignalServiceAddress(newlyBlockedAci), transaction: readTx))
            XCTAssertTrue(SSKEnvironment.shared.blockingManagerRef.isAddressBlocked(SignalServiceAddress(newlyBlockedPhoneNumber), transaction: readTx))
            XCTAssertTrue(SSKEnvironment.shared.blockingManagerRef.isGroupIdBlocked(newlyBlockedGroupId, transaction: readTx))

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
        SSKEnvironment.shared.databaseStorageRef.write { tx in
            (DependenciesBridge.shared.registrationStateChangeManager as! RegistrationStateChangeManagerImpl).registerForTests(
                localIdentifiers: .forUnitTests,
                tx: tx.asV2Write
            )
        }
        BlockingManager.TestingFlags.optimisticallyCommitSyncToken = true

        // Test
        expectation(forNotification: BlockingManager.blockListDidChange, object: nil)
        let neededSyncMessage = SSKEnvironment.shared.databaseStorageRef.write { writeTx -> Bool in
            SSKEnvironment.shared.blockingManagerRef.addBlockedAddress(SignalServiceAddress.randomForTesting(), blockMode: .localShouldLeaveGroups, transaction: writeTx)
            return SSKEnvironment.shared.blockingManagerRef._testingOnly_needsSyncMessage(writeTx)
        }
        waitForExpectations(timeout: 3)

        // Verify
        SSKEnvironment.shared.databaseStorageRef.read {
            XCTAssertTrue(neededSyncMessage)
            XCTAssertFalse(SSKEnvironment.shared.blockingManagerRef._testingOnly_needsSyncMessage($0))
        }
    }
}
