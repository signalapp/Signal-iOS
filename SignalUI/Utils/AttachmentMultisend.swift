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

    private class func prepareForSending(
        conversations: [ConversationItem],
        approvalMessageBody: MessageBody?,
        approvedAttachments: [SignalAttachment]
    ) throws -> PreparedMultisend {
        var storyConversationAttachments = [(StoryConversationItem, [SignalAttachment])]()
        var otherConversationAttachments = [(ConversationItem, [SignalAttachment])]()
        var correspondingAttachmentIds: [[String]] = []

        for conversation in conversations {
            // Duplicate attachments per conversation
            let clonedAttachments = try approvedAttachments.map { try $0.cloneAttachment() }

            if let storyConversation = conversation as? StoryConversationItem {
                storyConversationAttachments.append((storyConversation, clonedAttachments))
            } else {
                otherConversationAttachments.append((conversation, clonedAttachments))
            }
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
        var privateStoryMessageIds: [String] = []

        try self.databaseStorage.write { transaction in

            for (conversation, attachments) in storyConversationAttachments {
                guard let thread = conversation.getOrCreateThread(transaction: transaction) else {
                    owsFailDebug("Missing thread for conversation")
                    continue
                }

                for (idx, attachment) in attachments.enumerated() {
                    attachment.captionText = approvalMessageBody?.plaintextBody(transaction: transaction.unwrapGrdbRead)
                    let attachmentStream = try attachment
                        .buildOutgoingAttachmentInfo()
                        .asStreamConsumingDataSource(withIsVoiceMessage: attachment.isVoiceMessage)
                    attachmentStream.anyInsert(transaction: transaction)

                    if correspondingAttachmentIds.count > idx {
                        correspondingAttachmentIds[idx] += [attachmentStream.uniqueId]
                    } else {
                        correspondingAttachmentIds.append([attachmentStream.uniqueId])
                    }

                    let message: OutgoingStoryMessage
                    if thread is TSPrivateStoryThread, let privateStoryMessageId = privateStoryMessageIds[safe: idx] {
                        message = try OutgoingStoryMessage.createUnsentMessage(
                            thread: thread,
                            storyMessageId: privateStoryMessageId,
                            transaction: transaction
                        )
                    } else {
                        message = try OutgoingStoryMessage.createUnsentMessage(
                            attachment: attachmentStream,
                            thread: thread,
                            transaction: transaction
                        )
                        if thread is TSPrivateStoryThread {
                            privateStoryMessageIds.append(message.storyMessageId)
                        }
                    }

                    messages.append(message)
                    unsavedMessages.append(message)
                }
            }

            dedupePrivateStoryRecipients(for: messages, transaction: transaction)

            for (conversation, attachments) in otherConversationAttachments {
                guard let thread = conversation.getOrCreateThread(transaction: transaction) else {
                    owsFailDebug("Missing thread for conversation")
                    continue
                }

                // If this thread has a pending message request, treat it as accepted.
                ThreadUtil.addThreadToProfileWhitelistIfEmptyOrPendingRequestAndSetDefaultTimer(thread: thread,
                                                                                                transaction: transaction)

                let messageBodyForContext = approvalMessageBody?.forNewContext(thread, transaction: transaction.unwrapGrdbRead)

                let message = try! ThreadUtil.createUnsentMessage(body: messageBodyForContext,
                                                                  mediaAttachments: attachments,
                                                                  thread: thread,
                                                                  transaction: transaction)
                messages.append(message)
                threads.append(thread)

                for (idx, attachmentId) in message.attachmentIds.enumerated() {
                    if correspondingAttachmentIds.count > idx {
                        correspondingAttachmentIds[idx] += [attachmentId]
                    } else {
                        correspondingAttachmentIds.append([attachmentId])
                    }
                }

                thread.donateSendMessageIntent(for: message, transaction: transaction)
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

    /// When sending to private stories, each private story list may have overlap in recipients. We want to
    /// dedupe sends such that we only send one copy of a given story to each recipient even though they
    /// are represented in multiple targeted lists.
    ///
    /// Additionally, each private story has different levels of permissions. Some may allow replies & reactions
    /// while others do not. Since we convey to the recipient if this is allowed in the sent proto, it's important that
    /// we send to a recipient only from the thread with the most privilege (or randomly select one with equal privilege)
    private class func dedupePrivateStoryRecipients(for messages: [TSOutgoingMessage], transaction: SDSAnyWriteTransaction) {
        // Bucket outgoing messages per recipient and story. We may be sending multiple stories if the user selected multiple attachments.
        let messagesPerRecipientPerStory = messages.reduce(into: [String: [SignalServiceAddress: [OutgoingStoryMessage]]]()) { result, message in
            guard let storyMessage = message as? OutgoingStoryMessage, storyMessage.isPrivateStorySend.boolValue else { return }
            var messagesByRecipient = result[storyMessage.storyMessageId] ?? [:]
            for address in storyMessage.recipientAddresses() {
                var messages = messagesByRecipient[address] ?? []
                // Always prioritize sending to stories that allow replies,
                // we'll later select the first message from this list as
                // the one to actually send to for a given recipient.
                if storyMessage.storyAllowsReplies.boolValue {
                    messages.insert(storyMessage, at: 0)
                } else {
                    messages.append(storyMessage)
                }
                messagesByRecipient[address] = messages
            }
            result[storyMessage.storyMessageId] = messagesByRecipient
        }

        for messagesPerRecipient in messagesPerRecipientPerStory.values {
            for (address, messages) in messagesPerRecipient {
                // For every message after the first for a given recipient, mark the
                // recipient as skipped so we don't send them any additional copies.
                for message in messages.dropFirst() {
                    message.update(withSkippedRecipient: address, transaction: transaction)
                }
            }
        }
    }
}
