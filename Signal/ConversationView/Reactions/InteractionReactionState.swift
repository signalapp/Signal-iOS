//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

final class InteractionReactionState: Equatable {
    struct EmojiCount {
        let emoji: Emoji
        let emojiVariant: String
        let count: Int
    }

    let reactions: [ReactionRecord]
    let emojiReactions: [Emoji: [ReactionRecord]]
    let emojiCounts: [EmojiCount]
    let localUserEmojiVariant: String?

    init?(interaction: TSInteraction, tx: DBReadTransaction) {
        // No reactions on non-message interactions
        guard let message = interaction as? TSMessage else {
            return nil
        }
        let messageId = message.sqliteRowId.owsFailUnwrap("must exist")

        let recipientStore = DependenciesBridge.shared.recipientDatabaseTable
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        guard
            let localIdentifiers = tsAccountManager.localIdentifiers(tx: tx),
            let localRecipient = recipientStore.fetchRecipient(serviceId: localIdentifiers.aci, transaction: tx)
        else {
            owsFailDebug("missing local identifiers")
            return nil
        }

        let finder = ReactionFinder(messageId: messageId)
        let sortedReactions = finder.allReactions(tx: tx)
        let localUserReaction = sortedReactions.first(where: { $0.reactorId == localRecipient.id })
        let localUserEmojiVariant = localUserReaction?.emoji
        let localUserEmoji = localUserEmojiVariant.flatMap { Emoji($0) }

        var emojiReactions = [Emoji: [ReactionRecord]]()
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
            let reactionVariant: ReactionRecord
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

    static func ==(lhs: InteractionReactionState, rhs: InteractionReactionState) -> Bool {
        return lhs === rhs
    }
}
