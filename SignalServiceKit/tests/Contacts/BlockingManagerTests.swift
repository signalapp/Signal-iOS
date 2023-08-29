//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import XCTest

@testable import SignalServiceKit

class BlockingManagerTests: SSKBaseTestSwift {
    // Some tests will use this to simulate the state as seen by another process
    // If working correctly, state should be reloaded
    var remoteState = BlockingManager.State._testing_createEmpty()

    override func setUp() {
        super.setUp()
        databaseStorage.read { remoteState.reloadIfNecessary($0) }
    }

    override func tearDown() {
        super.tearDown()
        BlockingManager.TestingFlags.optimisticallyCommitSyncToken = false
    }

    func testAddBlockedAddress() {
        // Setup
        let generatedAddresses = generateAddresses(count: 30)
        let generatedThread = ContactThreadFactory().create()

        // Test
        expectation(forNotification: BlockingManager.blockListDidChange, object: nil)
        databaseStorage.write { writeTx in
            blockingManager.addBlockedThread(generatedThread, blockMode: .localShouldNotLeaveGroups, transaction: writeTx)
            generatedAddresses.forEach {
                blockingManager.addBlockedAddress($0, blockMode: .localShouldNotLeaveGroups, transaction: writeTx)
            }
        }

        // Verify
        databaseStorage.read { readTx in
            // First, query the whole set of blocked addresses:
            // Because these are made up generated addresses, a ACI+e164 that goes in may be low trust
            // If that happens, the addresses that come out will be two separate SignalServiceAddresses
            // To work around this, we compactMap the result sets to e164/ACI to compare apples to apples
            let allFetchedBlockedAddresses = blockingManager.blockedAddresses(transaction: readTx)
            let allExpectedBlockedAddresses = generatedAddresses.union([generatedThread.contactAddress])
            XCTAssertEqual(
                Set(allFetchedBlockedAddresses.compactMap { $0.phoneNumber }),
                Set(allExpectedBlockedAddresses.compactMap { $0.phoneNumber })
            )
            XCTAssertEqual(
                Set(allFetchedBlockedAddresses.compactMap { $0.aci }),
                Set(allExpectedBlockedAddresses.compactMap { $0.aci })
            )
            // Next, ensure that querying an individual address or thread works properly
            generatedAddresses.forEach {
                XCTAssertTrue(blockingManager.isAddressBlocked($0, transaction: readTx))
            }
            XCTAssertTrue(blockingManager.isAddressBlocked(generatedThread.contactAddress, transaction: readTx))
            XCTAssertTrue(blockingManager.isThreadBlocked(generatedThread, transaction: readTx))

            // Since this was a local change, we expect to need a sync message
            XCTAssertTrue(blockingManager._testingOnly_needsSyncMessage(readTx))

            // Reload the remote state and ensure it sees the up-to-date block list.
            let oldToken = remoteState.changeToken
            remoteState.reloadIfNecessary(readTx)
            let newToken = remoteState.changeToken
            XCTAssertNotEqual(oldToken, newToken)
            XCTAssertEqual(remoteState.blockedPhoneNumbers, Set(allExpectedBlockedAddresses.compactMap { $0.phoneNumber }))
            XCTAssertEqual(remoteState.blockedAcis, Set(allExpectedBlockedAddresses.compactMap { $0.aci }))
            XCTAssertEqual(remoteState.blockedGroupMap, [:])
        }
        waitForExpectations(timeout: 3)
    }

    func testRemoveBlockedAddress() {
        // Setup
        let blockedContact = CommonGenerator.address()
        let unblockedContact = CommonGenerator.address()
        let blockedThread = ContactThreadFactory().create()
        let unblockedThread = ContactThreadFactory().create()
        databaseStorage.write {
            blockingManager.addBlockedAddress(blockedContact, blockMode: .localShouldLeaveGroups, transaction: $0)
            blockingManager.addBlockedAddress(blockedContact, blockMode: .localShouldLeaveGroups, transaction: $0)
            blockingManager.addBlockedThread(blockedThread, blockMode: .localShouldLeaveGroups, transaction: $0)
            blockingManager.addBlockedThread(unblockedThread, blockMode: .localShouldLeaveGroups, transaction: $0)
        }
        databaseStorage.write {
            remoteState.reloadIfNecessary($0)
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
            let oldToken = remoteState.changeToken
            remoteState.reloadIfNecessary(readTx)
            let newToken = remoteState.changeToken
            XCTAssertNotEqual(oldToken, newToken)

            let expectedRemainingBlocks = [blockedContact, blockedThread.contactAddress]
            XCTAssertEqual(remoteState.blockedAcis, Set(expectedRemainingBlocks.compactMap { $0.aci }))
            XCTAssertEqual(remoteState.blockedPhoneNumbers, Set(expectedRemainingBlocks.compactMap { $0.phoneNumber }))
            XCTAssertEqual(remoteState.blockedGroupMap, [:])
        }
    }

    func testIncomingSyncMessage() {
        // Setup
        let victimBlockedAddress = CommonGenerator.address()
        let victimGroupId = TSGroupModel.generateRandomV1GroupId()

        let blockedAcis = Set((0..<10).map { _ in Aci.randomForTesting() })
        let blockedE164s = Set((0..<10).map { _ in CommonGenerator.e164() })
        let blockedGroupIds = Set((0..<10).map { _ in TSGroupModel.generateRandomV1GroupId() })
        databaseStorage.write { writeTx in
            // For our initial state, we insert the victims that we expect to see removed
            // and a single item out of our block sets that we expect to see persisted.
            blockingManager.addBlockedAddress(
                victimBlockedAddress,
                blockMode: .localShouldNotLeaveGroups,
                transaction: writeTx)
            blockingManager.addBlockedGroup(
                groupId: victimGroupId,
                blockMode: .localShouldNotLeaveGroups,
                transaction: writeTx)

            blockingManager.addBlockedGroup(
                groupId: blockedGroupIds.randomElement()!,
                blockMode: .localShouldNotLeaveGroups,
                transaction: writeTx)
            blockingManager.addBlockedAddress(
                SignalServiceAddress(blockedAcis.randomElement()!),
                blockMode: .localShouldNotLeaveGroups,
                transaction: writeTx)
            blockingManager.addBlockedAddress(
                SignalServiceAddress(phoneNumber: blockedE164s.randomElement()!),
                blockMode: .localShouldNotLeaveGroups,
                transaction: writeTx)
        }

        // Test
        databaseStorage.write { writeTx in
            blockingManager.processIncomingSync(
                blockedPhoneNumbers: blockedE164s,
                blockedAcis: Set(blockedAcis),
                blockedGroupIds: blockedGroupIds,
                tx: writeTx)
        }

        // Verify
        databaseStorage.read { readTx in
            // First, our incoming sync message should've cleared our "NeedsSync" flag
            XCTAssertFalse(blockingManager._testingOnly_needsSyncMessage(readTx))

            // Verify our victims aren't blocked anymore
            XCTAssertFalse(blockingManager.isAddressBlocked(victimBlockedAddress, transaction: readTx))
            XCTAssertFalse(blockingManager.isGroupIdBlocked(victimGroupId, transaction: readTx))

            // Verify everything that came through our sync message is now blocked
            XCTAssertTrue(blockedE164s
                .map { SignalServiceAddress(phoneNumber: $0) }
                .allSatisfy { blockingManager.isAddressBlocked($0, transaction: readTx) })
            XCTAssertTrue(blockedAcis
                .map { SignalServiceAddress($0) }
                .allSatisfy { blockingManager.isAddressBlocked($0, transaction: readTx) })
            XCTAssertTrue(blockedGroupIds
                .allSatisfy { blockingManager.isGroupIdBlocked($0, transaction: readTx) })

            // Finally, verify that any remote state agrees
            remoteState.reloadIfNecessary(readTx)
            XCTAssertEqual(Set(remoteState.blockedGroupMap.keys), blockedGroupIds)
            XCTAssertEqual(remoteState.blockedAcis, Set(blockedAcis))
            XCTAssertEqual(remoteState.blockedPhoneNumbers, blockedE164s)
        }
    }

    func testSendSyncMessage() {
        // Setup
        // ensure local client has necessary "registered" state
        let identityManager = DependenciesBridge.shared.identityManager
        identityManager.generateAndPersistNewIdentityKey(for: .aci)
        tsAccountManager.registerForTests(localIdentifiers: .forUnitTests)
        BlockingManager.TestingFlags.optimisticallyCommitSyncToken = true

        // Test
        expectation(forNotification: BlockingManager.blockListDidChange, object: nil)
        let neededSyncMessage = databaseStorage.write { writeTx -> Bool in
            blockingManager.addBlockedAddress(CommonGenerator.address(), blockMode: .localShouldLeaveGroups, transaction: writeTx)
            return blockingManager._testingOnly_needsSyncMessage(writeTx)
        }
        waitForExpectations(timeout: 3)

        // Verify
        databaseStorage.read {
            XCTAssertTrue(neededSyncMessage)
            XCTAssertFalse(blockingManager._testingOnly_needsSyncMessage($0))
        }
    }

    // MARK: - Helpers

    func generateAddresses(count: UInt) -> Set<SignalServiceAddress> {
        Set((0..<count).map { _ in
            let hasPhoneNumber = Int.random(in: 0...2) == 0
            let hasAci = !hasPhoneNumber || Bool.random()
            return CommonGenerator.address(hasAci: hasAci, hasPhoneNumber: hasPhoneNumber)
        })
    }
}
