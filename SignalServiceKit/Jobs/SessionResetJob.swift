//
// Copyright 2016 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

final public class SessionResetJobQueue {
    private let jobQueueRunner: JobQueueRunner<JobRecordFinderImpl<SessionResetJobRecord>, SessionResetJobRunnerFactory>

    public init(db: any DB, reachabilityManager: SSKReachabilityManager) {
        self.jobQueueRunner = JobQueueRunner(
            canExecuteJobsConcurrently: true,
            db: db,
            jobFinder: JobRecordFinderImpl(db: db),
            jobRunnerFactory: SessionResetJobRunnerFactory()
        )
        self.jobQueueRunner.listenForReachabilityChanges(reachabilityManager: reachabilityManager)
    }

    public func start(appContext: AppContext) {
        guard appContext.isMainApp else { return }
        jobQueueRunner.start(shouldRestartExistingJobs: true)
    }

    public func add(contactThread: TSContactThread, transaction tx: DBWriteTransaction) {
        let jobRecord = SessionResetJobRecord(contactThread: contactThread)
        jobRecord.anyInsert(transaction: tx)
        tx.addSyncCompletion { self.jobQueueRunner.addPersistedJob(jobRecord) }
    }
}

final private class SessionResetJobRunnerFactory: JobRunnerFactory {
    func buildRunner() -> SessionResetJobRunner { SessionResetJobRunner() }
}

final private class SessionResetJobRunner: JobRunner {
    private enum Constants {
        static let maxRetries: UInt = 10
    }

    private var hasArchivedAllSessions = false

    func runJobAttempt(_ jobRecord: SessionResetJobRecord) async -> JobAttemptResult {
        do {
            try await _runJobAttempt(jobRecord)
            return .finished(.success(()))
        } catch {
            return await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
                let result = JobAttemptResult.performDefaultErrorHandler(
                    error: error, jobRecord: jobRecord, retryLimit: Constants.maxRetries, tx: tx
                )
                if case .finished(.failure) = result {
                    // Even though this is the failure handler - which means probably the
                    // recipient didn't receive the message - there's a chance that our send
                    // did succeed and the server just timed out our response or something.
                    // Since the cost of sending a future message using a session the recipient
                    // doesn't have is so high, we archive the session just in case.
                    Logger.warn("Terminal failure: \(error)")
                    if let contactThread = try? self.fetchThread(jobRecord: jobRecord, tx: tx) {
                        self.archiveAllSessions(for: contactThread, tx: tx)
                    }
                }
                return result
            }
        }
    }

    func didFinishJob(_ jobRecordId: JobRecord.RowId, result: JobResult) async {}

    private func _runJobAttempt(_ jobRecord: SessionResetJobRecord) async throws {
        let endSessionMessagePromise = try await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
            let contactThread = try self.fetchThread(jobRecord: jobRecord, tx: tx)
            if !self.hasArchivedAllSessions {
                self.archiveAllSessions(for: contactThread, tx: tx)
            }
            let endSessionMessage = EndSessionMessage(thread: contactThread, transaction: tx)
            let preparedMessage = PreparedOutgoingMessage.preprepared(
                transientMessageWithoutAttachments: endSessionMessage
            )
            return ThreadUtil.enqueueMessagePromise(message: preparedMessage, isHighPriority: true, transaction: tx)
        }
        self.hasArchivedAllSessions = true

        try await endSessionMessagePromise.awaitable()

        Logger.info("successfully sent EndSessionMessage.")
        try await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
            let contactThread = try self.fetchThread(jobRecord: jobRecord, tx: tx)
            // Archive the just-created session since the recipient should delete their
            // corresponding session upon receiving and decrypting our EndSession
            // message. Otherwise if we send another message before them, they won't
            // have the session to decrypt it.
            self.archiveAllSessions(for: contactThread, tx: tx)
            let message = TSInfoMessage(thread: contactThread, messageType: .typeLocalUserEndedSession)
            message.anyInsert(transaction: tx)
            jobRecord.anyRemove(transaction: tx)
        }
    }

    private func fetchThread(jobRecord: SessionResetJobRecord, tx: DBReadTransaction) throws -> TSContactThread {
        let threadId = jobRecord.contactThreadId
        guard let contactThread = TSContactThread.anyFetchContactThread(uniqueId: threadId, transaction: tx) else {
            throw OWSGenericError("thread for session reset no longer exists")
        }
        return contactThread
    }

    private func archiveAllSessions(for contactThread: TSContactThread, tx: DBWriteTransaction) {
        let sessionStore = DependenciesBridge.shared.signalProtocolStoreManager.signalProtocolStore(for: .aci).sessionStore
        sessionStore.archiveAllSessions(for: contactThread.contactAddress, tx: tx)
    }
}
