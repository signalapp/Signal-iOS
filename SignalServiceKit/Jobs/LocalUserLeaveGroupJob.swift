//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

final private class LocalUserLeaveGroupJobRunnerFactory: JobRunnerFactory {
    func buildRunner() -> LocalUserLeaveGroupJobRunner { buildRunner(future: nil) }

    func buildRunner(future: Future<Void>?) -> LocalUserLeaveGroupJobRunner {
        return LocalUserLeaveGroupJobRunner(future: future)
    }
}

final private class LocalUserLeaveGroupJobRunner: JobRunner {
    private enum Constants {
        static let maxRetries: UInt = 110
    }

    private let future: Future<Void>?

    init(future: Future<Void>?) {
        self.future = future
    }

    func runJobAttempt(_ jobRecord: LocalUserLeaveGroupJobRecord) async -> JobAttemptResult {
        return await JobAttemptResult.executeBlockWithDefaultErrorHandler(
            jobRecord: jobRecord,
            retryLimit: Constants.maxRetries,
            db: DependenciesBridge.shared.db,
            block: { try await _runJobAttempt(jobRecord) }
        )
    }

    func didFinishJob(_ jobRecordId: JobRecord.RowId, result: JobResult) async {
        switch result.ranSuccessfullyOrError {
        case .success:
            future?.resolve()
        case .failure(let error):
            future?.reject(error)
        }
    }

    private func _runJobAttempt(_ jobRecord: LocalUserLeaveGroupJobRecord) async throws {
        if jobRecord.waitForMessageProcessing {
            try await GroupManager.waitForMessageFetchingAndProcessingWithTimeout()
        }

        let groupThread = SSKEnvironment.shared.databaseStorageRef.read { tx in
            return TSGroupThread.anyFetchGroupThread(uniqueId: jobRecord.threadId, transaction: tx)
        }

        guard let groupThread, let groupModel = groupThread.groupModel as? TSGroupModelV2 else {
            throw OWSAssertionError("Missing V2 group thread for operation")
        }

        let replacementAdminAci: Aci? = try jobRecord.replacementAdminAciString.map { aciString in
            guard let aci = Aci.parseFrom(aciString: aciString) else {
                throw OWSAssertionError("Couldn't parse replacementAdminAci")
            }
            return aci
        }

        do {
            try await refreshGroupSendEndorsementsIfNeeded(threadId: groupThread.sqliteRowId!, groupModel: groupModel)
        } catch where !error.isNetworkFailureOrTimeout {
            Logger.warn("Tried and failed to refresh credentials; continuing anyways because credentials aren't required; error: \(error)")
        }

        try await GroupManager.updateGroupV2(
            groupModel: groupModel,
            description: #fileID
        ) { groupChangeSet in
            groupChangeSet.setShouldLeaveGroupDeclineInvite()

            // Sometimes when we leave a group we take care to assign a new admin.
            if let replacementAdminAci {
                groupChangeSet.changeRoleForMember(replacementAdminAci, role: .administrator)
            }
        }

        await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
            jobRecord.anyRemove(transaction: tx)
        }
    }

    private func refreshGroupSendEndorsementsIfNeeded(
        threadId: TSGroupThread.RowId,
        groupModel: TSGroupModelV2,
    ) async throws {
        // If we're not a full member, we can't fetch credentials.
        guard groupModel.groupMembership.isLocalUserFullMember else {
            return
        }
        let groupSendEndorsementStore = DependenciesBridge.shared.groupSendEndorsementStore
        let combinedEndorsement = SSKEnvironment.shared.databaseStorageRef.read { tx in
            return try? groupSendEndorsementStore.fetchCombinedEndorsement(groupThreadId: threadId, tx: tx)
        }
        // If we have recent-ish credentials, we don't need to refresh.
        guard GroupSendEndorsements.willExpireSoon(expirationDate: combinedEndorsement?.expiration) else {
            return
        }
        let secretParams = try groupModel.secretParams()
        let groupId = try secretParams.getPublicParams().getGroupIdentifier()
        Logger.info("Refreshing GSEs before leaving \(groupId)")
        // Otherwise, try to refresh the credentials to use them when leaving.
        try await SSKEnvironment.shared.groupV2UpdatesRef.refreshGroup(secretParams: secretParams)
    }
}

final public class LocalUserLeaveGroupJobQueue {
    private let jobQueueRunner: JobQueueRunner<
        JobRecordFinderImpl<LocalUserLeaveGroupJobRecord>,
        LocalUserLeaveGroupJobRunnerFactory
    >
    private var jobSerializer = CompletionSerializer()
    private let jobRunnerFactory: LocalUserLeaveGroupJobRunnerFactory

    public init(db: any DB, reachabilityManager: SSKReachabilityManager) {
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
        tx: DBWriteTransaction
    ) -> Promise<Void> {
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
        future: Future<Void>,
        tx: DBWriteTransaction
    ) {
        let jobRecord = LocalUserLeaveGroupJobRecord(
            threadId: threadId,
            replacementAdminAci: replacementAdminAci,
            waitForMessageProcessing: waitForMessageProcessing
        )
        jobRecord.anyInsert(transaction: tx)
        jobSerializer.addOrderedSyncCompletion(tx: tx) {
            self.jobQueueRunner.addPersistedJob(jobRecord, runner: self.jobRunnerFactory.buildRunner(future: future))
        }
    }
}
