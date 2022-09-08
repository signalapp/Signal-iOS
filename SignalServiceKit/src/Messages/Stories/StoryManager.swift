//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class StoryManager: NSObject {
    public static let storyLifetimeMillis = kDayInMs

    @objc
    public class func setup() {
        AppReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            // Create My Story thread if necessary
            Self.databaseStorage.asyncWrite { transaction in
                TSPrivateStoryThread.getOrCreateMyStory(transaction: transaction)
                if CurrentAppContext().isMainApp {
                    TSPrivateStoryThread.cleanupDeletedTimestamps(transaction: transaction)
                }
            }
        }
    }

    @objc
    public class func processIncomingStoryMessage(
        _ storyMessage: SSKProtoStoryMessage,
        timestamp: UInt64,
        author: SignalServiceAddress,
        transaction: SDSAnyWriteTransaction
    ) throws {
        // Drop all story messages until the feature is enabled.
        guard RemoteConfig.stories else { return }

        guard StoryFinder.story(
            timestamp: timestamp,
            author: author,
            transaction: transaction
        ) == nil else {
            owsFailDebug("Dropping story message with duplicate timestamp \(timestamp) from author \(author)")
            return
        }

        guard let thread: TSThread = {
            if let masterKey = storyMessage.group?.masterKey,
                let contextInfo = try? groupsV2.groupV2ContextInfo(forMasterKeyData: masterKey) {
                return TSGroupThread.fetch(groupId: contextInfo.groupId, transaction: transaction)
            } else {
                return TSContactThread.getWithContactAddress(author, transaction: transaction)
            }
        }(), !thread.hasPendingMessageRequest(transaction: transaction.unwrapGrdbRead) else {
            Logger.warn("Dropping story message with timestamp \(timestamp) from author \(author) with pending message request.")
            return
        }

        guard let message = try StoryMessage.create(
            withIncomingStoryMessage: storyMessage,
            timestamp: timestamp,
            author: author,
            transaction: transaction
        ) else { return }

        startAutomaticDownloadIfNecessary(for: message, transaction: transaction)

        OWSDisappearingMessagesJob.shared.scheduleRun(byTimestamp: message.timestamp + storyLifetimeMillis)

        earlyMessageManager.applyPendingMessages(for: message, transaction: transaction)
    }

    @objc
    public class func processStoryMessageTranscript(
        _ proto: SSKProtoSyncMessageSent,
        transaction: SDSAnyWriteTransaction
    ) throws {
        // Drop all story messages until the feature is enabled.
        guard RemoteConfig.stories else { return }

        let existingStory = StoryFinder.story(
            timestamp: proto.timestamp,
            author: tsAccountManager.localAddress!,
            transaction: transaction
        )

        if proto.isRecipientUpdate {
            if let existingStory = existingStory {
                existingStory.updateRecipients(proto.storyMessageRecipients, transaction: transaction)

                // If there are no recipients remaining for a private story, delete the story model
                if existingStory.groupId == nil,
                   case .outgoing(let recipientStates) = existingStory.manifest,
                   recipientStates.values.flatMap({ $0.contexts }).isEmpty {
                    Logger.info("Deleting story with timestamp \(existingStory.timestamp) with no remaining contexts")
                    existingStory.anyRemove(transaction: transaction)
                }
            } else {
                owsFailDebug("Missing existing story for recipient update with timestamp \(proto.timestamp)")
            }
        } else if existingStory == nil {
            let message = try StoryMessage.create(withSentTranscript: proto, transaction: transaction)

            attachmentDownloads.enqueueDownloadOfAttachmentsForNewStoryMessage(message, transaction: transaction)

            OWSDisappearingMessagesJob.shared.scheduleRun(byTimestamp: message.timestamp + storyLifetimeMillis)

            earlyMessageManager.applyPendingMessages(for: message, transaction: transaction)
        } else {
            owsFailDebug("Ignoring sync transcript for story with timestamp \(proto.timestamp)")
        }
    }

    @objc
    public class func deleteExpiredStories(transaction: SDSAnyWriteTransaction) -> UInt {
        var removedCount: UInt = 0
        StoryFinder.enumerateExpiredStories(transaction: transaction) { message, _ in
            guard !message.authorAddress.isSystemStoryAddress else {
                // We do not auto-expire system stories, they remain until viewed.
                return
            }
            Logger.info("Removing StoryMessage \(message.timestamp) which expired at: \(message.timestamp + storyLifetimeMillis)")
            message.anyRemove(transaction: transaction)
            removedCount += 1
        }
        return removedCount
    }

    @objc
    public class func nextExpirationTimestamp(transaction: SDSAnyReadTransaction) -> NSNumber? {
        guard let timestamp = StoryFinder.oldestExpirableTimestamp(transaction: transaction) else { return nil }
        return NSNumber(value: timestamp + storyLifetimeMillis)
    }

    private static let perContextAutomaticDownloadLimit = 3
    private static let recentContextAutomaticDownloadLimit: UInt = 20

    /// We automatically download incoming stories IFF:
    /// * The context has been recently interacted with (sent message to group, 1:1, viewed story, etc), is associated with a pinned thread, or has been recently viewed
    /// * We have not already exceeded the limit for how many unviewed stories we should download for this context
    private class func startAutomaticDownloadIfNecessary(for message: StoryMessage, transaction: SDSAnyWriteTransaction) {
        guard case .file(let attachmentId) = message.attachment else {
            // We always auto-download non-file story attachments, this will generally only be link preview thumbnails.
            Logger.info("Automatically enqueueing download of non-file based story with timestamp \(message.timestamp)")
            attachmentDownloads.enqueueDownloadOfAttachmentsForNewStoryMessage(message, transaction: transaction)
            return
        }

        guard let attachmentPointer = TSAttachmentPointer.anyFetchAttachmentPointer(uniqueId: attachmentId, transaction: transaction) else {
            // Already downloaded, nothing to do.
            return
        }

        var unviewedDownloadedStoriesForContext = 0
        StoryFinder.enumerateUnviewedIncomingStoriesForContext(message.context, transaction: transaction) { otherMessage, stop in
            guard otherMessage.uniqueId != message.uniqueId else { return }
            switch otherMessage.attachment {
            case .text:
                unviewedDownloadedStoriesForContext += 1
            case .file(let attachmentId):
                guard let attachment = TSAttachment.anyFetch(uniqueId: attachmentId, transaction: transaction) else {
                    owsFailDebug("Missing attachment for attachmentId \(attachmentId)")
                    return
                }
                if let pointer = attachment as? TSAttachmentPointer, [.downloading, .enqueued].contains(pointer.state) {
                    unviewedDownloadedStoriesForContext += 1
                } else if attachment is TSAttachmentStream {
                    unviewedDownloadedStoriesForContext += 1
                }
            }

            if unviewedDownloadedStoriesForContext >= perContextAutomaticDownloadLimit {
                stop.pointee = true
            }
        }

        guard unviewedDownloadedStoriesForContext < perContextAutomaticDownloadLimit else {
            Logger.info("Skipping automatic download of attachments for story with timestamp \(message.timestamp), automatic download limit exceeded for context \(message.context)")
            attachmentPointer.updateAttachmentPointerState(.pendingManualDownload, transaction: transaction)
            return
        }

        // See if the context has been recently active

        let pinnedThreads = PinnedThreadManager.pinnedThreads(transaction: transaction)
        let recentlyInteractedThreads = AnyThreadFinder().threadsWithRecentInteractions(limit: recentContextAutomaticDownloadLimit, transaction: transaction)
        let recentlyViewedThreads = AnyThreadFinder().threadsWithRecentlyViewedStories(limit: recentContextAutomaticDownloadLimit, transaction: transaction)
        let autoDownloadContexts = (pinnedThreads + recentlyInteractedThreads + recentlyViewedThreads).map { $0.storyContext }

        if autoDownloadContexts.contains(message.context) || autoDownloadContexts.contains(.authorUuid(message.authorUuid)) {
            Logger.info("Automatically downloading attachments for story with timestamp \(message.timestamp) and context \(message.context)")

            attachmentDownloads.enqueueDownloadOfAttachmentsForNewStoryMessage(message, transaction: transaction)
        } else {
            Logger.info("Skipping automatic download of attachments for story with timestamp \(message.timestamp), context \(message.context) not recently active")
            attachmentPointer.updateAttachmentPointerState(.pendingManualDownload, transaction: transaction)
        }
    }
}

public enum StoryContext: Equatable, Hashable {
    case groupId(Data)
    case authorUuid(UUID)
    case privateStory(String)
    case none
}

public extension TSThread {
    var storyContext: StoryContext {
        if let groupThread = self as? TSGroupThread {
            return .groupId(groupThread.groupId)
        } else if let contactThread = self as? TSContactThread, let authorUuid = contactThread.contactAddress.uuid {
            return .authorUuid(authorUuid)
        } else if let privateStoryThread = self as? TSPrivateStoryThread {
            return .privateStory(privateStoryThread.uniqueId)
        } else {
            return .none
        }
    }
}

public extension StoryContext {
    func threadUniqueId(transaction: SDSAnyReadTransaction) -> String? {
        switch self {
        case .groupId(let data):
            return TSGroupThread.threadId(
                forGroupId: data,
                transaction: transaction
            )
        case .authorUuid(let uuid):
            return TSContactThread.getWithContactAddress(
                uuid.asSignalServiceAddress(),
                transaction: transaction
            )?.uniqueId
        case .privateStory(let uniqueId):
            return uniqueId
        case .none:
            return nil
        }
    }

    func thread(transaction: SDSAnyReadTransaction) -> TSThread? {
        switch self {
        case .groupId(let data):
            return TSGroupThread.fetch(groupId: data, transaction: transaction)
        case .authorUuid(let uuid):
            return TSContactThread.getWithContactAddress(
                SignalServiceAddress(uuid: uuid),
                transaction: transaction
            )
        case .privateStory(let uniqueId):
            return TSPrivateStoryThread.anyFetchPrivateStoryThread(uniqueId: uniqueId, transaction: transaction)
        case .none:
            return nil
        }
    }

    func isHidden(
        transaction: SDSAnyReadTransaction
    ) -> Bool {
        return isHidden(threadUniqueId: self.threadUniqueId(transaction: transaction), transaction: transaction)
    }

    func isHidden(
        threadUniqueId: String?,
        transaction: SDSAnyReadTransaction
    ) -> Bool {
        guard let threadUniqueId = threadUniqueId else {
            return false
        }
        return ThreadAssociatedData.fetchOrDefault(for: threadUniqueId, transaction: transaction).hideStory
    }
}
