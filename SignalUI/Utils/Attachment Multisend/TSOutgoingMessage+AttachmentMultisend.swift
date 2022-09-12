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
            switch destination.content {
            case .media(let attachments):
                message = try ThreadUtil.createUnsentMessage(
                    body: messageBodyForContext,
                    mediaAttachments: attachments,
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
                if state.correspondingAttachmentIds.count > idx {
                    state.correspondingAttachmentIds[idx] += [attachmentId]
                } else {
                    state.correspondingAttachmentIds.append([attachmentId])
                }
            }

            destination.thread.donateSendMessageIntent(for: message, transaction: transaction)
        }
    }
}
