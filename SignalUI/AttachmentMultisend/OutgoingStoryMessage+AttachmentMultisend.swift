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
                        let attachment = identifiedAttachment.value
                        let captionBody = state.approvalMessageBody?
                            .hydrating(mentionHydrator: ContactsMentionHydrator.mentionHydrator(transaction: transaction.asV2Read))
                            .asStyleOnlyBody()
                        attachment.captionText = captionBody?.text
                        let dataSource = attachment.buildAttachmentDataSource()
                        let attachmentStreamId = try TSAttachmentManager().createAttachmentStream(
                            from: dataSource,
                            tx: transaction
                        )
                        let attachmentBuilder = OwnedAttachmentBuilder<StoryMessageAttachment>.withoutFinalizer(
                            .file(StoryMessageFileAttachment(
                                attachmentId: attachmentStreamId,
                                captionStyles: captionBody?.collapsedStyles ?? []
                            ))
                        )

                        var correspondingIdsForAttachment = state.correspondingAttachmentIds[identifiedAttachment.id] ?? []
                        correspondingIdsForAttachment += [attachmentStreamId]
                        state.correspondingAttachmentIds[identifiedAttachment.id] = correspondingIdsForAttachment

                        message = try OutgoingStoryMessage.createUnsentMessage(
                            thread: destination.thread,
                            attachmentBuilder: attachmentBuilder,
                            transaction: transaction
                        )
                        if destination.thread is TSPrivateStoryThread {
                            privateStoryMessageIds[identifiedAttachment.id] = message.storyMessageId
                        }
                    }

                    state.messages.append(PreparedOutgoingMessage.preprepared(
                        outgoingStoryMessage: message
                    ))
                    state.storyMessagesToSend.append(message)
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
                    guard
                        let textAttachmentBuilder = textAttachment.value
                            .validateLinkPreviewAndBuildTextAttachment(transaction: transaction)
                    else {
                        throw OWSAssertionError("Invalid text attachment")
                    }
                    if let linkPreviewAttachmentId = textAttachmentBuilder.info.preview?.legacyImageAttachmentId {
                        var correspondingIdsForAttachment = state.correspondingAttachmentIds[textAttachment.id] ?? []
                        correspondingIdsForAttachment += [linkPreviewAttachmentId]
                        state.correspondingAttachmentIds[textAttachment.id] = correspondingIdsForAttachment
                    }
                    message = try OutgoingStoryMessage.createUnsentMessage(
                        thread: destination.thread,
                        attachmentBuilder: textAttachmentBuilder.wrap { .text($0) },
                        transaction: transaction
                    )
                    if destination.thread is TSPrivateStoryThread {
                        privateStoryMessageIds[textAttachment.id] = message.storyMessageId
                    }
                }

                state.messages.append(PreparedOutgoingMessage.preprepared(
                    outgoingStoryMessage: message
                ))
                state.storyMessagesToSend.append(message)
            }
        }

        OutgoingStoryMessage.dedupePrivateStoryRecipients(for: state.messages.lazy.compactMap(\.storyMessage), transaction: transaction)
    }
}
