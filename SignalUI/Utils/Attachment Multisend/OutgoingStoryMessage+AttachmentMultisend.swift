//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

extension OutgoingStoryMessage {
    override class func prepareForMultisending(
        destinations: [MultisendDestination],
        state: MultisendState,
        transaction: SDSAnyWriteTransaction
    ) throws {
        var privateStoryMessageIds: [UUID: String] = [:]

        for destination in destinations {
            switch destination.content {
            case .media(let attachments):
                for identifiedAttachment in attachments {
                    let message: OutgoingStoryMessage
                    if destination.thread is TSPrivateStoryThread, let privateStoryMessageId = privateStoryMessageIds[identifiedAttachment.id] {
                        message = try OutgoingStoryMessage.createUnsentMessage(
                            thread: destination.thread,
                            storyMessageId: privateStoryMessageId,
                            transaction: transaction
                        )
                    } else {
                        message = try OutgoingStoryMessage.createUnsentMessage(
                            thread: destination.thread,
                            transaction: transaction,
                            attachmentGenerator: { _, storyMessageUniqueId, transaction in
                                let attachment = identifiedAttachment.value
                                let captionBody = state.approvalMessageBody?
                                    .hydrating(mentionHydrator: ContactsMentionHydrator.mentionHydrator(transaction: transaction.asV2Read))
                                    .asStyleOnlyBody()
                                attachment.captionText = captionBody?.text
                                let attachmentStream = try attachment
                                    .buildOutgoingAttachmentInfo()
                                    .asStreamConsumingDataSource(isVoiceMessage: attachment.isVoiceMessage)
                                attachmentStream.anyInsert(transaction: transaction)

                                var correspondingIdsForAttachment = state.correspondingAttachmentIds[identifiedAttachment.id] ?? []
                                correspondingIdsForAttachment += [attachmentStream.uniqueId]
                                state.correspondingAttachmentIds[identifiedAttachment.id] = correspondingIdsForAttachment
                                return .file(StoryMessageFileAttachment(
                                    attachmentId: attachmentStream.uniqueId,
                                    captionStyles: captionBody?.collapsedStyles ?? []
                                ))
                            }
                        )
                        if destination.thread is TSPrivateStoryThread {
                            privateStoryMessageIds[identifiedAttachment.id] = message.storyMessageId
                        }
                    }

                    state.messages.append(message)
                    state.unsavedMessages.append(message)
                }

            case .text(let textAttachment):
                let message: OutgoingStoryMessage
                if destination.thread is TSPrivateStoryThread, let privateStoryMessageId = privateStoryMessageIds[textAttachment.id] {
                    message = try OutgoingStoryMessage.createUnsentMessage(
                        thread: destination.thread,
                        storyMessageId: privateStoryMessageId,
                        transaction: transaction
                    )
                } else {
                    message = try OutgoingStoryMessage.createUnsentMessage(
                        thread: destination.thread,
                        transaction: transaction,
                        attachmentGenerator: { _, _, transaction in
                            guard let finalTextAttachment = textAttachment.value.validateLinkPreviewAndBuildTextAttachment(transaction: transaction) else {
                                throw OWSAssertionError("Invalid text attachment")
                            }

                            if let linkPreviewAttachmentId = finalTextAttachment.preview?.imageAttachmentId {
                                var correspondingIdsForAttachment = state.correspondingAttachmentIds[textAttachment.id] ?? []
                                correspondingIdsForAttachment += [linkPreviewAttachmentId]
                                state.correspondingAttachmentIds[textAttachment.id] = correspondingIdsForAttachment
                            }
                            return .text(finalTextAttachment)
                        }
                    )
                    if destination.thread is TSPrivateStoryThread {
                        privateStoryMessageIds[textAttachment.id] = message.storyMessageId
                    }
                }

                state.messages.append(message)
                state.unsavedMessages.append(message)
            }
        }

        OutgoingStoryMessage.dedupePrivateStoryRecipients(for: state.messages.lazy.compactMap { $0 as? OutgoingStoryMessage }, transaction: transaction)
    }
}
