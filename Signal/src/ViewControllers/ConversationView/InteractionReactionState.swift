//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

public class InteractionReactionState: NSObject {
    var hasReactions: Bool { return !emojiCounts.isEmpty }

    struct EmojiCount {
        let emoji: String
        let count: Int
        let lastReceivedAtTimestamp: UInt64
    }

    let reactionsByEmoji: [Emoji: [OWSReaction]]
    let emojiCounts: [EmojiCount]
    let localUserEmoji: String?

    init?(interaction: TSInteraction, transaction: SDSAnyReadTransaction) {
        // No reactions on non-message interactions
        guard let message = interaction as? TSMessage else { return nil }

        guard let localAddress = TSAccountManager.shared.localAddress else {
            owsFailDebug("missing local address")
            return nil
        }

        let finder = ReactionFinder(uniqueMessageId: message.uniqueId)
        let allReactions = finder.allReactions(transaction: transaction.unwrapGrdbRead)
        let localUserReaction = allReactions.first(where: { $0.reactor == localAddress })

        reactionsByEmoji = allReactions.reduce(
            into: [Emoji: [OWSReaction]]()
        ) { result, reaction in
            guard let emoji = Emoji(reaction.emoji) else {
                return owsFailDebug("Skipping reaction with [unknown emoji]")
            }

            var reactions = result[emoji] ?? []
            reactions.append(reaction)
            result[emoji] = reactions
        }

        emojiCounts = reactionsByEmoji.values.compactMap { reactions in
            guard let mostRecentReaction = reactions.first else {
                owsFailDebug("unexpectedly missing reactions")
                return nil
            }
            let mostRecentEmoji = mostRecentReaction.emoji

            // We show your own skintone (if you’ve reacted), or the most
            // recent skintone (if you haven’t reacted).
            let emojiToRender: String
            if let localUserReaction = localUserReaction, reactions.contains(localUserReaction) {
                emojiToRender = localUserReaction.emoji
            } else {
                emojiToRender = mostRecentEmoji
            }

            let lastReceivedAtTimestamp = (reactions.map { $0.receivedAtTimestamp }.max()
                                                ?? mostRecentReaction.receivedAtTimestamp)

            return EmojiCount(emoji: emojiToRender,
                              count: reactions.count,
                              lastReceivedAtTimestamp: lastReceivedAtTimestamp)
        }.sorted { (lhs: EmojiCount, rhs: EmojiCount) in
            if lhs.count != rhs.count {
                // Sort more common reactions (higher counter) first.
                return lhs.count > rhs.count
            } else if lhs.lastReceivedAtTimestamp != rhs.lastReceivedAtTimestamp {
                // Sort reactions received in descending order of when we received them.
                return lhs.lastReceivedAtTimestamp > rhs.lastReceivedAtTimestamp
            } else {
                // Ensure stability of sort by comparing emoji.
                return lhs.emoji > rhs.emoji
            }
        }

        localUserEmoji = localUserReaction?.emoji
    }
}
