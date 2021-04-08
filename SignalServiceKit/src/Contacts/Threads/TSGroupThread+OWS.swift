//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

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

    private static let groupThreadUniqueIdPrefix = "g"

    private static let uniqueIdMappingStore = SDSKeyValueStore(collection: "TSGroupThread.uniqueIdMappingStore")

    private static func mappingKey(forGroupId groupId: Data) -> String {
        groupId.hexadecimalString
    }

    private static func existingThreadId(forGroupId groupId: Data,
                                         transaction: SDSAnyReadTransaction) -> String? {
        owsAssertDebug(!groupId.isEmpty)

        let mappingKey = self.mappingKey(forGroupId: groupId)
        return uniqueIdMappingStore.getString(mappingKey, transaction: transaction)
    }

    static func threadId(forGroupId groupId: Data,
                         transaction: SDSAnyReadTransaction) -> String {
        owsAssertDebug(!groupId.isEmpty)

        if let threadUniqueId = existingThreadId(forGroupId: groupId, transaction: transaction) {
            return threadUniqueId
        }

        return defaultThreadId(forGroupId: groupId)
    }

    static func defaultThreadId(forGroupId groupId: Data) -> String {
        owsAssertDebug(!groupId.isEmpty)

        return groupThreadUniqueIdPrefix + groupId.base64EncodedString()
    }

    private static func setThreadId(_ threadUniqueId: String,
                                    forGroupId groupId: Data,
                                    transaction: SDSAnyWriteTransaction) {
        owsAssertDebug(!groupId.isEmpty)

        let mappingKey = self.mappingKey(forGroupId: groupId)

        if let existingThreadUniqueId = uniqueIdMappingStore.getString(mappingKey, transaction: transaction) {
            // Don't overwrite existing mapping; but verify.
            owsAssertDebug(threadUniqueId == existingThreadUniqueId)
            return
        }

        uniqueIdMappingStore.setString(threadUniqueId, key: mappingKey, transaction: transaction)
    }

    // Used to update the mapping whenever we know of an existing
    // group-id-to-thread-unique-id pair.
    static func setGroupIdMapping(_ threadUniqueId: String,
                                  forGroupId groupId: Data,
                                  transaction: SDSAnyWriteTransaction) {
        owsAssertDebug(!groupId.isEmpty)

        setThreadId(threadUniqueId, forGroupId: groupId, transaction: transaction)

        if GroupManager.isV1GroupId(groupId) {
            guard let v2GroupId = groupsV2.v2GroupId(forV1GroupId: groupId) else {
                owsFailDebug("Couldn't derive v2GroupId.")
                return
            }
            setThreadId(threadUniqueId, forGroupId: v2GroupId, transaction: transaction)
        } else if GroupManager.isV2GroupId(groupId) {
            // Do nothing.
        } else {
            owsFailDebug("Invalid group id: \(groupId.hexadecimalString)")
        }
    }

    // Used to update the mapping for a given group id.
    //
    // * Uses existing threads/mapping if possible.
    // * If a v1 group id, it also update the mapping for the v2 group id.
    static func ensureGroupIdMapping(forGroupId groupId: Data,
                                     transaction: SDSAnyWriteTransaction) {
        owsAssertDebug(!groupId.isEmpty)

        guard GroupManager.isValidGroupIdOfAnyKind(groupId) else {
            return
        }

        let buildThreadUniqueId = { () -> String in
            if let threadUniqueId = existingThreadId(forGroupId: groupId,
                                                     transaction: transaction) {
                return threadUniqueId
            }
            if GroupManager.isV1GroupId(groupId) {
                if let v2GroupId = groupsV2.v2GroupId(forV1GroupId: groupId) {
                    if let threadUniqueId = existingThreadId(forGroupId: v2GroupId,
                                                             transaction: transaction) {
                        return threadUniqueId
                    }
                } else {
                    owsFailDebug("Couldn't derive v2GroupId.")
                }
            }
            return defaultThreadId(forGroupId: groupId)
        }

        let threadUniqueId = buildThreadUniqueId()
        setGroupIdMapping(threadUniqueId, forGroupId: groupId, transaction: transaction)
    }

    func updateGroupMemberRecords(transaction: SDSAnyWriteTransaction) {
        let memberAddresses = Set(groupMembership.fullMembers)
        let previousMembers = TSGroupMember.groupMembers(in: uniqueId, transaction: transaction)
        let membersToDelete = previousMembers.filter { !memberAddresses.contains($0.address) }
        let addressesToAdd = memberAddresses.subtracting(previousMembers.map { $0.address })

        guard !membersToDelete.isEmpty || !addressesToAdd.isEmpty else { return }

        Logger.info("Updating group members with \(membersToDelete.count) removed members and \(addressesToAdd.count) added members.")

        for member in membersToDelete {
            member.anyRemove(transaction: transaction)
        }

        let interactionFinder = InteractionFinder(threadUniqueId: uniqueId)
        for address in addressesToAdd {
            // We look up the latest interaction by this user, because they could
            // have been a member of the group previously.
            let lastInteraction = interactionFinder.latestInteraction(
                from: address,
                transaction: transaction
            )
            TSGroupMember(
                address: address,
                groupThreadId: uniqueId,
                lastInteractionTimestamp: lastInteraction?.timestamp ?? 0
            ).anyInsert(transaction: transaction)
        }
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
