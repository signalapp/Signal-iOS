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

    private enum Constants {
        static let maxRetries: UInt = 4
    }

    func runJobAttempt(_ jobRecord: TSAttachmentMultisendJobRecord) async -> JobAttemptResult {
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
            // When this job finishes, the send is enqueued.
            // Send future resolution is handled within the job.
            jobFutures?.enqueuedFuture.resolve(())
        case .failure(let error):
            jobFutures?.enqueuedFuture.reject(error)
        }
    }

    private func _runJobAttempt(_ jobRecord: TSAttachmentMultisendJobRecord) async throws {
        try await TSAttachmentMultisendUploader.uploadAttachments(
            attachmentIdMap: jobRecord.attachmentIdMap,
            sendMessages: { uploadedMessages, tx in
                let preparedStoryMessages: [PreparedOutgoingMessage] = jobRecord.storyMessagesToSend?.map {
                    return PreparedOutgoingMessage.preprepared(
                        outgoingStoryMessage: $0
                    )
                } ?? []
                for preparedMessage in uploadedMessages + preparedStoryMessages {
                    let sendPromise = SSKEnvironment.shared.messageSenderJobQueueRef.add(
                        .promise,
                        message: preparedMessage,
                        transaction: tx
                    )
                    self.jobFutures?.sentFuture.resolve(on: SyncScheduler(), with: sendPromise)
                }
                jobRecord.anyRemove(transaction: tx)
            }
        )
    }
}

// MARK: -

public enum TSAttachmentMultisendUploader {
    public static func uploadAttachments<T>(
        attachmentIdMap: [String: [String]],
        sendMessages: @escaping (_ messages: [PreparedOutgoingMessage], _ tx: SDSAnyWriteTransaction) -> T
    ) async throws -> T {
        let observer = NotificationCenter.default.addObserver(
            forName: Upload.Constants.resourceUploadProgressNotification,
            object: nil,
            queue: nil
        ) { notification in
            guard let notificationResourceId = notification.userInfo?[Upload.Constants.uploadResourceIDKey] as? TSResourceId else {
                owsFailDebug("Missing notificationAttachmentId.")
                return
            }
            guard case let .legacy(notificationAttachmentId) = notificationResourceId else {
                // Ignore v2 attachments in a multisend context.
                return
            }
            guard let progress = notification.userInfo?[Upload.Constants.uploadProgressKey] as? NSNumber else {
                owsFailDebug("Missing progress.")
                return
            }
            guard let correspondingAttachments = attachmentIdMap[notificationAttachmentId] else {
                return
            }
            // Forward upload progress notifications to the corresponding attachments.
            for correspondingId in correspondingAttachments {
                guard correspondingId != notificationAttachmentId else {
                    owsFailDebug("Unexpected attachment id.")
                    continue
                }
                NotificationCenter.default.post(
                    name: Upload.Constants.resourceUploadProgressNotification,
                    object: nil,
                    userInfo: [
                        Upload.Constants.uploadResourceIDKey: TSResourceId.legacy(uniqueId: correspondingId),
                        Upload.Constants.uploadProgressKey: progress
                    ]
                )
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        Logger.info("Starting \(attachmentIdMap.count) uploads")
        try await withThrowingTaskGroup(of: Void.self) { taskGroup in
            SSKEnvironment.shared.databaseStorageRef.read { tx in
                for (attachmentId, correspondingAttachmentIds) in attachmentIdMap {
                    let messageIds: [String] = correspondingAttachmentIds.compactMap { correspondingId in
                        let attachment = TSAttachmentStream.anyFetchAttachmentStream(uniqueId: correspondingId, transaction: tx)
                        guard let attachment else {
                            Logger.warn("correspondingAttachment is missing. User has since deleted?")
                            return nil
                        }
                        guard let messageId = attachment.albumMessageId else {
                            return nil
                        }
                        return messageId
                    }
                    taskGroup.addTask {
                        try await Upload.uploadQueue.run {
                            try await DependenciesBridge.shared.tsResourceUploadManager.uploadAttachment(
                                attachmentId: .legacy(uniqueId: attachmentId),
                                legacyMessageOwnerIds: messageIds
                            )
                        }
                    }
                }
            }
            try await taskGroup.waitForAll()
        }

        return await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { transaction in
            var messageIdsToSend: Set<String> = Set()

            // The attachments we've uploaded don't appear in any thread. Once they're
            // uploaded, update the potentially many corresponding attachments (one per
            // thread that the attachment was uploaded to) with the details of that
            // upload.
            let uploadedAttachments = attachmentIdMap.keys.compactMap { attachmentId in
                // Probably should foreach to check for missing and warn.
                TSAttachmentStream.anyFetchAttachmentStream(
                    uniqueId: attachmentId,
                    transaction: transaction
                )
            }
            for uploadedAttachment in uploadedAttachments {
                guard let correspondingAttachments = attachmentIdMap[uploadedAttachment.uniqueId] else {
                    owsFailDebug("correspondingAttachments was unexpectedly nil")
                    continue
                }

                let serverId = uploadedAttachment.serverId
                let cdnKey = uploadedAttachment.cdnKey
                let cdnNumber = uploadedAttachment.cdnNumber
                let uploadTimestamp = uploadedAttachment.uploadTimestamp
                guard
                    let encryptionKey = uploadedAttachment.encryptionKey,
                    let digest = uploadedAttachment.digest,
                    cdnKey.isEmpty.negated
                else {
                    owsFailDebug("uploaded attachment was incomplete")
                    continue
                }
                if uploadTimestamp < 1 {
                    owsFailDebug("Missing uploadTimestamp.")
                }

                for correspondingId in correspondingAttachments {
                    guard let correspondingAttachment = TSAttachmentStream.anyFetchAttachmentStream(
                        uniqueId: correspondingId,
                        transaction: transaction
                    ) else {
                        Logger.warn("correspondingAttachment is missing. User has since deleted?")
                        continue
                    }
                    correspondingAttachment.updateAsUploaded(
                        withEncryptionKey: encryptionKey,
                        digest: digest,
                        serverId: serverId,
                        cdnKey: cdnKey,
                        cdnNumber: cdnNumber,
                        uploadTimestamp: uploadTimestamp,
                        transaction: transaction
                    )

                    uploadedAttachment.blurHash.map { blurHash in
                        correspondingAttachment.update(withBlurHash: blurHash, transaction: transaction)
                    }

                    guard let albumMessageId = correspondingAttachment.albumMessageId else {
                        continue
                    }
                    messageIdsToSend.insert(albumMessageId)
                }
            }

            let messagesToSend: [PreparedOutgoingMessage] = messageIdsToSend.compactMap { messageId in
                guard let message = TSOutgoingMessage.anyFetchOutgoingMessage(
                        uniqueId: messageId,
                        transaction: transaction
                ) else {
                    owsFailDebug("outgoingMessage was unexpectedly nil")
                    return nil
                }
                return PreparedOutgoingMessage.preprepared(
                    forMultisendOf: message,
                    messageRowId: message.sqliteRowId!
                )
            }

            // The attachment we uploaded should not be associated with any actual
            // messages/threads, and is effectively orphaned.
            owsAssertDebug(uploadedAttachments.allSatisfy { $0.albumMessageId == nil })
#if DEBUG
            for uploadedAttachment in uploadedAttachments {
                guard let uploadedAttachmentInDb = TSAttachmentStream.anyFetchAttachmentStream(
                    uniqueId: uploadedAttachment.uniqueId,
                    transaction: transaction
                ) else {
                    owsFailDebug("Unexpectedly missing uploaded attachment from DB")
                    continue
                }

                owsAssertDebug(uploadedAttachmentInDb.albumMessageId == nil)
            }
#endif

            // TODO: should we delete the orphaned attachments from the DB and disk here, now that we're done with them?

            return sendMessages(messagesToSend, transaction)
        }
    }
}
