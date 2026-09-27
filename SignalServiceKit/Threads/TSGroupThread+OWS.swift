//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

extension TSGroupThread {

    public var groupId: Data { groupModel.groupId }

    @objc
    public var groupMembership: GroupMembership {
        groupModel.groupMembership
    }

    // MARK: -

    static let groupThreadUniqueIdPrefix = "g"

    /// Returns the uniqueId for the ``TSGroupThread`` with the given group ID.
    public static func threadUniqueId(forGroupIdData groupIdData: Data, tx: DBReadTransaction) -> String? {
        owsAssertDebug(!groupIdData.isEmpty)

        let threadId = GroupStore().fetchThreadId(forGroupIdData: groupIdData, tx: tx)
        guard let threadId else {
            return nil
        }

        return threadUniqueId(forThreadId: threadId, tx: tx)
    }

    public static func threadUniqueId(forThreadId threadId: TSThread.RowId, tx: DBReadTransaction) -> String? {
        let fetchQuery = TSGroupThread
            .filter(key: threadId)
            .select(TSThread.Columns.uniqueId, as: TSThread.UniqueId.self)

        return failIfThrows { try fetchQuery.fetchOne(tx.database) }
    }

    static func defaultThreadUniqueId(forGroupIdData groupIdData: Data) -> String {
        owsAssertDebug(!groupIdData.isEmpty)
        return groupThreadUniqueIdPrefix + groupIdData.base64EncodedString()
    }

    // MARK: -

    /// Posted when the group associated with this thread adds or removes members.
    ///
    /// The object is the group's unique ID as a string. Note that NotificationCenter dispatches by
    /// object identity rather than equality, so any observer should register for *all* membership
    /// changes and then filter the notifications they receive as needed.
    public static let membershipDidChange = Notification.Name("TSGroupThread.membershipDidChange")

    public func updateGroupMemberRecords(transaction: DBWriteTransaction) {
        let groupMemberUpdater = DependenciesBridge.shared.groupMemberUpdater
        groupMemberUpdater.updateRecords(
            groupThreadUniqueId: self.uniqueId,
            groupMembership: self.groupMembership,
            transaction: transaction,
        )
    }
}

// MARK: -

extension TSThread {
    public var isLocalUserFullMemberOfThread: Bool {
        guard let groupThread = self as? TSGroupThread else {
            return true
        }
        return groupThread.groupModel.groupMembership.isLocalUserFullMember
    }

    public var isTerminatedGroup: Bool {
        guard
            let groupThread = self as? TSGroupThread,
            let groupModelV2 = groupThread.groupModel as? TSGroupModelV2
        else {
            return false
        }
        return groupModelV2.isTerminated
    }
}
