//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

final class DisappearingMessagesFinder {
    public func fetchAllMessageUniqueIdsWhichFailedToStartExpiring(tx: DBReadTransaction) -> [String] {
        InteractionFinder.fetchAllMessageUniqueIdsWhichFailedToStartExpiring(transaction: tx)
    }

    /// - Returns:
    /// The next expiration timestamp, or `nil` if there are no upcoming expired messages.
    public func nextExpirationTimestamp(transaction tx: DBReadTransaction) -> UInt64? {
        return InteractionFinder.nextMessageWithStartedPerConversationExpirationToExpire(transaction: tx)?.expiresAt
    }
}
