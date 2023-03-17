//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class FailedMessagesJob {
    /// Used for logging the total number of messages modified
    private var count: UInt = 0
    public init() {}

    public func runSync(databaseStorage: SDSDatabaseStorage) {
        databaseStorage.write { writeTx in
            InteractionFinder.attemptingOutInteractionIds(transaction: writeTx).forEach { failedInteractionId in
                // Since we can't directly mutate the enumerated "attempting out" expired messages, we store
                // only their ids in hopes of saving a little memory and then enumerate the (larger)
                // TSMessage objects one at a time.
                autoreleasepool {
                    updateFailedMessageIfNecessary(failedInteractionId, transaction: writeTx)
                }
            }

            StoryFinder.enumerateSendingStories(transaction: writeTx) { storyMessage, _ in
                storyMessage.updateWithAllSendingRecipientsMarkedAsFailed(transaction: writeTx)
                self.count += 1
            }
        }
        Logger.info("Finished job. Marked \(count) incomplete sends as failed")
    }

    private func updateFailedMessageIfNecessary(
        _ uniqueId: String,
        transaction writeTx: SDSAnyWriteTransaction
    ) {
        // Preconditions
        guard let message = TSOutgoingMessage.anyFetchOutgoingMessage(uniqueId: uniqueId, transaction: writeTx) else {
            owsFailDebug("Missing interaction with id: \(uniqueId)")
            return
        }
        guard message.messageState == .sending else {
            owsFailDebug("Refusing to mark as unsent message \(message.timestamp) with state: \(message.messageState)")
            return
        }

        // Update
        message.updateWithAllSendingRecipientsMarkedAsFailed(with: writeTx)
        count += 1

        // Log if appropriate
        switch count {
        case ...3:
            Logger.info("marking message as unsent: \(message.uniqueId) \(message.timestamp)")
        case 4:
            Logger.info("eliding logs for further unsent messages. final update count will be reported once complete.")
        default:
            break
        }

        // Postcondition
        owsAssertDebug(message.messageState == .failed)
    }
}
