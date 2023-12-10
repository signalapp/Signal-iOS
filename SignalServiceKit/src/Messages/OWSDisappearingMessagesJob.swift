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

    private enum Constants {
        static let fetchCount = 50
    }

    private func deleteAllExpiredMessages() throws -> Int {
        let db = DependenciesBridge.shared.db
        let count = try TimeGatedBatch.processAll(db: db) { tx in try deleteSomeExpiredMessages(tx: tx) }
        if count > 0 { Logger.info("Deleted \(count) expired messages") }
        return count
    }

    private func deleteSomeExpiredMessages(tx: DBWriteTransaction) throws -> Int {
        let tx = SDSDB.shimOnlyBridge(tx)
        let now = Date.ows_millisecondTimestamp()
        let rowIds = try InteractionFinder.fetchSomeExpiredMessageRowIds(now: now, limit: Constants.fetchCount, tx: tx)
        for rowId in rowIds {
            guard let message = InteractionFinder.fetch(rowId: rowId, transaction: tx) else {
                // We likely hit a database error that's not exposed to us. It's important
                // that we stop in this case to avoid infinite loops.
                throw OWSAssertionError("Couldn't fetch message that must exist.")
            }
            message.anyRemove(transaction: tx)
        }
        return rowIds.count
    }

    private func deleteAllExpiredStories() throws -> Int {
        let db = DependenciesBridge.shared.db
        let count = try TimeGatedBatch.processAll(db: db) { tx in try deleteSomeExpiredStories(tx: tx) }
        if count > 0 { Logger.info("Deleted \(count) expired stories") }
        return count
    }

    private func deleteSomeExpiredStories(tx: DBWriteTransaction) throws -> Int {
        let tx = SDSDB.shimOnlyBridge(tx)
        let now = Date.ows_millisecondTimestamp()
        let storyMessages = try StoryFinder.fetchSomeExpiredStories(now: now, limit: Constants.fetchCount, tx: tx)
        for storyMessage in storyMessages {
            storyMessage.anyRemove(transaction: tx)
        }
        return storyMessages.count
    }

    // deletes any expired messages and schedules the next run.
    @objc
    func _runLoop() -> Int {
        let backgroundTask = OWSBackgroundTask(label: #function)
        defer { backgroundTask.end() }

        var deletedCount = 0
        do {
            deletedCount += try deleteAllExpiredMessages()
            deletedCount += try deleteAllExpiredStories()
        } catch {
            owsFailDebug("Couldn't delete expired messages/stories: \(error)")
        }

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
