//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
public class DisappearingMessagesFinder: NSObject {
    @objc(enumerateExpiredMessagesWithTransaction:block:)
    public func enumerateExpiredMessages(transaction: SDSAnyReadTransaction, block: (TSMessage) -> Void) {
        // Since we can't directly mutate the enumerated expired messages, we store only their ids
        // in hopes of saving a little memory and then enumerate the (larger) TSMessage objects one
        // at a time.
        let expiredMessageIds = InteractionFinder.interactionIdsWithExpiredPerConversationExpiration(
            transaction: transaction
        )
        for expiredMessageId in expiredMessageIds {
            guard
                let message = TSMessage.anyFetchMessage(
                    uniqueId: expiredMessageId,
                    transaction: transaction
                )
            else {
                owsFailDebug("Missing interaction")
                continue
            }
            block(message)
        }
    }

    @objc
    public func fetchAllMessageUniqueIdsWhichFailedToStartExpiring(
        transaction: SDSAnyReadTransaction
    ) -> [String] {
        InteractionFinder.fetchAllMessageUniqueIdsWhichFailedToStartExpiring(
            transaction: transaction
        )
    }

    /// - Returns:
    /// The next expiration timestamp, or `nil` if there are no upcoming expired messages.
    public func nextExpirationTimestamp(transaction: SDSAnyReadTransaction) -> UInt64? {
        guard
            let message = InteractionFinder.nextMessageWithStartedPerConversationExpirationToExpire(
                transaction: transaction
            ),
            message.expiresAt > 0
        else {
            return nil
        }
        return message.expiresAt
    }

    /// - Returns:
    /// The next expiration timestamp, or `nil` if there are no upcoming expired messages.
    @objc(nextExpirationTimestampWithTransaction:)
    public func nextExpirationTimestampObjc(transaction: SDSAnyReadTransaction) -> NSNumber? {
        guard let result = nextExpirationTimestamp(transaction: transaction) else {
            return nil
        }
        return NSNumber(value: result)
    }

    #if DEBUG

    /// Don't use this in production because we don't want to instantiate potentially many messages
    /// at once. Useful for testing.
    func fetchExpiredMessages(transaction: SDSAnyReadTransaction) -> [TSMessage] {
        var result = [TSMessage]()
        enumerateExpiredMessages(transaction: transaction) { result.append($0) }
        return result
    }

    /// Don't use this in production because we don't want to instantiate potentially many messages
    /// at once. Useful for testing.
    func fetchUnstartedExpiringMessages(
        in thread: TSThread,
        transaction: SDSAnyReadTransaction
    ) -> [TSMessage] {
        var result = [TSMessage]()
        let finder = InteractionFinder(threadUniqueId: thread.uniqueId)
        finder.enumerateUnstartedExpiringMessages(transaction: transaction) { message, _ in
            result.append(message)
        }
        return result
    }

    #endif
}
