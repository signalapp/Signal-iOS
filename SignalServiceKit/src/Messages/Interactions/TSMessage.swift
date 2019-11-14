//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

public extension TSMessage {
    var reactionFinder: ReactionFinder {
        return ReactionFinder(uniqueMessageId: uniqueId)
    }

    @objc
    func removeAllReactions(transaction: SDSAnyWriteTransaction) throws {
        try reactionFinder.deleteAllReactions(transaction: transaction)
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
    ) -> OWSReaction {

        Logger.info("")

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
}
