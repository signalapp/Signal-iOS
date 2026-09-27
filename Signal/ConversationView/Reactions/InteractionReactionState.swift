//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

public final class InteractionReactionState: Equatable {
    struct EmojiCount {
        let emoji: Emoji
        let emojiVariant: String
        let count: Int
    }

    let reactions: [OWSReaction]
    let emojiReactions: [Emoji: [OWSReaction]]
    let emojiCounts: [EmojiCount]
    let localUserEmojiVariant: String?

    init?(interaction: TSInteraction, tx: DBReadTransaction) {
        // No reactions on non-message interactions
        guard let message = interaction as? TSMessage else {
            return nil
        }

        guard let localAddress = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx)?.aciAddress else {
            owsFailDebug("missing local address")
            return nil
        }

        let finder = ReactionFinder(uniqueMessageId: message.uniqueId)
        let sortedReactions = finder.allReactions(transaction: tx)
        let localUserReaction = sortedReactions.first(where: { $0.reactor == localAddress })
        let localUserEmojiVariant = localUserReaction?.emoji
        let localUserEmoji = localUserEmojiVariant.flatMap { Emoji($0) }

        var emojiReactions = [Emoji: [OWSReaction]]()
        // These are "partially ordered" because they are sorted in reverse
        // chronological order, but they are not sorted by frequency.
        var partiallyOrderedEmojis = [Emoji]()
        for reaction in sortedReactions {
            guard let emoji = Emoji(reaction.emoji) else {
                continue
            }
            if emojiReactions[emoji] == nil {
                partiallyOrderedEmojis.append(emoji)
            }
            emojiReactions[emoji, default: []].append(reaction)
        }
        // Sort them by frequency using a stable sort so that ties are resolved
        // using the reverse chronological order established above.
        partiallyOrderedEmojis.sort(by: {
            return emojiReactions[$0]!.count > emojiReactions[$1]!.count
        })

        let sortedEmojiCounts = partiallyOrderedEmojis.map {
            let reactions = emojiReactions[$0].owsFailUnwrap("must exist")
            let reactionVariant: OWSReaction
            if $0 == localUserEmoji {
                reactionVariant = localUserReaction.owsFailUnwrap("must exist when localUserEmoji does")
            } else {
                reactionVariant = reactions.first.owsFailUnwrap("does not exist unless non-empty")
            }
            return EmojiCount(
                emoji: $0,
                emojiVariant: reactionVariant.emoji,
                count: reactions.count,
            )
        }

        guard !sortedEmojiCounts.isEmpty else {
            return nil
        }

        self.reactions = sortedReactions
        self.emojiReactions = emojiReactions
        self.emojiCounts = sortedEmojiCounts
        self.localUserEmojiVariant = localUserEmojiVariant
    }

    public static func ==(lhs: InteractionReactionState, rhs: InteractionReactionState) -> Bool {
        return lhs === rhs
    }
}
