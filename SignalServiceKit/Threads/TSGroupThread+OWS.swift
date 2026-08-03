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

    public static let groupThreadUniqueIdPrefix = "g"

    private static let uniqueIdMappingStore = NewKeyValueStore(collection: "TSGroupThread.uniqueIdMappingStore")

    private static func mappingKey(forGroupId groupId: Data) -> String {
        groupId.hexadecimalString
    }

    private static func existingThreadUniqueId(forGroupId groupId: Data, tx: DBReadTransaction) -> String? {
        owsAssertDebug(!groupId.isEmpty)

        let mappingKey = self.mappingKey(forGroupId: groupId)
        return uniqueIdMappingStore.fetchValue(String.self, forKey: mappingKey, tx: tx)
    }

    /// Returns the uniqueId for the ``TSGroupThread`` with the given group ID.
    public static func threadUniqueId(forGroupId groupId: Data, tx: DBReadTransaction) -> String? {
        owsAssertDebug(!groupId.isEmpty)

        let threadUniqueId = existingThreadUniqueId(forGroupId: groupId, tx: tx) ?? defaultThreadUniqueId(forGroupId: groupId)

        guard SDSCodableModelDatabaseInterface().fetchRowId(modelType: TSThread.self, uniqueId: threadUniqueId, tx: tx) != nil else {
            return nil
        }

        return threadUniqueId
    }

    static func defaultThreadUniqueId(forGroupId groupId: Data) -> String {
        owsAssertDebug(!groupId.isEmpty)

        return groupThreadUniqueIdPrefix + groupId.base64EncodedString()
    }

    /// Sets a `[GroupId: ThreadUniqueId]` mapping.
    ///
    /// - SeeAlso ``threadId(forGroupId:transaction:)``
    public static func setUniqueId(
        _ threadUniqueId: String,
        forGroupId groupId: Data,
        tx: DBWriteTransaction,
    ) {
        _setUniqueId(threadUniqueId, forGroupId: groupId, tx: tx)

        if GroupManager.isV1GroupId(groupId) {
            do {
                let v2GroupId = try self.v2GroupId(forV1GroupId: groupId)
                _setUniqueId(threadUniqueId, forGroupId: v2GroupId, tx: tx)
            } catch {
                Logger.warn("Couldn't set GV2 mapping for legacy thread")
            }
        }
    }

    private static func v2GroupId(forV1GroupId v1GroupId: Data) throws -> Data {
        owsPrecondition(GroupManager.isV1GroupId(v1GroupId))

        let keyBytes = try hkdf(
            outputLength: GroupMasterKey.SIZE,
            inputKeyMaterial: v1GroupId,
            salt: [],
            info: Data("GV2 Migration".utf8),
        )

        let contextInfo = try GroupV2ContextInfo.deriveFrom(masterKeyData: keyBytes)
        return contextInfo.groupId.serialize()
    }

    private static func _setUniqueId(
        _ threadUniqueId: String,
        forGroupId groupId: Data,
        tx: DBWriteTransaction,
    ) {
        let mappingKey = mappingKey(forGroupId: groupId)
        uniqueIdMappingStore.writeValue(threadUniqueId, forKey: mappingKey, tx: tx)
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

    func removeGroupMemberRecords(transaction: DBWriteTransaction) {
        let groupMemberUpdater = DependenciesBridge.shared.groupMemberUpdater
        groupMemberUpdater.updateRecords(
            groupThreadUniqueId: self.uniqueId,
            groupMembership: .empty,
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
