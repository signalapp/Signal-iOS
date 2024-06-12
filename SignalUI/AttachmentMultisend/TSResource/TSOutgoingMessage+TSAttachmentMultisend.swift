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

            // Legacy only codepath; don't need validation.
            let validatedMessageBody = messageBodyForContext.map {
                TSResourceContentValidatorImpl.prepareLegacyOversizeTextIfNeeded(
                    from: $0
                )
            } ?? nil

            let preparedMessage: PreparedOutgoingMessage
            let attachmentUUIDs: [UUID]
            switch destination.content {
            case .media(let attachments):
                attachmentUUIDs = attachments.map(\.id)
                preparedMessage = try Self.createUnsentMessage(
                    body: validatedMessageBody,
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
        body messageBody: ValidatedTSMessageBody?,
        mediaAttachments: [SignalAttachment],
        thread: TSThread,
        transaction: SDSAnyWriteTransaction
    ) throws -> PreparedOutgoingMessage {
        // Don't do any validation.
        let attachmentsForSending = mediaAttachments.map { attachment in
            let dataSource = TSAttachmentDataSource(
                mimeType: attachment.mimeType,
                caption: attachment.captionText.map { MessageBody(text: $0, ranges: .empty) },
                renderingFlag: attachment.renderingFlag,
                sourceFilename: attachment.sourceFilename,
                dataSource: .dataSource(attachment.dataSource, shouldCopy: false)
            ).tsDataSource
            return SignalAttachment.ForSending(
                dataSource: dataSource,
                isViewOnce: attachment.isViewOnceAttachment,
                renderingFlag: attachment.renderingFlag
            )
        }

        let unpreparedMessage = UnpreparedOutgoingMessage.build(
            thread: thread,
            messageBody: messageBody,
            mediaAttachments: attachmentsForSending,
            quotedReplyDraft: nil,
            linkPreviewDataSource: nil,
            transaction: transaction)
        let preparedMessage = try unpreparedMessage.prepare(tx: transaction)
        preparedMessage.updateAllUnsentRecipientsAsSending(tx: transaction)
        return preparedMessage
    }
}
