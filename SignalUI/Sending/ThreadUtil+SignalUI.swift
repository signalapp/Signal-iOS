//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

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
        AssertIsOnMainThread()

        let messageTimestamp = Date.ows_millisecondTimestamp()

        let benchEventId = sendMessageBenchEventStart(messageTimestamp: messageTimestamp)
        self.enqueueSendQueue.async {
            let unpreparedMessage: UnpreparedOutgoingMessage
            do {
                let linkPreviewDataSource = try linkPreviewDraft.map {
                    try DependenciesBridge.shared.linkPreviewManager.buildDataSource(from: $0)
                }

                unpreparedMessage = Self.databaseStorage.read { readTransaction in
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

        let messageTimestamp = Date.ows_millisecondTimestamp()

        let benchEventId = sendMessageBenchEventStart(messageTimestamp: messageTimestamp)
        self.enqueueSendQueue.async {
            let unpreparedMessage: UnpreparedOutgoingMessage
            do {
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
        Self.databaseStorage.write { writeTransaction in
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
                writeTransaction.addAsyncCompletionOnMain {
                    persistenceCompletion()
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
        messageBody: MessageBody?,
        mediaAttachments: [SignalAttachment] = [],
        quotedReplyDraft: DraftQuotedReplyModel?,
        linkPreviewDataSource: LinkPreviewTSResourceDataSource?,
        transaction: SDSAnyReadTransaction
    ) -> UnpreparedOutgoingMessage {

        let (truncatedBody, oversizeTextDataSource) = handleOversizeText(messageBody: messageBody)

        let dmConfigurationStore = DependenciesBridge.shared.disappearingMessagesConfigurationStore
        let expiresInSeconds = dmConfigurationStore.durationSeconds(for: thread, tx: transaction.asV2Read)

        assert(mediaAttachments.allSatisfy { !$0.hasError && !$0.mimeType.isEmpty })

        let isVoiceMessage = mediaAttachments.count == 1
            && oversizeTextDataSource == nil
            && mediaAttachments.last?.isVoiceMessage == true

        var isViewOnceMessage = false
        for attachment in mediaAttachments {
            if attachment.isViewOnceAttachment {
                assert(mediaAttachments.count == 1)
                isViewOnceMessage = true
                break
            }

            if attachment.isBorderless {
                assert(mediaAttachments.count == 1)
                break
            }
        }

        let messageBuilder = TSOutgoingMessageBuilder(thread: thread, timestamp: timestamp)

        messageBuilder.messageBody = truncatedBody?.text
        messageBuilder.bodyRanges = truncatedBody?.ranges

        messageBuilder.expiresInSeconds = expiresInSeconds
        messageBuilder.isVoiceMessage = isVoiceMessage
        messageBuilder.isViewOnceMessage = isViewOnceMessage

        let message = messageBuilder.build(transaction: transaction)

        let attachmentInfos = mediaAttachments.map { $0.buildAttachmentDataSource(message: message) }

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
        messageBody: MessageBody?,
        quotedReplyEdit: MessageEdits.Edit<Void>,
        linkPreviewDataSource: LinkPreviewTSResourceDataSource?,
        editTarget: TSOutgoingMessage
    ) -> UnpreparedOutgoingMessage {

        let (truncatedBody, oversizeTextDataSource) = handleOversizeText(messageBody: messageBody)

        let edits = MessageEdits(
            timestamp: timestamp,
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

    private static func handleOversizeText(
        messageBody: MessageBody?
    ) -> (MessageBody?, DataSource?) {
        guard let messageBody, !messageBody.text.isEmpty else {
            return (nil, nil)
        }
        if let truncatedText = messageBody.text.trimmedIfNeeded(maxByteCount: Int(kOversizeTextMessageSizeThreshold)) {
            let bodyRanges = messageBody.ranges
            let truncatedBody = MessageBody(text: truncatedText, ranges: bodyRanges)

            let dataSource = DataSourceValue.dataSource(withOversizeText: messageBody.text)
            return (truncatedBody, dataSource)
        } else {
            return (messageBody, nil)
        }
    }
}
