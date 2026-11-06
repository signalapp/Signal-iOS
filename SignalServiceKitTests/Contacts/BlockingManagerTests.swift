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
    private var blockingManager: BlockingManager { SSKEnvironment.shared.blockingManagerRef }
    private var recipientStore: RecipientDatabaseTable { DependenciesBridge.shared.recipientDatabaseTable }

    override func tearDown() {
        let flushTask = blockingManager.flushSyncQueueTask()
        let flushExpectation = self.expectation(description: "flush sync queues")
        Task {
            try! await flushTask.value
            flushExpectation.fulfill()
        }
        self.wait(for: [flushExpectation], timeout: 60)
        super.tearDown()
    }

    private func addBlockedAci(_ aci: Aci, tx: DBWriteTransaction) {
        let recipientFetcher = DependenciesBridge.shared.recipientFetcher
        var recipient = recipientFetcher.fetchOrCreate(serviceId: aci, tx: tx)
        blockingManager.addBlockedRecipient(&recipient, blockedAt: .now(), blockMode: .localUser, tx: tx)
    }

    private func addBlockedPhoneNumber(_ phoneNumber: E164, tx: DBWriteTransaction) {
        let recipientFetcher = DependenciesBridge.shared.recipientFetcher
        var recipient = recipientFetcher.fetchOrCreate(phoneNumber: phoneNumber, tx: tx)
        blockingManager.addBlockedRecipient(&recipient, blockedAt: .now(), blockMode: .localUser, tx: tx)
    }

    private func removeBlockedAci(_ aci: Aci, tx: DBWriteTransaction) {
        let recipient = recipientStore.fetchRecipient(serviceId: aci, transaction: tx)
        guard var recipient else {
            return
        }
        blockingManager.removeBlockedRecipient(&recipient, wasLocallyInitiated: true, tx: tx)
    }

    func testAddBlockedAddress() {
        // Setup
        let aci = Aci.randomForTesting()

        // Test
        expectation(forNotification: BlockingManager.blockListDidChange, object: nil)
        SSKEnvironment.shared.databaseStorageRef.write { tx in
            let oldChangeToken = blockingManager.fetchChangeToken(tx: tx)
            addBlockedAci(aci, tx: tx)
            let newChangeToken = blockingManager.fetchChangeToken(tx: tx)
            // Since this was a local change, we expect to need a sync message
            XCTAssertGreaterThan(newChangeToken, oldChangeToken)
        }

        // Verify
        SSKEnvironment.shared.databaseStorageRef.read { tx in
            // First, query the whole set of blocked addresses:
            let blockedAddresses = recipientStore.fetchBlockedRecipients(tx: tx).map(\.address)
            XCTAssertEqual(blockedAddresses.map { $0.aci }, [aci])
            XCTAssertTrue(blockingManager.isAddressBlocked(SignalServiceAddress(aci), transaction: tx))
        }
        waitForExpectations(timeout: 3)
    }

    func testRemoveBlockedAddress() {
        // Setup
        let blockedAci = Aci.randomForTesting()
        let unblockedAci = Aci.randomForTesting()
        SSKEnvironment.shared.databaseStorageRef.write { tx in
            addBlockedAci(blockedAci, tx: tx)
            addBlockedAci(unblockedAci, tx: tx)
        }

        let oldChangeToken = SSKEnvironment.shared.databaseStorageRef.read { tx in
            return blockingManager.fetchChangeToken(tx: tx)
        }

        // Test
        SSKEnvironment.shared.databaseStorageRef.write { tx in
            removeBlockedAci(unblockedAci, tx: tx)
        }

        // Verify
        SSKEnvironment.shared.databaseStorageRef.read { tx in
            XCTAssertTrue(blockingManager.isAddressBlocked(SignalServiceAddress(blockedAci), transaction: tx))
            XCTAssertFalse(blockingManager.isAddressBlocked(SignalServiceAddress(unblockedAci), transaction: tx))

            // Since this was a local change, we expect to need a sync message
            let newChangeToken = blockingManager.fetchChangeToken(tx: tx)
            XCTAssertGreaterThan(newChangeToken, oldChangeToken)
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
        let newlyBlockedPhoneNumber = E164("+17635550102")!
        let newlyBlockedGroupParams = try GroupSecretParams.generate()

        try SSKEnvironment.shared.databaseStorageRef.write { tx in
            addBlockedAci(noLongerBlockedAci, tx: tx)
            addBlockedPhoneNumber(noLongerBlockedPhoneNumber, tx: tx)
            do {
                let thread = TSGroupThread.forUnitTest(masterKey: try noLongerBlockedGroupParams.getMasterKey())
                thread.anyInsert(transaction: tx)
                var groupRecord = GroupRecord.insertRecord(
                    groupId: thread.groupId,
                    threadId: thread.sqliteRowId!,
                    masterKey: try noLongerBlockedGroupParams.getMasterKey(),
                    refreshedAt: .distantPast,
                    tx: tx,
                )
                blockingManager.addBlockedGroup(
                    &groupRecord,
                    blockedAt: .now(),
                    blockMode: .localUser,
                    tx: tx,
                )
            }

            addBlockedAci(stillBlockedAci, tx: tx)
            addBlockedPhoneNumber(stillBlockedPhoneNumber, tx: tx)
            do {
                let thread = TSGroupThread.forUnitTest(masterKey: try stillBlockedGroupParams.getMasterKey())
                thread.anyInsert(transaction: tx)
                var groupRecord = GroupRecord.insertRecord(
                    groupId: thread.groupId,
                    threadId: thread.sqliteRowId!,
                    masterKey: try stillBlockedGroupParams.getMasterKey(),
                    refreshedAt: .distantPast,
                    tx: tx,
                )
                blockingManager.addBlockedGroup(
                    &groupRecord,
                    blockedAt: .now(),
                    blockMode: .localUser,
                    tx: tx,
                )
            }
        }

        // Test
        try SSKEnvironment.shared.databaseStorageRef.write { tx in
            blockingManager.processIncomingSync(
                blockedPhoneNumbers: [
                    stillBlockedPhoneNumber: .unspecified,
                    newlyBlockedPhoneNumber: .unspecified,
                ],
                blockedAcis: [
                    stillBlockedAci: .unspecified,
                    newlyBlockedAci: .unspecified,
                ],
                blockedGroups: [
                    .V2(try stillBlockedGroupParams.getPublicParams().getGroupIdentifier()): .unspecified,
                    .V2(try newlyBlockedGroupParams.getPublicParams().getGroupIdentifier()): .unspecified,
                ],
                localIdentifiers: .forUnitTests,
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

        fakeMessageSender.stubbedFailingErrors = [nil]

        await withCheckedContinuation { continuation in
            fakeMessageSender.sendMessageWasCalledBlock = { _ in continuation.resume() }
            // Test
            SSKEnvironment.shared.databaseStorageRef.write { tx in
                addBlockedAci(Aci.randomForTesting(), tx: tx)
            }
        }

        // Verify
        XCTAssertEqual(fakeMessageSender.sentMessages.count, 1)
        XCTAssert(fakeMessageSender.sentMessages.first! is OutgoingBlockedSyncMessage)
    }
}
