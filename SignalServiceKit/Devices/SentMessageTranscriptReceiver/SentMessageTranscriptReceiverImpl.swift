//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public class SentMessageTranscriptReceiverImpl: SentMessageTranscriptReceiver {

    private let attachmentDownloads: AttachmentDownloadManager
    private let attachmentManager: AttachmentManager
    private let disappearingMessagesJob: Shims.DisappearingMessagesJob
    private let earlyMessageManager: Shims.EarlyMessageManager
    private let groupManager: Shims.GroupManager
    private let interactionDeleteManager: InteractionDeleteManager
    private let interactionStore: InteractionStore
    private let messageStickerManager: MessageStickerManager
    private let paymentsHelper: Shims.PaymentsHelper
    private let signalProtocolStoreManager: SignalProtocolStoreManager
    private let tsAccountManager: TSAccountManager
    private let viewOnceMessages: Shims.ViewOnceMessages

    public init(
        attachmentDownloads: AttachmentDownloadManager,
        attachmentManager: AttachmentManager,
        disappearingMessagesJob: Shims.DisappearingMessagesJob,
        earlyMessageManager: Shims.EarlyMessageManager,
        groupManager: Shims.GroupManager,
        interactionDeleteManager: InteractionDeleteManager,
        interactionStore: InteractionStore,
        messageStickerManager: MessageStickerManager,
        paymentsHelper: Shims.PaymentsHelper,
        signalProtocolStoreManager: SignalProtocolStoreManager,
        tsAccountManager: TSAccountManager,
        viewOnceMessages: Shims.ViewOnceMessages
    ) {
        self.attachmentDownloads = attachmentDownloads
        self.attachmentManager = attachmentManager
        self.disappearingMessagesJob = disappearingMessagesJob
        self.earlyMessageManager = earlyMessageManager
        self.groupManager = groupManager
        self.interactionDeleteManager = interactionDeleteManager
        self.interactionStore = interactionStore
        self.messageStickerManager = messageStickerManager
        self.paymentsHelper = paymentsHelper
        self.signalProtocolStoreManager = signalProtocolStoreManager
        self.tsAccountManager = tsAccountManager
        self.viewOnceMessages = viewOnceMessages
    }

    public func process(
        _ transcript: SentMessageTranscript,
        localIdentifiers: LocalIdentifiers,
        tx: DBWriteTransaction
    ) -> Result<TSOutgoingMessage?, Error> {

        func validateTimestampInt64() -> Bool {
            guard SDS.fitsInInt64(transcript.timestamp) else {
                owsFailDebug("Invalid timestamp.")
                return false
            }
            return true
        }

        func validateTimestampValue() -> Bool {
            guard validateTimestampInt64() else {
                return false
            }
            guard transcript.timestamp >= 1 else {
                owsFailDebug("Transcript is missing timestamp.")
                // This transcript is invalid, discard it.
                return false
            }
            return true
        }

        switch transcript.type {
        case .recipientUpdate(let groupThread):
            // "Recipient updates" are processed completely separately in order
            // to avoid resurrecting threads or messages.
            // No timestamp validation
            return self.processRecipientUpdate(transcript, groupThread: groupThread, tx: tx)
        case .endSessionUpdate(let thread):
            guard validateTimestampInt64() else {
                return .failure(OWSAssertionError("Timestamp validation failed"))
            }
            Logger.info("EndSession was sent to recipient: \(thread.contactAddress)")
            self.archiveSessions(for: thread.contactAddress, tx: tx)

            let infoMessage = TSInfoMessage(thread: thread, messageType: .typeLocalUserEndedSession)
            interactionStore.insertInteraction(infoMessage, tx: tx)

            // Don't continue processing lest we print a bubble for the session reset.
            return .success(nil)
        case .paymentNotification(let paymentNotification):
            Logger.info("Recording payment notification from sync transcript in thread: \(paymentNotification.target.threadUniqueId) timestamp: \(transcript.timestamp)")
            guard validateTimestampValue() else {
                return .failure(OWSAssertionError("Timestamp validation failed"))
            }
            guard validateProtocolVersion(for: transcript, thread: paymentNotification.target.thread, tx: tx) else {
                return .failure(OWSAssertionError("Protocol version validation failed"))
            }

            let messageTimestamp = paymentNotification.serverTimestamp
            owsAssertDebug(messageTimestamp > 0)

            self.paymentsHelper.processReceivedTranscriptPaymentNotification(
                thread: paymentNotification.target.thread,
                paymentNotification: paymentNotification.notification,
                messageTimestamp: messageTimestamp,
                tx: tx
            )
            return .success(nil)

        case .archivedPayment(let archivedPayment):

            guard validateProtocolVersion(for: transcript, thread: archivedPayment.target.thread, tx: tx) else {
                return .failure(OWSAssertionError("Protocol version validation failed"))
            }

            let message = interactionStore.buildOutgoingArchivedPaymentMessage(
                builder: .withDefaultValues(
                    thread: archivedPayment.target.thread,
                    timestamp: transcript.timestamp,
                    expiresInSeconds: archivedPayment.expirationDurationSeconds,
                    // Archived payments don't set the chat timer; version is irrelevant.
                    expireTimerVersion: nil,
                    expireStartedAt: archivedPayment.expirationStartedAt
                ),
                amount: archivedPayment.amount,
                fee: archivedPayment.fee,
                note: archivedPayment.note,
                tx: tx
            )

            interactionStore.insertInteraction(message, tx: tx)
            interactionStore.updateRecipientsFromNonLocalDevice(
                message,
                recipientStates: transcript.recipientStates,
                isSentUpdate: false,
                tx: tx
            )

            return .success(message)
        case .expirationTimerUpdate(let target):
            Logger.info("Recording expiration timer update transcript in thread: \(target.threadUniqueId) timestamp: \(transcript.timestamp)")
            guard validateTimestampValue() else {
                return .failure(OWSAssertionError("Timestamp validation failed"))
            }
            guard validateProtocolVersion(for: transcript, thread: target.thread, tx: tx) else {
                return .failure(OWSAssertionError("Protocol version validation failed"))
            }

            updateDisappearingMessageTokenIfNecessary(target: target, localIdentifiers: localIdentifiers, tx: tx)
            return .success(nil)

        case .message(let messageParams):
            Logger.info("Recording transcript in thread: \(messageParams.target.threadUniqueId) timestamp: \(transcript.timestamp)")
            guard validateTimestampValue() else {
                return .failure(OWSAssertionError("Timestamp validation failed"))
            }
            return self.process(
                messageParams: messageParams,
                transcript: transcript,
                localIdentifiers: localIdentifiers,
                tx: tx
            ).map { $0 }
        }
    }

    private func process(
        messageParams: SentMessageTranscriptType.Message,
        transcript: SentMessageTranscript,
        localIdentifiers: LocalIdentifiers,
        tx: DBWriteTransaction
    ) -> Result<TSOutgoingMessage, Error> {
        guard validateProtocolVersion(for: transcript, thread: messageParams.target.thread, tx: tx) else {
            return .failure(OWSAssertionError("Protocol version validation failed"))
        }

        updateDisappearingMessageTokenIfNecessary(target: messageParams.target, localIdentifiers: localIdentifiers, tx: tx)

        let linkPreviewBuilder: OwnedAttachmentBuilder<OWSLinkPreview>?
        let quotedMessageBuilder: OwnedAttachmentBuilder<TSQuotedMessage>?
        let contactBuilder: OwnedAttachmentBuilder<OWSContact>?
        let messageStickerBuilder: OwnedAttachmentBuilder<MessageSticker>?
        do {
            linkPreviewBuilder = try messageParams.makeLinkPreviewBuilder(tx)
            quotedMessageBuilder = try messageParams.makeQuotedMessageBuilder(tx)
            contactBuilder = try messageParams.makeContactBuilder(tx)
            messageStickerBuilder = try messageParams.makeMessageStickerBuilder(tx)
        } catch let error {
            return .failure(error)
        }

        let outgoingMessageBuilder = TSOutgoingMessageBuilder(
            thread: messageParams.target.thread,
            timestamp: transcript.timestamp,
            receivedAtTimestamp: nil,
            messageBody: messageParams.body,
            bodyRanges: messageParams.bodyRanges,
            editState: .none, // Sent transcripts with edit state are handled by a different codepath
            expiresInSeconds: messageParams.expirationDurationSeconds,
            expireTimerVersion: messageParams.expireTimerVersion,
            expireStartedAt: messageParams.expirationStartedAt,
            isVoiceMessage: false,
            groupMetaMessage: .unspecified,
            isSmsMessageRestoredFromBackup: false,
            isViewOnceMessage: messageParams.isViewOnceMessage,
            isViewOnceComplete: false,
            wasRemotelyDeleted: false,
            groupChangeProtoData: nil,
            storyAuthorAci: messageParams.storyAuthorAci,
            storyTimestamp: messageParams.storyTimestamp,
            storyReactionEmoji: nil,
            quotedMessage: quotedMessageBuilder?.info,
            contactShare: contactBuilder?.info,
            linkPreview: linkPreviewBuilder?.info,
            messageSticker: messageStickerBuilder?.info,
            giftBadge: messageParams.giftBadge
        )
        var outgoingMessage = interactionStore.buildOutgoingMessage(builder: outgoingMessageBuilder, tx: tx)

        let hasRenderableContent = outgoingMessageBuilder.hasRenderableContent(
            hasBodyAttachments: messageParams.attachmentPointerProtos.isEmpty.negated,
            hasLinkPreview: linkPreviewBuilder != nil,
            hasQuotedReply: quotedMessageBuilder != nil,
            hasContactShare: contactBuilder != nil,
            hasSticker: messageStickerBuilder != nil,
            // Payment notifications go through a different path.
            hasPayment: false
        )
        if !hasRenderableContent && !outgoingMessage.isViewOnceMessage {
            switch messageParams.target {
            case .group(let thread):
                if thread.isGroupV2Thread {
                    // This is probably a v2 group update.
                    Logger.warn("Ignoring message transcript for empty v2 group message.")
                } else {
                    fallthrough
                }
            case .contact:
                Logger.warn("Ignoring message transcript for empty message.")
            }
            return .failure(OWSAssertionError("Empty message transcript"))
        }

        let existingFailedMessage = interactionStore.findMessage(
            withTimestamp: outgoingMessage.timestamp,
            threadId: outgoingMessage.uniqueThreadId,
            author: localIdentifiers.aciAddress,
            tx: tx
        )
        if let existingFailedMessage = existingFailedMessage as? TSOutgoingMessage {
            // Update the reference to the outgoing message so that we apply all updates to the
            // existing copy, and just throw away the new copy before we insert it.
            outgoingMessage = existingFailedMessage
        } else {

            guard let threadRowId = messageParams.target.thread.sqliteRowId else {
                return .failure(OWSAssertionError("Uninserted thread"))
            }

            // Check for any placeholders inserted because of a previously undecryptable message
            // The sender may have resent the message. If so, we should swap it in place of the placeholder
            interactionStore.insertOrReplacePlaceholder(for: outgoingMessage, from: localIdentifiers.aciAddress, tx: tx)

            do {
                try attachmentManager.createAttachmentPointers(
                    from: messageParams.attachmentPointerProtos.map { proto in
                        return .init(
                            proto: proto,
                            owner: .messageBodyAttachment(.init(
                                messageRowId: outgoingMessage.sqliteRowId!,
                                receivedAtTimestamp: outgoingMessage.receivedAtTimestamp,
                                threadRowId: threadRowId,
                                isViewOnce: outgoingMessage.isViewOnceMessage,
                                isPastEditRevision: outgoingMessage.isPastEditRevision()
                            ))
                        )
                    },
                    tx: tx
                )

                try quotedMessageBuilder?.finalize(
                    owner: .quotedReplyAttachment(.init(
                        messageRowId: outgoingMessage.sqliteRowId!,
                        receivedAtTimestamp: outgoingMessage.receivedAtTimestamp,
                        threadRowId: threadRowId,
                        isPastEditRevision: outgoingMessage.isPastEditRevision()
                    )),
                    tx: tx
                )

                try linkPreviewBuilder?.finalize(
                    owner: .messageLinkPreview(.init(
                        messageRowId: outgoingMessage.sqliteRowId!,
                        receivedAtTimestamp: outgoingMessage.receivedAtTimestamp,
                        threadRowId: threadRowId,
                        isPastEditRevision: outgoingMessage.isPastEditRevision()
                    )),
                    tx: tx
                )

                try messageStickerBuilder.map {
                    try $0.finalize(
                        owner: .messageSticker(.init(
                            messageRowId: outgoingMessage.sqliteRowId!,
                            receivedAtTimestamp: outgoingMessage.receivedAtTimestamp,
                            threadRowId: threadRowId,
                            isPastEditRevision: outgoingMessage.isPastEditRevision(),
                            stickerPackId: $0.info.packId,
                            stickerId: $0.info.stickerId
                        )),
                        tx: tx
                    )
                }
                try contactBuilder?.finalize(
                    owner: .messageContactAvatar(.init(
                        messageRowId: outgoingMessage.sqliteRowId!,
                        receivedAtTimestamp: outgoingMessage.receivedAtTimestamp,
                        threadRowId: threadRowId,
                        isPastEditRevision: outgoingMessage.isPastEditRevision()
                    )),
                    tx: tx
                )
            } catch let error {
                Logger.error("Attachment failure: \(error)")
                // Roll back the message
                interactionDeleteManager.delete(outgoingMessage, sideEffects: .default(), tx: tx)
                return .failure(error)
            }
        }
        owsAssertDebug(interactionStore.insertedMessageHasRenderableContent(
            message: outgoingMessage,
            rowId: outgoingMessage.sqliteRowId!,
            tx: tx
        ))

        interactionStore.updateRecipientsFromNonLocalDevice(
            outgoingMessage,
            recipientStates: transcript.recipientStates,
            isSentUpdate: false,
            tx: tx
        )

        if let expirationStartedAt = messageParams.expirationStartedAt {
            /// The insert and update methods above may start expiration for
            /// this message, but transcript.expirationStartedAt may be earlier,
            /// so we need to pass that to the OWSDisappearingMessagesJob in
            /// case it needs to back-date the expiration.
            disappearingMessagesJob.startExpiration(
                for: outgoingMessage,
                expirationStartedAt: expirationStartedAt,
                tx: tx
            )
        }

        self.earlyMessageManager.applyPendingMessages(for: outgoingMessage, localIdentifiers: localIdentifiers, tx: tx)

        if (outgoingMessage.isViewOnceMessage) {
            // Don't download attachments for "view-once" messages from linked devices.
            // To be extra-conservative, always mark as complete immediately.
            viewOnceMessages.markAsComplete(message: outgoingMessage, sendSyncMessages: false, tx: tx)
        } else {
            attachmentDownloads.enqueueDownloadOfAttachmentsForMessage(outgoingMessage, tx: tx)
        }

        return .success(outgoingMessage)
    }

    private func validateProtocolVersion(
        for transcript: SentMessageTranscript,
        thread: TSThread,
        tx: DBWriteTransaction
    ) -> Bool {
        if
            let requiredProtocolVersion = transcript.requiredProtocolVersion,
            requiredProtocolVersion > SSKProtos.currentProtocolVersion
        {
            owsFailDebug("Unknown protocol version: \(requiredProtocolVersion)")

            let message = OWSUnknownProtocolVersionMessage(
                thread: thread,
                timestamp: MessageTimestampGenerator.sharedInstance.generateTimestamp(),
                sender: nil,
                protocolVersion: UInt(requiredProtocolVersion)
            )
            interactionStore.insertInteraction(message, tx: tx)
            return false
        }
        return true
    }

    private func updateDisappearingMessageTokenIfNecessary(
        target: SentMessageTranscriptTarget,
        localIdentifiers: LocalIdentifiers,
        tx: DBWriteTransaction
    ) {
        switch target {
        case .group:
            return
        case .contact(let thread, let disappearingMessageToken):
            groupManager.remoteUpdateDisappearingMessages(
                withContactThread: thread,
                disappearingMessageToken: disappearingMessageToken,
                changeAuthor: localIdentifiers.aci,
                localIdentifiers: localIdentifiers,
                tx: tx
            )
        }
    }

    // MARK: -

    private func processRecipientUpdate(
        _ transcript: SentMessageTranscript,
        groupThread: TSGroupThread,
        tx: DBWriteTransaction
    ) -> Result<TSOutgoingMessage?, Error> {

        if transcript.recipientStates.isEmpty {
            return .failure(OWSAssertionError("Ignoring empty 'recipient update' transcript."))
        }

        let timestamp = transcript.timestamp
        if timestamp < 1 {
            return .failure(OWSAssertionError("'recipient update' transcript has invalid timestamp."))
        }
        if !SDS.fitsInInt64(timestamp) {
            return .failure(OWSAssertionError("Invalid timestamp."))
        }

        let groupId = groupThread.groupId
        if groupId.isEmpty {
            return .failure(OWSAssertionError("'recipient update' transcript has invalid groupId."))
        }

        let messages: [TSOutgoingMessage]
        do {
            messages = try interactionStore
                .interactions(withTimestamp: timestamp, tx: tx)
                .compactMap { $0 as? TSOutgoingMessage }
        } catch {
            return .failure(OWSAssertionError("Error loading interactions: \(error)"))
        }

        if messages.isEmpty {
            // This message may have disappeared.
            Logger.error("No matching message with timestamp: \(timestamp)")
            return .success(nil)
        }

        var messageFound: TSOutgoingMessage?
        for message in messages {
            guard message.wasNotCreatedLocally else {
                // wasNotCreatedLocally isn't always set for very old linked messages, but:
                //
                // a) We should never receive a "sent update" for a very old message.
                // b) It's safe to discard suspicious "sent updates."
                continue
            }
            guard message.uniqueThreadId == groupThread.uniqueId else {
                continue
            }

            Logger.info("Processing 'recipient update' transcript in thread: \(groupThread.uniqueId), timestamp: \(timestamp), recipientIds: \(transcript.recipientStates.keys)")

            interactionStore.updateRecipientsFromNonLocalDevice(
                message,
                recipientStates: transcript.recipientStates,
                isSentUpdate: true,
                tx: tx
            )

            // In theory more than one message could be found.
            // In practice, this should never happen, as we functionally
            // use timestamps as unique identifiers.
            messageFound = message
        }

        if messageFound == nil {
            // This message may have disappeared.
            Logger.error("No matching message with timestamp: \(timestamp)")
        }

        return .success(messageFound)
    }

    private func archiveSessions(for address: SignalServiceAddress, tx: DBWriteTransaction) {
        let sessionStore = signalProtocolStoreManager.signalProtocolStore(for: .aci).sessionStore
        sessionStore.archiveAllSessions(for: address, tx: tx)
    }
}
