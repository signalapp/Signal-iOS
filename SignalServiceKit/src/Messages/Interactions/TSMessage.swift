//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

public extension TSMessage {
    var reactionFinder: ReactionFinder {
        return ReactionFinder(uniqueMessageId: uniqueId)
    }

    @objc
    func removeAllReactions(transaction: SDSAnyWriteTransaction) {
        reactionFinder.deleteAllReactions(transaction: transaction)
    }

    @objc
    func allReactionIds(transaction: SDSAnyReadTransaction) -> [String]? {
        return reactionFinder.allUniqueIds(transaction: transaction)
    }

    @objc(reactionForReactor:transaction:)
    func reaction(for reactor: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> OWSReaction? {
        return reactionFinder.reaction(for: reactor, transaction: transaction)
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
        databaseStorage.touch(interaction: self, transaction: transaction)

        return reaction
    }

    @objc(removeReactionForReactor:transaction:)
    func removeReaction(for reactor: SignalServiceAddress, transaction: SDSAnyWriteTransaction) {
        Logger.info("")

        guard let reaction = reaction(for: reactor, transaction: transaction) else { return }

        reaction.anyRemove(transaction: transaction)
        databaseStorage.touch(interaction: self, transaction: transaction)
    }

    // MARK: - Remote Delete

    @objc
    class func tryToRemotelyDeleteMessage(
        fromAddress authorAddress: SignalServiceAddress,
        sentAtTimestamp: UInt64,
        threadUniqueId: String,
        serverTimestamp: UInt64,
        transaction: SDSAnyWriteTransaction
    ) -> Bool {
        guard let messageToDelete = InteractionFinder.findMessage(
            withTimestamp: sentAtTimestamp,
            threadId: threadUniqueId,
            author: authorAddress,
            transaction: transaction
        ) else {
            // The message doesn't exist locally, so nothing to do.
            Logger.info("Attempted to remotely delete a message that doesn't exist \(sentAtTimestamp)")
            return false
        }

        guard let incomingMessageToDelete = messageToDelete as? TSIncomingMessage else {
            owsFailDebug("Only incoming messages can be deleted remotely")
            return false
        }

        guard let messageToDeleteServerTimestamp = incomingMessageToDelete.serverTimestamp?.uint64Value else {
            // Older messages might be missing this, but since we only allow deleting for a small
            // window after you send a message we should generally never hit this path.
            owsFailDebug("can't delete a message without a serverTimestamp")
            return false
        }

        guard messageToDeleteServerTimestamp < serverTimestamp else {
            owsFailDebug("Can't delete a message from the future.")
            return false
        }

        guard serverTimestamp - messageToDeleteServerTimestamp < kDayInMs else {
            owsFailDebug("Ignoring message delete sent more than a day after the original message")
            return false
        }

        incomingMessageToDelete.updateWithRemotelyDeletedAndRemoveRenderableContent(with: transaction)

        DispatchQueue.main.async {
            SSKEnvironment.shared.notificationsManager.cancelNotifications(messageId: incomingMessageToDelete.uniqueId)
        }

        return true
    }
}
