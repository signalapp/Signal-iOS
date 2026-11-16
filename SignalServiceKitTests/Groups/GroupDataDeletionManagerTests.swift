//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import XCTest

@testable import SignalServiceKit

final class GroupDataDeletionManagerTests: SSKBaseTest {
    private var bulkDeleteInteractionJobQueue: BulkDeleteInteractionJobQueue!
    private var groupDataDeletionManager: GroupDataDeletionManagerImpl!

    override func setUp() {
        super.setUp()
        write { tx in
            (DependenciesBridge.shared.registrationStateChangeManager as! RegistrationStateChangeManagerImpl).registerForTests(
                localIdentifiers: .forUnitTests,
                tx: tx,
            )
        }
        bulkDeleteInteractionJobQueue = BulkDeleteInteractionJobQueue(
            addressableMessageFinder: DeleteForMeAddressableMessageFinderImpl(),
            db: DependenciesBridge.shared.db,
            interactionDeleteManager: DependenciesBridge.shared.interactionDeleteManager,
            threadDeletionManager: DependenciesBridge.shared.threadDeletionManager,
            threadStore: ThreadStoreImpl(),
            tsAccountManager: DependenciesBridge.shared.tsAccountManager,
        )
        groupDataDeletionManager = GroupDataDeletionManagerImpl(
            bulkDeleteInteractionJobQueue: bulkDeleteInteractionJobQueue,
            threadDeletionManager: DependenciesBridge.shared.threadDeletionManager,
        )
    }

    private func insertGroupThread(tx: DBWriteTransaction) -> TSGroupThread {
        return try! GroupManager.createGroupForTests(
            members: [LocalIdentifiers.forUnitTests.aciAddress],
            name: "Roommates",
            transaction: tx,
        )
    }

    private func insertInfoMessage(in groupThread: TSGroupThread, tx: DBWriteTransaction) -> TSInfoMessage {
        let infoMessage = TSInfoMessage(thread: groupThread, messageType: .typeGroupUpdate)
        infoMessage.anyInsert(transaction: tx)
        return infoMessage
    }

    private func bulkDeleteJobCount() -> Int {
        return SSKEnvironment.shared.databaseStorageRef.read { tx in
            try! Int.fetchOne(
                tx.database,
                sql: """
                    SELECT COUNT(*) FROM \(BulkDeleteInteractionJobRecord.databaseTableName)
                    WHERE "\(BulkDeleteInteractionJobRecord.columnName(.label))" = ?
                """,
                arguments: [BulkDeleteInteractionJobRecord.jobRecordType.jobRecordLabel],
            )!
        }
    }

    private func waitForBulkDeleteJobsToFinish() async throws {
        let deadline = Date().addingTimeInterval(10)
        while bulkDeleteJobCount() > 0 {
            guard Date() < deadline else {
                XCTFail("Bulk delete job didn't finish")
                return
            }
            try await Task.sleep(nanoseconds: 10 * NSEC_PER_MSEC)
        }
    }

    func testDeletesOnlyInteractionsBeforePreservedInteraction() async throws {
        let (groupThread, preservedMessage, laterMessage) = await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
            let groupThread = self.insertGroupThread(tx: tx)
            _ = self.insertInfoMessage(in: groupThread, tx: tx)
            _ = self.insertInfoMessage(in: groupThread, tx: tx)
            let preservedMessage = self.insertInfoMessage(in: groupThread, tx: tx)
            self.groupDataDeletionManager.deleteGroupData(
                groupThread: groupThread,
                preservedInteraction: preservedMessage,
                localIdentifiers: .forUnitTests,
                tx: tx,
            )
            let laterMessage = self.insertInfoMessage(in: groupThread, tx: tx)
            return (groupThread, preservedMessage, laterMessage)
        }

        bulkDeleteInteractionJobQueue.start(appContext: CurrentAppContext())
        try await waitForBulkDeleteJobsToFinish()

        let remainingUniqueIds = SSKEnvironment.shared.databaseStorageRef.read { tx in
            try! InteractionFinder(threadUniqueId: groupThread.uniqueId)
                .fetchAllInteractions(rowIdFilter: .newest, limit: 10, tx: tx)
                .map(\.uniqueId)
        }
        XCTAssertEqual(Set(remainingUniqueIds), [preservedMessage.uniqueId, laterMessage.uniqueId])
    }

    func testClearsDrafts() throws {
        let voiceMessageUrl = OWSFileSystem.temporaryFileUrl(isAvailableWhileDeviceLocked: true)
        try Data(count: 16).write(to: voiceMessageUrl)

        let groupThread = write { tx in
            let groupThread = insertGroupThread(tx: tx)
            groupThread.anyUpdate(transaction: tx) { thread in
                thread.messageDraft = "Draft"
            }
            _ = VoiceMessageInterruptedDraftStore.saveDraft(
                audioFileUrl: voiceMessageUrl,
                threadUniqueId: groupThread.uniqueId,
                transaction: tx,
            )
            let preservedMessage = insertInfoMessage(in: groupThread, tx: tx)
            groupDataDeletionManager.deleteGroupData(
                groupThread: groupThread,
                preservedInteraction: preservedMessage,
                localIdentifiers: .forUnitTests,
                tx: tx,
            )
            return groupThread
        }

        let (messageDraft, hasVoiceMessageDraft) = SSKEnvironment.shared.databaseStorageRef.read { tx in
            (
                TSThread.anyFetch(uniqueId: groupThread.uniqueId, transaction: tx)?.messageDraft,
                VoiceMessageInterruptedDraftStore.hasDraft(for: groupThread.uniqueId, transaction: tx),
            )
        }
        XCTAssertNil(messageDraft)
        XCTAssertFalse(hasVoiceMessageDraft)
    }
}
