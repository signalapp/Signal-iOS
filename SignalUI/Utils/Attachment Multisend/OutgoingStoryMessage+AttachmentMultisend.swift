//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

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
                    let attachment = identifiedAttachment.value
                    // TODO[TextFormatting]: preserve styles on the story message proto but hydrate mentions
                    attachment.captionText = state.approvalMessageBody?.plaintextBody(transaction: transaction.unwrapGrdbRead)
                    let attachmentStream = try attachment
                        .buildOutgoingAttachmentInfo()
                        .asStreamConsumingDataSource(withIsVoiceMessage: attachment.isVoiceMessage)
                    attachmentStream.anyInsert(transaction: transaction)

                    var correspondingIdsForAttachment = state.correspondingAttachmentIds[identifiedAttachment.id] ?? []
                    correspondingIdsForAttachment += [attachmentStream.uniqueId]
                    state.correspondingAttachmentIds[identifiedAttachment.id] = correspondingIdsForAttachment

                    let message: OutgoingStoryMessage
                    if destination.thread is TSPrivateStoryThread, let privateStoryMessageId = privateStoryMessageIds[identifiedAttachment.id] {
                        message = try OutgoingStoryMessage.createUnsentMessage(
                            thread: destination.thread,
                            storyMessageId: privateStoryMessageId,
                            transaction: transaction
                        )
                    } else {
                        message = try OutgoingStoryMessage.createUnsentMessage(
                            attachment: .file(attachmentId: attachmentStream.uniqueId),
                            thread: destination.thread,
                            transaction: transaction
                        )
                        if destination.thread is TSPrivateStoryThread {
                            privateStoryMessageIds[identifiedAttachment.id] = message.storyMessageId
                        }
                    }

                    state.messages.append(message)
                    state.unsavedMessages.append(message)
                }

            case .text(let textAttachment):
                guard let finalTextAttachment = textAttachment.value.validateLinkPreviewAndBuildTextAttachment(transaction: transaction) else {
                    throw OWSAssertionError("Invalid text attachment")
                }

                if let linkPreviewAttachmentId = finalTextAttachment.preview?.imageAttachmentId {
                    var correspondingIdsForAttachment = state.correspondingAttachmentIds[textAttachment.id] ?? []
                    correspondingIdsForAttachment += [linkPreviewAttachmentId]
                    state.correspondingAttachmentIds[textAttachment.id] = correspondingIdsForAttachment
                }

                let message: OutgoingStoryMessage
                if destination.thread is TSPrivateStoryThread, let privateStoryMessageId = privateStoryMessageIds[textAttachment.id] {
                    message = try OutgoingStoryMessage.createUnsentMessage(
                        thread: destination.thread,
                        storyMessageId: privateStoryMessageId,
                        transaction: transaction
                    )
                } else {
                    message = try OutgoingStoryMessage.createUnsentMessage(
                        attachment: .text(attachment: finalTextAttachment),
                        thread: destination.thread,
                        transaction: transaction
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
