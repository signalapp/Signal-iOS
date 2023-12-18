//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalCoreKit

private class LocalUserLeaveGroupJobRunnerFactory: JobRunnerFactory {
    func buildRunner() -> LocalUserLeaveGroupJobRunner { buildRunner(future: nil) }

    func buildRunner(future: Future<TSGroupThread>?) -> LocalUserLeaveGroupJobRunner {
        return LocalUserLeaveGroupJobRunner(future: future)
    }
}

private class LocalUserLeaveGroupJobRunner: JobRunner, Dependencies {
    private enum Constants {
        static let maxRetries: UInt = 110
    }

    private let future: Future<TSGroupThread>?

    init(future: Future<TSGroupThread>?) {
        self.future = future
    }

    func runJobAttempt(_ jobRecord: LocalUserLeaveGroupJobRecord) async -> JobAttemptResult {
        return await JobAttemptResult.executeBlockWithDefaultErrorHandler(
            jobRecord: jobRecord,
            retryLimit: Constants.maxRetries,
            db: DependenciesBridge.shared.db,
            block: {
                let groupThread = try await _runJobAttempt(jobRecord)
                future?.resolve(groupThread)
            }
        )
    }

    func didFinishJob(_ jobRecordId: JobRecord.RowId, result: JobResult) async {
        switch result.ranSuccessfullyOrError {
        case .success:
            break
        case .failure(let error):
            future?.reject(error)
        }
    }

    private func _runJobAttempt(_ jobRecord: LocalUserLeaveGroupJobRecord) async throws -> TSGroupThread {
        if jobRecord.waitForMessageProcessing {
            let groupModel = try databaseStorage.read { tx in
                try fetchGroupModel(threadUniqueId: jobRecord.threadId, tx: tx)
            }
            try await GroupManager.messageProcessingPromise(for: groupModel, description: #fileID).awaitable()
        }

        // Read the group model again from the DB to ensure we have the
        // latest before we try and update the group
        let groupModel = try databaseStorage.read { tx in
            try fetchGroupModel(threadUniqueId: jobRecord.threadId, tx: tx)
        }

        let replacementAdminAci: Aci? = try jobRecord.replacementAdminAciString.map { aciString in
            guard let aci = Aci.parseFrom(aciString: aciString) else {
                throw OWSAssertionError("Couldn't parse replacementAdminAci")
            }
            return aci
        }

        let groupThread = try await GroupManager.updateGroupV2(
            groupModel: groupModel,
            description: #fileID
        ) { groupChangeSet in
            groupChangeSet.setShouldLeaveGroupDeclineInvite()

            // Sometimes when we leave a group we take care to assign a new admin.
            if let replacementAdminAci {
                groupChangeSet.changeRoleForMember(replacementAdminAci, role: .administrator)
            }
        }.awaitable()

        await databaseStorage.awaitableWrite { tx in
            jobRecord.anyRemove(transaction: tx)
        }

        return groupThread
    }

    private func fetchGroupModel(threadUniqueId: String, tx: SDSAnyReadTransaction) throws -> TSGroupModelV2 {
        guard
            let groupThread = TSGroupThread.anyFetchGroupThread(uniqueId: threadUniqueId, transaction: tx),
            let groupModel = groupThread.groupModel as? TSGroupModelV2
        else {
            throw OWSAssertionError("Missing V2 group thread for operation")
        }
        return groupModel
    }
}

public class LocalUserLeaveGroupJobQueue {
    private let jobQueueRunner: JobQueueRunner<
        JobRecordFinderImpl<LocalUserLeaveGroupJobRecord>,
        LocalUserLeaveGroupJobRunnerFactory
    >
    private let jobRunnerFactory: LocalUserLeaveGroupJobRunnerFactory

    public init(db: DB, reachabilityManager: SSKReachabilityManager) {
        self.jobRunnerFactory = LocalUserLeaveGroupJobRunnerFactory()
        self.jobQueueRunner = JobQueueRunner(
            canExecuteJobsConcurrently: false,
            db: db,
            jobFinder: JobRecordFinderImpl(db: db),
            jobRunnerFactory: self.jobRunnerFactory
        )
        self.jobQueueRunner.listenForReachabilityChanges(reachabilityManager: reachabilityManager)
    }

    func start(appContext: AppContext) {
        jobQueueRunner.start(shouldRestartExistingJobs: appContext.isMainApp)
    }

    // MARK: - Promises

    public func addJob(
        groupThread: TSGroupThread,
        replacementAdminAci: Aci?,
        waitForMessageProcessing: Bool,
        tx: SDSAnyWriteTransaction
    ) -> Promise<TSGroupThread> {
        guard groupThread.isGroupV2Thread else {
            owsFail("[GV1] Mutations on V1 groups should be impossible!")
        }
        return Promise { future in
            addJob(
                threadId: groupThread.uniqueId,
                replacementAdminAci: replacementAdminAci,
                waitForMessageProcessing: waitForMessageProcessing,
                future: future,
                tx: tx
            )
        }
    }

    private func addJob(
        threadId: String,
        replacementAdminAci: Aci?,
        waitForMessageProcessing: Bool,
        future: Future<TSGroupThread>,
        tx: SDSAnyWriteTransaction
    ) {
        let jobRecord = LocalUserLeaveGroupJobRecord(
            threadId: threadId,
            replacementAdminAci: replacementAdminAci,
            waitForMessageProcessing: waitForMessageProcessing
        )
        jobRecord.anyInsert(transaction: tx)
        tx.addSyncCompletion {
            self.jobQueueRunner.addPersistedJob(jobRecord, runner: self.jobRunnerFactory.buildRunner(future: future))
        }
    }
}
