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
    private var blockingManager: BlockingManager { SSKEnvironment.shared.blockingManagerRef }

    override func setUp() {
        super.setUp()
        otherBlockingManager = BlockingManager(
            blockedGroupStore: BlockedGroupStore(),
            blockedRecipientStore: BlockedRecipientStore(),
        )
    }

    override func tearDown() {
        let flushTask = blockingManager.flushSyncQueueTask()
        let otherFlushTask = otherBlockingManager.flushSyncQueueTask()
        let flushExpectation = self.expectation(description: "flush sync queues")
        Task {
            try! await flushTask.value
            try! await otherFlushTask.value
            flushExpectation.fulfill()
        }
        self.wait(for: [flushExpectation], timeout: 60)
        super.tearDown()
    }

    func testAddBlockedAddress() {
        // Setup
        let aci = Aci.randomForTesting()

        // Test
        expectation(forNotification: BlockingManager.blockListDidChange, object: nil)
        SSKEnvironment.shared.databaseStorageRef.write { tx in
            _ = otherBlockingManager.blockedAddresses(transaction: tx)
            let oldChangeToken = blockingManager.fetchChangeToken(tx: tx)
            blockingManager.addBlockedAci(aci, blockMode: .localShouldNotLeaveGroups, tx: tx)
            let newChangeToken = blockingManager.fetchChangeToken(tx: tx)
            // Since this was a local change, we expect to need a sync message
            XCTAssertGreaterThan(newChangeToken, oldChangeToken)
        }

        // Verify
        SSKEnvironment.shared.databaseStorageRef.read { tx in
            // First, query the whole set of blocked addresses:
            let blockedAddresses = blockingManager.blockedAddresses(transaction: tx)
            XCTAssertEqual(blockedAddresses.map { $0.aci }, [aci])

            XCTAssertTrue(blockingManager.isAddressBlocked(SignalServiceAddress(aci), transaction: tx))

            // Reload the remote state and ensure it sees the up-to-date block list.
            XCTAssertEqual(otherBlockingManager.blockedAddresses(transaction: tx).map { $0.aci }, [aci])
        }
        waitForExpectations(timeout: 3)
    }

    func testRemoveBlockedAddress() {
        // Setup
        let blockedAci = Aci.randomForTesting()
        let unblockedAci = Aci.randomForTesting()
        SSKEnvironment.shared.databaseStorageRef.write { tx in
            blockingManager.addBlockedAci(blockedAci, blockMode: .localShouldLeaveGroups, tx: tx)
            blockingManager.addBlockedAci(unblockedAci, blockMode: .localShouldLeaveGroups, tx: tx)
            _ = otherBlockingManager.blockedAddresses(transaction: tx)
        }

        let oldChangeToken = SSKEnvironment.shared.databaseStorageRef.read { tx in
            return blockingManager.fetchChangeToken(tx: tx)
        }

        // Test
        SSKEnvironment.shared.databaseStorageRef.write { tx in
            blockingManager.removeBlockedAddress(SignalServiceAddress(unblockedAci), wasLocallyInitiated: true, transaction: tx)
        }

        // Verify
        SSKEnvironment.shared.databaseStorageRef.read { tx in
            XCTAssertTrue(blockingManager.isAddressBlocked(SignalServiceAddress(blockedAci), transaction: tx))
            XCTAssertFalse(blockingManager.isAddressBlocked(SignalServiceAddress(unblockedAci), transaction: tx))

            // Since this was a local change, we expect to need a sync message
            let newChangeToken = blockingManager.fetchChangeToken(tx: tx)
            XCTAssertGreaterThan(newChangeToken, oldChangeToken)

            // Reload the remote state and ensure it sees the up-to-date block list.
            XCTAssertEqual(otherBlockingManager.blockedAddresses(transaction: tx).map(\.aci), [blockedAci])
        }
    }

    func testIncomingSyncMessage() throws {
        // Setup
        let noLongerBlockedAci = Aci.randomForTesting()
        let noLongerBlockedPhoneNumber = E164("+17635550100")!
        let noLongerBlockedGroupParams = try GroupSecretParams.generate()

        let stillBlockedAci = Aci.randomForTesting()
        let stillBlockedPhoneNumber = E164("+17635550101")!
        let stillBlockedGroupParams = try GroupSecretParams.generate()

        let newlyBlockedAci = Aci.randomForTesting()
        let newlyBlockedPhoneNumber = E164("+17635550101")!
        let newlyBlockedGroupParams = try GroupSecretParams.generate()

        try SSKEnvironment.shared.databaseStorageRef.write { tx in
            blockingManager.addBlockedAddress(
                SignalServiceAddress(noLongerBlockedAci),
                blockMode: .localShouldNotLeaveGroups,
                transaction: tx,
            )
            blockingManager.addBlockedAddress(
                SignalServiceAddress(noLongerBlockedPhoneNumber),
                blockMode: .localShouldNotLeaveGroups,
                transaction: tx,
            )
            TSGroupThread.forUnitTest(
                masterKey: try noLongerBlockedGroupParams.getMasterKey(),
            ).anyInsert(transaction: tx)
            blockingManager.addBlockedGroupId(
                try noLongerBlockedGroupParams.getPublicParams().getGroupIdentifier().serialize(),
                blockMode: .localShouldNotLeaveGroups,
                transaction: tx,
            )

            blockingManager.addBlockedAddress(
                SignalServiceAddress(stillBlockedAci),
                blockMode: .localShouldNotLeaveGroups,
                transaction: tx,
            )
            blockingManager.addBlockedAddress(
                SignalServiceAddress(stillBlockedPhoneNumber),
                blockMode: .localShouldNotLeaveGroups,
                transaction: tx,
            )
            TSGroupThread.forUnitTest(
                masterKey: try stillBlockedGroupParams.getMasterKey(),
            ).anyInsert(transaction: tx)
            blockingManager.addBlockedGroupId(
                try stillBlockedGroupParams.getPublicParams().getGroupIdentifier().serialize(),
                blockMode: .localShouldNotLeaveGroups,
                transaction: tx,
            )
            _ = otherBlockingManager.blockedAddresses(transaction: tx)
        }

        // Test
        try SSKEnvironment.shared.databaseStorageRef.write { tx in
            blockingManager.processIncomingSync(
                blockedPhoneNumbers: Set([stillBlockedPhoneNumber, newlyBlockedPhoneNumber].map(\.stringValue)),
                blockedAcis: [stillBlockedAci, newlyBlockedAci],
                blockedGroupIds: [
                    try stillBlockedGroupParams.getPublicParams().getGroupIdentifier().serialize(),
                    try newlyBlockedGroupParams.getPublicParams().getGroupIdentifier().serialize(),
                ],
                tx: tx,
            )
        }

        // Verify
        try SSKEnvironment.shared.databaseStorageRef.read { readTx in
            // First, our incoming sync message should've cleared our "NeedsSync" flag
            XCTAssertEqual(
                blockingManager.fetchChangeToken(tx: readTx),
                blockingManager.fetchLastSyncedChangeToken(tx: readTx),
            )

            // Verify our victims aren't blocked anymore
            XCTAssertFalse(blockingManager.isAddressBlocked(SignalServiceAddress(noLongerBlockedAci), transaction: readTx))
            XCTAssertFalse(blockingManager.isAddressBlocked(SignalServiceAddress(noLongerBlockedPhoneNumber), transaction: readTx))
            XCTAssertFalse(blockingManager.isGroupIdBlocked(try noLongerBlockedGroupParams.getPublicParams().getGroupIdentifier(), transaction: readTx))

            XCTAssertTrue(blockingManager.isAddressBlocked(SignalServiceAddress(stillBlockedAci), transaction: readTx))
            XCTAssertTrue(blockingManager.isAddressBlocked(SignalServiceAddress(stillBlockedPhoneNumber), transaction: readTx))
            XCTAssertTrue(blockingManager.isGroupIdBlocked(try stillBlockedGroupParams.getPublicParams().getGroupIdentifier(), transaction: readTx))

            XCTAssertTrue(blockingManager.isAddressBlocked(SignalServiceAddress(newlyBlockedAci), transaction: readTx))
            XCTAssertTrue(blockingManager.isAddressBlocked(SignalServiceAddress(newlyBlockedPhoneNumber), transaction: readTx))
            XCTAssertTrue(blockingManager.isGroupIdBlocked(try newlyBlockedGroupParams.getPublicParams().getGroupIdentifier(), transaction: readTx))

            // Finally, verify that any remote state agrees
            let otherBlockedAddresses = otherBlockingManager.blockedAddresses(transaction: readTx)
            let expectedBlockedAddresses = [
                SignalServiceAddress(stillBlockedAci),
                SignalServiceAddress(stillBlockedPhoneNumber),
                SignalServiceAddress(newlyBlockedAci),
                SignalServiceAddress(newlyBlockedPhoneNumber),
            ]
            XCTAssertEqual(Set(otherBlockedAddresses), Set(expectedBlockedAddresses))
            let otherBlockedGroupIds = otherBlockingManager.blockedGroupIds(transaction: readTx)
            let expectedBlockedGroupIds = [
                try stillBlockedGroupParams.getPublicParams().getGroupIdentifier().serialize(),
                try newlyBlockedGroupParams.getPublicParams().getGroupIdentifier().serialize(),
            ]
            XCTAssertEqual(Set(otherBlockedGroupIds), Set(expectedBlockedGroupIds))
        }
    }

    @MainActor
    func testSendSyncMessage() async {
        // Setup
        // ensure local client has necessary "registered" state
        let identityManager = DependenciesBridge.shared.identityManager
        identityManager.generateAndPersistNewIdentityKey(for: .aci)
        SSKEnvironment.shared.databaseStorageRef.write { tx in
            (DependenciesBridge.shared.registrationStateChangeManager as! RegistrationStateChangeManagerImpl).registerForTests(
                localIdentifiers: .forUnitTests,
                tx: tx,
            )
        }

        SSKEnvironment.shared.messageSenderJobQueueRef.setUp()

        let messageSender = SSKEnvironment.shared.messageSenderRef as! FakeMessageSender
        messageSender.stubbedFailingErrors = [nil]

        await withCheckedContinuation { continuation in
            messageSender.sendMessageWasCalledBlock = { _ in continuation.resume() }
            // Test
            SSKEnvironment.shared.databaseStorageRef.write { tx in
                blockingManager.addBlockedAci(Aci.randomForTesting(), blockMode: .localShouldLeaveGroups, tx: tx)
            }
        }

        // Verify
        XCTAssertEqual(messageSender.sentMessages.count, 1)
        XCTAssert(messageSender.sentMessages.first! is OWSBlockedPhoneNumbersMessage)
    }
}
