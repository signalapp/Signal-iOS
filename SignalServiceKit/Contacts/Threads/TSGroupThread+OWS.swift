//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

@objc
public extension TSGroupThread {

    var groupId: Data { groupModel.groupId }

    var groupMembership: GroupMembership {
        groupModel.groupMembership
    }

    var isLocalUserMemberOfAnyKind: Bool {
        groupMembership.isLocalUserMemberOfAnyKind
    }

    var isLocalUserFullMember: Bool {
        groupMembership.isLocalUserFullMember
    }

    var isLocalUserInvitedMember: Bool {
        groupMembership.isLocalUserInvitedMember
    }

    var isLocalUserRequestingMember: Bool {
        groupMembership.isLocalUserRequestingMember
    }

    var isLocalUserFullOrInvitedMember: Bool {
        groupMembership.isLocalUserFullOrInvitedMember
    }

    var isLocalUserFullMemberAndAdministrator: Bool {
        groupMembership.isLocalUserFullMemberAndAdministrator
    }

    // MARK: -

    static let groupThreadUniqueIdPrefix = "g"

    @nonobjc
    private static let uniqueIdMappingStore = KeyValueStore(collection: "TSGroupThread.uniqueIdMappingStore")

    private static func mappingKey(forGroupId groupId: Data) -> String {
        groupId.hexadecimalString
    }

    private static func existingThreadId(forGroupId groupId: Data,
                                         transaction: SDSAnyReadTransaction) -> String? {
        owsAssertDebug(!groupId.isEmpty)

        let mappingKey = self.mappingKey(forGroupId: groupId)
        return uniqueIdMappingStore.getString(mappingKey, transaction: transaction.asV2Read)
    }

    /// Returns the uniqueId for the ``TSGroupThread`` with the given group ID,
    /// if one exists.
    ///
    /// We've historically stored a mapping of `[GroupId: ThreadUniqueId]`,
    /// which facilitated things like V1 -> V2 migration. We'll still check the
    /// mapping to find the correct unique ID for old threads who had an entry
    /// there, but for new threads going forward we'll deterministically derive
    /// a unique ID from the group ID.
    ///
    /// We've actually been doing a deterministic unique ID derivation for new
    /// threads for some time; we'd then also store that mapping, which is not
    /// necessary.
    static func threadId(
        forGroupId groupId: Data,
        transaction tx: SDSAnyReadTransaction
    ) -> String {
        owsAssertDebug(!groupId.isEmpty)

        if let threadUniqueId = existingThreadId(
            forGroupId: groupId, transaction: tx
        ) {
            return threadUniqueId
        }

        return defaultThreadId(forGroupId: groupId)
    }

    static func defaultThreadId(forGroupId groupId: Data) -> String {
        owsAssertDebug(!groupId.isEmpty)

        return groupThreadUniqueIdPrefix + groupId.base64EncodedString()
    }

    /// Sets a `[GroupId: ThreadUniqueId]` mapping for a legacy thread.
    ///
    /// All newly-created threads use a deterministic mapping from group ID to
    /// thread unique ID, so this is unnecessary except for legacy threads for
    /// whom the mapping does not exist.
    ///
    /// - SeeAlso ``threadId(forGroupId:transaction:)``
    static func setGroupIdMappingForLegacyThread(
        threadUniqueId: String,
        groupId: Data,
        tx: SDSAnyWriteTransaction
    ) {
        setGroupIdMapping(threadUniqueId: threadUniqueId, groupId: groupId, tx: tx)

        if GroupManager.isV1GroupId(groupId) {
            do {
                let v2GroupId = try self.v2GroupId(forV1GroupId: groupId)
                setGroupIdMapping(threadUniqueId: threadUniqueId, groupId: v2GroupId, tx: tx)
            } catch {
                Logger.warn("Couldn't set GV2 mapping for legacy thread")
            }
        }
    }

    private static func v2GroupId(forV1GroupId v1GroupId: Data) throws -> Data {
        owsPrecondition(GroupManager.isV1GroupId(v1GroupId))

        let infoString = "GV2 Migration"
        guard let keyBytes = try infoString.utf8.withContiguousStorageIfAvailable({ ptr in
            try hkdf(
                outputLength: GroupMasterKey.SIZE,
                inputKeyMaterial: v1GroupId,
                salt: [],
                info: ptr
            )
        }) else {
            owsFail("Failed to compute key bytes!")
        }

        let contextInfo = try GroupV2ContextInfo.deriveFrom(masterKeyData: Data(keyBytes))
        return contextInfo.groupId
    }

    private static func setGroupIdMapping(
        threadUniqueId: String,
        groupId: Data,
        tx: SDSAnyWriteTransaction
    ) {
        let mappingKey = mappingKey(forGroupId: groupId)
        uniqueIdMappingStore.setString(threadUniqueId, key: mappingKey, transaction: tx.asV2Write)
    }

    // MARK: -

    /// Posted when the group associated with this thread adds or removes members.
    ///
    /// The object is the group's unique ID as a string. Note that NotificationCenter dispatches by
    /// object identity rather than equality, so any observer should register for *all* membership
    /// changes and then filter the notifications they receive as needed.
    static let membershipDidChange = Notification.Name("TSGroupThread.membershipDidChange")

    func updateGroupMemberRecords(transaction: SDSAnyWriteTransaction) {
        let groupMemberUpdater = DependenciesBridge.shared.groupMemberUpdater
        groupMemberUpdater.updateRecords(groupThread: self, transaction: transaction.asV2Write)
    }

}

// MARK: -

@objc
public extension TSThread {
    var isLocalUserFullMemberOfThread: Bool {
        guard let groupThread = self as? TSGroupThread else {
            return true
        }
        return groupThread.groupMembership.isLocalUserFullMember
    }
}
