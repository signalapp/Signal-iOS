//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

extension TSOutgoingMessage {
    @objc
    class func prepareForMultisending(
        destinations: [MultisendDestination],
        state: MultisendState,
        transaction: SDSAnyWriteTransaction
    ) throws {
        for destination in destinations {
            // If this thread has a pending message request, treat it as accepted.
            ThreadUtil.addThreadToProfileWhitelistIfEmptyOrPendingRequestAndSetDefaultTimer(
                thread: destination.thread,
                transaction: transaction
            )

            let messageBodyForContext = state.approvalMessageBody?.forNewContext(
                destination.thread,
                transaction: transaction.unwrapGrdbRead
            )

            let message: TSOutgoingMessage
            let attachmentUUIDs: [UUID]
            switch destination.content {
            case .media(let attachments):
                attachmentUUIDs = attachments.map(\.id)
                message = try ThreadUtil.createUnsentMessage(
                    body: messageBodyForContext,
                    mediaAttachments: attachments.map(\.value),
                    thread: destination.thread,
                    transaction: transaction
                )

            case .text:
                owsFailDebug("Cannot send TextAttachment to chats.")
                continue
            }

            state.messages.append(message)
            state.threads.append(destination.thread)

            for (idx, attachmentId) in message.attachmentIds.enumerated() {
                let attachmentUUID = attachmentUUIDs[idx]
                var correspondingIdsForAttachment = state.correspondingAttachmentIds[attachmentUUID] ?? []
                correspondingIdsForAttachment += [attachmentId]
                state.correspondingAttachmentIds[attachmentUUID] = correspondingIdsForAttachment
            }

            destination.thread.donateSendMessageIntent(for: message, transaction: transaction)
        }
    }
}
