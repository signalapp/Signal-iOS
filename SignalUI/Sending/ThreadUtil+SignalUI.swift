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
        mediaAttachments: [SignalAttachment] = [],
        thread: TSThread,
        quotedReplyDraft: DraftQuotedReplyModel? = nil,
        linkPreviewDraft: OWSLinkPreviewDraft? = nil,
        persistenceCompletionHandler persistenceCompletion: PersistenceCompletion? = nil
    ) {
        let messageTimestamp = MessageTimestampGenerator.sharedInstance.generateTimestamp()

        let benchEventId = sendMessageBenchEventStart(messageTimestamp: messageTimestamp)
        self.enqueueSendQueue.async {
            let unpreparedMessage: UnpreparedOutgoingMessage
            do {
                let messageBody = try messageBody.map {
                    try DependenciesBridge.shared.attachmentContentValidator
                        .prepareOversizeTextsIfNeeded(from: ["": $0])
                        .values.first
                } ?? nil
                let linkPreviewDataSource = try linkPreviewDraft.map {
                    try DependenciesBridge.shared.linkPreviewManager.buildDataSource(from: $0)
                }
                let mediaAttachments = try mediaAttachments.map {
                    try $0.forSending()
                }
                let quotedReplyDraft = try quotedReplyDraft.map {
                    try DependenciesBridge.shared.quotedReplyManager.prepareDraftForSending($0)
                }

                unpreparedMessage = SSKEnvironment.shared.databaseStorageRef.read { readTransaction in
                    UnpreparedOutgoingMessage.build(
                        thread: thread,
                        timestamp: messageTimestamp,
                        messageBody: messageBody,
                        mediaAttachments: mediaAttachments,
                        quotedReplyDraft: quotedReplyDraft,
                        linkPreviewDataSource: linkPreviewDataSource,
                        transaction: readTransaction
                    )
                }
            } catch {
                owsFailDebug("Failed to build message")
                return
            }

            Self.enqueueMessageSync(
                unpreparedMessage,
                benchEventId: benchEventId,
                thread: thread,
                persistenceCompletionHandler: persistenceCompletion
            )
        }
    }

    public class func enqueueEditMessage(
        body messageBody: MessageBody?,
        thread: TSThread,
        quotedReplyEdit: MessageEdits.Edit<Void>,
        linkPreviewDraft: OWSLinkPreviewDraft?,
        editTarget: TSOutgoingMessage,
        persistenceCompletionHandler persistenceCompletion: PersistenceCompletion? = nil
    ) {
        AssertIsOnMainThread()

        let messageTimestamp = MessageTimestampGenerator.sharedInstance.generateTimestamp()

        let benchEventId = sendMessageBenchEventStart(messageTimestamp: messageTimestamp)
        self.enqueueSendQueue.async {
            let unpreparedMessage: UnpreparedOutgoingMessage
            do {
                let messageBody = try messageBody.map {
                    try DependenciesBridge.shared.attachmentContentValidator
                        .prepareOversizeTextsIfNeeded(from: ["": $0])
                        .values.first
                } ?? nil
                let linkPreviewDataSource = try linkPreviewDraft.map {
                    try DependenciesBridge.shared.linkPreviewManager.buildDataSource(from: $0)
                }

                unpreparedMessage = UnpreparedOutgoingMessage.buildForEdit(
                    thread: thread,
                    timestamp: messageTimestamp,
                    messageBody: messageBody,
                    quotedReplyEdit: quotedReplyEdit,
                    linkPreviewDataSource: linkPreviewDataSource,
                    editTarget: editTarget
                )
            } catch {
                owsFailDebug("Failed to build message")
                return
            }

            Self.enqueueMessageSync(
                unpreparedMessage,
                benchEventId: benchEventId,
                thread: thread,
                persistenceCompletionHandler: persistenceCompletion
            )
        }
    }

    // MARK: - Durable Message Enqueue

    class func enqueueMessage(
        _ unpreparedMessage: UnpreparedOutgoingMessage,
        thread: TSThread,
        persistenceCompletionHandler persistenceCompletion: PersistenceCompletion? = nil
    ) {
        let benchEventId = sendMessageBenchEventStart(messageTimestamp: unpreparedMessage.messageTimestampForLogging)
        self.enqueueSendQueue.async {
            Self.enqueueMessageSync(
                unpreparedMessage,
                benchEventId: benchEventId,
                thread: thread,
                persistenceCompletionHandler: persistenceCompletion
            )
        }
    }

    /// WARNING: MUST be called on enqueueSendQueue!
    private class func enqueueMessageSync(
        _ unpreparedMessage: UnpreparedOutgoingMessage,
        benchEventId: String,
        thread: TSThread,
        persistenceCompletionHandler persistenceCompletion: PersistenceCompletion? = nil
    ) {
        assertOnQueue(Self.enqueueSendQueue)
        SSKEnvironment.shared.databaseStorageRef.write { writeTransaction in
            guard let preparedMessage = try? unpreparedMessage.prepare(tx: writeTransaction) else {
                owsFailDebug("Failed to prepare message")
                return
            }
            let promise = SSKEnvironment.shared.messageSenderJobQueueRef.add(
                .promise,
                message: preparedMessage,
                transaction: writeTransaction
            )
            if let persistenceCompletion = persistenceCompletion {
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

    private static func sendMessageBenchEventStart(messageTimestamp: UInt64) -> String {
        let eventId = "sendMessageMarkedAsSent-\(messageTimestamp)"
        BenchEventStart(
            title: "Send Message Milestone: Marked as Sent (\(messageTimestamp))",
            eventId: eventId,
            logInProduction: true
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
        mediaAttachments: [SignalAttachment.ForSending] = [],
        quotedReplyDraft: DraftQuotedReplyModel.ForSending?,
        linkPreviewDataSource: LinkPreviewDataSource?,
        transaction: DBReadTransaction
    ) -> UnpreparedOutgoingMessage {

        let truncatedBody: MessageBody?
        let oversizeTextDataSource: AttachmentDataSource?
        switch messageBody {
        case .inline(let messageBody):
            truncatedBody = messageBody
            oversizeTextDataSource = nil
        case .oversize(let truncated, let fullsize):
            truncatedBody = truncated
            oversizeTextDataSource = .pendingAttachment(fullsize)
        case nil:
            truncatedBody = nil
            oversizeTextDataSource = nil
        }

        let dmConfigurationStore = DependenciesBridge.shared.disappearingMessagesConfigurationStore
        let dmConfig = dmConfigurationStore.fetchOrBuildDefault(for: .thread(thread), tx: transaction)

        let isVoiceMessage = mediaAttachments.count == 1
            && oversizeTextDataSource == nil
            && mediaAttachments.last?.renderingFlag == .voiceMessage

        var isViewOnceMessage = false
        for attachment in mediaAttachments {
            if attachment.isViewOnce {
                assert(mediaAttachments.count == 1)
                isViewOnceMessage = true
                break
            }

            if attachment.renderingFlag == .borderless {
                assert(mediaAttachments.count == 1)
                break
            }
        }

        let messageBuilder: TSOutgoingMessageBuilder = .withDefaultValues(thread: thread, timestamp: timestamp)

        messageBuilder.messageBody = truncatedBody?.text
        messageBuilder.bodyRanges = truncatedBody?.ranges

        messageBuilder.expiresInSeconds = dmConfig.durationSeconds
        messageBuilder.expireTimerVersion = NSNumber.init(value: dmConfig.timerVersion)
        messageBuilder.isVoiceMessage = isVoiceMessage
        messageBuilder.isViewOnceMessage = isViewOnceMessage

        let message = messageBuilder.build(transaction: transaction)

        let attachmentInfos = mediaAttachments.map(\.dataSource)

        let unpreparedMessage = UnpreparedOutgoingMessage.forMessage(
            message,
            unsavedBodyMediaAttachments: attachmentInfos,
            oversizeTextDataSource: oversizeTextDataSource,
            linkPreviewDraft: linkPreviewDataSource,
            quotedReplyDraft: quotedReplyDraft
        )
        return unpreparedMessage
    }

    public static func buildForEdit(
        thread: TSThread,
        timestamp: UInt64,
        messageBody: ValidatedMessageBody?,
        quotedReplyEdit: MessageEdits.Edit<Void>,
        linkPreviewDataSource: LinkPreviewDataSource?,
        editTarget: TSOutgoingMessage
    ) -> UnpreparedOutgoingMessage {

        let truncatedBody: MessageBody?
        let oversizeTextDataSource: AttachmentDataSource?
        switch messageBody {
        case .inline(let messageBody):
            truncatedBody = messageBody
            oversizeTextDataSource = nil
        case .oversize(let truncated, let fullsize):
            truncatedBody = truncated
            oversizeTextDataSource = .pendingAttachment(fullsize)
        case nil:
            truncatedBody = nil
            oversizeTextDataSource = nil
        }

        let edits: MessageEdits = .forOutgoingEdit(
            timestamp: .change(timestamp),
            // "Received" now!
            receivedAtTimestamp: .change(Date.ows_millisecondTimestamp()),
            body: .change(truncatedBody?.text),
            bodyRanges: .change(truncatedBody?.ranges)
        )

        let unpreparedMessage = UnpreparedOutgoingMessage.forEditMessage(
            targetMessage: editTarget,
            edits: edits,
            oversizeTextDataSource: oversizeTextDataSource,
            linkPreviewDraft: linkPreviewDataSource,
            quotedReplyEdit: quotedReplyEdit
        )
        return unpreparedMessage
    }
}
