//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public struct TSAttachmentMultisendResult {
    /// Resolved when the attachments are uploaded and sending is enqueued.
    public let enqueuedPromise: Promise<Void>
    /// Resolved when the message is sent.
    public let sentPromise: Promise<Void>
}

public class TSAttachmentMultisendJobQueue {
    private let jobQueueRunner: JobQueueRunner<
        JobRecordFinderImpl<TSAttachmentMultisendJobRecord>,
        TSAttachmentMultisendJobRunnerFactory
    >
    private let jobRunnerFactory: TSAttachmentMultisendJobRunnerFactory

    public init(db: any DB, reachabilityManager: SSKReachabilityManager) {
        self.jobRunnerFactory = TSAttachmentMultisendJobRunnerFactory()
        self.jobQueueRunner = JobQueueRunner(
            canExecuteJobsConcurrently: false,
            db: db,
            jobFinder: JobRecordFinderImpl(db: db),
            jobRunnerFactory: jobRunnerFactory
        )
        self.jobQueueRunner.listenForReachabilityChanges(reachabilityManager: reachabilityManager)
    }

    public func start(appContext: AppContext) {
        if appContext.isNSE { return }
        jobQueueRunner.start(shouldRestartExistingJobs: appContext.isMainApp)
    }

    @discardableResult
    public func add(
        attachmentIdMap: [String: [String]],
        storyMessagesToSend: [OutgoingStoryMessage],
        transaction: SDSAnyWriteTransaction
    ) -> TSAttachmentMultisendResult {
        let jobRecord = TSAttachmentMultisendJobRecord(
            attachmentIdMap: attachmentIdMap,
            storyMessagesToSend: storyMessagesToSend
        )
        jobRecord.anyInsert(transaction: transaction)

        let enqueuePromise = Promise<Void>.pending()
        let sendPromise = Promise<Void>.pending()
        let jobFutures = TSAttachmentMultisendFutures(
            enqueuedFuture: enqueuePromise.1,
            sentFuture: sendPromise.1
        )

        transaction.addSyncCompletion {
            let runner = self.jobRunnerFactory.buildRunner(jobFutures)
            self.jobQueueRunner.addPersistedJob(jobRecord, runner: runner)
        }

        return .init(
            enqueuedPromise: enqueuePromise.0,
            sentPromise: sendPromise.0
        )
    }
}

private class TSAttachmentMultisendFutures {
    /// Resolved when the attachments are uploaded and sending is enqueued.
    public let enqueuedFuture: Future<Void>
    /// Resolved when the message is sent.
    public let sentFuture: Future<Void>

    init(enqueuedFuture: Future<Void>, sentFuture: Future<Void>) {
        self.enqueuedFuture = enqueuedFuture
        self.sentFuture = sentFuture
    }
}

private class TSAttachmentMultisendJobRunnerFactory: JobRunnerFactory {

    func buildRunner() -> TSAttachmentMultisendJobRunner {
        TSAttachmentMultisendJobRunner(jobFutures: nil)
    }

    func buildRunner(_ jobFutures: TSAttachmentMultisendFutures?) -> TSAttachmentMultisendJobRunner {
        TSAttachmentMultisendJobRunner(jobFutures: jobFutures)
    }
}

private class TSAttachmentMultisendJobRunner: JobRunner {

    private let jobFutures: TSAttachmentMultisendFutures?

    init(jobFutures: TSAttachmentMultisendFutures?) {
        self.jobFutures = jobFutures
    }

    func runJobAttempt(_ jobRecord: TSAttachmentMultisendJobRecord) async -> JobAttemptResult {
        owsFailDebug("TSAttachment is obsoleted")
        await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { transaction in
            jobRecord.anyRemove(transaction: transaction)
        }
        return .finished(.success(()))
    }

    func didFinishJob(_ jobRecordId: JobRecord.RowId, result: JobResult) async {
        switch result.ranSuccessfullyOrError {
        case .success:
            // When this job finishes, the send is enqueued.
            // Send future resolution is handled within the job.
            jobFutures?.enqueuedFuture.resolve(())
        case .failure(let error):
            jobFutures?.enqueuedFuture.reject(error)
        }
    }
}
