//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class InteractionReactionState: NSObject {
    @objc
    var hasReactions: Bool { return !emojiCounts.isEmpty }

    let reactionsByEmoji: [Emoji: [OWSReaction]]
    let emojiCounts: [(emoji: String, count: Int)]
    let localUserEmoji: String?

    @objc
    init?(interaction: TSInteraction, transaction: SDSAnyReadTransaction) {
        // No reactions on non-message interactions
        guard let message = interaction as? TSMessage else { return nil }

        guard let localAddress = TSAccountManager.shared().localAddress else {
            owsFailDebug("missing local address")
            return nil
        }

        let finder = ReactionFinder(uniqueMessageId: message.uniqueId)
        let allReactions = finder.allReactions(transaction: transaction.unwrapGrdbRead)
        let localUserReaction = finder.reaction(for: localAddress, transaction: transaction.unwrapGrdbRead)

        reactionsByEmoji = allReactions.reduce(
            into: [Emoji: [OWSReaction]]()
        ) { result, reaction in
            guard let emoji = Emoji(reaction.emoji) else {
                return owsFailDebug("Skipping reaction with unknown emoji \(reaction.emoji)")
            }

            var reactions = result[emoji] ?? []
            reactions.append(reaction)
            result[emoji] = reactions
        }

        emojiCounts = reactionsByEmoji.values.compactMap { reactions in
            guard let mostRecentEmoji = reactions.first?.emoji else {
                owsFailDebug("unexpectedly missing reactions")
                return nil
            }

            // We show your own skintone (if you’ve reacted), or the most
            // recent skintone (if you haven’t reacted).
            let emojiToRender: String
            if let localUserReaction = localUserReaction, reactions.contains(localUserReaction) {
                emojiToRender = localUserReaction.emoji
            } else {
                emojiToRender = mostRecentEmoji
            }

            return (emoji: emojiToRender, count: reactions.count)
        }.sorted { $0.count > $1.count }

        localUserEmoji = localUserReaction?.emoji
    }
}
