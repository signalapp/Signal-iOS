//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalCoreKit

@objc
public class StoryManager: NSObject {
    public static let storyLifetimeMillis = kDayInMs

    @objc
    public class func setup() {
        cacheAreStoriesEnabled()
        cacheAreViewReceiptsEnabled()

        AppReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            Self.databaseStorage.asyncWrite { transaction in
                // Create My Story thread if necessary
                TSPrivateStoryThread.getOrCreateMyStory(transaction: transaction)

                if CurrentAppContext().isMainApp {
                    TSPrivateStoryThread.cleanupDeletedTimestamps(transaction: transaction)
                }
            }
        }
    }

    public class func processIncomingStoryMessage(
        _ storyMessage: SSKProtoStoryMessage,
        timestamp: UInt64,
        author: Aci,
        transaction: SDSAnyWriteTransaction
    ) throws {
        guard StoryFinder.story(
            timestamp: timestamp,
            author: author,
            transaction: transaction
        ) == nil else {
            Logger.warn("Dropping story message with duplicate timestamp \(timestamp) from author \(author)")
            return
        }

        guard !blockingManager.isAddressBlocked(SignalServiceAddress(author), transaction: transaction) else {
            Logger.warn("Dropping story message with timestamp \(timestamp) from blocked or hidden author \(author)")
            return
        }

        if DependenciesBridge.shared.recipientHidingManager.isHiddenAddress(SignalServiceAddress(author), tx: transaction.asV2Read) {
            Logger.warn("Dropping story message with timestamp \(timestamp) from hidden author \(author)")
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
            guard profileManager.isUser(inProfileWhitelist: SignalServiceAddress(author), transaction: transaction) else {
                Logger.warn("Dropping story message with timestamp \(timestamp) from unapproved author \(author).")
                return
            }
        }

        if let profileKey = storyMessage.profileKey {
            profileManager.setProfileKeyData(
                profileKey,
                for: SignalServiceAddress(author),
                userProfileWriter: .localUser,
                authedAccount: .implicit(),
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
        case .authorAci(let authorAci):
            // Make sure the thread exists for the contact who sent us this story.
            _ = TSContactThread.getOrCreateThread(withContactAddress: SignalServiceAddress(authorAci), transaction: transaction)
        case .groupId, .privateStory, .none:
            break
        }

        startAutomaticDownloadIfNecessary(for: message, transaction: transaction)

        OWSDisappearingMessagesJob.shared.scheduleRun(byTimestamp: message.timestamp + storyLifetimeMillis)

        earlyMessageManager.applyPendingMessages(for: message, transaction: transaction)
    }

    public class func processStoryMessageTranscript(
        _ proto: SSKProtoSyncMessageSent,
        transaction: SDSAnyWriteTransaction
    ) throws {
        let existingStory = StoryFinder.story(
            timestamp: proto.timestamp,
            author: DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: transaction.asV2Read)!.aci,
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

    public class func deleteAllStories(forSender senderAci: Aci, tx: SDSAnyWriteTransaction) {
        StoryFinder.enumerateStories(fromSender: senderAci, tx: tx) { storyMessage, _ in
            storyMessage.anyRemove(transaction: tx)
        }
    }

    /// Removes a given address from any TSPrivateStoryThread(s) that have it as an _explicit_ address, whether by exclusion or
    /// inclusion.
    public class func removeAddressFromAllPrivateStoryThreads(_ address: SignalServiceAddress, tx: SDSAnyWriteTransaction) {
        // We don't have a mapping from recipient to the set of TSPrivateStoryThreads they
        // are a part of, so the best we can do is index over all of them and find
        // the recipient if present. If this becomes an issue, we can consider adding such a lookup table.
        // In practice, since private story threads are generated exclusively by the user themselves,
        // and explicit memberships are a subset, the count is going to be very low.
        ThreadFinder().storyThreads(
            includeImplicitGroupThreads: false,
            transaction: tx
        ).forEach { thread in
            guard let storyThread = thread as? TSPrivateStoryThread else {
                return
            }
            switch storyThread.storyViewMode {
            case .default, .disabled:
                return
            case .explicit, .blockList:
                var finalAddresses = storyThread.addresses
                finalAddresses.removeAll(where: { $0 == address })
                if finalAddresses.count != storyThread.addresses.count {
                    // Remove the recipient from the private story thread.
                    storyThread.updateWithStoryViewMode(
                        storyThread.storyViewMode,
                        addresses: finalAddresses,
                        updateStorageService: true,
                        transaction: tx
                    )
                }
            }
        }
    }

    public class func nextExpirationTimestamp(transaction: SDSAnyReadTransaction) -> UInt64? {
        guard let timestamp = StoryFinder.oldestExpirableTimestamp(transaction: transaction) else { return nil }
        return timestamp + storyLifetimeMillis
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
        guard case .file(let file) = message.attachment else {
            // We always auto-download non-file story attachments, this will generally only be link preview thumbnails.
            Logger.info("Automatically enqueueing download of non-file based story with timestamp \(message.timestamp)")
            attachmentDownloads.enqueueDownloadOfAttachmentsForNewStoryMessage(message, transaction: transaction)
            return
        }

        guard let attachmentPointer = TSAttachmentPointer.anyFetchAttachmentPointer(uniqueId: file.attachmentId, transaction: transaction) else {
            // Already downloaded, nothing to do.
            return
        }

        var unviewedDownloadedStoriesForContext = 0
        StoryFinder.enumerateUnviewedIncomingStoriesForContext(message.context, transaction: transaction) { otherMessage, stop in
            guard otherMessage.uniqueId != message.uniqueId else { return }
            switch otherMessage.attachment {
            case .text:
                unviewedDownloadedStoriesForContext += 1
            case .file, .foreignReferenceAttachment:
                guard let attachment = otherMessage.fileAttachment(tx: transaction) else {
                    owsFailDebug("Missing attachment for attachmentId \(file.attachmentId)")
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

        let pinnedThreads = DependenciesBridge.shared.pinnedThreadManager.pinnedThreads(tx: transaction.asV2Read)
        let recentlyInteractedThreads = ThreadFinder().threadsWithRecentInteractions(limit: recentContextAutomaticDownloadLimit, transaction: transaction)
        let recentlyViewedContexts = StoryFinder.associatedDatasWithRecentlyViewedStories(
            limit: Int(recentContextAutomaticDownloadLimit),
            transaction: transaction
        ).map(\.sourceContext.asStoryContext)
        let autoDownloadContexts = (pinnedThreads + recentlyInteractedThreads).map { $0.storyContext } + recentlyViewedContexts

        if autoDownloadContexts.contains(message.context) || autoDownloadContexts.contains(.authorAci(message.authorAci)) {
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
    public static var areStoriesEnabled: Bool { areStoriesEnabledCache.get() }

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

    // MARK: - Story Thread Name

    public static func storyName(for thread: TSThread) -> String {
        if let groupThread = thread as? TSGroupThread {
            return groupThread.groupNameOrDefault
        } else if let story = thread as? TSPrivateStoryThread {
            return story.name
        } else {
            owsFailDebug("Unexpected thread type \(type(of: thread))")
            return ""
        }
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

    // TODO: should this live on OWSReceiptManager?
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
    case authorAci(Aci)
    case privateStory(String)
    case none
}

public extension TSThread {
    var storyContext: StoryContext {
        if let groupThread = self as? TSGroupThread {
            return .groupId(groupThread.groupId)
        } else if let contactThread = self as? TSContactThread, let authorAci = contactThread.contactAddress.serviceId as? Aci {
            return .authorAci(authorAci)
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
        case .authorAci(let authorAci):
            return .contact(contactAci: authorAci)
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
        case .authorAci(let authorAci):
            return TSContactThread.getWithContactAddress(
                SignalServiceAddress(authorAci),
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
        case .authorAci(let authorAci):
            return TSContactThread.getWithContactAddress(
                SignalServiceAddress(authorAci),
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
        if self == .authorAci(StoryMessage.systemStoryAuthor) {
            return Self.systemStoryManager.areSystemStoriesHidden(transaction: transaction)
        }
        return self.associatedData(transaction: transaction)?.isHidden ?? false
    }
}

public extension StoryContextAssociatedData.SourceContext {

    var asStoryContext: StoryContext {
        switch self {
        case .contact(let contactAci):
            return .authorAci(contactAci)
        case .group(let groupId):
            return .groupId(groupId)
        }
    }
}
