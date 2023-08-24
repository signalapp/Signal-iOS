//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging

public extension ThreadUtil {
    // MARK: - Durable Message Enqueue

    @discardableResult
    class func enqueueMessage(
        body messageBody: MessageBody?,
        mediaAttachments: [SignalAttachment] = [],
        thread: TSThread,
        quotedReplyModel: QuotedReplyModel? = nil,
        linkPreviewDraft: OWSLinkPreviewDraft? = nil,
        editTarget: TSOutgoingMessage? = nil,
        persistenceCompletionHandler persistenceCompletion: PersistenceCompletion? = nil,
        transaction readTransaction: SDSAnyReadTransaction
    ) -> TSOutgoingMessage {
        AssertIsOnMainThread()

        let outgoingMessagePreparer = OutgoingMessagePreparer(
            messageBody: messageBody,
            mediaAttachments: mediaAttachments,
            thread: thread,
            quotedReplyModel: quotedReplyModel,
            editTarget: editTarget,
            transaction: readTransaction
        )

        let message: TSOutgoingMessage = outgoingMessagePreparer.unpreparedMessage

        return enqueueMessage(
            message,
            thread: thread,
            insertMessage: {
                outgoingMessagePreparer.insertMessage(
                    linkPreviewDraft: linkPreviewDraft,
                    transaction: $0
                )
                return outgoingMessagePreparer
            },
            persistenceCompletionHandler: persistenceCompletion,
            transaction: readTransaction
        )
    }

    @discardableResult
    class func enqueueMessage(
        _ message: TSOutgoingMessage,
        thread: TSThread,
        insertMessage: @escaping (SDSAnyWriteTransaction) -> OutgoingMessagePreparer,
        persistenceCompletionHandler persistenceCompletion: PersistenceCompletion? = nil,
        transaction readTransaction: SDSAnyReadTransaction
    ) -> TSOutgoingMessage {
        BenchManager.startEvent(
            title: "Send Message Milestone: Sending (\(message.timestamp))",
            eventId: "sendMessageSending-\(message.timestamp)",
            logInProduction: true
        )
        BenchManager.startEvent(
            title: "Send Message Milestone: Sent (\(message.timestamp))",
            eventId: "sendMessageSentSent-\(message.timestamp)",
            logInProduction: true
        )
        BenchManager.startEvent(
            title: "Send Message Milestone: Marked as Sent (\(message.timestamp))",
            eventId: "sendMessageMarkedAsSent-\(message.timestamp)",
            logInProduction: true
        )
        BenchManager.benchAsync(title: "Send Message Milestone: Enqueue \(message.timestamp)") { benchmarkCompletion in
            enqueueSendAsyncWrite { writeTransaction in
                let outgoingMessagePreparer = insertMessage(writeTransaction)
                Self.sskJobQueues.messageSenderJobQueue.add(
                    message: outgoingMessagePreparer,
                    transaction: writeTransaction
                )
                writeTransaction.addSyncCompletion {
                    benchmarkCompletion()
                }
                if let persistenceCompletion = persistenceCompletion {
                    writeTransaction.addAsyncCompletionOnMain {
                        persistenceCompletion()
                    }
                }
            }
        }

        if message.hasRenderableContent() {
            thread.donateSendMessageIntent(for: message, transaction: readTransaction)
        }
        return message
    }

    class func createUnsentMessage(body messageBody: MessageBody?,
                                   mediaAttachments: [SignalAttachment],
                                   thread: TSThread,
                                   quotedReplyModel: QuotedReplyModel? = nil,
                                   linkPreviewDraft: OWSLinkPreviewDraft? = nil,
                                   transaction: SDSAnyWriteTransaction) throws -> TSOutgoingMessage {

        let preparer = OutgoingMessagePreparer(messageBody: messageBody,
                                               mediaAttachments: mediaAttachments,
                                               thread: thread,
                                               quotedReplyModel: quotedReplyModel,
                                               editTarget: nil,
                                               transaction: transaction)
        preparer.insertMessage(linkPreviewDraft: linkPreviewDraft, transaction: transaction)
        return try preparer.prepareMessage(transaction: transaction)
    }
}

// MARK: -

extension OutgoingMessagePreparer {

    public convenience init(
        messageBody: MessageBody?,
        mediaAttachments: [SignalAttachment] = [],
        thread: TSThread,
        quotedReplyModel: QuotedReplyModel? = nil,
        editTarget: TSOutgoingMessage?,
        transaction: SDSAnyReadTransaction
    ) {

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

        // Discard quoted reply for view-once messages.
        let quotedMessage: TSQuotedMessage? = (isViewOnceMessage
                                               ? nil
                                               : quotedReplyModel?.buildQuotedMessageForSending())

        let message: TSOutgoingMessage
        if let editTarget {
            message = DependenciesBridge.shared.editManager.createOutgoingEditMessage(
                targetMessage: editTarget,
                thread: thread,
                tx: transaction.asV2Read) { builder in
                    builder.messageBody = truncatedText
                    builder.bodyRanges = bodyRanges
                    builder.expiresInSeconds = expiresInSeconds
                    builder.quotedMessage = quotedMessage
                }
        } else {
            let messageBuilder = TSOutgoingMessageBuilder(thread: thread)

            messageBuilder.messageBody = truncatedText
            messageBuilder.bodyRanges = bodyRanges

            messageBuilder.expiresInSeconds = expiresInSeconds
            messageBuilder.isVoiceMessage = isVoiceMessage
            messageBuilder.quotedMessage = quotedMessage
            messageBuilder.isViewOnceMessage = isViewOnceMessage

            message = messageBuilder.build(transaction: transaction)
        }

        let attachmentInfos = attachments.map { $0.buildOutgoingAttachmentInfo(message: message) }

        self.init(message, unsavedAttachmentInfos: attachmentInfos)
    }
}
