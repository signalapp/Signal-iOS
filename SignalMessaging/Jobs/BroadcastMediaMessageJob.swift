//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

public class BroadcastMediaMessageJobQueue {
    private let jobQueueRunner: JobQueueRunner<
        JobRecordFinderImpl<BroadcastMediaMessageJobRecord>,
        BroadcastMediaMessageJobRunnerFactory
    >

    public init(db: DB, reachabilityManager: SSKReachabilityManager) {
        self.jobQueueRunner = JobQueueRunner(
            canExecuteJobsConcurrently: false,
            db: db,
            jobFinder: JobRecordFinderImpl(db: db),
            jobRunnerFactory: BroadcastMediaMessageJobRunnerFactory()
        )
        self.jobQueueRunner.listenForReachabilityChanges(reachabilityManager: reachabilityManager)
    }

    func start(appContext: AppContext) {
        if appContext.isNSE { return }
        jobQueueRunner.start(shouldRestartExistingJobs: appContext.isMainApp)
    }

    public func add(attachmentIdMap: [String: [String]], unsavedMessagesToSend: [TSOutgoingMessage], transaction: SDSAnyWriteTransaction) {
        let jobRecord = BroadcastMediaMessageJobRecord(
            attachmentIdMap: attachmentIdMap,
            unsavedMessagesToSend: unsavedMessagesToSend
        )
        jobRecord.anyInsert(transaction: transaction)
        transaction.addSyncCompletion { self.jobQueueRunner.addPersistedJob(jobRecord) }
    }
}

private class BroadcastMediaMessageJobRunnerFactory: JobRunnerFactory {
    func buildRunner() -> BroadcastMediaMessageJobRunner { BroadcastMediaMessageJobRunner() }
}

private class BroadcastMediaMessageJobRunner: JobRunner, Dependencies {
    private enum Constants {
        static let maxRetries: UInt = 4
    }

    func runJobAttempt(_ jobRecord: BroadcastMediaMessageJobRecord) async -> JobAttemptResult {
        return await .executeBlockWithDefaultErrorHandler(
            jobRecord: jobRecord,
            retryLimit: Constants.maxRetries,
            db: DependenciesBridge.shared.db,
            block: { try await _runJobAttempt(jobRecord) }
        )
    }

    func didFinishJob(_ jobRecordId: JobRecord.RowId, result: JobResult) async {}

    private func _runJobAttempt(_ jobRecord: BroadcastMediaMessageJobRecord) async throws {
        try await BroadcastMediaUploader.uploadAttachments(
            attachmentIdMap: jobRecord.attachmentIdMap,
            sendMessages: { uploadedMessages, tx in
                for message in uploadedMessages + (jobRecord.unsavedMessagesToSend ?? []) {
                    SSKEnvironment.shared.messageSenderJobQueueRef.add(message: message.asPreparer, transaction: tx)
                }
                jobRecord.anyRemove(transaction: tx)
            }
        )
    }
}

// MARK: -

public enum BroadcastMediaUploader: Dependencies {
    public static func uploadAttachments<T>(
        attachmentIdMap: [String: [String]],
        sendMessages: @escaping (_ messages: [TSOutgoingMessage], _ tx: SDSAnyWriteTransaction) -> T
    ) async throws -> T {
        let observer = NotificationCenter.default.addObserver(
            forName: Upload.Constants.uploadProgressNotification,
            object: nil,
            queue: nil
        ) { notification in
            guard let notificationAttachmentId = notification.userInfo?[Upload.Constants.uploadAttachmentIDKey] as? String else {
                owsFailDebug("Missing notificationAttachmentId.")
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
                    name: Upload.Constants.uploadProgressNotification,
                    object: nil,
                    userInfo: [
                        Upload.Constants.uploadAttachmentIDKey: correspondingId,
                        Upload.Constants.uploadProgressKey: progress
                    ]
                )
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        let uploadOperations: [AsyncBlockOperation] = databaseStorage.read { tx in
            return attachmentIdMap.map { (attachmentId, correspondingAttachmentIds) in
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
                return AsyncBlockOperation {
                    try await DependenciesBridge.shared.uploadManager.uploadAttachment(
                        attachmentId: attachmentId,
                        messageIds: messageIds,
                        version: FeatureFlags.useAttachmentsV4Endpoint ? .v4 : .v3
                    )
                }
            }
        }

        Logger.info("Starting \(uploadOperations.count) uploads")

        try? await withCheckedThrowingContinuation { continuation in
            let waitingOperation = AwaitableAsyncBlockOperation(completionContinuation: continuation, asyncBlock: {})
            uploadOperations.forEach { waitingOperation.addDependency($0) }
            Upload.uploadQueue.addOperations(uploadOperations, waitUntilFinished: false)
            Upload.uploadQueue.addOperation(waitingOperation)
        }
        if let error = (uploadOperations.compactMap { $0.failingError }).first { throw error }

        return await databaseStorage.awaitableWrite { transaction in
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

            let messagesToSend: [TSOutgoingMessage] = messageIdsToSend.compactMap { messageId in
                guard let message = TSOutgoingMessage.anyFetchOutgoingMessage(
                        uniqueId: messageId,
                        transaction: transaction
                ) else {
                    owsFailDebug("outgoingMessage was unexpectedly nil")
                    return nil
                }
                return message
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
