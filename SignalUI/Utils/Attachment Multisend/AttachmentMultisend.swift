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

    private struct PreparedMultisend {
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
    ) throws -> PreparedMultisend {
        var attachmentsByMessageType = [TypeWrapper: [(ConversationItem, [SignalAttachment])]]()
        var correspondingAttachmentIds: [[String]] = []

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

        var threads: [TSThread] = []
        var attachmentIdMap: [String: [String]] = [:]
        var messages: [TSOutgoingMessage] = []
        var unsavedMessages: [TSOutgoingMessage] = []

        try self.databaseStorage.write { transaction in
            for (wrapper, values) in attachmentsByMessageType {
                let destinations = try values.lazy.map { conversation, attachments -> (TSThread, [SignalAttachment]) in
                    guard let thread = conversation.getOrCreateThread(transaction: transaction) else {
                        throw OWSAssertionError("Missing thread for conversation")
                    }
                    return (thread, attachments)
                }

                // TODO: If TSOutgoingMessage is ever converted to Swift,
                // we can have `OutgoingStoryMessage` properly override
                // `prepareForMultisending` and eliminate this overhead.
                if wrapper.type === OutgoingStoryMessage.self {
                    try OutgoingStoryMessage.prepareForStoryMultisending(
                        destinations: destinations,
                        approvalMessageBody: approvalMessageBody,
                        messages: &messages,
                        unsavedMessages: &unsavedMessages,
                        threads: &threads,
                        correspondingAttachmentIds: &correspondingAttachmentIds,
                        transaction: transaction
                    )
                } else {
                    try wrapper.type.prepareForMultisending(
                        destinations: destinations,
                        approvalMessageBody: approvalMessageBody,
                        messages: &messages,
                        unsavedMessages: &unsavedMessages,
                        threads: &threads,
                        correspondingAttachmentIds: &correspondingAttachmentIds,
                        transaction: transaction
                    )
                }
            }

            // Let N be the number of attachments, and M be the number of conversations each attachment
            // is being sent to. We should now have an array of N sub-arrays of size M, where each sub-array
            // represents a given attachment and contains the IDs of that attachment for each conversation
            // it is being sent to.
            owsAssertDebug(correspondingAttachmentIds.count == attachmentsToUpload.count)
            owsAssertDebug(correspondingAttachmentIds.allSatisfy({ attachmentIds in attachmentIds.count == conversations.count }))

            for (index, attachmentInfo) in attachmentsToUpload.enumerated() {
                do {
                    let attachmentToUpload = try attachmentInfo.asStreamConsumingDataSource(withIsVoiceMessage: false)
                    attachmentToUpload.anyInsert(transaction: transaction)

                    attachmentIdMap[attachmentToUpload.uniqueId] = correspondingAttachmentIds[index]
                } catch {
                    owsFailDebug("error: \(error)")
                }
            }
        }

        return PreparedMultisend(
            attachmentIdMap: attachmentIdMap,
            messages: messages,
            unsavedMessages: unsavedMessages,
            threads: threads)
    }
}
