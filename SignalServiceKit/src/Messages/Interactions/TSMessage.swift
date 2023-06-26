//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

public extension TSMessage {

    @objc
    var isIncoming: Bool { self as? TSIncomingMessage != nil }

    @objc
    var isOutgoing: Bool { self as? TSOutgoingMessage != nil }

    // MARK: - Any Transaction Hooks

    // Override anyWillRemove to ensure any associated edits are deleted before
    // removing the interaction
    override func anyWillRemove(with transaction: SDSAnyWriteTransaction) {
        removeEdits(transaction: transaction)
        super.anyWillRemove(with: transaction)
    }

    // MARK: - Attachments

    func failedAttachments(transaction: SDSAnyReadTransaction) -> [TSAttachmentPointer] {
        let attachments: [TSAttachment] = allAttachments(with: transaction.unwrapGrdbRead)
        let states: [TSAttachmentPointerState] = [.failed]
        return Self.onlyAttachmentPointers(attachments: attachments, withStateIn: Set(states))
    }

    func failedOrPendingAttachments(transaction: SDSAnyReadTransaction) -> [TSAttachmentPointer] {
        let attachments: [TSAttachment] = allAttachments(with: transaction.unwrapGrdbRead)
        let states: [TSAttachmentPointerState] = [.failed, .pendingMessageRequest, .pendingManualDownload]
        return Self.onlyAttachmentPointers(attachments: attachments, withStateIn: Set(states))
    }

    func failedBodyAttachments(transaction: SDSAnyReadTransaction) -> [TSAttachmentPointer] {
        let attachments: [TSAttachment] = bodyAttachments(with: transaction.unwrapGrdbRead)
        let states: [TSAttachmentPointerState] = [.failed]
        return Self.onlyAttachmentPointers(attachments: attachments, withStateIn: Set(states))
    }

    func pendingBodyAttachments(transaction: SDSAnyReadTransaction) -> [TSAttachmentPointer] {
        let attachments: [TSAttachment] = bodyAttachments(with: transaction.unwrapGrdbRead)
        let states: [TSAttachmentPointerState] = [.pendingMessageRequest, .pendingManualDownload]
        return Self.onlyAttachmentPointers(attachments: attachments, withStateIn: Set(states))
    }

    private static func onlyAttachmentPointers(attachments: [TSAttachment],
                                               withStateIn states: Set<TSAttachmentPointerState>) -> [TSAttachmentPointer] {
        return attachments.compactMap { attachment -> TSAttachmentPointer? in
            guard let attachmentPointer = attachment as? TSAttachmentPointer else {
                return nil
            }
            guard states.contains(attachmentPointer.state) else {
                return nil
            }
            return attachmentPointer
        }
    }

    // MARK: - Reactions

    var reactionFinder: ReactionFinder {
        return ReactionFinder(uniqueMessageId: uniqueId)
    }

    @objc
    func removeAllReactions(transaction: SDSAnyWriteTransaction) {
        guard !CurrentAppContext().isRunningTests else { return }
        reactionFinder.deleteAllReactions(transaction: transaction.unwrapGrdbWrite)
    }

    @objc
    func allReactionIds(transaction: SDSAnyReadTransaction) -> [String]? {
        return reactionFinder.allUniqueIds(transaction: transaction.unwrapGrdbRead)
    }

    @objc
    func markUnreadReactionsAsRead(transaction: SDSAnyWriteTransaction) {
        let unreadReactions = reactionFinder.unreadReactions(transaction: transaction.unwrapGrdbWrite)
        unreadReactions.forEach { $0.markAsRead(transaction: transaction) }
    }

    @objc(reactionFor:tx:)
    func reaction(for reactor: ServiceIdObjC, tx: SDSAnyReadTransaction) -> OWSReaction? {
        return reactionFinder.reaction(for: reactor.wrappedValue, tx: tx.unwrapGrdbRead)
    }

    @objc(recordReactionFor:emoji:sentAtTimestamp:receivedAtTimestamp:tx:)
    @discardableResult
    func recordReaction(
        for reactor: ServiceIdObjC,
        emoji: String,
        sentAtTimestamp: UInt64,
        receivedAtTimestamp: UInt64,
        tx: SDSAnyWriteTransaction
    ) -> OWSReaction? {
        Logger.info("")

        guard !wasRemotelyDeleted else {
            owsFailDebug("attempted to record a reaction for a message that was deleted")
            return nil
        }

        assert(emoji.isSingleEmoji)

        // Remove any previous reaction, there can only be one
        removeReaction(for: reactor, tx: tx)

        let reaction = OWSReaction(
            uniqueMessageId: uniqueId,
            emoji: emoji,
            reactor: SignalServiceAddress(reactor.wrappedValue),
            sentAtTimestamp: sentAtTimestamp,
            receivedAtTimestamp: receivedAtTimestamp
        )

        reaction.anyInsert(transaction: tx)

        // Reactions to messages we send need to be manually marked
        // as read as they trigger notifications we need to clear
        // out. Everything else can be automatically read.
        if !(self is TSOutgoingMessage) { reaction.markAsRead(transaction: tx) }

        databaseStorage.touch(interaction: self, shouldReindex: false, transaction: tx)

        return reaction
    }

    @objc(removeReactionFor:tx:)
    func removeReaction(for reactor: ServiceIdObjC, tx: SDSAnyWriteTransaction) {
        Logger.info("")

        guard let reaction = reaction(for: reactor, tx: tx) else { return }

        reaction.anyRemove(transaction: tx)
        databaseStorage.touch(interaction: self, shouldReindex: false, transaction: tx)

        Self.notificationsManager?.cancelNotifications(reactionId: reaction.uniqueId)
    }

    // MARK: - Edits

    @objc
    func removeEdits(transaction: SDSAnyWriteTransaction) {
        try! processEdits(transaction: transaction) { record, message in
            try record.delete(transaction.unwrapGrdbWrite.database)
            message?.anyRemove(transaction: transaction)
        }
    }

    /// Build a list of all related edits based on this message.  An array of record, message pairs are
    /// returned, allowing the caller to operate on one or both of these items at the same time.
    ///
    /// The processing of edit records is unbounded, but the number of edits per message
    /// is limited by both the sender and receiver.
    private func processEdits(
        transaction: SDSAnyWriteTransaction,
        block: ((EditRecord, TSMessage?) throws -> Void)
    ) throws {
        let editsToProcess = try EditMessageFinder.findEditDeleteRecords(
            for: self,
            transaction: transaction
        )
        for edit in editsToProcess {
            try block(edit.0, edit.1)
        }
    }

    // MARK: - Remote Delete

    // A message can be remotely deleted iff:
    //  * you sent this message
    //  * you haven't already remotely deleted this message
    //  * it's not a message with a gift badge
    //  * it has been less than 3 hours since you sent the message
    //    * this includes messages sent in the future
    var canBeRemotelyDeleted: Bool {
        guard let outgoingMessage = self as? TSOutgoingMessage else { return false }
        guard !outgoingMessage.wasRemotelyDeleted else { return false }
        guard outgoingMessage.giftBadge == nil else { return false }

        let (elapsedTime, isInFuture) = Date.ows_millisecondTimestamp().subtractingReportingOverflow(outgoingMessage.timestamp)
        guard isInFuture || (elapsedTime <= (kHourInMs * 3)) else { return false }

        return true
    }

    @objc(OWSRemoteDeleteProcessingResult)
    enum RemoteDeleteProcessingResult: Int, Error {
        case deletedMessageMissing
        case invalidDelete
        case success
    }

    @objc
    class func tryToRemotelyDeleteMessage(
        fromAddress authorAddress: SignalServiceAddress,
        sentAtTimestamp: UInt64,
        threadUniqueId: String?,
        serverTimestamp: UInt64,
        transaction: SDSAnyWriteTransaction
    ) -> RemoteDeleteProcessingResult {
        guard SDS.fitsInInt64(sentAtTimestamp) else {
            owsFailDebug("Unable to delete a message with invalid sentAtTimestamp: \(sentAtTimestamp)")
            return .invalidDelete
        }

        if let threadUniqueId = threadUniqueId, let messageToDelete = InteractionFinder.findMessage(
            withTimestamp: sentAtTimestamp,
            threadId: threadUniqueId,
            author: authorAddress,
            transaction: transaction
        ) {
            if messageToDelete is TSOutgoingMessage, authorAddress.isLocalAddress {
                messageToDelete.markMessageAsRemotelyDeleted(transaction: transaction)
                return .success
            } else if var incomingMessageToDelete = messageToDelete as? TSIncomingMessage {
                if incomingMessageToDelete.editState == .pastRevision {
                    // The remote delete targeted an old revision, fetch
                    // swap out the target message for the latest (or return an error)
                    // This avoids cases where older edits could be deleted and
                    // leave newer revisions
                    if let latestEdit = EditMessageFinder.findMessage(
                        fromEdit: incomingMessageToDelete,
                        transaction: transaction) as? TSIncomingMessage {
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

                guard serverTimestamp - messageToDeleteServerTimestamp < kDayInMs else {
                    owsFailDebug("Ignoring message delete sent more than a day after the original message")
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
            author: authorAddress,
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

    private func markMessageAsRemotelyDeleted(transaction: SDSAnyWriteTransaction) {

        // Delete the current interaction
        updateWithRemotelyDeletedAndRemoveRenderableContent(with: transaction)

        // Delete any past edit revisions.
        try! processEdits(transaction: transaction) { record, message in
            message?.updateWithRemotelyDeletedAndRemoveRenderableContent(with: transaction)
        }
        Self.notificationsManager?.cancelNotifications(messageIds: [self.uniqueId])
    }

    // MARK: - Preview text

    @objc(previewTextForGiftBadgeWithTransaction:)
    func previewTextForGiftBadge(transaction: SDSAnyReadTransaction) -> String {
        if let incomingMessage = self as? TSIncomingMessage {
            let senderShortName = contactsManager.shortDisplayName(
                for: incomingMessage.authorAddress, transaction: transaction
            )
            let format = OWSLocalizedString(
                "DONATION_ON_BEHALF_OF_A_FRIEND_PREVIEW_INCOMING",
                comment: "A friend has donated on your behalf. This text is shown in the list of chats, when the most recent message is one of these donations. Embeds {friend's short display name}."
            )
            return String(format: format, senderShortName)
        } else if let outgoingMessage = self as? TSOutgoingMessage {
            let recipientShortName: String
            let recipients = outgoingMessage.recipientAddresses()
            if let recipient = recipients.first, recipients.count == 1 {
                recipientShortName = contactsManager.shortDisplayName(
                    for: recipient, transaction: transaction
                )
            } else {
                owsFailDebug("[Gifting] Expected exactly 1 recipient but got \(recipients.count)")
                recipientShortName = OWSLocalizedString(
                    "UNKNOWN_USER",
                    comment: "Label indicating an unknown user."
                )
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

    func notificationPreviewText(_ tx: SDSAnyReadTransaction) -> String {
        switch previewText(tx) {
        case let .body(body, prefix, ranges):
            let hydrated = MessageBody(text: body, ranges: ranges ?? .empty)
                .hydrating(mentionHydrator: ContactsMentionHydrator.mentionHydrator(transaction: tx.asV2Read))
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
            let .infoMessage(text):
            return text
        case .empty:
            return ""
        }
    }

    func conversationListPreviewText(_ tx: SDSAnyReadTransaction) -> HydratedMessageBody {
        switch previewText(tx) {
        case let .body(body, prefix, ranges):
            let hydrated = MessageBody(text: body, ranges: ranges ?? .empty)
                .hydrating(mentionHydrator: ContactsMentionHydrator.mentionHydrator(transaction: tx.asV2Read))
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
            let .infoMessage(text):
            return HydratedMessageBody.fromPlaintextWithoutRanges(text)
        case .empty:
            return HydratedMessageBody.fromPlaintextWithoutRanges("")
        }
    }

    func conversationListSearchResultsBody(_ tx: SDSAnyReadTransaction) -> MessageBody? {
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
        case empty
    }

    private func previewText(_ tx: SDSAnyReadTransaction) -> PreviewText {
        if let infoMessage = self as? TSInfoMessage {
            return .infoMessage(infoMessage.infoMessagePreviewText(with: tx))
        }

        if self.wasRemotelyDeleted {
            return .remotelyDeleted((self is TSIncomingMessage)
                ? OWSLocalizedString("THIS_MESSAGE_WAS_DELETED", comment: "text indicating the message was remotely deleted")
                : OWSLocalizedString("YOU_DELETED_THIS_MESSAGE", comment: "text indicating the message was remotely deleted by you")
            )
        }

        let bodyDescription = self.rawBody(with: tx.unwrapGrdbRead)
        if
            bodyDescription == nil,
            let storyReactionEmoji,
            storyReactionEmoji.isEmpty.negated
        {
            if let storyAuthorAddress, storyAuthorAddress.isLocalAddress.negated {
                let storyAuthorName = self.contactsManager.shortDisplayName(for: storyAuthorAddress, transaction: tx)
                return .storyReactionEmoji(String(
                    format: OWSLocalizedString(
                        "STORY_REACTION_REMOTE_AUTHOR_PREVIEW_FORMAT",
                        comment: "inbox and notification text for a reaction to a story authored by another user. Embeds {{ %1$@ reaction emoji, %2$@ story author name }}"
                    ),
                    storyReactionEmoji,
                    storyAuthorName
                ))
            } else {
                return .storyReactionEmoji(String(
                    format: OWSLocalizedString(
                        "STORY_REACTION_LOCAL_AUTHOR_PREVIEW_FORMAT",
                        comment: "inbox and notification text for a reaction to a story authored by the local user. Embeds {{reaction emoji}}"
                    ),
                    storyReactionEmoji
                ))
            }
        }

        let mediaAttachment = self.mediaAttachments(with: tx.unwrapGrdbRead).first
        let attachmentEmoji = mediaAttachment?.emoji
        let attachmentDescription = mediaAttachment?.description()

        if isViewOnceMessage {
            if self is TSOutgoingMessage || mediaAttachment == nil {
                return .viewOnceMessage(OWSLocalizedString(
                    "PER_MESSAGE_EXPIRATION_NOT_VIEWABLE",
                    comment: "inbox cell and notification text for an already viewed view-once media message."
                ))
            } else if mediaAttachment?.isVideo == true {
                return .viewOnceMessage(OWSLocalizedString(
                    "PER_MESSAGE_EXPIRATION_VIDEO_PREVIEW",
                    comment: "inbox cell and notification text for a view-once video."
                ))
            } else {
                // Make sure that if we add new types we cover them here.
                owsAssertDebug(
                    mediaAttachment?.isImage == true
                    || mediaAttachment?.isLoopingVideo == true
                    || mediaAttachment?.isAnimated == true
                )
                return .viewOnceMessage(OWSLocalizedString(
                    "PER_MESSAGE_EXPIRATION_PHOTO_PREVIEW",
                    comment: "inbox cell and notification text for a view-once photo."
                ))
            }
        }

        if let bodyDescription = bodyDescription?.nilIfEmpty {
            return .body(bodyDescription, prefix: attachmentEmoji?.nilIfEmpty?.appending(" "), ranges: bodyRanges)
        } else if let attachmentDescription = attachmentDescription?.nilIfEmpty {
            return .body(attachmentDescription, prefix: nil, ranges: bodyRanges)
        } else if let contactShare {
            return .contactShare("👤".appending(" ").appending(contactShare.name.displayName))
        } else if let messageSticker {
            let stickerDescription = OWSLocalizedString(
                "STICKER_MESSAGE_PREVIEW",
                comment: "Preview text shown in notifications and conversation list for sticker messages."
            )
            if let stickerEmoji = StickerManager.firstEmoji(inEmojiString: messageSticker.emoji)?.nilIfEmpty {
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
        transaction: SDSAnyWriteTransaction
    ) {
        guard
            self.isStoryReply,
            let storyAuthorAddress,
            let storyTimestamp
        else {
            return
        }
        let storyMessage = StoryFinder.story(
            timestamp: storyTimestamp.uint64Value,
            author: storyAuthorAddress,
            transaction: transaction
        )
        if let storyMessage {
            // Note that changes are aggregated; the touch below won't double
            // up observer notifications.
            self.databaseStorage.touch(storyMessage: storyMessage, transaction: transaction)
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
}
