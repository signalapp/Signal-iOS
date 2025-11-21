//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public extension TSMessage {

    @objc
    var isIncoming: Bool { self is TSIncomingMessage }

    @objc
    var isOutgoing: Bool { self is TSOutgoingMessage }

    // MARK: - Attachments

    func hasBodyAttachments(transaction: DBReadTransaction) -> Bool {
        guard let sqliteRowId else { return false }
        return DependenciesBridge.shared.attachmentStore
            .fetchReferences(
                owners: [
                    .messageOversizeText(messageRowId: sqliteRowId),
                    .messageBodyAttachment(messageRowId: sqliteRowId)
                ],
                tx: transaction
            )
            .isEmpty.negated
    }

    func hasMediaAttachments(transaction: DBReadTransaction) -> Bool {
        guard let sqliteRowId else { return false }
        return DependenciesBridge.shared.attachmentStore
            .fetchFirstReference(
                owner: .messageBodyAttachment(messageRowId: sqliteRowId),
                tx: transaction
            ) != nil
    }

    func oversizeTextAttachment(transaction: DBReadTransaction) -> Attachment? {
        guard let sqliteRowId else { return nil }
        return DependenciesBridge.shared.attachmentStore
            .fetchFirstReferencedAttachment(
                for: .messageOversizeText(messageRowId: sqliteRowId),
                tx: transaction
            )?
            .attachment
    }

    func allAttachments(transaction: DBReadTransaction) -> [Attachment] {
        guard let sqliteRowId else { return [] }
        return DependenciesBridge.shared.attachmentStore
            .allAttachments(forMessageWithRowId: sqliteRowId, tx: transaction)
            .fetchAll(tx: transaction)
    }

    /// The raw body contains placeholders for things like mentions and is not user friendly.
    /// If you want a constant string representing the body of this message, this is it.
    @objc(rawBodyWithTransaction:)
    func rawBody(transaction: DBReadTransaction) -> String? {
        if let oversizeText = try? self.oversizeTextAttachment(transaction: transaction)?.asStream()?.decryptedLongText() {
            return oversizeText
        }
        return self.body?.nilIfEmpty
    }

    func failedOrPendingAttachments(transaction tx: DBReadTransaction) -> [AttachmentPointer] {
        let attachments: [Attachment] = allAttachments(transaction: tx)
        let states: [AttachmentDownloadState] = [.failed, .none]

        return attachments.compactMap { attachment -> AttachmentPointer? in
            guard
                attachment.asStream() == nil,
                let attachmentPointer = attachment.asAnyPointer()
            else {
                return nil
            }
            let downloadState = attachmentPointer.downloadState(tx: tx)
            guard states.contains(downloadState) else {
                return nil
            }
            return attachmentPointer
        }
    }

    // MARK: Attachment Deletes

    @objc
    func removeBodyMediaAttachments(tx: DBWriteTransaction) {
        guard let sqliteRowId else { return }
        try? DependenciesBridge.shared.attachmentManager.removeAllAttachments(
            from: [.messageBodyAttachment(messageRowId: sqliteRowId)],
            tx: tx
        )
    }

    @objc
    func removeOversizeTextAttachment(tx: DBWriteTransaction) {
        guard let sqliteRowId else { return }
        try? DependenciesBridge.shared.attachmentManager.removeAllAttachments(
            from: [.messageOversizeText(messageRowId: sqliteRowId)],
            tx: tx
        )
    }

    @objc
    func removeLinkPreviewAttachment(tx: DBWriteTransaction) {
        guard let sqliteRowId else { return }
        try? DependenciesBridge.shared.attachmentManager.removeAllAttachments(
            from: [.messageLinkPreview(messageRowId: sqliteRowId)],
            tx: tx
        )
    }

    @objc
    func removeStickerAttachment(tx: DBWriteTransaction) {
        guard let sqliteRowId else { return }
        try? DependenciesBridge.shared.attachmentManager.removeAllAttachments(
            from: [.messageSticker(messageRowId: sqliteRowId)],
            tx: tx
        )
    }

    @objc
    func removeContactShareAvatarAttachment(tx: DBWriteTransaction) {
        guard let sqliteRowId else { return }
        try? DependenciesBridge.shared.attachmentManager.removeAllAttachments(
            from: [.messageContactAvatar(messageRowId: sqliteRowId)],
            tx: tx
        )
    }

    @objc
    func removeAllAttachments(tx: DBWriteTransaction) {
        guard let sqliteRowId else { return }
        try? DependenciesBridge.shared.attachmentManager.removeAllAttachments(
            from: AttachmentReference.MessageOwnerTypeRaw.allCases.map {
                $0.with(messageRowId: sqliteRowId)
            },
            tx: tx
        )
    }

    // MARK: - Mentions

    @objc
    func insertMentionsInDatabase(tx: DBWriteTransaction) {
        Self.insertMentionsInDatabase(message: self, tx: tx)
    }

    static func insertMentionsInDatabase(message: TSMessage, tx: DBWriteTransaction) {
        guard let bodyRanges = message.bodyRanges else {
            return
        }
        // If we have any mentions, we need to save them to aid in querying for
        // messages that mention a given user. We only need to save one mention
        // record per ACI, even if the same ACI is mentioned multiple times in the
        // message.
        let uniqueMentionedAcis = Set(bodyRanges.mentions.values)
        for mentionedAci in uniqueMentionedAcis {
            let mention = TSMention(uniqueMessageId: message.uniqueId, uniqueThreadId: message.uniqueThreadId, aci: mentionedAci)
            mention.anyInsert(transaction: tx)
        }
    }

    // MARK: - Reactions

    var reactionFinder: ReactionFinder {
        return ReactionFinder(uniqueMessageId: uniqueId)
    }

    @objc
    func removeAllReactions(transaction: DBWriteTransaction) {
        guard !CurrentAppContext().isRunningTests else { return }
        reactionFinder.deleteAllReactions(transaction: transaction)
    }

    @objc
    func removeAllMentions(transaction tx: DBWriteTransaction) {
        MentionFinder.deleteAllMentions(for: self, transaction: tx)
    }

    @objc
    func allReactionIds(transaction: DBReadTransaction) -> [String]? {
        return reactionFinder.allUniqueIds(transaction: transaction)
    }

    @objc
    func markUnreadReactionsAsRead(transaction: DBWriteTransaction) {
        let unreadReactions = reactionFinder.unreadReactions(transaction: transaction)
        unreadReactions.forEach { $0.markAsRead(transaction: transaction) }
    }

    func reaction(for reactor: Aci, tx: DBReadTransaction) -> OWSReaction? {
        return reactionFinder.reaction(for: reactor, tx: tx)
    }

    @discardableResult
    func recordReaction(
        for reactor: Aci,
        emoji: String,
        sentAtTimestamp: UInt64,
        receivedAtTimestamp: UInt64,
        tx: DBWriteTransaction
    ) -> (oldValue: OWSReaction?, newValue: OWSReaction)? {
        return self.recordReaction(
            for: reactor,
            emoji: emoji,
            sentAtTimestamp: sentAtTimestamp,
            sortOrder: receivedAtTimestamp,
            tx: tx
        )
    }

    @discardableResult
    func recordReaction(
        for reactor: Aci,
        emoji: String,
        sentAtTimestamp: UInt64,
        sortOrder: UInt64,
        tx: DBWriteTransaction
    ) -> (oldValue: OWSReaction?, newValue: OWSReaction)? {
        guard !wasRemotelyDeleted else {
            owsFailDebug("attempted to record a reaction for a message that was deleted")
            return nil
        }

        assert(emoji.isSingleEmoji)

        // Remove any previous reaction, there can only be one
        let oldReaction = removeReaction(for: reactor, tx: tx)

        let newReaction = OWSReaction(
            uniqueMessageId: uniqueId,
            emoji: emoji,
            reactor: reactor,
            sentAtTimestamp: sentAtTimestamp,
            receivedAtTimestamp: receivedAtTimestamp
        )

        newReaction.anyInsert(transaction: tx)

        // Reactions to messages we send need to be manually marked
        // as read as they trigger notifications we need to clear
        // out. Everything else can be automatically read.
        if !(self is TSOutgoingMessage) { newReaction.markAsRead(transaction: tx) }

        SSKEnvironment.shared.databaseStorageRef.touch(interaction: self, shouldReindex: false, tx: tx)

        return (oldReaction, newReaction)
    }

    @discardableResult
    func removeReaction(for reactor: Aci, tx: DBWriteTransaction) -> OWSReaction? {
        guard let reaction = reaction(for: reactor, tx: tx) else {
            return nil
        }

        reaction.anyRemove(transaction: tx)
        SSKEnvironment.shared.databaseStorageRef.touch(interaction: self, shouldReindex: false, tx: tx)

        SSKEnvironment.shared.notificationPresenterRef.cancelNotifications(reactionId: reaction.uniqueId)

        return reaction
    }

    // MARK: - Edits

    func removeEdits(transaction: DBWriteTransaction) {
        try! processRelatedMessageEdits(
            deleteEditRecords: true,
            tx: transaction,
            processMessage: { message in
                // Don't delete the message driving the deletion, just the related edits/interactions.
                // The presumption is the message itself will be deleted after this step.
                guard message.uniqueId != self.uniqueId else { return }

                // Delete the message, but since edits are already in the process of being
                // handled, don't do anything further by passing in `.doNotDelete`
                DependenciesBridge.shared.interactionDeleteManager.delete(
                    message,
                    sideEffects: .custom(deleteAssociatedEdits: false),
                    tx: transaction
                )
            }
        )
    }

    /// Enumerate "edited messages" (ie revisions) related to self.
    ///
    /// You may pass the latest revision or a prior revision. Prior revisions
    /// are passed to `processMessage` before the latest revision. If there
    /// aren't any prior revisions, `self` is assumed to be the latest revision.
    ///
    /// The message for `self` isn't re-fetched -- `self` is always passed to
    /// `processMessage`. (Note also that `self` is always passed to
    /// `processMessage` exactly once.)
    ///
    /// The processing of edit records is unbounded, but the number of edits per
    /// message is limited by both the sender and receiver.
    private func processRelatedMessageEdits(
        deleteEditRecords: Bool,
        tx: DBWriteTransaction,
        processMessage: ((TSMessage) throws -> Void)
    ) throws {
        let editMessageStore = DependenciesBridge.shared.editMessageStore
        let editRecords = try editMessageStore.findEditRecords(relatedTo: self, tx: tx)

        if deleteEditRecords {
            for editRecord in editRecords {
                try editRecord.delete(tx.database)
            }
        }

        let pastRevisionIds = Set(editRecords.map(\.pastRevisionId))
        var latestRevisionIds = Set(editRecords.map(\.latestRevisionId))
        latestRevisionIds.subtract(pastRevisionIds)

        if editRecords.isEmpty {
            latestRevisionIds.insert(self.sqliteRowId!)
        } else {
            // Check the integrity of the EditRecords.
            if latestRevisionIds.count != 1 || pastRevisionIds.count != editRecords.count {
                let revisionIds = editRecords.map { ($0.pastRevisionId, $0.latestRevisionId) }
                owsFailDebug("Found malformed edit history: \(revisionIds)")
            }
        }

        for revisionId in pastRevisionIds.sorted() + latestRevisionIds.sorted() {
            if revisionId == self.sqliteRowId {
                try processMessage(self)
            } else {
                let interaction = InteractionFinder.fetch(rowId: revisionId, transaction: tx)
                if let message = interaction as? TSMessage {
                    try processMessage(message)
                }
            }
        }
    }

    // MARK: - Remote Delete

    // A message can be remotely deleted iff:
    //  * you sent this message
    //  * you haven't already remotely deleted this message
    //  * it's not a message with a gift badge
    //  * it has been less than 24 hours since you sent the message
    //    * this includes messages sent in the future
    var canBeRemotelyDeleted: Bool {
        guard let outgoingMessage = self as? TSOutgoingMessage else { return false }
        guard !outgoingMessage.wasRemotelyDeleted else { return false }
        guard outgoingMessage.giftBadge == nil else { return false }

        let (elapsedTime, isInFuture) = Date.ows_millisecondTimestamp().subtractingReportingOverflow(outgoingMessage.timestamp)
        guard isInFuture || (elapsedTime <= UInt64.dayInMs) else { return false }

        return true
    }

    @objc(OWSRemoteDeleteProcessingResult)
    enum RemoteDeleteProcessingResult: Int, Error {
        case deletedMessageMissing
        case invalidDelete
        case success
    }

    class func tryToRemotelyDeleteMessage(
        fromAuthor authorAci: Aci,
        sentAtTimestamp: UInt64,
        threadUniqueId: String?,
        serverTimestamp: UInt64,
        transaction: DBWriteTransaction
    ) -> RemoteDeleteProcessingResult {
        guard SDS.fitsInInt64(sentAtTimestamp) else {
            owsFailDebug("Unable to delete a message with invalid sentAtTimestamp: \(sentAtTimestamp)")
            return .invalidDelete
        }

        if let threadUniqueId = threadUniqueId, let messageToDelete = InteractionFinder.findMessage(
            withTimestamp: sentAtTimestamp,
            threadId: threadUniqueId,
            author: SignalServiceAddress(authorAci),
            transaction: transaction
        ) {
            if messageToDelete is TSOutgoingMessage, SignalServiceAddress(authorAci).isLocalAddress {
                messageToDelete.markMessageAsRemotelyDeleted(transaction: transaction)
                return .success
            } else if var incomingMessageToDelete = messageToDelete as? TSIncomingMessage {
                if incomingMessageToDelete.editState == .pastRevision {
                    // The remote delete targeted an old revision, fetch
                    // swap out the target message for the latest (or return an error)
                    // This avoids cases where older edits could be deleted and
                    // leave newer revisions
                    if let latestEdit = DependenciesBridge.shared.editMessageStore.findMessage(
                        fromEdit: incomingMessageToDelete,
                        tx: transaction) as? TSIncomingMessage {
                        incomingMessageToDelete = latestEdit
                    } else {
                        Logger.info("Ignoring delete for missing edit target.")
                        return .invalidDelete
                    }
                }

                guard let messageToDeleteServerTimestamp = incomingMessageToDelete.serverTimestamp?.uint64Value else {
                    // Older messages might be missing this, but since we only allow deleting for a small
                    // window after you send a message we should generally never hit this path.
                    owsFailDebug("can't delete a message without a serverTimestamp")
                    return .invalidDelete
                }

                guard messageToDeleteServerTimestamp < serverTimestamp else {
                    owsFailDebug("Can't delete a message from the future.")
                    return .invalidDelete
                }

                guard serverTimestamp - messageToDeleteServerTimestamp < (2 * UInt64.dayInMs) else {
                    owsFailDebug("Ignoring message delete sent more than 48 hours after the original message")
                    return .invalidDelete
                }

                incomingMessageToDelete.markMessageAsRemotelyDeleted(transaction: transaction)

                return .success
            } else {
                owsFailDebug("Only incoming messages can be deleted remotely")
                return .invalidDelete
            }
        } else if let storyMessage = StoryFinder.story(
            timestamp: sentAtTimestamp,
            author: authorAci,
            transaction: transaction
        ) {
            // If there are still valid contexts for this outgoing private story message, don't actually delete the model.
            if storyMessage.groupId == nil,
               case .outgoing(let recipientStates) = storyMessage.manifest,
               !recipientStates.values.flatMap({ $0.contexts }).isEmpty {
                return .success
            }

            storyMessage.anyRemove(transaction: transaction)

            return .success
        } else {
            // The message doesn't exist locally, so nothing to do.
            Logger.info("Attempted to remotely delete a message that doesn't exist \(sentAtTimestamp)")
            return .deletedMessageMissing
        }

    }

    private func markMessageAsRemotelyDeleted(transaction: DBWriteTransaction) {
        // Delete any past edit revisions.
        try! processRelatedMessageEdits(
            deleteEditRecords: false,
            tx: transaction,
            processMessage: { message in
                message.updateWithRemotelyDeletedAndRemoveRenderableContent(with: transaction)
            }
        )
        SSKEnvironment.shared.notificationPresenterRef.cancelNotifications(messageIds: [self.uniqueId])
    }

    // MARK: - Preview text

    @objc(previewTextForGiftBadgeWithTransaction:)
    func previewTextForGiftBadge(transaction: DBReadTransaction) -> String {
        if let incomingMessage = self as? TSIncomingMessage {
            let senderShortName = SSKEnvironment.shared.contactManagerRef.displayName(
                for: incomingMessage.authorAddress, tx: transaction
            ).resolvedValue(useShortNameIfAvailable: true)
            let format = OWSLocalizedString(
                "DONATION_ON_BEHALF_OF_A_FRIEND_PREVIEW_INCOMING",
                comment: "A friend has donated on your behalf. This text is shown in the list of chats, when the most recent message is one of these donations. Embeds {friend's short display name}."
            )
            return String(format: format, senderShortName)
        } else if let outgoingMessage = self as? TSOutgoingMessage {
            let recipientShortName: String
            let recipients = outgoingMessage.recipientAddresses()
            if let recipient = recipients.first, recipients.count == 1 {
                recipientShortName = SSKEnvironment.shared.contactManagerRef.displayName(
                    for: recipient, tx: transaction
                ).resolvedValue(useShortNameIfAvailable: true)
            } else {
                owsFailDebug("[Gifting] Expected exactly 1 recipient but got \(recipients.count)")
                recipientShortName = CommonStrings.unknownUser
            }
            let format = OWSLocalizedString(
                "DONATION_ON_BEHALF_OF_A_FRIEND_PREVIEW_OUTGOING",
                comment: "You have a made a donation on a friend's behalf. This text is shown in the list of chats, when the most recent message is one of these donations. Embeds {friend's short display name}."
            )
            return String(format: format, recipientShortName)
        } else {
            owsFail("Could not generate preview text because message wasn't incoming or outgoing")
        }
    }

    func notificationPreviewText(_ tx: DBReadTransaction) -> String {
        switch previewText(tx) {
        case let .body(body, prefix, ranges):
            let hydrated = MessageBody(text: body, ranges: ranges ?? .empty)
                .hydrating(mentionHydrator: ContactsMentionHydrator.mentionHydrator(transaction: tx))
                .asPlaintext()
            guard let prefix else {
                return hydrated.filterForDisplay
            }
            return prefix.appending(hydrated).filterForDisplay
        case let .remotelyDeleted(text),
            let .storyReactionEmoji(text),
            let .viewOnceMessage(text),
            let .contactShare(text),
            let .stickerDescription(text),
            let .giftBadge(text),
            let .infoMessage(text),
            let .paymentMessage(text):
            return text
        case .empty:
            return ""
        }
    }

    func conversationListPreviewText(_ tx: DBReadTransaction) -> HydratedMessageBody {
        switch previewText(tx) {
        case let .body(body, prefix, ranges):
            let hydrated = MessageBody(text: body, ranges: ranges ?? .empty)
                .hydrating(mentionHydrator: ContactsMentionHydrator.mentionHydrator(transaction: tx))
            guard let prefix else {
                return hydrated
            }
            return hydrated.addingPrefix(prefix)
        case let .remotelyDeleted(text),
            let .storyReactionEmoji(text),
            let .viewOnceMessage(text),
            let .contactShare(text),
            let .stickerDescription(text),
            let .giftBadge(text),
            let .infoMessage(text),
            let .paymentMessage(text):
            return HydratedMessageBody.fromPlaintextWithoutRanges(text)
        case .empty:
            return HydratedMessageBody.fromPlaintextWithoutRanges("")
        }
    }

    func conversationListSearchResultsBody(_ tx: DBReadTransaction) -> MessageBody? {
        switch previewText(tx) {
        case let .body(body, _, ranges):
            // We ignore the prefix here.
            return MessageBody(text: body, ranges: ranges ?? .empty)
        case .remotelyDeleted,
            .storyReactionEmoji,
            .viewOnceMessage,
            .contactShare,
            .stickerDescription,
            .giftBadge,
            .infoMessage,
            .paymentMessage,
            .empty:
            return nil
        }
    }

    private enum PreviewText {
        case body(String, prefix: String?, ranges: MessageBodyRanges?)
        case remotelyDeleted(String)
        case storyReactionEmoji(String)
        case viewOnceMessage(String)
        case contactShare(String)
        case stickerDescription(String)
        case giftBadge(String)
        case infoMessage(String)
        case paymentMessage(String)
        case empty
    }

    private func previewText(_ tx: DBReadTransaction) -> PreviewText {
        if let infoMessage = self as? TSInfoMessage {
            return .infoMessage(infoMessage.infoMessagePreviewText(with: tx))
        }

        if (self is OWSPaymentMessage || self is OWSArchivedPaymentMessage) {
            return .paymentMessage(OWSLocalizedString(
                "PAYMENTS_THREAD_PREVIEW_TEXT",
                comment: "Payments Preview Text shown in chat list for payments."
            ))
        }

        if self.wasRemotelyDeleted {
            return .remotelyDeleted((self is TSIncomingMessage)
                ? OWSLocalizedString("THIS_MESSAGE_WAS_DELETED", comment: "text indicating the message was remotely deleted")
                : OWSLocalizedString("YOU_DELETED_THIS_MESSAGE", comment: "text indicating the message was remotely deleted by you")
            )
        }

        let bodyDescription = self.rawBody(transaction: tx)
        if
            bodyDescription == nil,
            let storyReactionEmoji = storyReactionEmoji?.strippedOrNil,
            let storyAuthorAci = storyAuthorAci?.wrappedAciValue
        {
            let tsAccountManager = DependenciesBridge.shared.tsAccountManager
            let contactManager = SSKEnvironment.shared.contactManagerRef

            if
                let localIdentifiers = tsAccountManager.localIdentifiers(tx: tx),
                localIdentifiers.contains(serviceId: storyAuthorAci)
            {
                return .storyReactionEmoji(String(
                    format: OWSLocalizedString(
                        "STORY_REACTION_LOCAL_AUTHOR_PREVIEW_FORMAT",
                        comment: "inbox and notification text for a reaction to a story authored by the local user. Embeds {{reaction emoji}}"
                    ),
                    storyReactionEmoji
                ))
            } else {
                let storyAuthorName = contactManager.displayName(for: SignalServiceAddress(storyAuthorAci), tx: tx)
                return .storyReactionEmoji(String(
                    format: OWSLocalizedString(
                        "STORY_REACTION_REMOTE_AUTHOR_PREVIEW_FORMAT",
                        comment: "inbox and notification text for a reaction to a story authored by another user. Embeds {{ %1$@ reaction emoji, %2$@ story author name }}"
                    ),
                    storyReactionEmoji,
                    storyAuthorName.resolvedValue(useShortNameIfAvailable: true)
                ))
            }
        }

        let mediaAttachment: ReferencedAttachment?
        if
            let sqliteRowId,
            let attachment = DependenciesBridge.shared.attachmentStore
                .fetchFirstReferencedAttachment(for: .messageBodyAttachment(messageRowId: sqliteRowId), tx: tx)
        {
            mediaAttachment = attachment
        } else {
            mediaAttachment = nil
        }
        let attachmentEmoji = mediaAttachment?.previewEmoji()
        let attachmentDescription = mediaAttachment?.previewText()

        if isViewOnceMessage {
            if self is TSOutgoingMessage || mediaAttachment == nil {
                return .viewOnceMessage(OWSLocalizedString(
                    "PER_MESSAGE_EXPIRATION_NOT_VIEWABLE",
                    comment: "inbox cell and notification text for an already viewed view-once media message."
                ))
            } else if
                let mimeType = mediaAttachment?.attachment.mimeType,
                MimeTypeUtil.isSupportedVideoMimeType(mimeType)
            {
                return .viewOnceMessage(OWSLocalizedString(
                    "PER_MESSAGE_EXPIRATION_VIDEO_PREVIEW",
                    comment: "inbox cell and notification text for a view-once video."
                ))
            } else {
                // Make sure that if we add new types we cover them here.
                return .viewOnceMessage(OWSLocalizedString(
                    "PER_MESSAGE_EXPIRATION_PHOTO_PREVIEW",
                    comment: "inbox cell and notification text for a view-once photo."
                ))
            }
        }

        var pollPrefix: String?
        if isPoll {
            let locPollString = OWSLocalizedString(
                "POLL_PREFIX",
                comment: "Prefix for a poll preview"
            )

            pollPrefix = PollMessageManager.pollEmoji + locPollString + " "
        }

        if let bodyDescription = bodyDescription?.nilIfEmpty {
            let prefix = pollPrefix ?? attachmentEmoji?.nilIfEmpty?.appending(" ")
            return .body(bodyDescription, prefix: prefix, ranges: bodyRanges)
        } else if let attachmentDescription = attachmentDescription?.nilIfEmpty {
            return .body(attachmentDescription, prefix: nil, ranges: bodyRanges)
        } else if let contactShare {
            return .contactShare("👤".appending(" ").appending(contactShare.name.displayName))
        } else if let messageSticker {
            let stickerDescription = OWSLocalizedString(
                "STICKER_MESSAGE_PREVIEW",
                comment: "Preview text shown in notifications and conversation list for sticker messages."
            )
            if let stickerEmoji = StickerManager.firstEmoji(in: messageSticker.emoji ?? "")?.nilIfEmpty {
                return .stickerDescription(stickerEmoji.appending(" ").appending(stickerDescription))
            } else {
                return .stickerDescription(stickerDescription)
            }
        } else if giftBadge != nil {
            return .giftBadge(self.previewTextForGiftBadge(transaction: tx))
        } else {
            // This can happen when initially saving outgoing messages
            // with camera first capture over the conversation list.
            return .empty
        }
    }

    // MARK: - Stories

    @objc
    enum ReplyCountIncrement: Int {
        case noIncrement
        case newReplyAdded
        case replyDeleted
    }

    @objc
    func touchStoryMessageIfNecessary(
        replyCountIncrement: ReplyCountIncrement,
        transaction: DBWriteTransaction
    ) {
        guard
            self.isStoryReply,
            let storyAuthorAci,
            let storyTimestamp
        else {
            return
        }
        let storyMessage = StoryFinder.story(
            timestamp: storyTimestamp.uint64Value,
            author: storyAuthorAci.wrappedAciValue,
            transaction: transaction
        )
        if let storyMessage {
            // Note that changes are aggregated; the touch below won't double
            // up observer notifications.
            SSKEnvironment.shared.databaseStorageRef.touch(storyMessage: storyMessage, tx: transaction)
            switch replyCountIncrement {
            case .noIncrement:
                break
            case .newReplyAdded:
                storyMessage.incrementReplyCount(transaction)
            case .replyDeleted:
                storyMessage.decrementReplyCount(transaction)
            }
        }
    }

    // MARK: - Indexing

    @objc
    internal func _anyDidInsert(tx: DBWriteTransaction) {
        do {
            try FullTextSearchIndexer.insert(self, tx: tx)
        } catch {
            owsFail("Error: \(error)")
        }
    }

    @objc
    internal func _anyDidUpdate(tx: DBWriteTransaction) {
        do {
            try FullTextSearchIndexer.update(self, tx: tx)
        } catch {
            owsFail("Error: \(error)")
        }
    }
}

// MARK: - Renderable content

extension TSMessage {

    /// Unsafe to use before insertion; until attachments are inserted (which happens after message insertion)
    /// this may not return accurate results.
    public func insertedMessageHasRenderableContent(
        rowId: Int64,
        tx: DBReadTransaction
    ) -> Bool {
        var fetchedAttachments: [AttachmentReference]?
        func fetchAttachments() -> [AttachmentReference] {
            if let fetchedAttachments { return fetchedAttachments }
            guard let sqliteRowId else { return [] }
            let attachments = DependenciesBridge.shared.attachmentStore.fetchReferences(
                owners: [
                    .messageOversizeText(messageRowId: sqliteRowId),
                    .messageBodyAttachment(messageRowId: sqliteRowId)
                ],
                tx: tx
            )
            fetchedAttachments = attachments
            return attachments
        }

        var isPaymentMessage = false
        if self is OWSPaymentMessage {
            isPaymentMessage = true
        }

        return TSMessageBuilder.hasRenderableContent(
            hasNonemptyBody: body?.nilIfEmpty != nil,
            hasBodyAttachmentsOrOversizeText: fetchAttachments().isEmpty.negated,
            hasLinkPreview: linkPreview != nil,
            hasQuotedReply: quotedMessage != nil,
            hasContactShare: contactShare != nil,
            hasSticker: messageSticker != nil,
            hasGiftBadge: giftBadge != nil,
            isStoryReply: isStoryReply,
            isPaymentMessage: isPaymentMessage,
            storyReactionEmoji: storyReactionEmoji,
            isPoll: isPoll
        )
    }
}

extension TSMessageBuilder {

    public func hasRenderableContent(
        hasBodyAttachments: Bool,
        hasLinkPreview: Bool,
        hasQuotedReply: Bool,
        hasContactShare: Bool,
        hasSticker: Bool,
        hasPayment: Bool,
        hasPoll: Bool
    ) -> Bool {
        return Self.hasRenderableContent(
            hasNonemptyBody: messageBody?.nilIfEmpty != nil,
            hasBodyAttachmentsOrOversizeText: hasBodyAttachments,
            hasLinkPreview: hasLinkPreview,
            hasQuotedReply: hasQuotedReply,
            hasContactShare: hasContactShare,
            hasSticker: hasSticker,
            hasGiftBadge: giftBadge != nil,
            isStoryReply: storyAuthorAci != nil && storyTimestamp != nil,
            isPaymentMessage: hasPayment,
            storyReactionEmoji: storyReactionEmoji,
            isPoll: hasPoll
        )
    }

    public static func hasRenderableContent(
        hasNonemptyBody: Bool,
        hasBodyAttachmentsOrOversizeText: @autoclosure () -> Bool,
        hasLinkPreview: Bool,
        hasQuotedReply: Bool,
        hasContactShare: Bool,
        hasSticker: Bool,
        hasGiftBadge: Bool,
        isStoryReply: Bool,
        isPaymentMessage: Bool,
        storyReactionEmoji: String?,
        isPoll: Bool
    ) -> Bool {
        if isPaymentMessage {
            // Android doesn't include any body or other content in payments.
            return true
        }

        // Story replies currently only support a subset of message features, so may not
        // be renderable in some circumstances where a normal message would be.
        if isStoryReply {
            return hasNonemptyBody || (storyReactionEmoji?.isSingleEmoji ?? false)
        }

        // We DO NOT consider a message with just a linkPreview
        // or quotedMessage to be renderable.
        if hasNonemptyBody || hasContactShare || hasSticker || hasGiftBadge {
            return true
        }

        if hasBodyAttachmentsOrOversizeText() {
            return true
        }

        if isPoll {
            return true
        }

        return false
    }
}
