//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalMessaging
import SignalServiceKit

public class AttachmentMultisend: Dependencies {

    public class func sendApprovedMedia(
        conversations: [ConversationItem],
        approvalMessageBody: MessageBody?,
        approvedAttachments: [SignalAttachment]
    ) -> Promise<[TSThread]> {
        return firstly(on: ThreadUtil.enqueueSendQueue) {
            let preparedSend = try self.prepareForSending(
                conversations: conversations,
                approvalMessageBody: approvalMessageBody,
                approvedAttachments: approvedAttachments)

            self.databaseStorage.write { transaction in
                self.broadcastMediaMessageJobQueue.add(
                    attachmentIdMap: preparedSend.attachmentIdMap,
                    unsavedMessagesToSend: preparedSend.unsavedMessages,
                    transaction: transaction)
            }

            return preparedSend.threads
        }
    }

    public class func sendApprovedMediaFromShareExtension(
        conversations: [ConversationItem],
        approvalMessageBody: MessageBody?,
        approvedAttachments: [SignalAttachment],
        messagesReadyToSend: (([TSOutgoingMessage]) -> Void)? = nil
    ) -> Promise<[TSThread]> {
        return firstly(on: .sharedUserInitiated) { () -> (Promise<[TSThread]>) in
            let preparedSend = try self.prepareForSending(
                conversations: conversations,
                approvalMessageBody: approvalMessageBody,
                approvedAttachments: approvedAttachments)

            messagesReadyToSend?(preparedSend.messages)

            let outgoingMessages = try BroadcastMediaUploader.upload(attachmentIdMap: preparedSend.attachmentIdMap) + preparedSend.unsavedMessages

            var messageSendPromises = [Promise<Void>]()
            databaseStorage.write { transaction in
                for message in outgoingMessages {
                    messageSendPromises.append(ThreadUtil.enqueueMessagePromise(
                        message: message,
                        isHighPriority: true,
                        transaction: transaction
                    ))
                }
            }

            return Promise.when(fulfilled: messageSendPromises).map { preparedSend.threads }
        }
    }

    private struct PreparedMediaMultisend {
        let attachmentIdMap: [String: [String]]
        let messages: [TSOutgoingMessage]
        let unsavedMessages: [TSOutgoingMessage]
        let threads: [TSThread]
    }

    // Used to allow a raw Type as the key of a dictionary
    private struct TypeWrapper: Hashable {
        let type: TSOutgoingMessage.Type

        static func == (lhs: TypeWrapper, rhs: TypeWrapper) -> Bool {
            lhs.type == rhs.type
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(ObjectIdentifier(type))
        }
    }

    private class func prepareForSending(
        conversations: [ConversationItem],
        approvalMessageBody: MessageBody?,
        approvedAttachments: [SignalAttachment]
    ) throws -> PreparedMediaMultisend {
        var attachmentsByMessageType = [TypeWrapper: [(ConversationItem, [SignalAttachment])]]()

        // If we're sending to any stories, limit all attachments to the standard quality level.
        var approvedAttachments = approvedAttachments
        if conversations.contains(where: { $0 is StoryConversationItem }) {
            approvedAttachments = approvedAttachments.map {
                $0.preparedForOutput(qualityLevel: .standard)
            }
        }

        for conversation in conversations {
            // Duplicate attachments per conversation
            let clonedAttachments = try approvedAttachments.map { try $0.cloneAttachment() }

            let wrappedType = TypeWrapper(type: conversation.outgoingMessageClass)
            var messageTypeArray = attachmentsByMessageType[wrappedType] ?? []
            messageTypeArray.append((conversation, clonedAttachments))
            attachmentsByMessageType[wrappedType] = messageTypeArray
        }

        // We only upload one set of attachments, and then copy the upload details into
        // each conversation before sending.
        let attachmentsToUpload: [OutgoingAttachmentInfo] = approvedAttachments.map { attachment in
            return OutgoingAttachmentInfo(dataSource: attachment.dataSource,
                                          contentType: attachment.mimeType,
                                          sourceFilename: attachment.filenameOrDefault,
                                          caption: attachment.captionText,
                                          albumMessageId: nil,
                                          isBorderless: attachment.isBorderless,
                                          isLoopingVideo: attachment.isLoopingVideo)
        }

        let state = MultisendState(approvalMessageBody: approvalMessageBody)

        try self.databaseStorage.write { transaction in
            for (wrapper, values) in attachmentsByMessageType {
                let destinations = try values.lazy.map { conversation, attachments -> MultisendDestination in
                    guard let thread = conversation.getOrCreateThread(transaction: transaction) else {
                        throw OWSAssertionError("Missing thread for conversation")
                    }
                    return .init(thread: thread, content: .media(attachments))
                }

                try wrapper.type.prepareForMultisending(destinations: destinations, state: state, transaction: transaction)
            }

            // Let N be the number of attachments, and M be the number of conversations each attachment
            // is being sent to. We should now have an array of N sub-arrays of size M, where each sub-array
            // represents a given attachment and contains the IDs of that attachment for each conversation
            // it is being sent to.
            owsAssertDebug(state.correspondingAttachmentIds.count == attachmentsToUpload.count)
            owsAssertDebug(state.correspondingAttachmentIds.allSatisfy({ attachmentIds in attachmentIds.count == conversations.count }))

            for (index, attachmentInfo) in attachmentsToUpload.enumerated() {
                do {
                    let attachmentToUpload = try attachmentInfo.asStreamConsumingDataSource(withIsVoiceMessage: false)
                    attachmentToUpload.anyInsert(transaction: transaction)

                    state.attachmentIdMap[attachmentToUpload.uniqueId] = state.correspondingAttachmentIds[index]
                } catch {
                    owsFailDebug("error: \(error)")
                }
            }
        }

        return PreparedMediaMultisend(
            attachmentIdMap: state.attachmentIdMap,
            messages: state.messages,
            unsavedMessages: state.unsavedMessages,
            threads: state.threads)
    }
}

public extension AttachmentMultisend {

    class func sendTextAttachment(
        _ textAttachment: TextAttachment,
        to conversations: [ConversationItem]
    ) -> Promise<[TSThread]> {
        return firstly(on: ThreadUtil.enqueueSendQueue) {
            let preparedSend = try self.prepareForSending(conversations: conversations, textAttachment: textAttachment)
            self.databaseStorage.write { transaction in
                for message in preparedSend.messages {
                    self.messageSenderJobQueue.add(message: message.asPreparer, transaction: transaction)
                }
            }
            return preparedSend.threads
        }
    }

    private struct PreparedTextMultisend {
        let messages: [TSOutgoingMessage]
        let threads: [TSThread]
    }

    private class func prepareForSending(
        conversations: [ConversationItem],
        textAttachment: TextAttachment
    ) throws -> PreparedTextMultisend {

        let state = MultisendState(approvalMessageBody: nil)
        let conversationsByMessageType = Dictionary(grouping: conversations, by: { TypeWrapper(type: $0.outgoingMessageClass) })
        try self.databaseStorage.write { transaction in
            for (wrapper, conversations) in conversationsByMessageType {
                let destinations = try conversations.lazy.map { conversation -> MultisendDestination in
                    guard let thread = conversation.getOrCreateThread(transaction: transaction) else {
                        throw OWSAssertionError("Missing thread for conversation")
                    }
                    return .init(thread: thread, content: .text(textAttachment))
                }

                try wrapper.type.prepareForMultisending(destinations: destinations, state: state, transaction: transaction)
            }
        }

        return PreparedTextMultisend(
            messages: state.unsavedMessages,
            threads: state.threads)
    }
}

enum MultisendContent {
    case media([SignalAttachment])
    case text(TextAttachment)
}

class MultisendDestination: NSObject {
    let thread: TSThread
    let content: MultisendContent

    init(thread: TSThread, content: MultisendContent) {
        self.thread = thread
        self.content = content
    }
}

class MultisendState: NSObject {
    let approvalMessageBody: MessageBody?
    var messages: [TSOutgoingMessage] = []
    var unsavedMessages: [TSOutgoingMessage] = []
    var threads: [TSThread] = []
    var correspondingAttachmentIds: [[String]] = []
    var attachmentIdMap: [String: [String]] = [:]

    init(approvalMessageBody: MessageBody?) {
        self.approvalMessageBody = approvalMessageBody
    }
}
