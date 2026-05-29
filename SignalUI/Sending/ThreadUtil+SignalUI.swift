//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import SignalServiceKit

extension ThreadUtil {

    // MARK: - Durable Message Enqueue

    public class func enqueueMessage(
        body messageBody: MessageBody?,
        attachments: ([SendableAttachment], isViewOnce: Bool) = ([], isViewOnce: false),
        thread: TSThread,
        quotedReplyDraft: DraftQuotedReplyModel? = nil,
        linkPreviewDraft: OWSLinkPreviewDraft? = nil,
        linkPreviewDraftForSending: Task<OWSLinkPreviewDraft?, Never>? = nil,
        persistenceCompletionHandler persistenceCompletion: PersistenceCompletion? = nil,
    ) {
        let messageTimestamp = MessageTimestampGenerator.sharedInstance.generateTimestamp()

        let benchEventId = sendMessageBenchEventStart(messageTimestamp: messageTimestamp)
        self.enqueueSendQueue.enqueue {
            let pendingLinkPreviewDraftTask = linkPreviewDraft == nil ? linkPreviewDraftForSending : nil
            let unpreparedMessage: UnpreparedOutgoingMessage
            do {
                let messageBody = try await messageBody.mapAsync {
                    try await DependenciesBridge.shared.attachmentContentValidator
                        .prepareOversizeTextIfNeeded($0)
                } ?? nil
                let linkPreviewDataSource = try await linkPreviewDraft.mapAsync {
                    try await DependenciesBridge.shared.linkPreviewManager.buildDataSource(from: $0)
                }
                let attachmentContentValidator = DependenciesBridge.shared.attachmentContentValidator
                let attachmentsForSending = try await attachments.0.mapAsync {
                    try await $0.forSending(attachmentContentValidator: attachmentContentValidator)
                }
                let quotedReplyDraft = try await quotedReplyDraft.mapAsync {
                    try await DependenciesBridge.shared.quotedReplyManager.prepareDraftForSending($0)
                }

                unpreparedMessage = SSKEnvironment.shared.databaseStorageRef.read { readTransaction in
                    UnpreparedOutgoingMessage.build(
                        thread: thread,
                        timestamp: messageTimestamp,
                        messageBody: messageBody,
                        mediaAttachments: attachmentsForSending,
                        isViewOnce: attachments.isViewOnce,
                        quotedReplyDraft: quotedReplyDraft,
                        linkPreviewDataSource: linkPreviewDataSource,
                        transaction: readTransaction,
                    )
                }
            } catch {
                owsFailDebug("Failed to build message")
                return
            }

            guard
                let deferredSend = await Self.prepareMessageForDeferredSend(
                    unpreparedMessage,
                    persistenceCompletionHandler: persistenceCompletion,
                )
            else {
                return
            }

            Self.sendFinalizationQueue.enqueue {
                await Self.finalizeDeferredSend(
                    deferredSend,
                    pendingLinkPreviewDraftForSending: pendingLinkPreviewDraftTask,
                    benchEventId: benchEventId,
                )
            }
        }
    }

    public class func enqueueEditMessage(
        body messageBody: MessageBody?,
        thread: TSThread,
        quotedReplyEdit: MessageEdits.Edit<Void>,
        linkPreviewDraft: OWSLinkPreviewDraft?,
        linkPreviewDraftForSending: Task<OWSLinkPreviewDraft?, Never>? = nil,
        editTarget: TSOutgoingMessage,
        persistenceCompletionHandler persistenceCompletion: PersistenceCompletion? = nil,
    ) {
        AssertIsOnMainThread()

        let messageTimestamp = MessageTimestampGenerator.sharedInstance.generateTimestamp()

        let benchEventId = sendMessageBenchEventStart(messageTimestamp: messageTimestamp)
        self.enqueueSendQueue.enqueue {
            let unpreparedMessage: UnpreparedOutgoingMessage
            do {
                let messageBody = try await messageBody.mapAsync {
                    try await DependenciesBridge.shared.attachmentContentValidator
                        .prepareOversizeTextIfNeeded($0)
                } ?? nil
                let resolvedLinkPreviewDraft = await Self.resolveLinkPreviewDraftForSending(
                    linkPreviewDraft: linkPreviewDraft,
                    linkPreviewDraftForSending: linkPreviewDraftForSending,
                )
                let linkPreviewDataSource = try await resolvedLinkPreviewDraft.mapAsync {
                    try await DependenciesBridge.shared.linkPreviewManager.buildDataSource(from: $0)
                }

                unpreparedMessage = UnpreparedOutgoingMessage.buildForEdit(
                    thread: thread,
                    timestamp: messageTimestamp,
                    messageBody: messageBody,
                    quotedReplyEdit: quotedReplyEdit,
                    linkPreviewDataSource: linkPreviewDataSource,
                    editTarget: editTarget,
                )
            } catch {
                owsFailDebug("Failed to build message")
                return
            }

            await Self.enqueueMessageSync(
                unpreparedMessage,
                benchEventId: benchEventId,
                thread: thread,
                persistenceCompletionHandler: persistenceCompletion,
            )
        }
    }

    // MARK: - Durable Message Enqueue

    class func enqueueMessage(
        _ unpreparedMessage: UnpreparedOutgoingMessage,
        thread: TSThread,
        persistenceCompletionHandler persistenceCompletion: PersistenceCompletion? = nil,
    ) {
        let benchEventId = sendMessageBenchEventStart(messageTimestamp: unpreparedMessage.messageTimestampForLogging)
        self.enqueueSendQueue.enqueue {
            await Self.enqueueMessageSync(
                unpreparedMessage,
                benchEventId: benchEventId,
                thread: thread,
                persistenceCompletionHandler: persistenceCompletion,
            )
        }
    }

    private static func resolveLinkPreviewDraftForSending(
        linkPreviewDraft: OWSLinkPreviewDraft?,
        linkPreviewDraftForSending: Task<OWSLinkPreviewDraft?, Never>?,
    ) async -> OWSLinkPreviewDraft? {
        guard let linkPreviewDraftForSending else {
            return linkPreviewDraft
        }

        // Preserve send/edit action order when a current link preview is still resolving.
        return await linkPreviewDraftForSending.value
    }

    /// WARNING: MUST be called on enqueueSendQueue!
    private class func enqueueMessageSync(
        _ unpreparedMessage: UnpreparedOutgoingMessage,
        benchEventId: String,
        thread: TSThread,
        persistenceCompletionHandler persistenceCompletion: PersistenceCompletion? = nil,
    ) async {
        await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { writeTransaction in
            guard let preparedMessage = try? unpreparedMessage.prepare(tx: writeTransaction) else {
                owsFailDebug("Failed to prepare message")
                return
            }
            let promise = SSKEnvironment.shared.messageSenderJobQueueRef.add(
                .promise,
                message: preparedMessage,
                transaction: writeTransaction,
            )
            if let persistenceCompletion {
                writeTransaction.addSyncCompletion {
                    Task { @MainActor in
                        persistenceCompletion()
                    }
                }
            }
            _ = promise.done(on: DispatchQueue.global()) {
                BenchEventComplete(eventId: benchEventId)
            }

            if
                let messageForIntent = preparedMessage.messageForIntentDonation(tx: writeTransaction),
                let thread = messageForIntent.thread(tx: writeTransaction)
            {
                thread.donateSendMessageIntent(for: messageForIntent, transaction: writeTransaction)
            }
        }
    }

    /// WARNING: MUST be called on enqueueSendQueue!
    private struct DeferredSend {
        let message: UnpreparedOutgoingMessage.DeferredPersistedMessage
        let job: MessageSenderJobQueue.DeferredJob
        let promise: Promise<Void>
    }

    /// WARNING: MUST be called on enqueueSendQueue!
    private class func prepareMessageForDeferredSend(
        _ unpreparedMessage: UnpreparedOutgoingMessage,
        persistenceCompletionHandler persistenceCompletion: PersistenceCompletion? = nil,
    ) async -> DeferredSend? {
        await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { writeTransaction in
            do {
                let deferredMessage = try unpreparedMessage.preparePersistableMessageForDeferredSend(tx: writeTransaction)
                guard
                    let message = TSOutgoingMessage.fetchOutgoingMessageViaCache(
                        uniqueId: deferredMessage.messageUniqueId,
                        transaction: writeTransaction,
                    ),
                    message.sqliteRowId == deferredMessage.messageRowId
                else {
                    throw OWSAssertionError("Failed to enqueue deferred message sender job.")
                }
                let (deferredJob, promise) = SSKEnvironment.shared.messageSenderJobQueueRef.addDeferred(
                    .promise,
                    message: PreparedOutgoingMessage.preprepared(
                        forResending: message,
                        messageRowId: deferredMessage.messageRowId,
                    ),
                    transaction: writeTransaction,
                )
                if let persistenceCompletion {
                    writeTransaction.addSyncCompletion {
                        Task { @MainActor in
                            persistenceCompletion()
                        }
                    }
                }
                return DeferredSend(message: deferredMessage, job: deferredJob, promise: promise)
            } catch {
                owsFailDebug("Failed to prepare deferred message")
                return nil
            }
        }
    }

    /// WARNING: MUST be called on sendFinalizationQueue!
    private class func finalizeDeferredSend(
        _ deferredSend: DeferredSend,
        pendingLinkPreviewDraftForSending: Task<OWSLinkPreviewDraft?, Never>?,
        benchEventId: String,
    ) async {
        let deferredMessage = deferredSend.message
        let linkPreviewDataSource: LinkPreviewDataSource?
        do {
            let linkPreviewDraft = await pendingLinkPreviewDraftForSending?.value
            linkPreviewDataSource = try await linkPreviewDraft.mapAsync {
                try await DependenciesBridge.shared.linkPreviewManager.buildDataSource(from: $0)
            }
        } catch {
            owsFailDebug("Failed to build deferred link preview")
            await Self.markDeferredMessageAsFailed(deferredSend, error: error)
            return
        }

        do {
            try await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { writeTransaction in
                let message: TSOutgoingMessage
                if let linkPreviewDataSource {
                    message = try UnpreparedOutgoingMessage.applyLinkPreviewDataSourceToDeferredMessage(
                        linkPreviewDataSource,
                        messageUniqueId: deferredMessage.messageUniqueId,
                        messageRowId: deferredMessage.messageRowId,
                        tx: writeTransaction,
                    )
                } else {
                    guard
                        let fetchedMessage = TSOutgoingMessage.fetchOutgoingMessageViaCache(
                            uniqueId: deferredMessage.messageUniqueId,
                            transaction: writeTransaction,
                        ),
                        fetchedMessage.sqliteRowId == deferredMessage.messageRowId
                    else {
                        throw OWSAssertionError("Missing deferred message.")
                    }
                    message = fetchedMessage
                }
                try SSKEnvironment.shared.messageSenderJobQueueRef.startDeferredJob(
                    deferredSend.job,
                    message: PreparedOutgoingMessage.preprepared(
                        forResending: message,
                        messageRowId: deferredMessage.messageRowId,
                    ),
                    transaction: writeTransaction,
                )
            }

            _ = deferredSend.promise.done(on: DispatchQueue.global()) {
                BenchEventComplete(eventId: benchEventId)
            }
        } catch {
            owsFailDebug("Failed to finalize deferred message")
            await Self.markDeferredMessageAsFailed(deferredSend, error: error)
        }
    }

    private class func markDeferredMessageAsFailed(
        _ deferredSend: DeferredSend,
        error: any Error,
    ) async {
        let deferredMessage = deferredSend.message
        await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { writeTransaction in
            if
                let message = TSOutgoingMessage.fetchOutgoingMessageViaCache(
                    uniqueId: deferredMessage.messageUniqueId,
                    transaction: writeTransaction,
                )
            {
                message.updateWithAllSendingRecipientsMarkedAsFailed(error: error, transaction: writeTransaction)
            }
            SSKEnvironment.shared.messageSenderJobQueueRef.cancelDeferredJob(
                deferredSend.job,
                error: error,
                transaction: writeTransaction,
            )
        }
    }

    private static func sendMessageBenchEventStart(messageTimestamp: UInt64) -> String {
        let eventId = "sendMessageMarkedAsSent-\(messageTimestamp)"
        BenchEventStart(
            title: "Send Message Milestone: Marked as Sent (\(messageTimestamp))",
            eventId: eventId,
            logInProduction: true,
        )
        return eventId
    }
}

// MARK: -

extension UnpreparedOutgoingMessage {

    public static func build(
        thread: TSThread,
        timestamp: UInt64? = nil,
        messageBody: ValidatedMessageBody?,
        mediaAttachments: [SendableAttachment.ForSending] = [],
        isViewOnce: Bool = false,
        quotedReplyDraft: DraftQuotedReplyModel.ForSending?,
        linkPreviewDataSource: LinkPreviewDataSource?,
        transaction: DBReadTransaction,
    ) -> UnpreparedOutgoingMessage {
        assert(!isViewOnce || mediaAttachments.count == 1)
        assert(!mediaAttachments.contains(where: { $0.renderingFlag == .borderless }) || mediaAttachments.count == 1)

        let dmConfigurationStore = DependenciesBridge.shared.disappearingMessagesConfigurationStore
        let dmConfig = dmConfigurationStore.fetchOrBuildDefault(for: .thread(thread), tx: transaction)

        let isVoiceMessage = mediaAttachments.count == 1
            && messageBody?.oversizeText == nil
            && mediaAttachments.last?.renderingFlag == .voiceMessage

        let messageBuilder: TSOutgoingMessageBuilder = .withDefaultValues(thread: thread, timestamp: timestamp)

        messageBuilder.setMessageBody(messageBody)

        messageBuilder.expiresInSeconds = dmConfig.durationSeconds
        messageBuilder.expireTimerVersion = NSNumber(value: dmConfig.timerVersion)
        messageBuilder.isVoiceMessage = isVoiceMessage
        messageBuilder.isViewOnceMessage = isViewOnce

        let message = messageBuilder.build(transaction: transaction)

        let attachmentInfos = mediaAttachments.map(\.dataSource)

        let unpreparedMessage = UnpreparedOutgoingMessage.forMessage(
            message,
            body: messageBody,
            unsavedBodyMediaAttachments: attachmentInfos,
            linkPreviewDraft: linkPreviewDataSource,
            quotedReplyDraft: quotedReplyDraft,
        )
        return unpreparedMessage
    }

    public static func buildForEdit(
        thread: TSThread,
        timestamp: UInt64,
        messageBody: ValidatedMessageBody?,
        quotedReplyEdit: MessageEdits.Edit<Void>,
        linkPreviewDataSource: LinkPreviewDataSource?,
        editTarget: TSOutgoingMessage,
    ) -> UnpreparedOutgoingMessage {

        let oversizeTextDataSource: AttachmentDataSource? = messageBody?.oversizeText.map { .pendingAttachment($0) }

        let edits: MessageEdits = .forOutgoingEdit(
            timestamp: .change(timestamp),
            // "Received" now!
            receivedAtTimestamp: .change(Date.ows_millisecondTimestamp()),
            body: .change(messageBody),
        )

        let unpreparedMessage = UnpreparedOutgoingMessage.forEditMessage(
            targetMessage: editTarget,
            edits: edits,
            oversizeTextDataSource: oversizeTextDataSource,
            linkPreviewDraft: linkPreviewDataSource,
            quotedReplyEdit: quotedReplyEdit,
        )
        return unpreparedMessage
    }
}
