//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

@objc
public class StoryManager: NSObject {
    public static let storyLifetimeMillis = kDayInMs

    @objc
    public class func setup() {
        AppReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            cacheAreStoriesEnabled()
            cacheAreViewReceiptsEnabled()

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
            Logger.warn("Dropping story message with duplicate timestamp \(timestamp) from author \(author)")
            return
        }

        guard !blockingManager.isAddressBlocked(author, transaction: transaction) else {
            Logger.warn("Dropping story message with timestamp \(timestamp) from blocked author \(author)")
            return
        }

        if let masterKey = storyMessage.group?.masterKey {
            let contextInfo = try groupsV2.groupV2ContextInfo(forMasterKeyData: masterKey)

            guard !blockingManager.isGroupIdBlocked(contextInfo.groupId, transaction: transaction) else {
                Logger.warn("Dropping story message with timestamp \(timestamp) in blocked group")
                return
            }

            guard
                let groupThread = TSGroupThread.fetch(groupId: contextInfo.groupId, transaction: transaction),
                groupThread.groupMembership.isFullMember(author)
            else {
                Logger.warn("Dropping story message with timestamp \(timestamp) from author \(author) not in group")
                return
            }

            if
                let groupModel = groupThread.groupModel as? TSGroupModelV2,
                groupModel.isAnnouncementsOnly,
                !groupModel.groupMembership.isFullMemberAndAdministrator(author)
            {
                Logger.warn("Dropping story message with timestamp \(timestamp) from non-admin author \(author) in announcement only group")
                return
            }

        } else {
            guard profileManager.isUser(inProfileWhitelist: author, transaction: transaction) else {
                Logger.warn("Dropping story message with timestamp \(timestamp) from unapproved author \(author).")
                return
            }
        }

        if let profileKey = storyMessage.profileKey {
            profileManager.setProfileKeyData(
                profileKey,
                for: author,
                userProfileWriter: .localUser,
                transaction: transaction
            )
        }

        guard let message = try StoryMessage.create(
            withIncomingStoryMessage: storyMessage,
            timestamp: timestamp,
            receivedTimestamp: Date().ows_millisecondsSince1970,
            author: author,
            transaction: transaction
        ) else { return }

        switch message.context {
        case .authorUuid(let uuid):
            // Make sure the thread exists for the contact who sent us this story.
            _ = TSContactThread.getOrCreateThread(withContactAddress: .init(uuid: uuid), transaction: transaction)
        case .groupId, .privateStory, .none:
            break
        }

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

    private static let hasSetMyStoriesPrivacyKey = "hasSetMyStoriesPrivacyKey"

    @objc
    public class func hasSetMyStoriesPrivacy(transaction: SDSAnyReadTransaction) -> Bool {
        return keyValueStore.getBool(hasSetMyStoriesPrivacyKey, defaultValue: false, transaction: transaction)
    }

    @objc
    public class func setHasSetMyStoriesPrivacy(
        _ hasSet: Bool = true,
        transaction: SDSAnyWriteTransaction,
        shouldUpdateStorageService: Bool = true
    ) {
        guard hasSet != hasSetMyStoriesPrivacy(transaction: transaction) else {
            // Don't trigger account record updates unneccesarily!
            return
        }
        keyValueStore.setBool(hasSet, key: hasSetMyStoriesPrivacyKey, transaction: transaction)
        if shouldUpdateStorageService {
            Self.storageServiceManager.recordPendingLocalAccountUpdates()
        }
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
        let recentlyViewedContexts = StoryFinder.associatedDatasWithRecentlyViewedStories(
            limit: Int(recentContextAutomaticDownloadLimit),
            transaction: transaction
        ).map(\.sourceContext.asStoryContext)
        let autoDownloadContexts = (pinnedThreads + recentlyInteractedThreads).map { $0.storyContext } + recentlyViewedContexts

        if autoDownloadContexts.contains(message.context) || autoDownloadContexts.contains(.authorUuid(message.authorUuid)) {
            Logger.info("Automatically downloading attachments for story with timestamp \(message.timestamp) and context \(message.context)")

            attachmentDownloads.enqueueDownloadOfAttachmentsForNewStoryMessage(message, transaction: transaction)
        } else {
            Logger.info("Skipping automatic download of attachments for story with timestamp \(message.timestamp), context \(message.context) not recently active")
            attachmentPointer.updateAttachmentPointerState(.pendingManualDownload, transaction: transaction)
        }
    }
}

// MARK: -

public extension Notification.Name {
    static let storiesEnabledStateDidChange = Notification.Name("storiesEnabledStateDidChange")
}

extension StoryManager {
    private static let keyValueStore = SDSKeyValueStore(collection: "StoryManager")
    private static let areStoriesEnabledKey = "areStoriesEnabled"

    private static var areStoriesEnabledCache = AtomicBool(true)

    /// A cache of if stories are enabled for the local user. For convenience, this also factors in whether the overall feature is available to the user.
    @objc
    public static var areStoriesEnabled: Bool { RemoteConfig.stories && areStoriesEnabledCache.get() }

    public static func setAreStoriesEnabled(_ areStoriesEnabled: Bool, shouldUpdateStorageService: Bool = true, transaction: SDSAnyWriteTransaction) {
        keyValueStore.setBool(areStoriesEnabled, key: areStoriesEnabledKey, transaction: transaction)
        areStoriesEnabledCache.set(areStoriesEnabled)

        if shouldUpdateStorageService {
            storageServiceManager.recordPendingLocalAccountUpdates()
        }

        transaction.addAsyncCompletionOnMain {
            NotificationCenter.default.post(name: .storiesEnabledStateDidChange, object: nil)
        }
    }

    /// Have stories been enabled by the local user. This never factors in any remote information, like is the feature available to the user.
    public static func areStoriesEnabled(transaction: SDSAnyReadTransaction) -> Bool {
        keyValueStore.getBool(areStoriesEnabledKey, defaultValue: true, transaction: transaction)
    }

    private static func cacheAreStoriesEnabled() {
        AssertIsOnMainThread()

        let areStoriesEnabled = databaseStorage.read { Self.areStoriesEnabled(transaction: $0) }
        areStoriesEnabledCache.set(areStoriesEnabled)

        if !areStoriesEnabled {
            NotificationCenter.default.post(name: .storiesEnabledStateDidChange, object: nil)
        }
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public class func appendStoryHeadersToRequest(_ mutableRequest: NSMutableURLRequest) {
        var request = mutableRequest as URLRequest
        appendStoryHeaders(to: &request)
        mutableRequest.allHTTPHeaderFields = request.allHTTPHeaderFields
    }

    public static func appendStoryHeaders(to request: inout URLRequest) {
        for (key, value) in buildStoryHeaders() {
            request.setValue(value, forHTTPHeaderField: key)
        }
    }

    public static func buildStoryHeaders() -> [String: String] {
        ["X-Signal-Receive-Stories": areStoriesEnabled ? "true" : "false"]
    }
}

// MARK: -

extension StoryManager {
    private static let areViewReceiptsEnabledKey = "areViewReceiptsEnabledKey"

    @objc
    @Atomic public private(set) static var areViewReceiptsEnabled: Bool = false

    public static func areViewReceiptsEnabled(transaction: SDSAnyReadTransaction) -> Bool {
        keyValueStore.getBool(areViewReceiptsEnabledKey, transaction: transaction) ?? receiptManager.areReadReceiptsEnabled(transaction: transaction)
    }

    public static func setAreViewReceiptsEnabled(_ enabled: Bool, shouldUpdateStorageService: Bool = true, transaction: SDSAnyWriteTransaction) {
        keyValueStore.setBool(enabled, key: areViewReceiptsEnabledKey, transaction: transaction)
        areViewReceiptsEnabled = enabled

        if shouldUpdateStorageService {
            storageServiceManager.recordPendingLocalAccountUpdates()
        }
    }

    private static func cacheAreViewReceiptsEnabled() {
        areViewReceiptsEnabled = databaseStorage.read { areViewReceiptsEnabled(transaction: $0) }
    }
}

// MARK: -

public enum StoryContext: Equatable, Hashable, Dependencies {
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

    var asAssociatedDataContext: StoryContextAssociatedData.SourceContext? {
        switch self {
        case .groupId(let data):
            return .group(groupId: data)
        case .authorUuid(let uUID):
            return .contact(contactUuid: uUID)
        case .privateStory:
            return nil
        case .none:
            return nil
        }
    }

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

    /// Returns nil only for outgoing contexts (private story contexts) which have no associated data.
    /// For valid contact and group contexts where the associated data does not yet exists, creates and returns a default one.
    func associatedData(transaction: SDSAnyReadTransaction) -> StoryContextAssociatedData? {
        guard let source = self.asAssociatedDataContext else {
            return nil
        }
        return StoryContextAssociatedData.fetchOrDefault(sourceContext: source, transaction: transaction)
    }

    func isHidden(
        transaction: SDSAnyReadTransaction
    ) -> Bool {
        if
            case .authorUuid(let uuid) = self,
            SignalServiceAddress(uuid: uuid).isSystemStoryAddress
        {
            return Self.systemStoryManager.areSystemStoriesHidden(transaction: transaction)
        }
        return self.associatedData(transaction: transaction)?.isHidden ?? false
    }
}

public extension StoryContextAssociatedData.SourceContext {

    var asStoryContext: StoryContext {
        switch self {
        case .contact(let contactUuid):
            return .authorUuid(contactUuid)
        case .group(let groupId):
            return .groupId(groupId)
        }
    }
}
