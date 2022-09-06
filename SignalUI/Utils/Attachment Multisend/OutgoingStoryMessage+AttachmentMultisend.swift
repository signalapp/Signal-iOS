//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

extension OutgoingStoryMessage {
    override class func prepareForMultisending(
        destinations: [MultisendDestination],
        state: MultisendState,
        transaction: SDSAnyWriteTransaction
    ) throws {
        var privateStoryMessageIds: [String] = []

        for destination in destinations {
            for (idx, attachment) in destination.attachments.enumerated() {
                attachment.captionText = state.approvalMessageBody?.plaintextBody(transaction: transaction.unwrapGrdbRead)
                let attachmentStream = try attachment
                    .buildOutgoingAttachmentInfo()
                    .asStreamConsumingDataSource(withIsVoiceMessage: attachment.isVoiceMessage)
                attachmentStream.anyInsert(transaction: transaction)

                if state.correspondingAttachmentIds.count > idx {
                    state.correspondingAttachmentIds[idx] += [attachmentStream.uniqueId]
                } else {
                    state.correspondingAttachmentIds.append([attachmentStream.uniqueId])
                }

                let message: OutgoingStoryMessage
                if destination.thread is TSPrivateStoryThread, let privateStoryMessageId = privateStoryMessageIds[safe: idx] {
                    message = try OutgoingStoryMessage.createUnsentMessage(
                        thread: destination.thread,
                        storyMessageId: privateStoryMessageId,
                        transaction: transaction
                    )
                } else {
                    message = try OutgoingStoryMessage.createUnsentMessage(
                        attachment: attachmentStream,
                        thread: destination.thread,
                        transaction: transaction
                    )
                    if destination.thread is TSPrivateStoryThread {
                        privateStoryMessageIds.append(message.storyMessageId)
                    }
                }

                state.messages.append(message)
                state.unsavedMessages.append(message)
            }
        }

        OutgoingStoryMessage.dedupePrivateStoryRecipients(for: state.messages.lazy.compactMap { $0 as? OutgoingStoryMessage }, transaction: transaction)
    }
}
