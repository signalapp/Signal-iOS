//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public class StoryManager {
    public static let storyLifetimeMillis = UInt64.dayInMs

    public class func setup(appReadiness: AppReadiness) {
        cacheAreStoriesEnabled()
        cacheAreViewReceiptsEnabled()

        appReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            SSKEnvironment.shared.databaseStorageRef.asyncWrite { transaction in
                // Create My Story thread if necessary
                TSPrivateStoryThread.getOrCreateMyStory(transaction: transaction)

                if CurrentAppContext().isMainApp {
                    DependenciesBridge.shared.privateStoryThreadDeletionManager
                        .cleanUpDeletedTimestamps(tx: transaction)
                }
            }
        }
    }

    public class func processIncomingStoryMessage(
        _ storyMessage: SSKProtoStoryMessage,
        timestamp: UInt64,
        author: Aci,
        localIdentifiers: LocalIdentifiers,
        transaction: DBWriteTransaction,
    ) throws {
        guard
            StoryFinder.story(
                timestamp: timestamp,
                author: author,
                transaction: transaction,
            ) == nil
        else {
            Logger.warn("Dropping story message with duplicate timestamp \(timestamp) from author \(author)")
            return
        }

        guard !SSKEnvironment.shared.blockingManagerRef.isAddressBlocked(SignalServiceAddress(author), transaction: transaction) else {
            Logger.warn("Dropping story message with timestamp \(timestamp) from blocked or hidden author \(author)")
            return
        }

        if DependenciesBridge.shared.recipientHidingManager.isHiddenAddress(SignalServiceAddress(author), tx: transaction) {
            Logger.warn("Dropping story message with timestamp \(timestamp) from hidden author \(author)")
            return
        }

        if let masterKey = storyMessage.group?.masterKey {
            let contextInfo = try GroupV2ContextInfo.deriveFrom(masterKeyData: masterKey)

            guard !SSKEnvironment.shared.blockingManagerRef.isGroupIdBlocked(contextInfo.groupId, transaction: transaction) else {
                Logger.warn("Dropping story message with timestamp \(timestamp) in blocked group")
                return
            }

            guard
                let groupThread = TSGroupThread.fetch(groupId: contextInfo.groupId.serialize(), transaction: transaction),
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
            guard SSKEnvironment.shared.profileManagerRef.isUser(inProfileWhitelist: SignalServiceAddress(author), transaction: transaction) else {
                Logger.warn("Dropping story message with timestamp \(timestamp) from unapproved author \(author).")
                return
            }
        }

        if let profileKey = storyMessage.profileKey {
            SSKEnvironment.shared.profileManagerRef.setProfileKeyData(
                profileKey,
                for: author,
                onlyFillInIfMissing: false,
                shouldFetchProfile: true,
                userProfileWriter: .localUser,
                localIdentifiers: localIdentifiers,
                authedAccount: .implicit(),
                tx: transaction,
            )
        }

        guard
            let message = try StoryMessage.create(
                withIncomingStoryMessage: storyMessage,
                timestamp: timestamp,
                receivedTimestamp: Date().ows_millisecondsSince1970,
                author: author,
                transaction: transaction,
            ) else { return }

        switch message.context {
        case .authorAci(let authorAci):
            // Make sure the thread exists for the contact who sent us this story.
            _ = TSContactThread.getOrCreateThread(withContactAddress: SignalServiceAddress(authorAci), transaction: transaction)
        case .groupId, .privateStory, .none:
            break
        }

        startAutomaticDownloadIfNecessary(for: message, transaction: transaction)

        // We have a new story message, so make sure our expiration job knows
        // about it.
        DependenciesBridge.shared.storyMessageExpirationJob.restart()

        SSKEnvironment.shared.earlyMessageManagerRef.applyPendingMessages(for: message, transaction: transaction)
    }

    public class func processStoryMessageTranscript(
        _ proto: SSKProtoSyncMessageSent,
        transaction: DBWriteTransaction,
    ) throws {
        let existingStory = StoryFinder.story(
            timestamp: proto.timestamp,
            author: DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: transaction)!.aci,
            transaction: transaction,
        )

        if proto.isRecipientUpdate {
            if let existingStory {
                existingStory.updateRecipients(proto.storyMessageRecipients, transaction: transaction)

                // If there are no recipients remaining for a private story, delete the story model
                if
                    existingStory.groupId == nil,
                    case .outgoing(let recipientStates) = existingStory.manifest,
                    recipientStates.values.flatMap({ $0.contexts }).isEmpty
                {
                    Logger.info("Deleting story with timestamp \(existingStory.timestamp) with no remaining contexts")
                    existingStory.anyRemove(transaction: transaction)
                }
            } else {
                owsFailDebug("Missing existing story for recipient update with timestamp \(proto.timestamp)")
            }
        } else if existingStory == nil {
            let message = try StoryMessage.create(withSentTranscript: proto, transaction: transaction)

            DependenciesBridge.shared.attachmentDownloadManager.enqueueDownloadOfAttachmentsForStoryMessage(message, tx: transaction)

            // We have a new story message, so make sure our expiration job
            // knows about it.
            DependenciesBridge.shared.storyMessageExpirationJob.restart()

            SSKEnvironment.shared.earlyMessageManagerRef.applyPendingMessages(for: message, transaction: transaction)
        } else {
            owsFailDebug("Ignoring sync transcript for story with timestamp \(proto.timestamp)")
        }
    }

    public class func deleteAllStories(forSender senderAci: Aci, tx: DBWriteTransaction) {
        StoryFinder.enumerateStories(fromSender: senderAci, tx: tx) { storyMessage, _ in
            storyMessage.anyRemove(transaction: tx)
        }
    }

    public class func deleteAllStories(forGroupId groupId: Data, tx: DBWriteTransaction) {
        StoryFinder.enumerateStoriesForContext(.groupId(groupId), transaction: tx) { storyMessage, _ in
            storyMessage.anyRemove(transaction: tx)
        }
    }

    private static let hasSetMyStoriesPrivacyKey = "hasSetMyStoriesPrivacyKey"

    public class func hasSetMyStoriesPrivacy(transaction: DBReadTransaction) -> Bool {
        return keyValueStore.getBool(hasSetMyStoriesPrivacyKey, defaultValue: false, transaction: transaction)
    }

    public class func setHasSetMyStoriesPrivacy(
        _ hasSet: Bool,
        shouldUpdateStorageService: Bool,
        transaction: DBWriteTransaction,
    ) {
        guard hasSet != hasSetMyStoriesPrivacy(transaction: transaction) else {
            // Don't trigger account record updates unneccesarily!
            return
        }
        keyValueStore.setBool(hasSet, key: hasSetMyStoriesPrivacyKey, transaction: transaction)
        if shouldUpdateStorageService {
            SSKEnvironment.shared.storageServiceManagerRef.recordPendingLocalAccountUpdates()
        }
    }

    private static let perContextAutomaticDownloadLimit = 3
    private static let recentContextAutomaticDownloadLimit: UInt = 20

    /// We automatically download incoming stories IFF:
    /// * The context has been recently interacted with (sent message to group, 1:1, viewed story, etc), is associated with a pinned thread, or has been recently viewed
    /// * We have not already exceeded the limit for how many unviewed stories we should download for this context
    private class func startAutomaticDownloadIfNecessary(for message: StoryMessage, transaction: DBWriteTransaction) {

        let attachmentPointerToDownload: AttachmentPointer?
        switch message.attachment {
        case .media:
            let attachment = message.id.map { rowId in
                return DependenciesBridge.shared.attachmentStore
                    .fetchAnyReferencedAttachment(
                        for: .storyMessageMedia(storyMessageRowId: rowId),
                        tx: transaction,
                    )?.attachment
            } ?? nil
            if attachment?.asStream() != nil {
                // Already downloaded!
                return
            } else {
                attachmentPointerToDownload = attachment?.asAnyPointer()
            }
        case .text:
            // We always auto-download non-file story attachments, this will generally only be link preview thumbnails.
            Logger.info("Automatically enqueueing download of non-file based story with timestamp \(message.timestamp)")
            DependenciesBridge.shared.attachmentDownloadManager.enqueueDownloadOfAttachmentsForStoryMessage(message, tx: transaction)
            return
        }

        guard
            let attachmentPointer = attachmentPointerToDownload,
            attachmentPointer.attachment.asStream() == nil
        else {
            // Already downloaded or couldn't find it, nothing to do.
            return
        }

        var unviewedDownloadedStoriesForContext = 0
        StoryFinder.enumerateUnviewedIncomingStoriesForContext(message.context, transaction: transaction) { otherMessage, stop in
            guard otherMessage.uniqueId != message.uniqueId else { return }
            switch otherMessage.attachment {
            case .text:
                unviewedDownloadedStoriesForContext += 1
            case .media:
                guard let attachment = otherMessage.fileAttachment(tx: transaction) else {
                    owsFailDebug("Missing attachment")
                    return
                }
                if attachment.attachment.asStream() != nil {
                    unviewedDownloadedStoriesForContext += 1
                } else if
                    let pointer = attachment.attachment.asAnyPointer(),
                    pointer.downloadState(tx: transaction) == .enqueuedOrDownloading
                {
                    unviewedDownloadedStoriesForContext += 1
                }
            }

            if unviewedDownloadedStoriesForContext >= perContextAutomaticDownloadLimit {
                stop.pointee = true
            }
        }

        guard unviewedDownloadedStoriesForContext < perContextAutomaticDownloadLimit else {
            Logger.info("Skipping automatic download of attachments for story with timestamp \(message.timestamp), automatic download limit exceeded for context \(message.context)")
            return
        }

        // See if the context has been recently active

        let pinnedThreads = DependenciesBridge.shared.pinnedThreadManager.pinnedThreads(tx: transaction)
        let recentlyInteractedThreads = ThreadFinder().threadsWithRecentInteractions(limit: recentContextAutomaticDownloadLimit, transaction: transaction)
        let recentlyViewedContexts = StoryFinder.associatedDatasWithRecentlyViewedStories(
            limit: Int(recentContextAutomaticDownloadLimit),
            transaction: transaction,
        ).map(\.sourceContext.asStoryContext)
        let autoDownloadContexts = (pinnedThreads + recentlyInteractedThreads).map { $0.storyContext } + recentlyViewedContexts

        if autoDownloadContexts.contains(message.context) || autoDownloadContexts.contains(.authorAci(message.authorAci)) {
            Logger.info("Automatically downloading attachments for story with timestamp \(message.timestamp) and context \(message.context)")

            Self.enqueueDownloadOfAttachmentsForStoryMessage(message, tx: transaction)
        } else {
            Logger.info("Skipping automatic download of attachments for story with timestamp \(message.timestamp), context \(message.context) not recently active")
        }
    }

    // Exposed for testing
    class func enqueueDownloadOfAttachmentsForStoryMessage(
        _ message: StoryMessage,
        tx: DBWriteTransaction,
    ) {
        DependenciesBridge.shared.attachmentDownloadManager.enqueueDownloadOfAttachmentsForStoryMessage(
            message,
            tx: tx,
        )
    }
}

// MARK: -

public extension Notification.Name {
    static let storiesEnabledStateDidChange = Notification.Name("storiesEnabledStateDidChange")
}

extension StoryManager {
    private static let keyValueStore = KeyValueStore(collection: "StoryManager")
    private static let areStoriesEnabledKey = "areStoriesEnabled"

    private static var areStoriesEnabledCache = AtomicBool(true, lock: .sharedGlobal)

    /// A cache of if stories are enabled for the local user. For convenience, this also factors in whether the overall feature is available to the user.
    public static var areStoriesEnabled: Bool { areStoriesEnabledCache.get() }

    public static func setAreStoriesEnabled(_ areStoriesEnabled: Bool, shouldUpdateStorageService: Bool = true, transaction: DBWriteTransaction) {
        keyValueStore.setBool(areStoriesEnabled, key: areStoriesEnabledKey, transaction: transaction)
        areStoriesEnabledCache.set(areStoriesEnabled)

        if shouldUpdateStorageService {
            SSKEnvironment.shared.storageServiceManagerRef.recordPendingLocalAccountUpdates()
        }

        transaction.addSyncCompletion {
            NotificationCenter.default.postOnMainThread(name: .storiesEnabledStateDidChange, object: nil)
        }
    }

    /// Have stories been enabled by the local user. This never factors in any remote information, like is the feature available to the user.
    public static func areStoriesEnabled(transaction: DBReadTransaction) -> Bool {
        keyValueStore.getBool(areStoriesEnabledKey, defaultValue: true, transaction: transaction)
    }

    private static func cacheAreStoriesEnabled() {
        AssertIsOnMainThread()

        let areStoriesEnabled = SSKEnvironment.shared.databaseStorageRef.read { Self.areStoriesEnabled(transaction: $0) }
        areStoriesEnabledCache.set(areStoriesEnabled)

        if !areStoriesEnabled {
            NotificationCenter.default.post(name: .storiesEnabledStateDidChange, object: nil)
        }
    }

    public static func appendStoryHeaders(to request: inout TSRequest) {
        request.headers.merge(buildStoryHeaders())
    }

    public static func buildStoryHeaders() -> HttpHeaders {
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

    @Atomic public private(set) static var areViewReceiptsEnabled: Bool = false

    public static func areViewReceiptsEnabled(transaction: DBReadTransaction) -> Bool {
        keyValueStore.getBool(areViewReceiptsEnabledKey, transaction: transaction) ?? OWSReceiptManager.areReadReceiptsEnabled(transaction: transaction)
    }

    // TODO: should this live on OWSReceiptManager?
    public static func setAreViewReceiptsEnabled(_ enabled: Bool, shouldUpdateStorageService: Bool = true, transaction: DBWriteTransaction) {
        keyValueStore.setBool(enabled, key: areViewReceiptsEnabledKey, transaction: transaction)
        areViewReceiptsEnabled = enabled

        if shouldUpdateStorageService {
            SSKEnvironment.shared.storageServiceManagerRef.recordPendingLocalAccountUpdates()
        }
    }

    private static func cacheAreViewReceiptsEnabled() {
        areViewReceiptsEnabled = SSKEnvironment.shared.databaseStorageRef.read { areViewReceiptsEnabled(transaction: $0) }
    }
}

// MARK: -

public enum StoryContext: Equatable, Hashable {
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

    func threadUniqueId(transaction: DBReadTransaction) -> String? {
        switch self {
        case .groupId(let data):
            return TSGroupThread.threadId(
                forGroupId: data,
                transaction: transaction,
            )
        case .authorAci(let authorAci):
            return TSContactThread.getWithContactAddress(
                SignalServiceAddress(authorAci),
                transaction: transaction,
            )?.uniqueId
        case .privateStory(let uniqueId):
            return uniqueId
        case .none:
            return nil
        }
    }

    func thread(transaction: DBReadTransaction) -> TSThread? {
        switch self {
        case .groupId(let data):
            return TSGroupThread.fetch(groupId: data, transaction: transaction)
        case .authorAci(let authorAci):
            return TSContactThread.getWithContactAddress(
                SignalServiceAddress(authorAci),
                transaction: transaction,
            )
        case .privateStory(let uniqueId):
            return TSPrivateStoryThread.anyFetchPrivateStoryThread(uniqueId: uniqueId, transaction: transaction)
        case .none:
            return nil
        }
    }

    /// Returns nil only for outgoing contexts (private story contexts) which have no associated data.
    /// For valid contact and group contexts where the associated data does not yet exists, creates and returns a default one.
    func associatedData(transaction: DBReadTransaction) -> StoryContextAssociatedData? {
        guard let source = self.asAssociatedDataContext else {
            return nil
        }
        return StoryContextAssociatedData.fetchOrDefault(sourceContext: source, transaction: transaction)
    }

    func isHidden(
        transaction: DBReadTransaction,
    ) -> Bool {
        if self == .authorAci(StoryMessage.systemStoryAuthor) {
            return SSKEnvironment.shared.systemStoryManagerRef.areSystemStoriesHidden(transaction: transaction)
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
