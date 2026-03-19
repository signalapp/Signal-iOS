//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import GRDB
public import LibSignalClient

public enum TSThreadMentionNotificationMode: UInt {
    case `default` = 0
    case always = 1
    case never = 2
}

public enum TSThreadStoryViewMode: UInt {
    case `default` = 0
    case explicit = 1
    case blockList = 2
    case disabled = 3
}

@objc
open class TSThread: NSObject, SDSCodableModel, InheritableRecord {
    public static let databaseTableName: String = "model_TSThread"
    public class var recordType: SDSRecordType { .thread }

    static func concreteType(forRecordType recordType: UInt) -> (any InheritableRecord.Type)? {
        switch recordType {
        case SDSRecordType.thread.rawValue: TSThread.self
        case SDSRecordType.contactThread.rawValue: TSContactThread.self
        case SDSRecordType.groupThread.rawValue: TSGroupThread.self
        case SDSRecordType.privateStoryThread.rawValue: TSPrivateStoryThread.self
        default: nil
        }
    }

    public var id: Int64?
    public var sqliteRowId: Int64? { self.id }

    @objc
    public let uniqueId: String

    public let creationDate: Date?
    public let isArchivedObsolete: Bool
    // zero if thread has never had an interaction.
    // The corresponding interaction may have been deleted.
    public internal(set) var lastInteractionRowId: UInt64
    public internal(set) var messageDraft: String?
    public internal(set) var shouldThreadBeVisible: Bool
    public let isMarkedUnreadObsolete: Bool
    public private(set) var messageDraftBodyRanges: MessageBodyRanges?
    public private(set) var mentionNotificationMode: TSThreadMentionNotificationMode
    public let mutedUntilTimestampObsolete: UInt64
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

    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case id
        case recordType
        case uniqueId

        case conversationColorNameObsolete = "conversationColorName"
        case creationDate
        case editTargetTimestamp
        case isArchivedObsolete = "isArchived"
        case isMarkedUnreadObsolete = "isMarkedUnread"
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
        case mutedUntilTimestampObsolete = "mutedUntilTimestamp"
        case shouldThreadBeVisible
        case storyViewMode
    }

    public required init(inheritableDecoder decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(Int64.self, forKey: .id)
        self.uniqueId = try container.decode(String.self, forKey: .uniqueId)
        self.creationDate = try container.decodeIfPresent(TimeInterval.self, forKey: .creationDate).map(Date.init(timeIntervalSince1970:))
        self.editTargetTimestamp = try container.decodeIfPresent(UInt64.self, forKey: .editTargetTimestamp)
        self.isArchivedObsolete = try container.decode(Bool.self, forKey: .isArchivedObsolete)
        self.isMarkedUnreadObsolete = try container.decode(Bool.self, forKey: .isMarkedUnreadObsolete)
        self.lastDraftInteractionRowId = try container.decode(UInt64.self, forKey: .lastDraftInteractionRowId)
        self.lastDraftUpdateTimestamp = try container.decode(UInt64.self, forKey: .lastDraftUpdateTimestamp)
        self.lastInteractionRowId = try container.decode(UInt64.self, forKey: .lastInteractionRowId)
        self.lastSentStoryTimestamp = try container.decodeIfPresent(UInt64.self, forKey: .lastSentStoryTimestamp)
        self.mentionNotificationMode = TSThreadMentionNotificationMode(rawValue: try container.decode(UInt.self, forKey: .mentionNotificationMode)) ?? .default
        self.messageDraft = try container.decodeIfPresent(String.self, forKey: .messageDraft)
        self.messageDraftBodyRanges = try container.decodeIfPresent(Data.self, forKey: .messageDraftBodyRanges).map({ try LegacySDSSerializer().deserializeLegacySDSData($0, ofClass: MessageBodyRanges.self) })
        self.mutedUntilTimestampObsolete = try container.decode(UInt64.self, forKey: .mutedUntilTimestampObsolete)
        self.shouldThreadBeVisible = try container.decode(Bool.self, forKey: .shouldThreadBeVisible)
        self.storyViewMode = TSThreadStoryViewMode(rawValue: try container.decode(UInt.self, forKey: .storyViewMode)) ?? .default
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.id, forKey: .id)
        try container.encode(Self.recordType.rawValue, forKey: .recordType)
        try container.encode(self.uniqueId, forKey: .uniqueId)
        try container.encode("", forKey: .conversationColorNameObsolete)
        try container.encode(self.creationDate?.timeIntervalSince1970, forKey: .creationDate)
        try container.encode(self.editTargetTimestamp, forKey: .editTargetTimestamp)
        try container.encode(self.isArchivedObsolete, forKey: .isArchivedObsolete)
        try container.encode(self.lastDraftInteractionRowId, forKey: .lastDraftInteractionRowId)
        try container.encode(self.lastDraftUpdateTimestamp, forKey: .lastDraftUpdateTimestamp)
        try container.encode(self.lastInteractionRowId, forKey: .lastInteractionRowId)
        try container.encode(self.lastSentStoryTimestamp, forKey: .lastSentStoryTimestamp)
        try container.encode(0 as UInt64, forKey: .lastVisibleSortIdObsolete)
        try container.encode(0 as Double, forKey: .lastVisibleSortIdOnScreenPercentageObsolete)
        try container.encode(self.mentionNotificationMode.rawValue, forKey: .mentionNotificationMode)
        try container.encode(self.messageDraft, forKey: .messageDraft)
        let messageDraftBodyRangesData = self.messageDraftBodyRanges.map(LegacySDSSerializer().serializeAsLegacySDSData(_:))
        try container.encode(messageDraftBodyRangesData, forKey: .messageDraftBodyRanges)
        try container.encode(nil as Date?, forKey: .mutedUntilDateObsolete)
        try container.encode(self.mutedUntilTimestampObsolete, forKey: .mutedUntilTimestampObsolete)
        try container.encode(self.shouldThreadBeVisible, forKey: .shouldThreadBeVisible)
        try container.encode(self.storyViewMode.rawValue, forKey: .storyViewMode)
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
    ) {
        self.id = id
        self.uniqueId = uniqueId
        self.creationDate = creationDate
        self.editTargetTimestamp = editTargetTimestamp
        self.isArchivedObsolete = isArchivedObsolete
        self.isMarkedUnreadObsolete = isMarkedUnreadObsolete
        self.lastDraftInteractionRowId = lastDraftInteractionRowId
        self.lastDraftUpdateTimestamp = lastDraftUpdateTimestamp
        self.lastInteractionRowId = lastInteractionRowId
        self.lastSentStoryTimestamp = lastSentStoryTimestamp
        self.mentionNotificationMode = mentionNotificationMode
        self.messageDraft = messageDraft
        self.messageDraftBodyRanges = messageDraftBodyRanges
        self.mutedUntilTimestampObsolete = mutedUntilTimestampObsolete
        self.shouldThreadBeVisible = shouldThreadBeVisible
        self.storyViewMode = storyViewMode
    }

    init(uniqueId: String) {
        self.isArchivedObsolete = false
        self.isMarkedUnreadObsolete = false
        self.lastDraftInteractionRowId = 0
        self.lastDraftUpdateTimestamp = 0
        self.lastInteractionRowId = 0
        self.mentionNotificationMode = .default
        self.messageDraft = nil
        self.mutedUntilTimestampObsolete = 0
        self.shouldThreadBeVisible = false
        self.storyViewMode = .default

        self.uniqueId = uniqueId
        self.creationDate = Date()
    }

    func deepCopy() -> TSThread {
        return TSThread(
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
        )
    }

    override public var hash: Int {
        var hasher = Hasher()
        hasher.combine(self.id)
        hasher.combine(self.uniqueId)
        hasher.combine(self.creationDate)
        hasher.combine(self.editTargetTimestamp)
        hasher.combine(self.isArchivedObsolete)
        hasher.combine(self.isMarkedUnreadObsolete)
        hasher.combine(self.lastDraftInteractionRowId)
        hasher.combine(self.lastDraftUpdateTimestamp)
        hasher.combine(self.lastInteractionRowId)
        hasher.combine(self.lastSentStoryTimestamp)
        hasher.combine(self.mentionNotificationMode)
        hasher.combine(self.messageDraft)
        hasher.combine(self.messageDraftBodyRanges)
        hasher.combine(self.mutedUntilTimestampObsolete)
        hasher.combine(self.shouldThreadBeVisible)
        hasher.combine(self.storyViewMode)
        return hasher.finalize()
    }

    override public func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard self.id == object.id else { return false }
        guard self.uniqueId == object.uniqueId else { return false }
        guard self.creationDate == object.creationDate else { return false }
        guard self.editTargetTimestamp == object.editTargetTimestamp else { return false }
        guard self.isArchivedObsolete == object.isArchivedObsolete else { return false }
        guard self.isMarkedUnreadObsolete == object.isMarkedUnreadObsolete else { return false }
        guard self.lastDraftInteractionRowId == object.lastDraftInteractionRowId else { return false }
        guard self.lastDraftUpdateTimestamp == object.lastDraftUpdateTimestamp else { return false }
        guard self.lastInteractionRowId == object.lastInteractionRowId else { return false }
        guard self.lastSentStoryTimestamp == object.lastSentStoryTimestamp else { return false }
        guard self.mentionNotificationMode == object.mentionNotificationMode else { return false }
        guard self.messageDraft == object.messageDraft else { return false }
        guard self.messageDraftBodyRanges == object.messageDraftBodyRanges else { return false }
        guard self.mutedUntilTimestampObsolete == object.mutedUntilTimestampObsolete else { return false }
        guard self.shouldThreadBeVisible == object.shouldThreadBeVisible else { return false }
        guard self.storyViewMode == object.storyViewMode else { return false }
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
        ThreadAssociatedData.create(for: self.uniqueId, transaction: transaction)

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

        DependenciesBridge.shared.pinnedThreadManager.handleUpdatedThread(self, tx: transaction)
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

    public func updateWithMentionNotificationMode(
        _ mentionNotificationMode: TSThreadMentionNotificationMode,
        wasLocallyInitiated: Bool,
        transaction tx: DBWriteTransaction,
    ) {
        anyUpdate(transaction: tx) { thread in
            thread.mentionNotificationMode = mentionNotificationMode
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

    /// Updates `shouldThreadBeVisible`.
    public func updateWithShouldThreadBeVisible(
        _ shouldThreadBeVisible: Bool,
        transaction tx: DBWriteTransaction,
    ) {
        anyUpdate(transaction: tx) { thread in
            thread.shouldThreadBeVisible = true
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
        let threadAssociatedData = ThreadAssociatedData.fetchOrDefault(for: self, transaction: tx)
        let needsToClearArchived = shouldClearArchivedStatusWhenUpdatingWithInteraction(
            interaction,
            wasInteractionInserted: wasInteractionInserted,
            threadAssociatedData: threadAssociatedData,
            tx: tx,
        )
        let needsToUpdateLastInteractionRowId = interactionRowId > lastInteractionRowId
        let needsToClearIsMarkedUnread = threadAssociatedData.isMarkedUnread && wasInteractionInserted
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

            threadAssociatedData.clear(
                isArchived: needsToClearArchived,
                isMarkedUnread: needsToClearIsMarkedUnread,
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
        threadAssociatedData: ThreadAssociatedData,
        tx: DBReadTransaction,
    ) -> Bool {
        var needsToClearArchived = threadAssociatedData.isArchived && wasInteractionInserted

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
            threadAssociatedData.isMuted,
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
