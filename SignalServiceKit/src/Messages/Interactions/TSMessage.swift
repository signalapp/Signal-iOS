//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public extension TSMessage {

    @objc
    var isIncoming: Bool { self as? TSIncomingMessage != nil }

    @objc
    var isOutgoing: Bool { self as? TSOutgoingMessage != nil }

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

    @objc(reactionForReactor:transaction:)
    func reaction(for reactor: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> OWSReaction? {
        return reactionFinder.reaction(for: reactor, transaction: transaction.unwrapGrdbRead)
    }

    @objc(recordReactionForReactor:emoji:sentAtTimestamp:receivedAtTimestamp:transaction:)
    @discardableResult
    func recordReaction(
        for reactor: SignalServiceAddress,
        emoji: String,
        sentAtTimestamp: UInt64,
        receivedAtTimestamp: UInt64,
        transaction: SDSAnyWriteTransaction
    ) -> OWSReaction? {
        Logger.info("")

        guard !wasRemotelyDeleted else {
            owsFailDebug("attempted to record a reaction for a message that was deleted")
            return nil
        }

        assert(emoji.isSingleEmoji)

        // Remove any previous reaction, there can only be one
        removeReaction(for: reactor, transaction: transaction)

        let reaction = OWSReaction(
            uniqueMessageId: uniqueId,
            emoji: emoji,
            reactor: reactor,
            sentAtTimestamp: sentAtTimestamp,
            receivedAtTimestamp: receivedAtTimestamp
        )

        reaction.anyInsert(transaction: transaction)

        // Reactions to messages we send need to be manually marked
        // as read as they trigger notifications we need to clear
        // out. Everything else can be automatically read.
        if !(self is TSOutgoingMessage) { reaction.markAsRead(transaction: transaction) }

        databaseStorage.touch(interaction: self, shouldReindex: false, transaction: transaction)

        return reaction
    }

    @objc(removeReactionForReactor:transaction:)
    func removeReaction(for reactor: SignalServiceAddress, transaction: SDSAnyWriteTransaction) {
        Logger.info("")

        guard let reaction = reaction(for: reactor, transaction: transaction) else { return }

        reaction.anyRemove(transaction: transaction)
        databaseStorage.touch(interaction: self, shouldReindex: false, transaction: transaction)

        Self.notificationsManager?.cancelNotifications(reactionId: reaction.uniqueId)
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
        if let threadUniqueId = threadUniqueId, let messageToDelete = InteractionFinder.findMessage(
            withTimestamp: sentAtTimestamp,
            threadId: threadUniqueId,
            author: authorAddress,
            transaction: transaction
        ) {
            if messageToDelete is TSOutgoingMessage, authorAddress.isLocalAddress {
                messageToDelete.markMessageAsRemotelyDeleted(transaction: transaction)
                return .success
            } else if let incomingMessageToDelete = messageToDelete as? TSIncomingMessage {
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
        updateWithRemotelyDeletedAndRemoveRenderableContent(with: transaction)

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

}
