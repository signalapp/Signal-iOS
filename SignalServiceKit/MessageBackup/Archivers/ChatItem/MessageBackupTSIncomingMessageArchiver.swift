//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

class MessageBackupTSIncomingMessageArchiver: MessageBackupProtoArchiver {
    typealias Details = MessageBackup.InteractionArchiveDetails

    private typealias ArchiveFrameError = MessageBackup.ArchiveFrameError<MessageBackup.InteractionUniqueId>
    private typealias RestoreFrameError = MessageBackup.RestoreFrameError<MessageBackup.ChatItemId>

    private let contentsArchiver: MessageBackupTSMessageContentsArchiver
    private let editMessageStore: EditMessageStore
    private let interactionStore: InteractionStore

    init(
        contentsArchiver: MessageBackupTSMessageContentsArchiver,
        editMessageStore: EditMessageStore,
        interactionStore: InteractionStore
    ) {
        self.contentsArchiver = contentsArchiver
        self.editMessageStore = editMessageStore
        self.interactionStore = interactionStore
    }

    // MARK: - Archiving

    func archiveIncomingMessage(
        _ incomingMessage: TSIncomingMessage,
        thread _: TSThread,
        context: MessageBackup.ChatArchivingContext,
        tx: DBReadTransaction
    ) -> MessageBackup.ArchiveInteractionResult<Details> {
        var partialErrors = [ArchiveFrameError]()

        let shouldArchiveEditHistory: Bool
        switch incomingMessage.editState {
        case .pastRevision:
            /// This message represents a past revision of a message, which is
            /// archived as part of archiving the latest revision. Consequently,
            /// we can skip this past revision here.
            return .skippableChatUpdate(.pastRevisionOfEditedMessage)
        case .none:
            shouldArchiveEditHistory = false
        case .latestRevisionRead, .latestRevisionUnread:
            shouldArchiveEditHistory = true
        }

        var incomingMessageDetails: Details
        switch buildInteractionArchiveDetails(
            incomingMessage: incomingMessage,
            editRecord: nil,
            context: context,
            partialErrors: &partialErrors,
            tx: tx
        ).bubbleUp(Details.self, partialErrors: &partialErrors) {
        case .continue(let _incomingMessageDetails):
            incomingMessageDetails = _incomingMessageDetails
        case .bubbleUpError(let errorResult):
            return errorResult
        }

        if shouldArchiveEditHistory {
            switch addEditHistoryArchiveDetails(
                toLatestRevisionArchiveDetails: &incomingMessageDetails,
                latestRevisionMessage: incomingMessage,
                context: context,
                partialErrors: &partialErrors,
                tx: tx
            ).bubbleUp(Details.self, partialErrors: &partialErrors) {
            case .continue:
                break
            case .bubbleUpError(let errorResult):
                return errorResult
            }
        }

        if partialErrors.isEmpty {
            return .success(incomingMessageDetails)
        } else {
            return .partialFailure(incomingMessageDetails, partialErrors)
        }
    }

    /// Archive each of the prior revisions of the given latest revision of a
    /// message, and add those prior-revision archive details to the given
    /// archive details for the latest revision.
    private func addEditHistoryArchiveDetails(
        toLatestRevisionArchiveDetails latestRevisionDetails: inout Details,
        latestRevisionMessage: TSIncomingMessage,
        context: MessageBackup.ChatArchivingContext,
        partialErrors: inout [ArchiveFrameError],
        tx: DBReadTransaction
    ) -> MessageBackup.ArchiveInteractionResult<Void> {
        /// The edit history, from oldest revision to newest. This ordering
        /// matches the expected ordering for `revisions` on a `ChatItem`, but
        /// is reverse of what we get from `editMessageStore`.
        let editHistory: [(EditRecord, TSIncomingMessage?)]
        do {
            editHistory = try editMessageStore.findEditHistory(
                for: latestRevisionMessage,
                tx: tx
            ).reversed()
        } catch {
            return .messageFailure([.archiveFrameError(
                .editHistoryFailedToFetch,
                latestRevisionMessage.uniqueInteractionId
            )])
        }

        for (editRecord, pastRevisionMessage) in editHistory {
            guard let pastRevisionMessage else { continue }

            /// Build archive details for this past revision, so we can append
            /// them to the most recent revision's archive details.
            ///
            /// We'll power through anything less than a `.completeFailure`
            /// while restoring a past revision, instead tracking the error,
            /// dropping the revision, and moving on.
            let pastRevisionDetails: Details
            switch buildInteractionArchiveDetails(
                incomingMessage: pastRevisionMessage,
                editRecord: editRecord,
                context: context,
                partialErrors: &partialErrors,
                tx: tx
            ) {
            case .success(let _pastRevisionDetails):
                pastRevisionDetails = _pastRevisionDetails
            case .partialFailure(let _pastRevisionDetails, let _partialErrors):
                pastRevisionDetails = _pastRevisionDetails
                partialErrors.append(contentsOf: _partialErrors)
            case .messageFailure(let _partialErrors):
                partialErrors.append(contentsOf: _partialErrors)
                continue
            case .completeFailure(let fatalError):
                return .completeFailure(fatalError)
            case .skippableChatUpdate, .notYetImplemented:
                // This should never happen for an edit revision!
                continue
            }

            /// We're iterating the edit history from oldest to newest, so the
            /// past revision details stored on `latestRevisionDetails` will
            /// also be ordered oldest to newest.
            latestRevisionDetails.addPastRevision(pastRevisionDetails)
        }

        return .success(())
    }

    /// Build archive details for the given message.
    ///
    /// - Parameter editRecord
    /// If the given message is a prior revision, this should contain the edit
    /// record corresponding to that revision.
    private func buildInteractionArchiveDetails(
        incomingMessage message: TSIncomingMessage,
        editRecord: EditRecord?,
        context: MessageBackup.ChatArchivingContext,
        partialErrors: inout [ArchiveFrameError],
        tx: DBReadTransaction
    ) -> MessageBackup.ArchiveInteractionResult<Details> {
        guard
            let authorAddress = MessageBackup.ContactAddress(
                // Incoming message authors are always ACIs, not PNIs
                aci: Aci.parseFrom(aciString: message.authorUUID),
                e164: E164(message.authorPhoneNumber)
            )?.asArchivingAddress()
        else {
            // This is an invalid message.
            return .messageFailure([.archiveFrameError(.invalidIncomingMessageAuthor, message.uniqueInteractionId)])
        }
        guard let author = context.recipientContext[authorAddress] else {
            return .messageFailure([.archiveFrameError(
                .referencedRecipientIdMissing(authorAddress),
                message.uniqueInteractionId
            )])
        }

        let contentsResult = contentsArchiver.archiveMessageContents(
            message,
            context: context.recipientContext,
            tx: tx
        )

        let chatItemType: MessageBackupTSMessageContentsArchiver.ChatItemType
        switch contentsResult.bubbleUp(Details.self, partialErrors: &partialErrors) {
        case .continue(let t):
            chatItemType = t
        case .bubbleUpError(let errorResult):
            return errorResult
        }

        let details = Details(
            author: author,
            directionalDetails: buildIncomingMessageDetails(message, editRecord: editRecord),
            dateCreated: message.timestamp,
            expireStartDate: message.expireStartedAt,
            expiresInMs: UInt64(message.expiresInSeconds) * 1000,
            isSealedSender: message.wasReceivedByUD.negated,
            chatItemType: chatItemType
        )

        return .success(details)
    }

    private func buildIncomingMessageDetails(
        _ message: TSIncomingMessage,
        editRecord: EditRecord?
    ) -> Details.DirectionalDetails {
        var incomingMessage = BackupProto_ChatItem.IncomingMessageDetails()
        incomingMessage.dateReceived = message.receivedAtTimestamp
        incomingMessage.dateServerSent = message.serverTimestamp?.uint64Value ?? 0
        // The message may not have been marked read if it's a past revision,
        // but its edit record will have been.
        incomingMessage.read = editRecord?.read ?? message.wasRead
        incomingMessage.sealedSender = message.wasReceivedByUD

        return .incoming(incomingMessage)
    }

    // MARK: - Restoring

    func restoreIncomingChatItem(
        _ topLevelChatItem: BackupProto_ChatItem,
        incomingDetails: BackupProto_ChatItem.IncomingMessageDetails,
        chatThread: MessageBackup.ChatThread,
        context: MessageBackup.ChatRestoringContext,
        tx: DBWriteTransaction
    ) -> MessageBackup.RestoreInteractionResult<Void> {
        let authorAci: Aci?
        let authorE164: E164?
        switch context.recipientContext[topLevelChatItem.authorRecipientId] {
        case .contact(let address):
            authorAci = address.aci
            authorE164 = address.e164
            if authorAci == nil && authorE164 == nil {
                // Don't accept pni-only addresses. An incoming
                // message can only come from an aci, or if its
                // a legacy message, possibly from an e164.
                fallthrough
            }
        default:
            return .messageFailure([.restoreFrameError(
                .invalidProtoData(.incomingMessageNotFromAciOrE164),
                topLevelChatItem.id
            )])
        }

        var partialErrors = [RestoreFrameError]()

        let latestRevisionRestoreResult = _restoreIncomingChatItem(
            topLevelChatItem,
            incomingDetails: incomingDetails,
            authorAci: authorAci,
            authorE164: authorE164,
            hasRevisions: topLevelChatItem.revisions.count > 0,
            isRevision: false,
            chatThread: chatThread,
            context: context,
            tx: tx
        )
        guard let latestRevisionMessage = latestRevisionRestoreResult
            .unwrap(partialErrors: &partialErrors)
        else {
            return .messageFailure(partialErrors)
        }

        var earlierRevisionMessages = [TSIncomingMessage]()

        /// `ChatItem.revisions` is ordered oldest -> newest, which aligns with
        /// how we want to insert them. Older revisions should be inserted
        /// before newer ones.
        for revisionChatItem in topLevelChatItem.revisions {
            let incomingDetails: BackupProto_ChatItem.IncomingMessageDetails
            switch revisionChatItem.directionalDetails {
            case .incoming(let incomingMessageDetails):
                incomingDetails = incomingMessageDetails
            case nil, .outgoing, .directionless:
                return .messageFailure([.restoreFrameError(
                    .invalidProtoData(.revisionOfIncomingMessageMissingIncomingDetails),
                    revisionChatItem.id
                )])
            }

            let earlierRevisionRestoreResult = _restoreIncomingChatItem(
                revisionChatItem,
                incomingDetails: incomingDetails,
                authorAci: authorAci,
                authorE164: authorE164,
                hasRevisions: false,
                isRevision: true,
                chatThread: chatThread,
                context: context,
                tx: tx
            )
            guard let earlierRevisionMessage = earlierRevisionRestoreResult
                .unwrap(partialErrors: &partialErrors)
            else {
                /// This means we won't attempt to restore any later revisions,
                /// but we can't be confident they would have restored
                /// successfully anyway.
                return .messageFailure(partialErrors)
            }

            earlierRevisionMessages.append(earlierRevisionMessage)
        }

        for earlierRevisionMessage in earlierRevisionMessages {
            let editRecord = EditRecord(
                latestRevisionId: latestRevisionMessage.sqliteRowId!,
                pastRevisionId: earlierRevisionMessage.sqliteRowId!,
                read: earlierRevisionMessage.wasRead
            )

            editMessageStore.insert(editRecord, tx: tx)
        }

        if partialErrors.isEmpty {
            return .success(())
        } else {
            return .partialRestore((), partialErrors)
        }
    }

    /// Restore an "original" chat item, or one representing a message without
    /// any edits. The message represented by this chat item may later have
    /// edits applied.
    private func _restoreIncomingChatItem(
        _ chatItem: BackupProto_ChatItem,
        incomingDetails: BackupProto_ChatItem.IncomingMessageDetails,
        authorAci: Aci?,
        authorE164: E164?,
        hasRevisions: Bool,
        isRevision: Bool,
        chatThread: MessageBackup.ChatThread,
        context: MessageBackup.ChatRestoringContext,
        tx: DBWriteTransaction
    ) -> MessageBackup.RestoreInteractionResult<TSIncomingMessage> {
        guard let chatItemItem = chatItem.item else {
            return .messageFailure([.restoreFrameError(
                .invalidProtoData(.chatItemMissingItem),
                chatItem.id
            )])
        }

        var partialErrors = [RestoreFrameError]()

        let contentsResult = contentsArchiver.restoreContents(
            chatItemItem,
            chatItemId: chatItem.id,
            chatThread: chatThread,
            context: context,
            tx: tx
        )
        guard let contents = contentsResult.unwrap(partialErrors: &partialErrors) else {
            return .messageFailure(partialErrors)
        }

        let editState: TSEditState = {
            if isRevision {
                return .pastRevision
            } else if hasRevisions, incomingDetails.read {
                return .latestRevisionRead
            } else if hasRevisions {
                return .latestRevisionUnread
            } else {
                return .none
            }
        }()

        let message: TSIncomingMessage = {
            switch contents {
            case .archivedPayment(let archivedPayment):
                let messageBuilder = TSIncomingMessageBuilder(
                    thread: chatThread.tsThread,
                    timestamp: chatItem.dateSent,
                    receivedAtTimestamp: incomingDetails.dateReceived,
                    authorAci: authorAci,
                    authorE164: authorE164,
                    messageBody: nil,
                    bodyRanges: nil,
                    editState: editState,
                    expiresInSeconds: UInt32(chatItem.expiresInMs / 1000),
                    expireStartedAt: chatItem.expireStartDate,
                    read: incomingDetails.read,
                    serverTimestamp: incomingDetails.dateServerSent,
                    serverDeliveryTimestamp: 0,
                    serverGuid: nil,
                    wasReceivedByUD: incomingDetails.sealedSender,
                    isViewOnceMessage: false,
                    storyAuthorAci: nil,
                    storyTimestamp: nil,
                    storyReactionEmoji: nil,
                    giftBadge: nil,
                    paymentNotification: nil
                )
                return OWSIncomingArchivedPaymentMessage(
                    incomingMessageWith: messageBuilder,
                    amount: archivedPayment.amount,
                    fee: archivedPayment.fee,
                    note: archivedPayment.note
                )
            case .text(let text):
                let messageBody = text.body
                let messageBuilder = TSIncomingMessageBuilder(
                    thread: chatThread.tsThread,
                    timestamp: chatItem.dateSent,
                    receivedAtTimestamp: incomingDetails.dateReceived,
                    authorAci: authorAci,
                    authorE164: authorE164,
                    messageBody: messageBody.text,
                    bodyRanges: messageBody.ranges,
                    editState: editState,
                    expiresInSeconds: UInt32(chatItem.expiresInMs / 1000),
                    expireStartedAt: chatItem.expireStartDate,
                    read: incomingDetails.read,
                    serverTimestamp: incomingDetails.dateServerSent,
                    serverDeliveryTimestamp: 0,
                    serverGuid: nil,
                    wasReceivedByUD: incomingDetails.sealedSender,
                    isViewOnceMessage: false,
                    storyAuthorAci: nil,
                    storyTimestamp: nil,
                    storyReactionEmoji: nil,
                    giftBadge: nil,
                    paymentNotification: nil
                )
                let message = messageBuilder.build()
                text.quotedMessage.map { interactionStore.update(message, with: $0, tx: tx) }
                return message
            }
        }()

        interactionStore.insertInteraction(message, tx: tx)

        let downstreamObjectsResult = contentsArchiver.restoreDownstreamObjects(
            message: message,
            thread: chatThread,
            chatItemId: chatItem.id,
            restoredContents: contents,
            context: context,
            tx: tx
        )
        guard downstreamObjectsResult.unwrap(partialErrors: &partialErrors) else {
            return .messageFailure(partialErrors)
        }

        if partialErrors.isEmpty {
            return .success(message)
        } else {
            return .partialRestore(message, partialErrors)
        }
    }
}
