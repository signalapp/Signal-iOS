//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

public extension TSOutgoingMessage {
    class func prepareForMultisending(
        destinations: [(TSThread, [SignalAttachment])],
        approvalMessageBody: MessageBody?,
        messages: inout [TSOutgoingMessage],
        unsavedMessages: inout [TSOutgoingMessage],
        threads: inout [TSThread],
        correspondingAttachmentIds: inout [[String]],
        transaction: SDSAnyWriteTransaction
    ) throws {
        for (thread, attachments) in destinations {
            // If this thread has a pending message request, treat it as accepted.
            ThreadUtil.addThreadToProfileWhitelistIfEmptyOrPendingRequestAndSetDefaultTimer(
                thread: thread,
                transaction: transaction
            )

            let messageBodyForContext = approvalMessageBody?.forNewContext(
                thread,
                transaction: transaction.unwrapGrdbRead
            )

            let message = try ThreadUtil.createUnsentMessage(
                body: messageBodyForContext,
                mediaAttachments: attachments,
                thread: thread,
                transaction: transaction
            )

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
    }
}
