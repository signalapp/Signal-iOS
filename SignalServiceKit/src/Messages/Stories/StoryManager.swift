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
        // Drop all story messages until the feature is enabled.
        guard FeatureFlags.stories else { return }

        let message = try StoryMessage.create(
            withIncomingStoryMessage: storyMessage,
            timestamp: timestamp,
            author: author,
            transaction: transaction
        )

        // TODO: Optimistic downloading of story attachments.
        attachmentDownloads.enqueueDownloadOfAttachmentsForNewStoryMessage(message, transaction: transaction)

        OWSDisappearingMessagesJob.shared.scheduleRun(byTimestamp: message.timestamp + storyLifetime)

        earlyMessageManager.applyPendingMessages(for: message, transaction: transaction)
    }

    @objc
    public class func deleteExpiredStories(transaction: SDSAnyWriteTransaction) -> UInt {
        var removedCount: UInt = 0
        StoryFinder.enumerateExpiredStories(transaction: transaction) { message, _ in
            Logger.info("Removing StoryMessage \(message.timestamp) which expired at: \(message.timestamp + storyLifetime)")
            message.anyRemove(transaction: transaction)
            removedCount += 1
        }
        return removedCount
    }

    @objc
    public class func nextExpirationTimestamp(transaction: SDSAnyReadTransaction) -> NSNumber? {
        guard let timestamp = StoryFinder.oldestTimestamp(transaction: transaction) else { return nil }
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
