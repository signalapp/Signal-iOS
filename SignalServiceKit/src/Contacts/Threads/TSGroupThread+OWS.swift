//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
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

    static let groupThreadUniqueIdPrefix = "g"

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

    /// Posted when the group associated with this thread adds or removes members.
    ///
    /// The object is the group's unique ID as a string. Note that NotificationCenter dispatches by
    /// object identity rather than equality, so any observer should register for *all* membership
    /// changes and then filter the notifications they receive as needed.
    static let membershipDidChange = Notification.Name("TSGroupThread.membershipDidChange")

    func updateGroupMemberRecords(transaction: SDSAnyWriteTransaction) {
        let groupMemberUpdater = GroupMemberUpdaterImpl(
            temporaryShims: GroupMemberUpdaterTemporaryShimsImpl(),
            groupMemberDataStore: GroupMemberDataStoreImpl(),
            signalServiceAddressCache: Self.signalServiceAddressCache
        )
        groupMemberUpdater.updateRecords(groupThread: self, transaction: transaction.asV2Write)
    }

    /// Returns a list of up to `limit` names of group members.
    ///
    /// The list will not contain the local user. If `includingBlocked` is `false`, it will also not contain
    /// any users that have been blocked by the local user.
    ///
    /// The name returned is computed by `getDisplayName`, but sorting is always done using
    /// `ContactsManager.comparableName(for:transaction:)`. Phone numbers are sorted to the end of the list.
    ///
    /// If `searchText` is provided, members will be sorted to the front of the list if their display names
    /// (as returned by `getDisplayName`) contain the string. The names will also have the matching substring
    /// bracketed as `<match>substring</match>`, similar to the results of FullTextSearchFinder.
    func sortedMemberNames(searchText: String? = nil,
                           includingBlocked: Bool,
                           limit: Int = .max,
                           transaction: SDSAnyReadTransaction,
                           getDisplayName: (SignalServiceAddress) -> String) -> [String] {
        let members: [(
            address: SignalServiceAddress,
            displayName: String?,
            comparableName: String,
            isMatched: Bool
        )] = groupMembership.fullMembers.compactMap { address in
            guard !address.isLocalAddress else {
                return nil
            }
            guard includingBlocked || !blockingManager.isAddressBlocked(address, transaction: transaction) else {
                return nil
            }

            var maybeDisplayName: String?
            var isMatched = false
            if let searchText = searchText {
                var displayName = getDisplayName(address)
                if let matchRange = displayName.range(of: searchText,
                                                      options: [.caseInsensitive, .diacriticInsensitive]) {
                    isMatched = true
                    displayName = displayName.replacingCharacters(
                        in: matchRange,
                        with: "<\(FullTextSearchFinder.matchTag)>\(displayName[matchRange])</\(FullTextSearchFinder.matchTag)>")
                }
                maybeDisplayName = displayName
            }
            return (
                address: address,
                displayName: maybeDisplayName,
                comparableName: contactsManager.comparableName(for: address, transaction: transaction),
                isMatched: isMatched
            )
        }

        let sortedMembers = members.sorted { lhs, rhs in
            // Bubble matched members to the top
            if rhs.isMatched != lhs.isMatched { return lhs.isMatched }
            // Sort numbers to the end of the list
            if lhs.comparableName.hasPrefix("+") != rhs.comparableName.hasPrefix("+") {
                return !lhs.comparableName.hasPrefix("+")
            }
            // Otherwise, sort by comparable name
            return lhs.comparableName.caseInsensitiveCompare(rhs.comparableName) == .orderedAscending
        }

        return sortedMembers.prefix(limit).map {
            $0.displayName ?? getDisplayName($0.address)
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
