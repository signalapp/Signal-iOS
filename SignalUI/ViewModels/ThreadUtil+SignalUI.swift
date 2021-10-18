//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalMessaging

@objc
public extension ThreadUtil {

    // MARK: - Durable Message Enqueue

    @discardableResult
    class func enqueueMessage(body messageBody: MessageBody?,
                              thread: TSThread,
                              quotedReplyModel: OWSQuotedReplyModel?,
                              linkPreviewDraft: OWSLinkPreviewDraft?,
                              transaction: SDSAnyReadTransaction) -> TSOutgoingMessage {
        enqueueMessage(body: messageBody,
                       mediaAttachments: [],
                       thread: thread,
                       quotedReplyModel: quotedReplyModel,
                       linkPreviewDraft: linkPreviewDraft,
                       persistenceCompletionHandler: nil,
                       transaction: transaction)
    }

    @discardableResult
    class func enqueueMessage(body messageBody: MessageBody?,
                              mediaAttachments: [SignalAttachment],
                              thread: TSThread,
                              quotedReplyModel: OWSQuotedReplyModel?,
                              linkPreviewDraft: OWSLinkPreviewDraft?,
                              transaction: SDSAnyReadTransaction) -> TSOutgoingMessage {
        enqueueMessage(body: messageBody,
                       mediaAttachments: mediaAttachments,
                       thread: thread,
                       quotedReplyModel: quotedReplyModel,
                       linkPreviewDraft: linkPreviewDraft,
                       persistenceCompletionHandler: nil,
                       transaction: transaction)
    }

    @discardableResult
    class func enqueueMessage(body messageBody: MessageBody?,
                              mediaAttachments: [SignalAttachment],
                              thread: TSThread,
                              quotedReplyModel: OWSQuotedReplyModel?,
                              linkPreviewDraft: OWSLinkPreviewDraft?,
                              persistenceCompletionHandler persistenceCompletion: PersistenceCompletion?,
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
            eventId: "sendMessageMarkedAsSent-\(message.timestamp)"
        )
        BenchManager.benchAsync(title: "Send Message Milestone: Enqueue \(message.timestamp)") { benchmarkCompletion in
            Self.enqueueSendAsyncWrite { writeTransaction in
                outgoingMessagePreparer.insertMessage(linkPreviewDraft: linkPreviewDraft,
                                                      transaction: writeTransaction)
                Self.messageSenderJobQueue.add(message: outgoingMessagePreparer,
                                               transaction: writeTransaction)
                writeTransaction.addSyncCompletion {
                    benchmarkCompletion()
                }
                writeTransaction.addAsyncCompletionOnMain {
                    persistenceCompletion?()
                }
            }
        }

        if message.hasRenderableContent() {
            thread.donateSendMessageIntent(transaction: readTransaction)
        }
        return message
    }

    class func createUnsentMessage(body messageBody: MessageBody?,
                                   mediaAttachments: [SignalAttachment],
                                   thread: TSThread,
                                   quotedReplyModel: OWSQuotedReplyModel?,
                                   linkPreviewDraft: OWSLinkPreviewDraft?,
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
