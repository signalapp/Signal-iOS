//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import GRDB

/// Represents a story distribution list.
public final class TSPrivateStoryThread: TSThread {
    override public class var recordType: SDSRecordType { .privateStoryThread }

    public private(set) var allowsReplies: Bool
    public private(set) var _name: String

    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case allowsReplies
        case name
        case addresses
    }

    required init(inheritableDecoder decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.allowsReplies = try container.decode(Bool.self, forKey: .allowsReplies)
        self._name = try container.decode(String.self, forKey: .name)
        try super.init(inheritableDecoder: decoder)
    }

    override public func encode(to encoder: any Encoder) throws {
        try super.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.allowsReplies, forKey: .allowsReplies)
        try container.encode(self._name, forKey: .name)
        try container.encode(nil as Data?, forKey: .addresses)
    }

    init(
        id: Int64?,
        uniqueId: String,
        creationDate: Date?,
        editTargetTimestamp: UInt64?,
        isArchivedObsolete: Bool,
        isMarkedUnreadObsolete: Bool,
        lastDraftInteractionRowId: UInt64,
        lastDraftUpdateTimestamp: UInt64,
        lastInteractionRowId: UInt64,
        lastSentStoryTimestamp: UInt64?,
        mentionNotificationMode: TSThreadMentionNotificationMode,
        messageDraft: String?,
        messageDraftBodyRanges: MessageBodyRanges?,
        mutedUntilTimestampObsolete: UInt64,
        shouldThreadBeVisible: Bool,
        storyViewMode: TSThreadStoryViewMode,
        allowsReplies: Bool,
        name: String,
    ) {
        self.allowsReplies = allowsReplies
        self._name = name
        super.init(
            id: id,
            uniqueId: uniqueId,
            creationDate: creationDate,
            editTargetTimestamp: editTargetTimestamp,
            isArchivedObsolete: isArchivedObsolete,
            isMarkedUnreadObsolete: isMarkedUnreadObsolete,
            lastDraftInteractionRowId: lastDraftInteractionRowId,
            lastDraftUpdateTimestamp: lastDraftUpdateTimestamp,
            lastInteractionRowId: lastInteractionRowId,
            lastSentStoryTimestamp: lastSentStoryTimestamp,
            mentionNotificationMode: mentionNotificationMode,
            messageDraft: messageDraft,
            messageDraftBodyRanges: messageDraftBodyRanges,
            mutedUntilTimestampObsolete: mutedUntilTimestampObsolete,
            shouldThreadBeVisible: shouldThreadBeVisible,
            storyViewMode: storyViewMode,
        )
    }

    public init(uniqueId: String = UUID().uuidString, name: String, allowsReplies: Bool, viewMode: TSThreadStoryViewMode) {
        self._name = name
        self.allowsReplies = allowsReplies
        super.init(uniqueId: uniqueId)
        self.storyViewMode = viewMode
    }

    override func deepCopy() -> TSThread {
        return TSPrivateStoryThread(
            id: self.id,
            uniqueId: self.uniqueId,
            creationDate: self.creationDate,
            editTargetTimestamp: self.editTargetTimestamp,
            isArchivedObsolete: self.isArchivedObsolete,
            isMarkedUnreadObsolete: self.isMarkedUnreadObsolete,
            lastDraftInteractionRowId: self.lastDraftInteractionRowId,
            lastDraftUpdateTimestamp: self.lastDraftUpdateTimestamp,
            lastInteractionRowId: self.lastInteractionRowId,
            lastSentStoryTimestamp: self.lastSentStoryTimestamp,
            mentionNotificationMode: self.mentionNotificationMode,
            messageDraft: self.messageDraft,
            messageDraftBodyRanges: self.messageDraftBodyRanges,
            mutedUntilTimestampObsolete: self.mutedUntilTimestampObsolete,
            shouldThreadBeVisible: self.shouldThreadBeVisible,
            storyViewMode: self.storyViewMode,
            allowsReplies: self.allowsReplies,
            name: self.name,
        )
    }

    override public var hash: Int {
        var hasher = Hasher()
        hasher.combine(super.hash)
        hasher.combine(self.allowsReplies)
        hasher.combine(self.name)
        return hasher.finalize()
    }

    override public func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard super.isEqual(object) else { return false }
        guard self.allowsReplies == object.allowsReplies else { return false }
        guard self.name == object.name else { return false }
        return true
    }

    public class func fetchPrivateStoryThreadViaCache(uniqueId: String, transaction: DBReadTransaction) -> TSPrivateStoryThread? {
        return fetchViaCache(uniqueId: uniqueId, transaction: transaction)
    }

    public var isMyStory: Bool {
        return self.uniqueId == Self.myStoryUniqueId
    }

    public var name: String {
        if self.isMyStory {
            return OWSLocalizedString("MY_STORY_NAME", comment: "Name for the 'My Story' default story that sends to all the user's contacts.")
        }
        return _name
    }

    public typealias RowId = Int64

    @objc
    public class var myStoryUniqueId: String {
        // My Story always uses a UUID of all 0s
        "00000000-0000-0000-0000-000000000000"
    }

    public class func getMyStory(transaction: DBReadTransaction) -> TSPrivateStoryThread! {
        fetchPrivateStoryThreadViaCache(uniqueId: myStoryUniqueId, transaction: transaction)
    }

    @discardableResult
    public class func getOrCreateMyStory(transaction: DBWriteTransaction) -> TSPrivateStoryThread {
        if let myStory = getMyStory(transaction: transaction) { return myStory }

        let myStory = TSPrivateStoryThread(uniqueId: myStoryUniqueId, name: "", allowsReplies: true, viewMode: .blockList)
        myStory.anyInsert(transaction: transaction)
        return myStory
    }

    // MARK: -

    @objc
    public var distributionListIdentifier: Data? { UUID(uuidString: uniqueId)?.data }

    override public func recipientAddresses(with tx: DBReadTransaction) -> [SignalServiceAddress] {
        let storyRecipientManager = DependenciesBridge.shared.storyRecipientManager
        do {
            switch storyViewMode {
            case .default:
                throw OWSAssertionError("Unexpectedly have private story with no view mode")
            case .explicit, .disabled:
                return try storyRecipientManager.fetchRecipients(forStoryThread: self, tx: tx).map { $0.address }
            case .blockList:
                let blockedAddresses = try storyRecipientManager.fetchRecipients(forStoryThread: self, tx: tx).map { $0.address }
                let profileManager = SSKEnvironment.shared.profileManagerRef
                return profileManager.allWhitelistedRegisteredAddresses(tx: tx).filter {
                    return !blockedAddresses.contains($0) && !$0.isLocalAddress
                }
            }
        } catch {
            Logger.warn("Couldn't fetch addresses; returning []: \(error)")
            return []
        }
    }

    // MARK: - updateWith...

    public func updateWithAllowsReplies(
        _ allowsReplies: Bool,
        updateStorageService: Bool,
        transaction tx: DBWriteTransaction,
    ) {
        anyUpdate(transaction: tx) { privateStoryThread in
            privateStoryThread.allowsReplies = allowsReplies
        }

        if updateStorageService, let distributionListIdentifier {
            SSKEnvironment.shared.storageServiceManagerRef.recordPendingUpdates(
                updatedStoryDistributionListIds: [distributionListIdentifier],
            )
        }
    }

    public func updateWithName(
        _ name: String,
        updateStorageService: Bool,
        transaction tx: DBWriteTransaction,
    ) {
        anyUpdate(transaction: tx) { privateStoryThread in
            privateStoryThread._name = name
        }

        if updateStorageService, let distributionListIdentifier {
            SSKEnvironment.shared.storageServiceManagerRef.recordPendingUpdates(
                updatedStoryDistributionListIds: [distributionListIdentifier],
            )
        }
    }

    /// Update this private story thread with the given view mode and
    /// corresponding addresses.
    ///
    /// - Parameter updateStorageService
    /// Whether or not we should update the distribution list this thread
    /// represents in Storage Service.
    /// - Parameter updateHasSetMyStoryPrivacyIfNeeded
    /// Whether or not we should set the local "has set My Story privacy" flag
    /// (to `true`), assuming this thread represents "My Story". Only callers
    /// who will be managing that flag's state themselves – at the time of
    /// writing, that is exclusively Backups – should set this to `false`.
    public func updateWithStoryViewMode(
        _ storyViewMode: TSThreadStoryViewMode,
        storyRecipientIds storyRecipientIdsChange: OptionalChange<[SignalRecipient.RowId]>,
        updateStorageService: Bool,
        updateHasSetMyStoryPrivacyIfNeeded: Bool = true,
        transaction tx: DBWriteTransaction,
    ) {
        if updateHasSetMyStoryPrivacyIfNeeded, isMyStory {
            StoryManager.setHasSetMyStoriesPrivacy(
                true,
                shouldUpdateStorageService: updateStorageService,
                transaction: tx,
            )
        }

        anyUpdate(transaction: tx) { privateStoryThread in
            privateStoryThread.storyViewMode = storyViewMode
        }

        switch storyRecipientIdsChange {
        case .noChange:
            break
        case .setTo(let storyRecipientIds):
            let storyRecipientManager = DependenciesBridge.shared.storyRecipientManager
            failIfThrows {
                try storyRecipientManager.setRecipientIds(
                    storyRecipientIds,
                    for: self,
                    shouldUpdateStorageService: false, // handled below
                    tx: tx,
                )
            }
        }

        if updateStorageService, let distributionListIdentifier {
            tx.addSyncCompletion {
                let storageServiceManager = SSKEnvironment.shared.storageServiceManagerRef
                storageServiceManager.recordPendingUpdates(updatedStoryDistributionListIds: [distributionListIdentifier])
            }
        }
    }
}
