//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalServiceKit

class TSContactThreadTest: SSKBaseTest {
    private func contactThread() -> TSContactThread {
        TSContactThread.getOrCreateThread(contactAddress: SignalServiceAddress.randomForTesting())
    }

    override func setUp() {
        super.setUp()
        SSKEnvironment.shared.databaseStorageRef.write { tx in
            (DependenciesBridge.shared.registrationStateChangeManager as! RegistrationStateChangeManagerImpl).registerForTests(
                localIdentifiers: .forUnitTests,
                tx: tx,
            )
        }
    }

    func testHasSafetyNumbersWithoutRemoteIdentity() {
        XCTAssertFalse(contactThread().hasSafetyNumbers())
    }

    func testHasSafetyNumbersWithRemoteIdentity() {
        let contactThread = self.contactThread()

        let identityManager = DependenciesBridge.shared.identityManager
        SSKEnvironment.shared.databaseStorageRef.write { tx in
            _ = identityManager.saveIdentityKey(Data(count: 32), for: contactThread.contactAddress.serviceId!, shouldUpdateStorageService: false, tx: tx)
        }

        XCTAssert(contactThread.hasSafetyNumbers())
    }

    func testCanSendChatMessagesToThread() {
        XCTAssertTrue(contactThread().canSendChatMessagesToThread())
    }

    // MARK: - Archiving

    private func isArchivedAfterSendingMessage(shouldKeepMutedChatsArchived: Bool) -> Bool {
        let thread = contactThread()
        return SSKEnvironment.shared.databaseStorageRef.write { tx in
            SSKPreferences.setShouldKeepMutedChatsArchived(shouldKeepMutedChatsArchived, transaction: tx)
            thread.anyUpdate(transaction: tx) {
                $0.isArchived = true
                $0.mutedUntilTimestamp = TSThread.alwaysMutedTimestamp
            }

            let message = TSOutgoingMessageBuilder.outgoingMessageBuilder(thread: thread).build(transaction: tx)
            message.anyInsert(transaction: tx)

            return TSContactThread.fetchViaCache(uniqueId: thread.uniqueId, transaction: tx)!.isArchived
        }
    }

    func testSendingMessageKeepsMutedChatArchivedWhenKeepingMutedChatsArchived() {
        XCTAssertTrue(isArchivedAfterSendingMessage(shouldKeepMutedChatsArchived: true))
    }

    func testSendingMessageUnarchivesMutedChatWhenNotKeepingMutedChatsArchived() {
        XCTAssertFalse(isArchivedAfterSendingMessage(shouldKeepMutedChatsArchived: false))
    }
}
