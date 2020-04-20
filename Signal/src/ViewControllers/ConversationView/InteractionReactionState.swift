//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
class InteractionReactionState: NSObject {
    @objc
    var hasReactions: Bool { return !emojiCounts.isEmpty }

    let emojiCounts: [(emoji: String, count: Int)]
    let localUserEmoji: String?

    @objc
    init?(interaction: TSInteraction, transaction: SDSAnyReadTransaction) {
        // No reactions on non-message interactions
        guard let message = interaction as? TSMessage else { return nil }

        guard let localAddress = TSAccountManager.sharedInstance().localAddress else {
            owsFailDebug("missing local address")
            return nil
        }

        let finder = ReactionFinder(uniqueMessageId: message.uniqueId)
        emojiCounts = finder.emojiCounts(transaction: transaction.unwrapGrdbRead)
        localUserEmoji = finder.reaction(for: localAddress, transaction: transaction.unwrapGrdbRead)?.emoji
    }
}
