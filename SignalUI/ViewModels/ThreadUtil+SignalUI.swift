//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging

public extension ThreadUtil {
    // MARK: - Durable Message Enqueue

    @discardableResult
    class func enqueueMessage(body messageBody: MessageBody?,
                              mediaAttachments: [SignalAttachment] = [],
                              thread: TSThread,
                              quotedReplyModel: OWSQuotedReplyModel? = nil,
                              linkPreviewDraft: OWSLinkPreviewDraft? = nil,
                              persistenceCompletionHandler persistenceCompletion: PersistenceCompletion? = nil,
                              transaction readTransaction: SDSAnyReadTransaction) -> TSOutgoingMessage {
        AssertIsOnMainThread()

        let outgoingMessagePreparer = OutgoingMessagePreparer(messageBody: messageBody,
                                                              mediaAttachments: mediaAttachments,
                                                              thread: thread,
                                                              quotedReplyModel: quotedReplyModel,
                                                              transaction: readTransaction)
        let message: TSOutgoingMessage = outgoingMessagePreparer.unpreparedMessage

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
                outgoingMessagePreparer.insertMessage(linkPreviewDraft: linkPreviewDraft,
                                                      transaction: writeTransaction)
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
                                   quotedReplyModel: OWSQuotedReplyModel? = nil,
                                   linkPreviewDraft: OWSLinkPreviewDraft? = nil,
                                   transaction: SDSAnyWriteTransaction) throws -> TSOutgoingMessage {

        let preparer = OutgoingMessagePreparer(messageBody: messageBody,
                                               mediaAttachments: mediaAttachments,
                                               thread: thread,
                                               quotedReplyModel: quotedReplyModel,
                                               transaction: transaction)
        preparer.insertMessage(linkPreviewDraft: linkPreviewDraft, transaction: transaction)
        return try preparer.prepareMessage(transaction: transaction)
    }
}

// MARK: -

extension OutgoingMessagePreparer {

    public convenience init(messageBody: MessageBody?,
                            mediaAttachments: [SignalAttachment] = [],
                            thread: TSThread,
                            quotedReplyModel: OWSQuotedReplyModel? = nil,
                            transaction: SDSAnyReadTransaction) {

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

        let message = TSOutgoingMessageBuilder(
            thread: thread,
            messageBody: truncatedText,
            bodyRanges: bodyRanges,
            expiresInSeconds: expiresInSeconds,
            isVoiceMessage: isVoiceMessage,
            quotedMessage: quotedMessage,
            isViewOnceMessage: isViewOnceMessage
        ).build(transaction: transaction)

        let attachmentInfos = attachments.map { $0.buildOutgoingAttachmentInfo(message: message) }

        self.init(message, unsavedAttachmentInfos: attachmentInfos)
    }
}
