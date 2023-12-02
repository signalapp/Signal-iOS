//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

extension OWSDisappearingMessagesJob {
    /// Is the database corrupted? If so, we don't want to start the job.
    ///
    /// This is most likely to happen outside the main app, like in an extension, where we might not
    /// check for corruption before marking the app ready.
    @objc
    class func isDatabaseCorrupted() -> Bool {
        return DatabaseCorruptionState(userDefaults: CurrentAppContext().appUserDefaults())
            .status
            .isCorrupted
    }

    private func deleteExpiredMessages() -> Int {
        return databaseStorage.write { tx in
            var expirationCount = 0
            DisappearingMessagesFinder().enumerateExpiredMessages(transaction: tx) { message in
                message.anyRemove(transaction: tx)
                expirationCount += 1
            }
            if expirationCount > 0 {
                Logger.info("Deleted \(expirationCount) expired messages")
            }
            return expirationCount
        }
    }

    private func deleteExpiredStories() -> Int {
        return databaseStorage.write { tx in StoryManager.deleteExpiredStories(transaction: tx) }
    }

    // deletes any expired messages and schedules the next run.
    @objc
    func _runLoop() -> Int {
        let backgroundTask = OWSBackgroundTask(label: #function)
        defer { backgroundTask.end() }

        let deletedCount = deleteExpiredMessages() + deleteExpiredStories()

        let nextExpirationAt = databaseStorage.read { tx in
            return [
                DisappearingMessagesFinder().nextExpirationTimestamp(transaction: tx),
                StoryManager.nextExpirationTimestamp(transaction: tx)
            ].compacted().min()
        }
        if let nextExpirationAt {
            scheduleRun(byTimestamp: nextExpirationAt)
        }

        return deletedCount
    }

    @objc
    func cleanUpMessagesWhichFailedToStartExpiringWithSneakyTransaction() {
        databaseStorage.write { tx in
            let messageIds = DisappearingMessagesFinder().fetchAllMessageUniqueIdsWhichFailedToStartExpiring(tx: tx)
            for messageId in messageIds {
                guard let message = TSMessage.anyFetchMessage(uniqueId: messageId, transaction: tx) else {
                    owsFailDebug("Missing message.")
                    continue
                }
                // We don't know when it was actually read, so assume it was read as soon as it was received.
                let readTimeBestGuess = message.receivedAtTimestamp
                startAnyExpiration(for: message, expirationStartedAt: readTimeBestGuess, transaction: tx)
            }
        }
    }
}
