//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

extension TSOutgoingMessage {
    @objc
    class func prepareForMultisending(
        destinations: [MultisendDestination],
        state: MultisendState,
        transaction: SDSAnyWriteTransaction
    ) throws {
        for destination in destinations {
            // If this thread has a pending message request, treat it as accepted.
            ThreadUtil.addThreadToProfileWhitelistIfEmptyOrPendingRequest(
                destination.thread,
                setDefaultTimerIfNecessary: true,
                tx: transaction
            )

            let messageBodyForContext = state.approvalMessageBody?.forForwarding(
                to: destination.thread,
                transaction: transaction.unwrapGrdbRead
            ).asMessageBodyForForwarding()

            let preparedMessage: PreparedOutgoingMessage
            let attachmentUUIDs: [UUID]
            switch destination.content {
            case .media(let attachments):
                attachmentUUIDs = attachments.map(\.id)
                preparedMessage = try Self.createUnsentMessage(
                    body: messageBodyForContext,
                    mediaAttachments: attachments.map(\.value),
                    thread: destination.thread,
                    transaction: transaction
                )

            case .text:
                owsFailDebug("Cannot send TextAttachment to chats.")
                continue
            }

            state.messages.append(preparedMessage)
            state.threads.append(destination.thread)

            for (idx, attachmentId) in preparedMessage.legacyBodyAttachmentIdsForMultisend().enumerated() {
                let attachmentUUID = attachmentUUIDs[idx]
                var correspondingIdsForAttachment = state.correspondingAttachmentIds[attachmentUUID] ?? []
                correspondingIdsForAttachment += [attachmentId]
                state.correspondingAttachmentIds[attachmentUUID] = correspondingIdsForAttachment
            }

            if let message = preparedMessage.messageForIntentDonation(tx: transaction) {
                destination.thread.donateSendMessageIntent(for: message, transaction: transaction)
            }
        }
    }

    private class func createUnsentMessage(
        body messageBody: MessageBody?,
        mediaAttachments: [SignalAttachment],
        thread: TSThread,
        transaction: SDSAnyWriteTransaction
    ) throws -> PreparedOutgoingMessage {
        let unpreparedMessage = UnpreparedOutgoingMessage.build(
            thread: thread,
            messageBody: messageBody,
            mediaAttachments: mediaAttachments,
            quotedReplyDraft: nil,
            linkPreviewDraft: nil,
            transaction: transaction)
        let preparedMessage = try unpreparedMessage.prepare(tx: transaction)
        preparedMessage.updateAllUnsentRecipientsAsSending(tx: transaction)
        return preparedMessage
    }
}
