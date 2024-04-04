//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

public extension ThreadUtil {
    // MARK: - Durable Message Enqueue

    class func enqueueMessage(
        body messageBody: MessageBody?,
        mediaAttachments: [SignalAttachment] = [],
        thread: TSThread,
        quotedReplyDraft: DraftQuotedReplyModel? = nil,
        linkPreviewDraft: OWSLinkPreviewDraft? = nil,
        editTarget: TSOutgoingMessage? = nil,
        persistenceCompletionHandler persistenceCompletion: PersistenceCompletion? = nil,
        transaction readTransaction: SDSAnyReadTransaction
    ) {
        AssertIsOnMainThread()

        let unpreparedMessage = UnpreparedOutgoingMessage.build(
            thread: thread,
            messageBody: messageBody,
            mediaAttachments: mediaAttachments,
            quotedReplyDraft: quotedReplyDraft,
            linkPreviewDraft: linkPreviewDraft,
            editTarget: editTarget,
            transaction: readTransaction
        )

        enqueueMessage(
            unpreparedMessage,
            thread: thread,
            persistenceCompletionHandler: persistenceCompletion,
            transaction: readTransaction
        )
    }

    // MARK: - Durable Message Enqueue

    class func enqueueMessage(
        _ unpreparedMessage: UnpreparedOutgoingMessage,
        thread: TSThread,
        persistenceCompletionHandler persistenceCompletion: PersistenceCompletion? = nil,
        transaction readTransaction: SDSAnyReadTransaction
    ) {
        let messageTimestampForLogging = unpreparedMessage.messageTimestampForLogging
        let eventId = "sendMessageMarkedAsSent-\(messageTimestampForLogging)"
        BenchEventStart(
            title: "Send Message Milestone: Marked as Sent (\(messageTimestampForLogging))",
            eventId: eventId,
            logInProduction: true
        )
        enqueueSendAsyncWrite { writeTransaction in
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
                BenchEventComplete(eventId: eventId)
            }

            if
                let messageForIntent = preparedMessage.messageForIntentDonation(tx: writeTransaction),
                let thread = messageForIntent.thread(tx: writeTransaction)
            {
                thread.donateSendMessageIntent(for: messageForIntent, transaction: writeTransaction)
            }
        }
    }
}

// MARK: -

extension UnpreparedOutgoingMessage {

    public static func build(
        thread: TSThread,
        messageBody: MessageBody?,
        mediaAttachments: [SignalAttachment] = [],
        quotedReplyDraft: DraftQuotedReplyModel?,
        linkPreviewDraft: OWSLinkPreviewDraft?,
        editTarget: TSOutgoingMessage?,
        transaction: SDSAnyReadTransaction
    ) -> UnpreparedOutgoingMessage {

        var attachments = mediaAttachments
        let truncatedText: String?
        let bodyRanges: MessageBodyRanges?

        if let messageBody = messageBody, !messageBody.text.isEmpty {
            if messageBody.text.lengthOfBytes(using: .utf8) >= kOversizeTextMessageSizeThreshold {
                truncatedText = messageBody.text.truncated(toByteCount: kOversizeTextMessageSizeThreshold)
                bodyRanges = messageBody.ranges

                if let dataSource = DataSourceValue.dataSource(withOversizeText: messageBody.text) {
                    let attachment = SignalAttachment.attachment(dataSource: dataSource,
                                                                 dataUTI: kOversizeTextAttachmentUTI)
                    attachments.append(attachment)
                } else {
                    owsFailDebug("dataSource was unexpectedly nil")
                }
            } else {
                truncatedText = messageBody.text
                bodyRanges = messageBody.ranges
            }
        } else {
            truncatedText = nil
            bodyRanges = nil
        }

        let dmConfigurationStore = DependenciesBridge.shared.disappearingMessagesConfigurationStore
        let expiresInSeconds = dmConfigurationStore.durationSeconds(for: thread, tx: transaction.asV2Read)

        assert(attachments.allSatisfy { !$0.hasError && !$0.mimeType.isEmpty })

        let isVoiceMessage = attachments.count == 1 && attachments.last?.isVoiceMessage == true

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

        let message: TSOutgoingMessage
        if let editTarget {
            let edits = MessageEdits(
                timestamp: NSDate.ows_millisecondTimeStamp(),
                body: .change(truncatedText),
                bodyRanges: .change(bodyRanges)
            )

            message = DependenciesBridge.shared.editManager.createOutgoingEditMessage(
                targetMessage: editTarget,
                thread: thread,
                edits: edits,
                tx: transaction.asV2Read
            )
        } else {
            let messageBuilder = TSOutgoingMessageBuilder(thread: thread)

            messageBuilder.messageBody = truncatedText
            messageBuilder.bodyRanges = bodyRanges

            messageBuilder.expiresInSeconds = expiresInSeconds
            messageBuilder.isVoiceMessage = isVoiceMessage
            messageBuilder.isViewOnceMessage = isViewOnceMessage

            message = messageBuilder.build(transaction: transaction)
        }

        let attachmentInfos = attachments.map { $0.buildAttachmentDataSource(message: message) }

        let unpreparedMessage = UnpreparedOutgoingMessage.forMessage(
            message,
            unsavedBodyAttachments: attachmentInfos,
            linkPreviewDraft: linkPreviewDraft,
            quotedReplyDraft: quotedReplyDraft
        )
        return unpreparedMessage
    }
}
