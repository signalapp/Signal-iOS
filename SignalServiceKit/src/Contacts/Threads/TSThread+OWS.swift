//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
public extension TSThread {

    var isGroupThread: Bool {
        self is TSGroupThread
    }

    var isNonContactThread: Bool {
        !(self is TSContactThread)
    }

    var usesSenderKey: Bool {
        self is TSGroupThread || self is TSPrivateStoryThread
    }

    var isGroupV1Thread: Bool {
        guard let groupThread = self as? TSGroupThread else {
            return false
        }
        return groupThread.groupModel.groupsVersion == .V1
    }

    var isGroupV2Thread: Bool {
        guard let groupThread = self as? TSGroupThread else {
            return false
        }
        return groupThread.groupModel.groupsVersion == .V2
    }

    var groupModelIfGroupThread: TSGroupModel? {
        guard let groupThread = self as? TSGroupThread else {
            return nil
        }
        return groupThread.groupModel
    }

    var isBlockedByMigration: Bool {
        isGroupV1Thread
    }

    var canSendReactionToThread: Bool {
        guard !isBlockedByMigration else {
            return false
        }
        return true
    }

    var canSendNonChatMessagesToThread: Bool {
        guard !isBlockedByMigration else {
            return false
        }
        return true
    }

    @available(swift, obsoleted: 1.0)
    func canSendChatMessagesToThread() -> Bool {
        canSendChatMessagesToThread(ignoreAnnouncementOnly: false)
    }

    func canSendChatMessagesToThread(ignoreAnnouncementOnly: Bool = false) -> Bool {
        guard !isBlockedByMigration else {
            return false
        }
        if !ignoreAnnouncementOnly {
            guard !isBlockedByAnnouncementOnly else {
                return false
            }
        }
        if let groupThread = self as? TSGroupThread {
            guard groupThread.isLocalUserFullMember else {
                return false
            }
        }
        return true
    }

    var isBlockedByAnnouncementOnly: Bool {
        guard let groupThread = self as? TSGroupThread else {
            return false
        }
        guard let groupModel = groupThread.groupModel as? TSGroupModelV2 else {
            return false
        }
        // In "announcement-only" groups, only admins can send messages and start group calls.
        return (groupModel.isAnnouncementsOnly &&
                    !groupModel.groupMembership.isLocalUserFullMemberAndAdministrator)
    }

    var isAnnouncementOnlyGroupThread: Bool {
        guard let groupThread = self as? TSGroupThread else {
            return false
        }
        guard let groupModel = groupThread.groupModel as? TSGroupModelV2 else {
            return false
        }
        return groupModel.isAnnouncementsOnly
    }
}

// MARK: -

public extension TSThread {

    struct LastVisibleInteraction: Codable, Equatable {
        public let sortId: UInt64
        public let onScreenPercentage: CGFloat

        public init(sortId: UInt64, onScreenPercentage: CGFloat) {
            self.sortId = sortId
            self.onScreenPercentage = onScreenPercentage
        }
    }

    private static let lastVisibleInteractionStore = SDSKeyValueStore(collection: "lastVisibleInteractionStore")

    @objc
    func hasLastVisibleInteraction(transaction: SDSAnyReadTransaction) -> Bool {
        nil != Self.lastVisibleInteraction(forThread: self, transaction: transaction)
    }

    @objc
    func lastVisibleSortId(transaction: SDSAnyReadTransaction) -> NSNumber? {
        guard let lastVisibleInteraction = lastVisibleInteraction(transaction: transaction) else {
            return nil
        }
        return NSNumber(value: lastVisibleInteraction.sortId)
    }

    func lastVisibleInteraction(transaction: SDSAnyReadTransaction) -> LastVisibleInteraction? {
        Self.lastVisibleInteraction(forThread: self, transaction: transaction)
    }

    static func lastVisibleInteraction(forThread thread: TSThread,
                                       transaction: SDSAnyReadTransaction) -> LastVisibleInteraction? {
        guard let data = lastVisibleInteractionStore.getData(thread.uniqueId, transaction: transaction) else {
            return nil
        }
        do {
            return try JSONDecoder().decode(LastVisibleInteraction.self, from: data)
        } catch {
            owsFailDebug("Error: \(error)")
            return nil
        }
    }

    @objc
    func clearLastVisibleInteraction(transaction: SDSAnyWriteTransaction) {
        Self.setLastVisibleInteraction(nil, forThread: self, transaction: transaction)
    }

    @objc
    func setLastVisibleInteraction(sortId: UInt64,
                                   onScreenPercentage: CGFloat,
                                   transaction: SDSAnyWriteTransaction) {
        let lastVisibleInteraction = LastVisibleInteraction(sortId: sortId, onScreenPercentage: onScreenPercentage)
        Self.setLastVisibleInteraction(lastVisibleInteraction, forThread: self, transaction: transaction)
    }

    func setLastVisibleInteraction(_ lastVisibleInteraction: LastVisibleInteraction?,
                                   transaction: SDSAnyWriteTransaction) {
        Self.setLastVisibleInteraction(lastVisibleInteraction, forThread: self, transaction: transaction)
    }

    static func setLastVisibleInteraction(_ lastVisibleInteraction: LastVisibleInteraction?,
                                          forThread thread: TSThread,
                                          transaction: SDSAnyWriteTransaction) {
        guard let lastVisibleInteraction = lastVisibleInteraction else {
            lastVisibleInteractionStore.removeValue(forKey: thread.uniqueId, transaction: transaction)
            return
        }
        let data: Data
        do {
            data = try JSONEncoder().encode(lastVisibleInteraction)
        } catch {
            owsFailDebug("Error: \(error)")
            lastVisibleInteractionStore.removeValue(forKey: thread.uniqueId, transaction: transaction)
            return
        }
        lastVisibleInteractionStore.setData(data, key: thread.uniqueId, transaction: transaction)
    }

    @available(swift, obsoleted: 1.0)
    @objc
    func numberOfInteractions(transaction: SDSAnyReadTransaction) -> UInt {
        numberOfInteractions(transaction: transaction)
    }

    func numberOfInteractions(
        with storyReplyQueryMode: StoryReplyQueryMode = .excludeGroupReplies,
        transaction: SDSAnyReadTransaction
    ) -> UInt {
        InteractionFinder(threadUniqueId: uniqueId).count(
            excludingPlaceholders: true,
            storyReplyQueryMode: storyReplyQueryMode,
            transaction: transaction
        )
    }
}

// MARK: - Drafts

extension TSThread {

    @objc
    public func currentDraft(transaction: SDSAnyReadTransaction) -> MessageBody? {
        currentDraft(shouldFetchLatest: true, transaction: transaction)
    }

    @objc
    public func currentDraft(shouldFetchLatest: Bool,
                             transaction: SDSAnyReadTransaction) -> MessageBody? {
        if shouldFetchLatest {
            guard let thread = TSThread.anyFetch(uniqueId: uniqueId, transaction: transaction) else {
                return nil
            }
            return Self.draft(forThread: thread)
        } else {
            return Self.draft(forThread: self)
        }
    }

    private static func draft(forThread thread: TSThread) -> MessageBody? {
        guard let messageDraft = thread.messageDraft else {
            return nil
        }
        let ranges: MessageBodyRanges = thread.messageDraftBodyRanges ?? .empty
        return MessageBody(text: messageDraft, ranges: ranges)
    }
}

// MARK: - Drafts

extension TSContactThread {
    @objc
    public var addressComponentsDescription: String {
        SignalServiceAddress.addressComponentsDescription(uuidString: contactUUID,
                                                          phoneNumber: contactPhoneNumber)
    }
}
