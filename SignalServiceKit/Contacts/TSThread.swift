//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import GRDB
public import LibSignalClient

public enum TSThreadStoryViewMode: UInt {
    case `default` = 0
    case explicit = 1
    case blockList = 2
    case disabled = 3
}

public enum TSThreadType: UInt {
    case thread = 2
    case contactThread = 27
    case groupThread = 26
    case privateStoryThread = 72
    case releaseNotesThread = 80
}

@objc
open class TSThread: NSObject, SDSCodableModel, InheritableRecord {
    public static let databaseTableName: String = "model_TSThread"
    public class var recordType: TSThreadType { .thread }
    public typealias UniqueId = String

    static func concreteType(forRecordType recordType: UInt) -> (any InheritableRecord.Type)? {
        switch TSThreadType(rawValue: recordType) {
        case .thread: TSThread.self
        case .contactThread: TSContactThread.self
        case .groupThread: TSGroupThread.self
        case .privateStoryThread: TSPrivateStoryThread.self
        case .releaseNotesThread: TSReleaseNotesThread.self
        case nil: nil
        }
    }

    public var id: RowId?
    public var sqliteRowId: RowId? { self.id }

    @objc
    public let uniqueId: UniqueId

    public let creationDate: Date?
    public internal(set) var isArchived: Bool
    // zero if thread has never had an interaction.
    // The corresponding interaction may have been deleted.
    public internal(set) var lastInteractionRowId: UInt64
    public internal(set) var messageDraft: String?
    public internal(set) var shouldThreadBeVisible: Bool
    public internal(set) var isMarkedUnread: Bool
    public private(set) var messageDraftBodyRanges: MessageBodyRanges?
    // [Notifications] TODO: Remove
    public private(set) var shouldNotifyForMentionsWhenMutedLegacy: Bool
    /// `nil` inherits NotificationPreferencesManager's default
    public private(set) var shouldNotifyForMentionsWhenMuted: Bool?
    public private(set) var shouldNotifyForRepliesWhenMuted: Bool?
    public private(set) var shouldNotifyForCallsWhenMuted: Bool?
    public internal(set) var mutedUntilTimestamp: UInt64
    public private(set) var lastSentStoryTimestamp: UInt64?
    public internal(set) var storyViewMode: TSThreadStoryViewMode
    public private(set) var editTargetTimestamp: UInt64?
    // These are used to maintain the ordering of drafts in the chat list.
    // When a draft is saved, the lastDraftInteractionRowId for that thread
    // should be set to the max lastInteractionRowId across all threads to
    // prioritize it in the chat list. lastDraftUpdateTimestamp
    // can be used to break ties between threads with the same lastDraftInteractionRowId.
    public internal(set) var lastDraftInteractionRowId: UInt64
    public internal(set) var lastDraftUpdateTimestamp: UInt64
    public internal(set) var audioPlaybackRate: Float

    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case id
        case recordType
        case uniqueId

        case conversationColorNameObsolete = "conversationColorName"
        case creationDate
        case editTargetTimestamp
        case isArchived
        case isMarkedUnread
        case lastDraftInteractionRowId
        case lastDraftUpdateTimestamp
        case lastInteractionRowId
        case lastSentStoryTimestamp
        case lastVisibleSortIdObsolete = "lastVisibleSortId"
        case lastVisibleSortIdOnScreenPercentageObsolete = "lastVisibleSortIdOnScreenPercentage"
        case mentionNotificationMode
        case messageDraft
        case messageDraftBodyRanges
        case mutedUntilDateObsolete = "mutedUntilDate"
        case mutedUntilTimestamp
        case shouldNotifyForCallsWhenMuted
        case shouldNotifyForMentionsWhenMuted
        case shouldNotifyForRepliesWhenMuted
        case shouldThreadBeVisible
        case storyViewMode
        case audioPlaybackRate
    }

    enum MentionNotificationMode: Int64, Codable {
        case notifyWhenMuted = 1
        case doNotNotifyWhenMuted = 2

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            self = Self(rawValue: try container.decode(Int64.self)) ?? .notifyWhenMuted
        }

        var shouldNotifyForMentionsWhenMuted: Bool {
            switch self {
            case .notifyWhenMuted: true
            case .doNotNotifyWhenMuted: false
            }
        }
    }

    public required init(inheritableDecoder decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(Int64.self, forKey: .id)
        self.uniqueId = try container.decode(String.self, forKey: .uniqueId)
        self.creationDate = try container.decodeIfPresent(TimeInterval.self, forKey: .creationDate).map(Date.init(timeIntervalSince1970:))
        self.editTargetTimestamp = try container.decodeIfPresent(UInt64.self, forKey: .editTargetTimestamp)
        self.isArchived = try container.decode(Bool.self, forKey: .isArchived)
        self.isMarkedUnread = try container.decode(Bool.self, forKey: .isMarkedUnread)
        self.lastDraftInteractionRowId = try container.decode(UInt64.self, forKey: .lastDraftInteractionRowId)
        self.lastDraftUpdateTimestamp = try container.decode(UInt64.self, forKey: .lastDraftUpdateTimestamp)
        self.lastInteractionRowId = try container.decode(UInt64.self, forKey: .lastInteractionRowId)
        self.lastSentStoryTimestamp = try container.decodeIfPresent(UInt64.self, forKey: .lastSentStoryTimestamp)
        self.shouldNotifyForMentionsWhenMutedLegacy = try container.decode(MentionNotificationMode.self, forKey: .mentionNotificationMode).shouldNotifyForMentionsWhenMuted
        self.messageDraft = try container.decodeIfPresent(String.self, forKey: .messageDraft)
        self.messageDraftBodyRanges = try container.decodeIfPresent(Data.self, forKey: .messageDraftBodyRanges).map({ try LegacySDSSerializer().deserializeLegacySDSData($0, ofClass: MessageBodyRanges.self) })
        self.mutedUntilTimestamp = UInt64(bitPattern: try container.decode(Int64.self, forKey: .mutedUntilTimestamp))
        self.shouldNotifyForCallsWhenMuted = try container.decodeIfPresent(Bool.self, forKey: .shouldNotifyForCallsWhenMuted)
        self.shouldNotifyForMentionsWhenMuted = try container.decodeIfPresent(Bool.self, forKey: .shouldNotifyForMentionsWhenMuted)
        self.shouldNotifyForRepliesWhenMuted = try container.decodeIfPresent(Bool.self, forKey: .shouldNotifyForRepliesWhenMuted)
        self.shouldThreadBeVisible = try container.decode(Bool.self, forKey: .shouldThreadBeVisible)
        self.storyViewMode = TSThreadStoryViewMode(rawValue: try container.decode(UInt.self, forKey: .storyViewMode)) ?? .default
        self.audioPlaybackRate = try container.decode(Float.self, forKey: .audioPlaybackRate)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.id, forKey: .id)
        try container.encode(Self.recordType.rawValue, forKey: .recordType)
        try container.encode(self.uniqueId, forKey: .uniqueId)
        try container.encode("", forKey: .conversationColorNameObsolete)
        try container.encode(self.creationDate?.timeIntervalSince1970, forKey: .creationDate)
        try container.encode(self.editTargetTimestamp, forKey: .editTargetTimestamp)
        try container.encode(self.isArchived, forKey: .isArchived)
        try container.encode(self.isMarkedUnread, forKey: .isMarkedUnread)
        try container.encode(self.lastDraftInteractionRowId, forKey: .lastDraftInteractionRowId)
        try container.encode(self.lastDraftUpdateTimestamp, forKey: .lastDraftUpdateTimestamp)
        try container.encode(self.lastInteractionRowId, forKey: .lastInteractionRowId)
        try container.encode(self.lastSentStoryTimestamp, forKey: .lastSentStoryTimestamp)
        try container.encode(0 as UInt64, forKey: .lastVisibleSortIdObsolete)
        try container.encode(0 as Double, forKey: .lastVisibleSortIdOnScreenPercentageObsolete)
        let mentionNotificationMode: MentionNotificationMode
        mentionNotificationMode = self.shouldNotifyForMentionsWhenMutedLegacy ? .notifyWhenMuted : .doNotNotifyWhenMuted
        try container.encode(mentionNotificationMode, forKey: .mentionNotificationMode)
        try container.encode(self.messageDraft, forKey: .messageDraft)
        let messageDraftBodyRangesData = self.messageDraftBodyRanges.map(LegacySDSSerializer().serializeAsLegacySDSData(_:))
        try container.encode(messageDraftBodyRangesData, forKey: .messageDraftBodyRanges)
        try container.encode(nil as Date?, forKey: .mutedUntilDateObsolete)
        try container.encode(Int64(bitPattern: self.mutedUntilTimestamp), forKey: .mutedUntilTimestamp)
        try container.encode(self.shouldNotifyForCallsWhenMuted, forKey: .shouldNotifyForCallsWhenMuted)
        try container.encode(self.shouldNotifyForMentionsWhenMuted, forKey: .shouldNotifyForMentionsWhenMuted)
        try container.encode(self.shouldNotifyForRepliesWhenMuted, forKey: .shouldNotifyForRepliesWhenMuted)
        try container.encode(self.shouldThreadBeVisible, forKey: .shouldThreadBeVisible)
        try container.encode(self.storyViewMode.rawValue, forKey: .storyViewMode)
        try container.encode(self.audioPlaybackRate, forKey: .audioPlaybackRate)
    }

    init(
        id: Int64?,
        uniqueId: String,
        creationDate: Date?,
        editTargetTimestamp: UInt64?,
        isArchived: Bool,
        isMarkedUnread: Bool,
        lastDraftInteractionRowId: UInt64,
        lastDraftUpdateTimestamp: UInt64,
        lastInteractionRowId: UInt64,
        lastSentStoryTimestamp: UInt64?,
        shouldNotifyForMentionsWhenMutedLegacy: Bool,
        shouldNotifyForMentionsWhenMuted: Bool?,
        shouldNotifyForRepliesWhenMuted: Bool?,
        shouldNotifyForCallsWhenMuted: Bool?,
        messageDraft: String?,
        messageDraftBodyRanges: MessageBodyRanges?,
        mutedUntilTimestamp: UInt64,
        shouldThreadBeVisible: Bool,
        storyViewMode: TSThreadStoryViewMode,
        audioPlaybackRate: Float,
    ) {
        self.id = id
        self.uniqueId = uniqueId
        self.creationDate = creationDate
        self.editTargetTimestamp = editTargetTimestamp
        self.isArchived = isArchived
        self.isMarkedUnread = isMarkedUnread
        self.lastDraftInteractionRowId = lastDraftInteractionRowId
        self.lastDraftUpdateTimestamp = lastDraftUpdateTimestamp
        self.lastInteractionRowId = lastInteractionRowId
        self.lastSentStoryTimestamp = lastSentStoryTimestamp
        self.shouldNotifyForMentionsWhenMutedLegacy = shouldNotifyForMentionsWhenMutedLegacy
        self.shouldNotifyForMentionsWhenMuted = shouldNotifyForMentionsWhenMuted
        self.shouldNotifyForRepliesWhenMuted = shouldNotifyForRepliesWhenMuted
        self.shouldNotifyForCallsWhenMuted = shouldNotifyForCallsWhenMuted
        self.messageDraft = messageDraft
        self.messageDraftBodyRanges = messageDraftBodyRanges
        self.mutedUntilTimestamp = mutedUntilTimestamp
        self.shouldThreadBeVisible = shouldThreadBeVisible
        self.storyViewMode = storyViewMode
        self.audioPlaybackRate = audioPlaybackRate
    }

    init(uniqueId: String) {
        self.isArchived = false
        self.isMarkedUnread = false
        self.lastDraftInteractionRowId = 0
        self.lastDraftUpdateTimestamp = 0
        self.lastInteractionRowId = 0
        self.shouldNotifyForMentionsWhenMutedLegacy = NotificationPreferencesManager.Defaults.shouldNotifyForMentionsWhenMuted
        self.shouldNotifyForMentionsWhenMuted = nil
        self.shouldNotifyForRepliesWhenMuted = nil
        self.shouldNotifyForCallsWhenMuted = nil
        self.messageDraft = nil
        self.mutedUntilTimestamp = 0
        self.shouldThreadBeVisible = false
        self.storyViewMode = .default
        self.audioPlaybackRate = 1

        self.uniqueId = uniqueId
        self.creationDate = Date()
    }

    func deepCopy() -> TSThread {
        return TSThread(
            id: self.id,
            uniqueId: self.uniqueId,
            creationDate: self.creationDate,
            editTargetTimestamp: self.editTargetTimestamp,
            isArchived: self.isArchived,
            isMarkedUnread: self.isMarkedUnread,
            lastDraftInteractionRowId: self.lastDraftInteractionRowId,
            lastDraftUpdateTimestamp: self.lastDraftUpdateTimestamp,
            lastInteractionRowId: self.lastInteractionRowId,
            lastSentStoryTimestamp: self.lastSentStoryTimestamp,
            shouldNotifyForMentionsWhenMutedLegacy: self.shouldNotifyForMentionsWhenMutedLegacy,
            shouldNotifyForMentionsWhenMuted: self.shouldNotifyForMentionsWhenMuted,
            shouldNotifyForRepliesWhenMuted: self.shouldNotifyForRepliesWhenMuted,
            shouldNotifyForCallsWhenMuted: self.shouldNotifyForCallsWhenMuted,
            messageDraft: self.messageDraft,
            messageDraftBodyRanges: self.messageDraftBodyRanges,
            mutedUntilTimestamp: self.mutedUntilTimestamp,
            shouldThreadBeVisible: self.shouldThreadBeVisible,
            storyViewMode: self.storyViewMode,
            audioPlaybackRate: self.audioPlaybackRate,
        )
    }

    override public var hash: Int {
        var hasher = Hasher()
        hasher.combine(self.id)
        hasher.combine(self.uniqueId)
        hasher.combine(self.creationDate)
        hasher.combine(self.editTargetTimestamp)
        hasher.combine(self.isArchived)
        hasher.combine(self.isMarkedUnread)
        hasher.combine(self.lastDraftInteractionRowId)
        hasher.combine(self.lastDraftUpdateTimestamp)
        hasher.combine(self.lastInteractionRowId)
        hasher.combine(self.lastSentStoryTimestamp)
        hasher.combine(self.shouldNotifyForMentionsWhenMutedLegacy)
        hasher.combine(self.shouldNotifyForMentionsWhenMuted)
        hasher.combine(self.shouldNotifyForRepliesWhenMuted)
        hasher.combine(self.shouldNotifyForCallsWhenMuted)
        hasher.combine(self.messageDraft)
        hasher.combine(self.messageDraftBodyRanges)
        hasher.combine(self.mutedUntilTimestamp)
        hasher.combine(self.shouldThreadBeVisible)
        hasher.combine(self.storyViewMode)
        hasher.combine(self.audioPlaybackRate)
        return hasher.finalize()
    }

    override public func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard self.id == object.id else { return false }
        guard self.uniqueId == object.uniqueId else { return false }
        guard self.creationDate == object.creationDate else { return false }
        guard self.editTargetTimestamp == object.editTargetTimestamp else { return false }
        guard self.isArchived == object.isArchived else { return false }
        guard self.isMarkedUnread == object.isMarkedUnread else { return false }
        guard self.lastDraftInteractionRowId == object.lastDraftInteractionRowId else { return false }
        guard self.lastDraftUpdateTimestamp == object.lastDraftUpdateTimestamp else { return false }
        guard self.lastInteractionRowId == object.lastInteractionRowId else { return false }
        guard self.lastSentStoryTimestamp == object.lastSentStoryTimestamp else { return false }
        guard self.shouldNotifyForMentionsWhenMutedLegacy == object.shouldNotifyForMentionsWhenMutedLegacy else { return false }
        guard self.shouldNotifyForMentionsWhenMuted == object.shouldNotifyForMentionsWhenMuted else { return false }
        guard self.shouldNotifyForRepliesWhenMuted == object.shouldNotifyForRepliesWhenMuted else { return false }
        guard self.shouldNotifyForCallsWhenMuted == object.shouldNotifyForCallsWhenMuted else { return false }
        guard self.messageDraft == object.messageDraft else { return false }
        guard self.messageDraftBodyRanges == object.messageDraftBodyRanges else { return false }
        guard self.mutedUntilTimestamp == object.mutedUntilTimestamp else { return false }
        guard self.shouldThreadBeVisible == object.shouldThreadBeVisible else { return false }
        guard self.storyViewMode == object.storyViewMode else { return false }
        guard self.audioPlaybackRate == object.audioPlaybackRate else { return false }
        return true
    }

    public func anyDidFetchOne(transaction: DBReadTransaction) {
        SSKEnvironment.shared.modelReadCachesRef.threadReadCache.didReadThread(self, transaction: transaction)
    }

    public func anyDidEnumerateOne(transaction: DBReadTransaction) {
        SSKEnvironment.shared.modelReadCachesRef.threadReadCache.didReadThread(self, transaction: transaction)
    }

    open func anyWillInsert(transaction: DBWriteTransaction) {
    }

    public func anyDidInsert(transaction: DBWriteTransaction) {
        if self.shouldThreadBeVisible, !SSKPreferences.hasSavedThread(transaction: transaction) {
            SSKPreferences.setHasSavedThread(true, transaction: transaction)
        }

        _anyDidInsert(tx: transaction)

        SSKEnvironment.shared.modelReadCachesRef.threadReadCache.didInsertOrUpdate(thread: self, transaction: transaction)
    }

    public func anyWillUpdate(transaction: DBWriteTransaction) {
    }

    public func anyDidUpdate(transaction: DBWriteTransaction) {
        if self.shouldThreadBeVisible, !SSKPreferences.hasSavedThread(transaction: transaction) {
            SSKPreferences.setHasSavedThread(true, transaction: transaction)
        }

        SSKEnvironment.shared.modelReadCachesRef.threadReadCache.didInsertOrUpdate(thread: self, transaction: transaction)
    }

    public var isNoteToSelf: Bool { false }

    public final var recipientAddressesWithSneakyTransaction: [SignalServiceAddress] {
        let databaseStorage = SSKEnvironment.shared.databaseStorageRef
        return databaseStorage.read { tx in self.recipientAddresses(with: tx) }
    }

    @objc
    public func recipientAddresses(with tx: DBReadTransaction) -> [SignalServiceAddress] {
        owsFail("abstract method")
    }

    public func hasSafetyNumbers() -> Bool { false }

    public func lastInteractionForInbox(forChatListSorting isForSorting: Bool, transaction tx: DBReadTransaction) -> TSInteraction? {
        return InteractionFinder(threadUniqueId: self.uniqueId).mostRecentInteractionForInbox(forChatListSorting: isForSorting, transaction: tx)
    }

    public func firstInteraction(atOrAroundSortId sortId: UInt64, transaction tx: DBReadTransaction) -> TSInteraction? {
        return InteractionFinder(threadUniqueId: self.uniqueId).firstInteraction(atOrAroundSortId: sortId, transaction: tx)
    }

    func merge(from otherThread: TSThread) {
        self.shouldThreadBeVisible = self.shouldThreadBeVisible || otherThread.shouldThreadBeVisible
        self.lastInteractionRowId = max(self.lastInteractionRowId, otherThread.lastInteractionRowId)

        // Copy the draft if this thread doesn't have one. We always assign both
        // values if we assign one of them since they're related.
        if self.messageDraft == nil {
            self.messageDraft = otherThread.messageDraft
            self.messageDraftBodyRanges = otherThread.messageDraftBodyRanges
            self.lastDraftInteractionRowId = otherThread.lastDraftInteractionRowId
            self.lastDraftUpdateTimestamp = otherThread.lastDraftUpdateTimestamp
        }
    }

    public typealias RowId = Int64

    public var logString: String {
        return (self as? TSGroupThread)?.groupId.toHex() ?? self.uniqueId
    }

    @objc
    public class func fetchViaCacheObjC(uniqueId: String, transaction: DBReadTransaction) -> TSThread? {
        return fetchViaCache(uniqueId: uniqueId, transaction: transaction)
    }

    public class func fetchViaCache(uniqueId: String, transaction: DBReadTransaction) -> Self? {
        let cache = SSKEnvironment.shared.modelReadCachesRef.threadReadCache
        guard let thread = cache.getThread(uniqueId: uniqueId, transaction: transaction) else {
            return nil
        }
        guard let typedThread = thread as? Self else {
            owsFailDebug("object has type \(type(of: thread)), not \(Self.self)")
            return nil
        }
        return typedThread
    }

    public var isMuted: Bool { mutedUntilTimestamp > Date.ows_millisecondTimestamp() }

    public var mutedUntilDate: Date? {
        guard mutedUntilTimestamp > 0 else { return nil }
        return Date(millisecondsSince1970: mutedUntilTimestamp)
    }

    public static var alwaysMutedTimestamp: UInt64 { UInt64(LLONG_MAX) }

    public func markAllAsRead(updateStorageService: Bool, transaction: DBWriteTransaction) {
        markAllAsRead(transaction: transaction)
        updateWith(isMarkedUnread: false, updateStorageService: updateStorageService, transaction: transaction)
    }

    private func markAllAsRead(transaction: DBWriteTransaction) {
        let hasPendingMessageRequest = hasPendingMessageRequest(transaction: transaction)
        let circumstance: OWSReceiptCircumstance = hasPendingMessageRequest
            ? .onThisDeviceWhilePendingMessageRequest
            : .onThisDevice

        let finder = InteractionFinder(threadUniqueId: uniqueId)
        var cursor = finder.fetchAllUnreadMessages(transaction: transaction)
        do {
            while let message = try cursor.next() {
                message.markAsRead(
                    atTimestamp: Date.ows_millisecondTimestamp(),
                    thread: self,
                    circumstance: circumstance,
                    shouldClearNotifications: true,
                    transaction: transaction,
                )
            }
        } catch {
            owsFailDebug("unexpected failure fetching unread messages: \(error)")
        }

        // Just to be defensive, we'll also check for unread messages.
        owsAssertDebug(finder.unreadCount(transaction: transaction) == 0)
    }

    // MARK: - updateWith...

    public func updateWithDraft(
        draftMessageBody: MessageBody?,
        replyInfo: ThreadReplyInfo?,
        editTargetTimestamp: UInt64?,
        transaction tx: DBWriteTransaction,
    ) {
        let mostRecentInteractionID = InteractionFinder.maxInteractionRowId(transaction: tx)

        anyUpdate(transaction: tx) { thread in
            thread.messageDraft = draftMessageBody?.text
            thread.messageDraftBodyRanges = draftMessageBody?.ranges
            thread.editTargetTimestamp = editTargetTimestamp

            if draftMessageBody?.text.nilIfEmpty == nil {
                // 0 makes these values effectively irrelevant since they will
                // be compared to the lastInteractionRowId, which will always be > 0.
                thread.lastDraftInteractionRowId = 0
                thread.lastDraftUpdateTimestamp = 0
            } else {
                thread.lastDraftInteractionRowId = mostRecentInteractionID
                thread.lastDraftUpdateTimestamp = Date().ows_millisecondsSince1970
                thread.shouldThreadBeVisible = true
            }
        }

        if let replyInfo {
            DependenciesBridge.shared.threadReplyInfoStore
                .save(replyInfo, for: uniqueId, tx: tx)
        } else {
            DependenciesBridge.shared.threadReplyInfoStore
                .remove(for: uniqueId, tx: tx)
        }
    }

    public func updateWithShouldNotifyForMentionsWhenMutedLegacy(
        _ shouldNotifyForMentionsWhenMutedLegacy: Bool,
        wasLocallyInitiated: Bool,
        transaction tx: DBWriteTransaction,
    ) {
        anyUpdate(transaction: tx) { thread in
            thread.shouldNotifyForMentionsWhenMutedLegacy = shouldNotifyForMentionsWhenMutedLegacy
        }

        if
            wasLocallyInitiated,
            let groupThread = self as? TSGroupThread,
            groupThread.isGroupV2Thread
        {
            SSKEnvironment.shared.storageServiceManagerRef.recordPendingUpdates(
                groupModel: groupThread.groupModel,
            )
        }
    }

    func updateWithShouldNotifyForRepliesWhenMuted(
        _ shouldNotifyForRepliesWhenMuted: Bool?,
        transaction tx: DBWriteTransaction,
    ) {
        anyUpdate(transaction: tx) { thread in
            thread.shouldNotifyForRepliesWhenMuted = shouldNotifyForRepliesWhenMuted
        }
    }

    func updateWithShouldNotifyForMentionsWhenMuted(
        _ shouldNotifyForMentionsWhenMuted: Bool?,
        transaction tx: DBWriteTransaction,
    ) {
        anyUpdate(transaction: tx) { thread in
            thread.shouldNotifyForMentionsWhenMuted = shouldNotifyForMentionsWhenMuted
        }
    }

    func updateWithShouldNotifyForCallsWhenMuted(
        _ shouldNotifyForCallsWhenMuted: Bool?,
        transaction tx: DBWriteTransaction,
    ) {
        anyUpdate(transaction: tx) { thread in
            thread.shouldNotifyForCallsWhenMuted = shouldNotifyForCallsWhenMuted
        }
    }

    /// Updates `shouldThreadBeVisible`.
    public func updateWithShouldThreadBeVisible(
        _ shouldThreadBeVisible: Bool,
        transaction tx: DBWriteTransaction,
    ) {
        anyUpdate(transaction: tx) { thread in
            thread.shouldThreadBeVisible = shouldThreadBeVisible
        }
    }

    public func updateWithLastSentStoryTimestamp(
        _ lastSentStoryTimestamp: UInt64,
        transaction tx: DBWriteTransaction,
    ) {
        anyUpdate(transaction: tx) { thread in
            if lastSentStoryTimestamp > thread.lastSentStoryTimestamp ?? 0 {
                thread.lastSentStoryTimestamp = lastSentStoryTimestamp
            }
        }
    }

    public func updateWith(
        isArchived: Bool? = nil,
        isMarkedUnread: Bool? = nil,
        mutedUntilTimestamp: UInt64? = nil,
        audioPlaybackRate: Float? = nil,
        updateStorageService: Bool,
        transaction: DBWriteTransaction,
    ) {
        guard
            isArchived != nil
            || isMarkedUnread != nil
            || mutedUntilTimestamp != nil
            || audioPlaybackRate != nil
        else {
            return
        }

        anyUpdate(transaction: transaction) {
            if let isArchived {
                $0.isArchived = isArchived
            }
            if let isMarkedUnread {
                $0.isMarkedUnread = isMarkedUnread
            }
            if let mutedUntilTimestamp {
                $0.mutedUntilTimestamp = mutedUntilTimestamp
            }
            if let audioPlaybackRate {
                $0.audioPlaybackRate = audioPlaybackRate
            }
        }

        if updateStorageService {
            recordPendingUpdates(storageServiceManager: SSKEnvironment.shared.storageServiceManagerRef)
        }
    }

    func recordPendingUpdates(storageServiceManager: any StorageServiceManager) {
        owsFailDebug("can't record updates for \(type(of: self))")
    }

    // MARK: -

    func updateWithInsertedInteraction(_ interaction: TSInteraction, tx: DBWriteTransaction) {
        updateWithInteraction(interaction, wasInteractionInserted: true, tx: tx)
    }

    func updateWithUpdatedInteraction(_ interaction: TSInteraction, tx: DBWriteTransaction) {
        updateWithInteraction(interaction, wasInteractionInserted: false, tx: tx)
    }

    private func updateWithInteraction(_ interaction: TSInteraction, wasInteractionInserted: Bool, tx: DBWriteTransaction) {
        let db = DependenciesBridge.shared.db

        let hasLastVisibleInteraction = hasLastVisibleInteraction(transaction: tx)
        let needsToClearLastVisibleSortId = hasLastVisibleInteraction && wasInteractionInserted

        if !interaction.shouldAppearInInbox(transaction: tx) {
            // We want to clear the last visible sort ID on any new message,
            // even if the message doesn't appear in the inbox view.
            if needsToClearLastVisibleSortId {
                clearLastVisibleInteraction(transaction: tx)
            }
            scheduleTouchFinalization(transaction: tx)
            return
        }

        let interactionRowId = UInt64(interaction.sqliteRowId ?? 0)
        let needsToMarkAsVisible = !shouldThreadBeVisible
        let needsToClearArchived = shouldClearArchivedStatusWhenUpdatingWithInteraction(
            interaction,
            wasInteractionInserted: wasInteractionInserted,
            tx: tx,
        )
        let needsToUpdateLastInteractionRowId = interactionRowId > lastInteractionRowId
        let needsToClearIsMarkedUnread = self.isMarkedUnread && wasInteractionInserted
        let needsUpdatedRowId = interaction.shouldBumpThreadToTopOfChatList(transaction: tx)

        if
            needsToMarkAsVisible
            || needsToClearArchived
            || needsToUpdateLastInteractionRowId
            || needsToClearLastVisibleSortId
            || needsToClearIsMarkedUnread
        {
            anyUpdate(transaction: tx) { thread in
                thread.shouldThreadBeVisible = true
                if needsUpdatedRowId {
                    thread.lastInteractionRowId = max(thread.lastInteractionRowId, interactionRowId)
                }
            }

            updateWith(
                isArchived: needsToClearArchived ? false : nil,
                isMarkedUnread: needsToClearIsMarkedUnread ? false : nil,
                updateStorageService: true,
                transaction: tx,
            )

            if needsToMarkAsVisible {
                // Non-visible threads don't get indexed, so if we're becoming
                // visible for the first time...
                db.touch(
                    thread: self,
                    shouldReindex: true,
                    shouldUpdateChatListUi: true,
                    tx: tx,
                )
            }

            if needsToClearLastVisibleSortId {
                clearLastVisibleInteraction(transaction: tx)
            }
        } else {
            scheduleTouchFinalization(transaction: tx)
        }
    }

    private func shouldClearArchivedStatusWhenUpdatingWithInteraction(
        _ interaction: TSInteraction,
        wasInteractionInserted: Bool,
        tx: DBReadTransaction,
    ) -> Bool {
        var needsToClearArchived = self.isArchived && wasInteractionInserted

        // I'm not sure, at the time I am migrating this to Swift, if this is
        // a load-bearing check of some sort. Perhaps in the future, we can
        // more confidently remove this.
        if
            !CurrentAppContext().isRunningTests,
            !AppReadinessObjcBridge.isAppReady
        {
            needsToClearArchived = false
        }

        if let infoMessage = interaction as? TSInfoMessage {
            switch infoMessage.messageType {
            case
                .syncedThread,
                .threadMerge:
                needsToClearArchived = false
            case
                .typeLocalUserEndedSession,
                .typeRemoteUserEndedSession,
                .userNotRegistered,
                .typeUnsupportedMessage,
                .typeGroupUpdate,
                .typeGroupQuit,
                .typeDisappearingMessagesUpdate,
                .addToContactsOffer,
                .verificationStateChange,
                .addUserToProfileWhitelistOffer,
                .addGroupToProfileWhitelistOffer,
                .unknownProtocolVersion,
                .userJoinedSignal,
                .profileUpdate,
                .phoneNumberChange,
                .recipientHidden,
                .paymentsActivationRequest,
                .paymentsActivated,
                .sessionSwitchover,
                .reportedSpam,
                .learnedProfileName,
                .blockedOtherUser,
                .blockedGroup,
                .unblockedOtherUser,
                .unblockedGroup,
                .acceptedMessageRequest,
                .typeEndPoll,
                .typePinnedMessage:
                break
            }
        }

        // Shouldn't clear archived if:
        // - The thread is muted.
        // - The user has requested we keep muted chats archived.
        // - The message was sent by someone other than the current user. (If the
        //   current user sent the message, we should clear archived.)
        let wasMessageSentByUs = interaction is TSOutgoingMessage
        if
            self.isMuted,
            SSKPreferences.shouldKeepMutedChatsArchived(transaction: tx),
            !wasMessageSentByUs
        {
            needsToClearArchived = false
        }

        return needsToClearArchived
    }

    // MARK: -

    public func updateWithRemovedInteraction(
        _ interaction: TSInteraction,
        tx: DBWriteTransaction,
    ) {
        let interactionRowId = interaction.sqliteRowId ?? 0
        let needsToUpdateLastInteractionRowId = interactionRowId == lastInteractionRowId

        let lastVisibleSortId = lastVisibleSortId(transaction: tx) ?? 0
        let needsToUpdateLastVisibleSortId = lastVisibleSortId > 0 && lastVisibleSortId == interactionRowId

        updateOnInteractionsRemoved(
            needsToUpdateLastInteractionRowId: needsToUpdateLastInteractionRowId,
            needsToUpdateLastVisibleSortId: needsToUpdateLastVisibleSortId,
            lastVisibleSortId: lastVisibleSortId,
            tx: tx,
        )
    }

    public func updateOnInteractionsRemoved(
        needsToUpdateLastInteractionRowId: Bool,
        needsToUpdateLastVisibleSortId: Bool,
        tx: DBWriteTransaction,
    ) {
        updateOnInteractionsRemoved(
            needsToUpdateLastInteractionRowId: needsToUpdateLastInteractionRowId,
            needsToUpdateLastVisibleSortId: needsToUpdateLastVisibleSortId,
            lastVisibleSortId: lastVisibleSortId(transaction: tx) ?? 0,
            tx: tx,
        )
    }

    private func updateOnInteractionsRemoved(
        needsToUpdateLastInteractionRowId: Bool,
        needsToUpdateLastVisibleSortId: Bool,
        lastVisibleSortId: UInt64,
        tx: DBWriteTransaction,
    ) {
        if needsToUpdateLastInteractionRowId || needsToUpdateLastVisibleSortId {
            anyUpdate(transaction: tx) { thread in
                if needsToUpdateLastInteractionRowId {
                    let lastInteraction = thread.lastInteractionForInbox(forChatListSorting: true, transaction: tx)
                    thread.lastInteractionRowId = lastInteraction?.sortId ?? 0
                }
            }

            if needsToUpdateLastVisibleSortId {
                if
                    let interactionBeforeRemovedInteraction = firstInteraction(
                        atOrAroundSortId: lastVisibleSortId,
                        transaction: tx,
                    )
                {
                    setLastVisibleInteraction(
                        sortId: interactionBeforeRemovedInteraction.sortId,
                        onScreenPercentage: 1.0,
                        transaction: tx,
                    )
                } else {
                    clearLastVisibleInteraction(transaction: tx)
                }
            }
        } else {
            scheduleTouchFinalization(transaction: tx)
        }
    }

    // MARK: -

    @objc
    func scheduleTouchFinalization(transaction tx: DBWriteTransaction) {
        tx.addFinalizationBlock(key: uniqueId) { tx in
            let databaseStorage = SSKEnvironment.shared.databaseStorageRef

            guard let selfThread = Self.fetchViaCache(uniqueId: self.uniqueId, transaction: tx) else {
                return
            }

            databaseStorage.touch(thread: selfThread, shouldReindex: false, tx: tx)
        }
    }

    public func canUserEditPinnedMessages(aci: Aci, tx: DBReadTransaction) -> Bool {
        guard !hasPendingMessageRequest(transaction: tx) else {
            return false
        }

        guard
            let groupThread = self as? TSGroupThread
        else {
            // Not a group thread, so no additional access to check.
            return true
        }

        guard
            groupThread.groupModel.groupMembership.isFullMember(aci),
            let groupModel = groupThread.groupModel as? TSGroupModelV2
        else {
            return false
        }

        // Admins are good to pin.
        if groupModel.groupMembership.isFullMemberAndAdministrator(aci) {
            return true
        }

        // User is not an admin. Can't pin if its announcements-only group, or edit group is admin only.
        return groupModel.access.attributes != .administrator && !groupModel.isAnnouncementsOnly
    }
}

// MARK: - StringInterpolation

public extension String.StringInterpolation {
    mutating func appendInterpolation(threadColumn column: TSThread.CodingKeys) {
        appendLiteral(column.rawValue)
    }

    mutating func appendInterpolation(threadColumnFullyQualified column: TSThread.CodingKeys) {
        appendLiteral("\(TSThread.databaseTableName).\(column.rawValue)")
    }
}
