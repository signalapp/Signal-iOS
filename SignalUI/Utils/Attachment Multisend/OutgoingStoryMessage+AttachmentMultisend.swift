//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

public extension OutgoingStoryMessage {
    class func prepareForStoryMultisending(
        destinations: [(TSThread, [SignalAttachment])],
        approvalMessageBody: MessageBody?,
        messages: inout [TSOutgoingMessage],
        unsavedMessages: inout [TSOutgoingMessage],
        threads: inout [TSThread],
        correspondingAttachmentIds: inout [[String]],
        transaction: SDSAnyWriteTransaction
    ) throws {
        var privateStoryMessageIds: [String] = []

        for (thread, attachments) in destinations {
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
    }

    /// When sending to private stories, each private story list may have overlap in recipients. We want to
    /// dedupe sends such that we only send one copy of a given story to each recipient even though they
    /// are represented in multiple targeted lists.
    ///
    /// Additionally, each private story has different levels of permissions. Some may allow replies & reactions
    /// while others do not. Since we convey to the recipient if this is allowed in the sent proto, it's important that
    /// we send to a recipient only from the thread with the most privilege (or randomly select one with equal privilege)
    private static func dedupePrivateStoryRecipients(for messages: [TSOutgoingMessage], transaction: SDSAnyWriteTransaction) {
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
