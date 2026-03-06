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

    var canSendReactionToThread: Bool {
        return !isGroupV1Thread
    }

    func canSendChatMessagesToThread(ignoreAnnouncementOnly: Bool = false) -> Bool {
        guard !isGroupV1Thread else {
            return false
        }
        if !ignoreAnnouncementOnly {
            guard !isBlockedByAnnouncementOnly else {
                return false
            }
        }
        if let groupThread = self as? TSGroupThread {
            guard groupThread.groupModel.groupMembership.isLocalUserFullMember else {
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
        return groupModel.isAnnouncementsOnly && !groupModel.groupMembership.isLocalUserFullMemberAndAdministrator
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

    func hasPendingMessageRequest(transaction: DBReadTransaction) -> Bool {
        return ThreadFinder().hasPendingMessageRequest(thread: self, transaction: transaction)
    }

    @nonobjc
    func isSystemContact(contactsManager: ContactManager, tx: DBReadTransaction) -> Bool {
        guard let contactThread = self as? TSContactThread else { return false }
        return contactsManager.fetchSignalAccount(for: contactThread.contactAddress, transaction: tx) != nil
    }

    // MARK: - Database Hooks

    internal func _anyDidInsert(tx: DBWriteTransaction) {
        let searchableNameIndexer = DependenciesBridge.shared.searchableNameIndexer
        searchableNameIndexer.insert(self, tx: tx)
    }
}

// MARK: - Drafts

extension TSThread {

    @objc
    public func currentDraft(transaction: DBReadTransaction) -> MessageBody? {
        currentDraft(shouldFetchLatest: true, transaction: transaction)
    }

    @objc
    public func currentDraft(
        shouldFetchLatest: Bool,
        transaction: DBReadTransaction,
    ) -> MessageBody? {
        if shouldFetchLatest {
            guard let thread = TSThread.fetchViaCache(uniqueId: uniqueId, transaction: transaction) else {
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

    @objc
    public func editTarget(transaction: DBReadTransaction) -> TSOutgoingMessage? {
        guard
            let editTargetTimestamp,
            let localAddress = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: transaction)?.aciAddress
        else {
            return nil
        }
        return InteractionFinder.findMessage(
            withTimestamp: editTargetTimestamp,
            threadId: uniqueId,
            author: localAddress,
            transaction: transaction,
        ) as? TSOutgoingMessage
    }
}
