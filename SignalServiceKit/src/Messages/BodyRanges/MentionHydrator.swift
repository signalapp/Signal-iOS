//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum MentionHydrationOption {
    /// Do not hydrate the mention; this leaves the string as it was in the original,
    /// which we want to do e.g. when forwarding a message with mentions from one
    /// thread context to another, where we hydrate the mentions of members not in
    /// the destination, but preserve mentions of shared members fully intact.
    case preserveMention
    /// Replace the mention range with the populated display name.
    case hydrate(String)
}

public typealias MentionHydrator = (UUID) -> MentionHydrationOption

public class ContactsMentionHydrator {

    public static func mentionHydrator(
        excludedUuids: Set<UUID>? = nil,
        transaction: DBReadTransaction
    ) -> MentionHydrator {
        return { mentionUuid in
            if excludedUuids?.contains(mentionUuid) == true {
                return .preserveMention
            }
            return .hydrate(
                Self.hydrateMention(with: mentionUuid, transaction: transaction).1
            )
        }
    }

    public static func hydrateMention(
        with mentionUuid: UUID,
        transaction: DBReadTransaction
    ) -> (SignalServiceAddress, String) {
        let address = SignalServiceAddress(uuid: mentionUuid)
        let displayName = GlobalDependencies.contactsManager.displayName(
            for: address,
            transaction: SDSDB.shimOnlyBridge(transaction)
        )
        return (address, displayName)
    }

    private class GlobalDependencies: Dependencies {}
}
