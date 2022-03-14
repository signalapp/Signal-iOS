//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class StoryManager: NSObject {
    public static let storyLifetime = kDayInMs

    @objc
    public class func processIncomingStoryMessage(
        _ storyMessage: SSKProtoStoryMessage,
        timestamp: UInt64,
        author: SignalServiceAddress,
        transaction: SDSAnyWriteTransaction
    ) throws {
        let record = try StoryMessageRecord.create(
            withIncomingStoryMessage: storyMessage,
            timestamp: timestamp,
            author: author,
            transaction: transaction
        )

        // TODO: Optimistic downloading of story attachments.
        attachmentDownloads.enqueueDownloadOfAttachmentsForNewStoryMessage(record, transaction: transaction)

        OWSDisappearingMessagesJob.shared.scheduleRun(byTimestamp: record.timestamp + storyLifetime)

        earlyMessageManager.applyPendingMessages(for: record, transaction: transaction)
    }

    @objc
    public class func deleteExpiredStories(transaction: SDSAnyWriteTransaction) -> UInt {
        var removedCount: UInt = 0
        StoryFinder.enumerateExpiredStories(transaction: transaction.unwrapGrdbRead) { record, _ in
            Logger.info("Removing StoryMessage \(record.timestamp) which expired at: \(record.timestamp + storyLifetime)")
            do {
                try record.delete(transaction.unwrapGrdbWrite.database)
                removedCount += 1
            } catch {
                owsFailDebug("Failed to remove expired story with timestamp \(record.timestamp) \(error)")
            }
        }
        return removedCount
    }

    @objc
    public class func nextExpirationTimestamp(transaction: SDSAnyReadTransaction) -> NSNumber? {
        guard let timestamp = StoryFinder.oldestTimestamp(transaction: transaction.unwrapGrdbRead) else { return nil }
        return NSNumber(value: timestamp + storyLifetime)
    }
}

public enum StoryContext: Equatable, Hashable {
    case groupId(Data)
    case authorUuid(UUID)
    case none
}

public extension TSThread {
    var storyContext: StoryContext {
        if let groupThread = self as? TSGroupThread {
            return .groupId(groupThread.groupId)
        } else if let contactThread = self as? TSContactThread, let authorUuid = contactThread.contactAddress.uuid {
            return .authorUuid(authorUuid)
        } else {
            return .none
        }
    }
}
