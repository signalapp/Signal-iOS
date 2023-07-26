//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

public protocol GroupUpdateItemBuilder {
    /// Build a list of group updates by "diffing" the old and new group states
    /// alongside the other relevant properties given here.
    ///
    /// - Returns
    /// A list of updates. Each update item can present itself as localized
    /// text.
    func buildUpdateItems(
        oldGroupModel: TSGroupModel?,
        newGroupModel: TSGroupModel,
        oldDisappearingMessageToken: DisappearingMessageToken?,
        newDisappearingMessageToken: DisappearingMessageToken?,
        localIdentifiers: LocalIdentifiers,
        groupUpdateSourceAddress: SignalServiceAddress?,
        updaterKnownToBeLocalUser: Bool,
        updateMessages: TSInfoMessage.UpdateMessagesWrapper?,
        tx: DBReadTransaction
    ) -> [GroupUpdateItem]

    /// Get a default group update item, if the values to build more specific
    /// group updates are not available.
    func defaultGroupUpdateItem(
        groupUpdateSourceAddress: SignalServiceAddress?,
        localIdentifiers: LocalIdentifiers?,
        tx: DBReadTransaction
    ) -> GroupUpdateItem
}

public struct GroupUpdateItemBuilderImpl: GroupUpdateItemBuilder {
    private let contactsManager: Shims.ContactsManager

    init(contactsManager: Shims.ContactsManager) {
        self.contactsManager = contactsManager
    }

    public func buildUpdateItems(
        oldGroupModel: TSGroupModel?,
        newGroupModel: TSGroupModel,
        oldDisappearingMessageToken: DisappearingMessageToken?,
        newDisappearingMessageToken: DisappearingMessageToken?,
        localIdentifiers: LocalIdentifiers,
        groupUpdateSourceAddress: SignalServiceAddress?,
        updaterKnownToBeLocalUser: Bool,
        updateMessages: TSInfoMessage.UpdateMessagesWrapper?,
        tx: DBReadTransaction
    ) -> [GroupUpdateItem] {
        return SingleUseGroupUpdateItemBuilderImpl(
            oldGroupModel: oldGroupModel,
            newGroupModel: newGroupModel,
            oldDisappearingMessageToken: oldDisappearingMessageToken,
            newDisappearingMessageToken: newDisappearingMessageToken,
            localIdentifiers: localIdentifiers,
            groupUpdateSourceAddress: groupUpdateSourceAddress,
            updaterKnownToBeLocalUser: updaterKnownToBeLocalUser,
            updateMessages: updateMessages,
            contactsManager: contactsManager,
            tx: tx
        ).itemList
    }

    public func defaultGroupUpdateItem(
        groupUpdateSourceAddress: SignalServiceAddress?,
        localIdentifiers: LocalIdentifiers?,
        tx: DBReadTransaction
    ) -> GroupUpdateItem {
        return SingleUseGroupUpdateItemBuilderImpl.defaultGroupUpdateItem(
            groupUpdateSourceAddress: groupUpdateSourceAddress,
            localIdentifiers: localIdentifiers,
            contactsManager: contactsManager,
            tx: tx
        )
    }
}

/// This type populates itself, on initialization, with items representing the
/// updates made to a group. These updates are determined by "diffing" the old
/// and new group states, alongside information such as who the "updater" was.
///
/// The returned updates map to user-presentable localized strings.
///
/// - Note:
/// Historically, group update items were computed using a struct that populated
/// itself with update items during initialization. Rather than refactor many,
/// many call sites to pass through the historically stored-as-properties values
/// used by that computation, we preserve that pattern here and wrap it in a
/// protocolized type above.
private struct SingleUseGroupUpdateItemBuilderImpl {
    typealias Shims = GroupUpdateItemBuilderImpl.Shims

    private let contactsManager: Shims.ContactsManager

    private let localIdentifiers: LocalIdentifiers
    private let updater: Updater
    private let isReplacingJoinRequestPlaceholder: Bool

    /// The update items, in order.
    private(set) var itemList = [GroupUpdateItem]()

    /// Create a ``GroupUpdateCopy``.
    ///
    /// - Parameter groupUpdateSourceAddress
    /// The address to whom this update should be attributed, if known.
    /// - Parameter updaterKnownToBeLocalUser
    /// Whether we know, ahead of time, that this update should be attributed to
    /// the local user. Necessary if we cannot reliably determine attribution
    /// via ``groupUpdateSourceAddress`` alone. For example, the update address
    /// may refer to a PNI that has moved to another owner.
    init(
        oldGroupModel: TSGroupModel?,
        newGroupModel: TSGroupModel,
        oldDisappearingMessageToken: DisappearingMessageToken?,
        newDisappearingMessageToken: DisappearingMessageToken?,
        localIdentifiers: LocalIdentifiers,
        groupUpdateSourceAddress: SignalServiceAddress?,
        updaterKnownToBeLocalUser: Bool,
        updateMessages: TSInfoMessage.UpdateMessagesWrapper?,
        contactsManager: Shims.ContactsManager,
        tx: DBReadTransaction
    ) {
        self.contactsManager = contactsManager

        self.localIdentifiers = localIdentifiers
        self.updater = Self.buildUpdater(
            groupUpdateSourceAddress: groupUpdateSourceAddress,
            updaterKnownToBeLocalUser: updaterKnownToBeLocalUser,
            localIdentifiers: localIdentifiers,
            contactsManager: contactsManager,
            tx: tx
        )

        if let oldGroupModelV2 = oldGroupModel as? TSGroupModelV2 {
            self.isReplacingJoinRequestPlaceholder = oldGroupModelV2.isPlaceholderModel
        } else {
            self.isReplacingJoinRequestPlaceholder = false
        }

        populate(
            oldGroupModel: oldGroupModel,
            newGroupModel: newGroupModel,
            oldDisappearingMessageToken: oldDisappearingMessageToken,
            newDisappearingMessageToken: newDisappearingMessageToken,
            updateMessages: updateMessages,
            groupUpdateSourceAddress: groupUpdateSourceAddress,
            tx: tx
        )

        switch updater {
        case .unknown:
            Logger.warn("Missing updater info!")
        default:
            break
        }
    }

    /// Determine who this update should be attributed to.
    ///
    /// - Parameter updaterKnownToBeLocalUser
    /// Whether we know ahead of time that the updater is the local user.
    private static func buildUpdater(
        groupUpdateSourceAddress: SignalServiceAddress?,
        updaterKnownToBeLocalUser: Bool,
        localIdentifiers: LocalIdentifiers?,
        contactsManager: Shims.ContactsManager,
        tx: DBReadTransaction
    ) -> Updater {
        if updaterKnownToBeLocalUser {
            return .localUser
        }

        guard let updaterAddress = groupUpdateSourceAddress else {
            return .unknown
        }

        if let localIdentifiers, localIdentifiers.contains(address: updaterAddress) {
            return .localUser
        }

        return .otherUser(
            updaterName: contactsManager.displayName(address: updaterAddress, tx: tx),
            updaterAddress: updaterAddress
        )
    }

    // MARK: - Is local user?

    /// Returns whether the given address matches the local user's ACI or PNI.
    private func isLocalUser(address: SignalServiceAddress?) -> Bool {
        guard let address else { return false }
        return localIdentifiers.contains(address: address)
    }

    /// Returns whether the local user is contained in the given addresses.
    private func isLocalUser(inAddresses addresses: any Sequence<SignalServiceAddress>) -> Bool {
        return addresses.contains { isLocalUser(address: $0) }
    }

    private mutating func addItem(_ item: GroupUpdateItem) {
        itemList.append(item)
    }
}

// MARK: - Population

private extension SingleUseGroupUpdateItemBuilderImpl {

    /// Populate this builder's list of update items, by diffing the provided
    /// values.
    mutating func populate(
        oldGroupModel: TSGroupModel?,
        newGroupModel: TSGroupModel,
        oldDisappearingMessageToken: DisappearingMessageToken?,
        newDisappearingMessageToken: DisappearingMessageToken?,
        updateMessages: TSInfoMessage.UpdateMessagesWrapper?,
        groupUpdateSourceAddress: SignalServiceAddress?,
        tx: DBReadTransaction
    ) {
        if let oldGroupModel = oldGroupModel {
            if
                let updateMessages,
                addPrecomputedUpdateMessages(
                    updateMessages: updateMessages.updateMessages,
                    oldGroupMembership: oldGroupModel.groupMembership,
                    tx: tx
                )
            {
                return
            } else if isReplacingJoinRequestPlaceholder {
                addMembershipUpdates(
                    oldGroupMembership: oldGroupModel.groupMembership,
                    newGroupMembership: newGroupModel.groupMembership,
                    newGroupModel: newGroupModel,
                    groupUpdateSourceAddress: groupUpdateSourceAddress,
                    forLocalUserOnly: true,
                    tx: tx
                )
            } else if wasJustMigrated(newGroupModel: newGroupModel) {
                addMigrationUpdates(
                    oldGroupMembership: oldGroupModel.groupMembership,
                    newGroupMembership: newGroupModel.groupMembership,
                    newGroupModel: newGroupModel
                )
            } else {
                addMembershipUpdates(
                    oldGroupMembership: oldGroupModel.groupMembership,
                    newGroupMembership: newGroupModel.groupMembership,
                    newGroupModel: newGroupModel,
                    groupUpdateSourceAddress: groupUpdateSourceAddress,
                    forLocalUserOnly: false,
                    tx: tx
                )

                addAttributesUpdates(
                    oldGroupModel: oldGroupModel,
                    newGroupModel: newGroupModel
                )

                addAccessUpdates(
                    oldGroupModel: oldGroupModel,
                    newGroupModel: newGroupModel
                )

                addDisappearingMessageUpdates(oldToken: oldDisappearingMessageToken,
                                              newToken: newDisappearingMessageToken)

                addGroupInviteLinkUpdates(
                    oldGroupModel: oldGroupModel,
                    newGroupModel: newGroupModel
                )

                addIsAnnouncementOnlyLinkUpdates(
                    oldGroupModel: oldGroupModel,
                    newGroupModel: newGroupModel
                )
            }
        } else {
            // We're just learning of the group.
            addGroupWasInserted(
                newGroupModel: newGroupModel,
                newGroupMembership: newGroupModel.groupMembership,
                tx: tx
            )

            // Skip description of overall group state (current name, avatar, members, etc.).
            //
            // Include a description of current DM state, if necessary.
            addDisappearingMessageUpdates(oldToken: oldDisappearingMessageToken,
                                          newToken: newDisappearingMessageToken)

            if newGroupModel.wasJustCreatedByLocalUserV2 {
                addWasJustCreatedByLocalUserUpdates()
            }
        }

        if itemList.count < 1 {
            owsFailDebug("Empty group update!")

            switch updater {
            case .localUser:
                addItem(.genericUpdateByLocalUser)
            case let .otherUser(updaterName, updaterAddress):
                addItem(.genericUpdateByOtherUser(updaterName: updaterName, updaterAddress: updaterAddress))
            case .unknown:
                addItem(.genericUpdateByUnknownUser)
            }
        }
    }

    // MARK: - Precomputed update messages

    /// Add copy from precomputed update messages.
    ///
    /// - Returns
    /// Whether or not any messages were added.
    mutating func addPrecomputedUpdateMessages(
        updateMessages: [TSInfoMessage.UpdateMessage],
        oldGroupMembership: GroupMembership,
        tx: DBReadTransaction
    ) -> Bool {
        var addedItems: Bool = false

        var unnamedInviteCounts = UnnamedInviteCounts()

        for updateMessage in updateMessages {
            switch updateMessage {
            case let .sequenceOfInviteLinkRequestAndCancels(count, isTail):
                if addSequenceOfInviteLinkRequestAndCancels(count: count, isTail: isTail) {
                    addedItems = true
                }
            case let .invitedPniPromotedToFullMemberAci(pni, aci):
                let invitedPniAddress = SignalServiceAddress(pni)
                let fullMemberAciAddress = SignalServiceAddress(aci)

                addUserInviteWasAccepted(
                    invitedAsAddress: invitedPniAddress,
                    acceptedAsAddress: fullMemberAciAddress,
                    oldGroupMembership: oldGroupMembership,
                    tx: tx
                )

                addedItems = true
            case let .inviteRemoved(invitee, wasLocalUser):
                addUserInviteWasDeclinedOrRevoked(
                    inviteeAddress: SignalServiceAddress(invitee),
                    inviteeKnownToBeLocalUser: wasLocalUser,
                    oldGroupMembership: oldGroupMembership,
                    unnamedInviteCounts: &unnamedInviteCounts,
                    tx: tx
                )

                // At least, we added something to the unnamed invite counts
                // that we will add after the loop.
                addedItems = true
            }
        }

        addUnnamedInviteCounts(unnamedInviteCounts: unnamedInviteCounts)

        return addedItems
    }

    mutating func addSequenceOfInviteLinkRequestAndCancels(count: UInt, isTail: Bool) -> Bool {
        guard
            count > 0,
            case let .otherUser(updaterName, updaterAddress) = updater
        else {
            return false
        }

        addItem(.sequenceOfInviteLinkRequestAndCancels(
            userName: updaterName,
            userAddress: updaterAddress,
            count: count,
            isTail: isTail
        ))

        return true
    }

    // MARK: - Attributes

    mutating func addAttributesUpdates(
        oldGroupModel: TSGroupModel,
        newGroupModel: TSGroupModel
    ) {
        let groupName = { (groupModel: TSGroupModel) -> String? in
            groupModel.groupName?.stripped.nilIfEmpty
        }

        let oldGroupName = groupName(oldGroupModel)
        let newGroupName = groupName(newGroupModel)

        if oldGroupName != newGroupName {
            if let name = newGroupName {
                switch updater {
                case .localUser:
                    addItem(.nameChangedByLocalUser(newGroupName: name))
                case let .otherUser(updaterName, updaterAddress):
                    addItem(.nameChangedByOtherUser(
                        updaterName: updaterName,
                        updaterAddress: updaterAddress,
                        newGroupName: name
                    ))
                case .unknown:
                    addItem(.nameChangedByUnknownUser(newGroupName: name))
                }
            } else {
                switch updater {
                case .localUser:
                    addItem(.nameRemovedByLocalUser)
                case let .otherUser(updaterName, updaterAddress):
                    addItem(.nameRemovedByOtherUser(updaterName: updaterName, updaterAddress: updaterAddress))
                case .unknown:
                    addItem(.nameRemovedByUnknownUser)
                }
            }
        }

        if oldGroupModel.avatarHash != newGroupModel.avatarHash {
            if !newGroupModel.avatarHash.isEmptyOrNil {
                switch updater {
                case .localUser:
                    addItem(.avatarChangedByLocalUser)
                case let .otherUser(updaterName, updaterAddress):
                    addItem(.avatarChangedByOtherUser(
                        updaterName: updaterName,
                        updaterAddress: updaterAddress
                    ))
                case .unknown:
                    addItem(.avatarChangedByUnknownUser)
                }
            } else {
                switch updater {
                case .localUser:
                    addItem(.avatarRemovedByLocalUser)
                case let .otherUser(updaterName, updaterAddress):
                    addItem(.avatarRemovedByOtherUser(
                        updaterName: updaterName,
                        updaterAddress: updaterAddress
                    ))
                case .unknown:
                    addItem(.avatarRemovedByUnknownUser)
                }
            }
        }

        guard let oldGroupModel = oldGroupModel as? TSGroupModelV2,
              let newGroupModel = newGroupModel as? TSGroupModelV2 else { return }

        let groupDescription = { (groupModel: TSGroupModelV2) -> String? in
            return groupModel.descriptionText?.stripped.nilIfEmpty
        }
        let oldGroupDescription = groupDescription(oldGroupModel)
        let newGroupDescription = groupDescription(newGroupModel)
        if oldGroupDescription != newGroupDescription {
            if newGroupDescription != nil {
                switch updater {
                case .localUser:
                    addItem(.descriptionChangedByLocalUser)
                case let .otherUser(updaterName, updaterAddress):
                    addItem(.descriptionChangedByOtherUser(
                        updaterName: updaterName,
                        updaterAddress: updaterAddress
                    ))
                case .unknown:
                    addItem(.descriptionChangedByUnknownUser)
                }
            } else {
                switch updater {
                case .localUser:
                    addItem(.descriptionRemovedByLocalUser)
                case let .otherUser(updaterName, updaterAddress):
                    addItem(.descriptionRemovedByOtherUser(
                        updaterName: updaterName,
                        updaterAddress: updaterAddress
                    ))
                case .unknown:
                    addItem(.descriptionRemovedByUnknownUser)
                }
            }
        }
    }

    // MARK: - Access

    mutating func addAccessUpdates(
        oldGroupModel: TSGroupModel,
        newGroupModel: TSGroupModel
    ) {
        guard let oldGroupModel = oldGroupModel as? TSGroupModelV2 else {
            return
        }
        guard let newGroupModel = newGroupModel as? TSGroupModelV2 else {
            owsFailDebug("Invalid group model.")
            return
        }

        let oldAccess = oldGroupModel.access
        let newAccess = newGroupModel.access

        if oldAccess.members != newAccess.members {
            switch updater {
            case .localUser:
                addItem(.membersAccessChangedByLocalUser(newAccess: newAccess.members))
            case let .otherUser(updaterName, updaterAddress):
                addItem(.membersAccessChangedByOtherUser(
                    updaterName: updaterName,
                    updaterAddress: updaterAddress,
                    newAccess: newAccess.members
                ))
            case .unknown:
                addItem(.membersAccessChangedByUnknownUser(newAccess: newAccess.members))
            }
        }

        if oldAccess.attributes != newAccess.attributes {
            switch updater {
            case .localUser:
                addItem(.attributesAccessChangedByLocalUser(newAccess: newAccess.attributes))
            case let .otherUser(updaterName, updaterAddress):
                addItem(.attributesAccessChangedByOtherUser(
                    updaterName: updaterName,
                    updaterAddress: updaterAddress,
                    newAccess: newAccess.attributes
                ))
            case .unknown:
                addItem(.attributesAccessChangedByUnknownUser(newAccess: newAccess.attributes))
            }
        }
    }

    // MARK: - Membership

    /// Aggregates invite-related changes in which the invitee is unnamed, so we
    /// can display one update rather than individual updates for each unnamed
    /// user.
    struct UnnamedInviteCounts {
        var newInviteCount: UInt = 0
        var revokedInviteCount: UInt = 0
    }

    mutating func addMembershipUpdates(
        oldGroupMembership: GroupMembership,
        newGroupMembership: GroupMembership,
        newGroupModel: TSGroupModel,
        groupUpdateSourceAddress: SignalServiceAddress?,
        forLocalUserOnly: Bool,
        tx: DBReadTransaction
    ) {
        var unnamedInviteCounts = UnnamedInviteCounts()

        let allUsersUnsorted = oldGroupMembership.allMembersOfAnyKind.union(newGroupMembership.allMembersOfAnyKind)
        var allUsersSorted = Array(allUsersUnsorted).stableSort()

        /// Move the given service ID to the front of ``allUsersSorted``, if it
        /// is present therein.
        func moveServiceIdToFront(_ serviceId: UntypedServiceId?) {
            guard let address = serviceId.map({ SignalServiceAddress($0) }) else { return }

            if allUsersSorted.contains(address) {
                allUsersSorted = [address] + allUsersSorted.filter { $0 != address }
            }
        }

        // If the local user has a membership update, sort it to the front.
        moveServiceIdToFront(localIdentifiers.pni)
        moveServiceIdToFront(localIdentifiers.aci)

        // If the updater has changed their membership status, ensure it appears _last_.
        // This trumps the re-ordering of the local user above.
        if let updaterAddress = groupUpdateSourceAddress {
            allUsersSorted = allUsersSorted.filter { $0 != updaterAddress } + [updaterAddress]
        }

        for address in allUsersSorted {
            if forLocalUserOnly, !isLocalUser(address: address) {
                continue
            }

            let oldMembershipStatus = Self.membershipStatus(of: address, in: oldGroupMembership)
            let newMembershipStatus = Self.membershipStatus(of: address, in: newGroupMembership)

            switch oldMembershipStatus {
            case .normalMember:
                switch newMembershipStatus {
                case .normalMember:
                    // Membership status didn't change.
                    // Check for role changes.
                    addMemberRoleUpdates(
                        address: address,
                        oldGroupMembership: oldGroupMembership,
                        newGroupMembership: newGroupMembership,
                        newGroupModel: newGroupModel,
                        tx: tx
                    )
                case .invited:
                    addUserLeftOrWasKickedOutOfGroupThenWasInvitedToTheGroup(address: address, tx: tx)
                case .requesting:
                    // This could happen if a user leaves a group, the requests to rejoin
                    // and we do have access to the intervening revisions.
                    addUserRequestedToJoinGroup(address: address, tx: tx)
                case .none:
                    addUserLeftOrWasKickedOutOfGroup(address: address, tx: tx)
                }
            case .invited:
                switch newMembershipStatus {
                case .normalMember:
                    let wasInviteAccepted: Bool = {
                        switch updater {
                        case .localUser:
                            return isLocalUser(address: address)
                        case .otherUser(_, let updaterAddress):
                            return updaterAddress == address
                        case .unknown:
                            return false
                        }
                    }()

                    if wasInviteAccepted {
                        addUserInviteWasAccepted(
                            invitedAsAddress: address,
                            acceptedAsAddress: address,
                            oldGroupMembership: oldGroupMembership,
                            tx: tx
                        )
                    } else {
                        addUserWasAddedToTheGroup(
                            address: address,
                            newGroupModel: newGroupModel,
                            tx: tx
                        )
                    }
                case .invited:
                    // Membership status didn't change.
                    break
                case .requesting:
                    addUserRequestedToJoinGroup(address: address, tx: tx)
                case .none:
                    addUserInviteWasDeclinedOrRevoked(
                        inviteeAddress: address,
                        inviteeKnownToBeLocalUser: false,
                        oldGroupMembership: oldGroupMembership,
                        unnamedInviteCounts: &unnamedInviteCounts,
                        tx: tx
                    )
                }
            case .requesting:
                switch newMembershipStatus {
                case .normalMember:
                    addUserRequestWasApproved(
                        address: address,
                        oldGroupMembership: oldGroupMembership,
                        tx: tx
                    )
                case .invited:
                    addUserWasInvitedToTheGroup(
                        address: address,
                        unnamedInviteCounts: &unnamedInviteCounts,
                        tx: tx
                    )
                case .requesting:
                    // Membership status didn't change.
                    break
                case .none:
                    addUserRequestWasRejected(address: address, tx: tx)
                }
            case .none:
                switch newMembershipStatus {
                case .normalMember:
                    if newGroupMembership.didJoinFromInviteLink(forFullMember: address) {
                        addUserJoinedFromInviteLink(address: address, tx: tx)
                    } else {
                        addUserWasAddedToTheGroup(
                            address: address,
                            newGroupModel: newGroupModel,
                            tx: tx
                        )
                    }
                case .invited:
                    addUserWasInvitedToTheGroup(
                        address: address,
                        unnamedInviteCounts: &unnamedInviteCounts,
                        tx: tx
                    )
                case .requesting:
                    addUserRequestedToJoinGroup(address: address, tx: tx)
                case .none:
                    // Membership status didn't change.
                    break
                }
            }
        }

        addUnnamedInviteCounts(unnamedInviteCounts: unnamedInviteCounts)

        addInvalidInviteUpdates(oldGroupMembership: oldGroupMembership,
                                newGroupMembership: newGroupMembership)
    }

    mutating func addInvalidInviteUpdates(oldGroupMembership: GroupMembership,
                                          newGroupMembership: GroupMembership) {
        let oldInvalidInviteUserIds = Set(oldGroupMembership.invalidInviteUserIds)
        let newInvalidInviteUserIds = Set(newGroupMembership.invalidInviteUserIds)
        let addedInvalidInviteCount = newInvalidInviteUserIds.subtracting(oldInvalidInviteUserIds).count
        let removedInvalidInviteCount = oldInvalidInviteUserIds.subtracting(newInvalidInviteUserIds).count

        if addedInvalidInviteCount > 0 {
            switch updater {
            case .localUser:
                addItem(.invalidInvitesAddedByLocalUser(count: addedInvalidInviteCount))
            case let .otherUser(updaterName, updaterAddress):
                addItem(.invalidInvitesAddedByOtherUser(
                    updaterName: updaterName,
                    updaterAddress: updaterAddress,
                    count: addedInvalidInviteCount
                ))
            case .unknown:
                addItem(.invalidInvitesAddedByUnknownUser(count: addedInvalidInviteCount))
            }
        }

        if removedInvalidInviteCount > 0 {
            switch updater {
            case .localUser:
                addItem(.invalidInvitesRemovedByLocalUser(count: removedInvalidInviteCount))
            case let .otherUser(updaterName, updaterAddress):
                addItem(.invalidInvitesRemovedByOtherUser(
                    updaterName: updaterName,
                    updaterAddress: updaterAddress,
                    count: removedInvalidInviteCount
                ))
            case .unknown:
                addItem(.invalidInvitesRemovedByUnknownUser(count: removedInvalidInviteCount))
            }
        }
    }

    mutating func addMemberRoleUpdates(
        address: SignalServiceAddress,
        oldGroupMembership: GroupMembership,
        newGroupMembership: GroupMembership,
        newGroupModel: TSGroupModel,
        tx: DBReadTransaction
    ) {

        let oldIsAdministrator = oldGroupMembership.isFullMemberAndAdministrator(address)
        let newIsAdministrator = newGroupMembership.isFullMemberAndAdministrator(address)

        guard oldIsAdministrator != newIsAdministrator else {
            // Role didn't change.
            return
        }

        if newIsAdministrator {
            addUserWasGrantedAdministrator(address: address, newGroupModel: newGroupModel, tx: tx)
        } else {
            addUserWasRevokedAdministrator(address: address, tx: tx)
        }
    }

    mutating func addUserWasGrantedAdministrator(
        address userAddress: SignalServiceAddress,
        newGroupModel: TSGroupModel,
        tx: DBReadTransaction
    ) {

        if let newGroupModelV2 = newGroupModel as? TSGroupModelV2,
            newGroupModelV2.wasJustMigrated {
            // All v1 group members become admins when the
            // group is migrated to v2. We don't need to
            // surface this to the user.
            return
        }

        if isLocalUser(address: userAddress) {
            switch updater {
            case .localUser:
                owsFailDebug("Local user made themselves administrator!")
                addItem(.localUserWasGrantedAdministratorByLocalUser)
            case let .otherUser(updaterName, updaterAddress):
                addItem(.localUserWasGrantedAdministratorByOtherUser(
                    updaterName: updaterName,
                    updaterAddress: updaterAddress
                ))
            case .unknown:
                addItem(.localUserWasGrantedAdministratorByUnknownUser)
            }
        } else {
            let userName = self.contactsManager.displayName(address: userAddress, tx: tx)

            switch updater {
            case .localUser:
                addItem(.otherUserWasGrantedAdministratorByLocalUser(
                    userName: userName,
                    userAddress: userAddress
                ))
            case let .otherUser(updaterName, updaterAddress):
                if updaterAddress == userAddress {
                    owsFailDebug("Remote user made themselves administrator!")
                    addItem(.otherUserWasGrantedAdministratorByUnknownUser(
                        userName: userName,
                        userAddress: userAddress
                    ))
                } else {
                    addItem(.otherUserWasGrantedAdministratorByOtherUser(
                        updaterName: updaterName,
                        updaterAddress: updaterAddress,
                        userName: userName,
                        userAddress: userAddress
                    ))
                }
            case .unknown:
                addItem(.otherUserWasGrantedAdministratorByUnknownUser(
                    userName: userName,
                    userAddress: userAddress
                ))
            }
        }
    }

    mutating func addUserWasRevokedAdministrator(
        address userAddress: SignalServiceAddress,
        tx: DBReadTransaction
    ) {
        if isLocalUser(address: userAddress) {
            switch updater {
            case .localUser:
                addItem(.localUserWasRevokedAdministratorByLocalUser)
            case let .otherUser(updaterName, updaterAddress):
                addItem(.localUserWasRevokedAdministratorByOtherUser(
                    updaterName: updaterName,
                    updaterAddress: updaterAddress
                ))
            case .unknown:
                addItem(.localUserWasRevokedAdministratorByUnknownUser)
            }
        } else {
            let userName = contactsManager.displayName(address: userAddress, tx: tx)

            switch updater {
            case .localUser:
                addItem(.otherUserWasRevokedAdministratorByLocalUser(
                    userName: userName,
                    userAddress: userAddress
                ))
            case let .otherUser(updaterName, updaterAddress):
                if updaterAddress == userAddress {
                    addItem(.otherUserWasRevokedAdministratorByUnknownUser(
                        userName: userName,
                        userAddress: userAddress
                    ))
                } else {
                    addItem(.otherUserWasRevokedAdministratorByOtherUser(
                        updaterName: updaterName,
                        updaterAddress: updaterAddress,
                        userName: userName,
                        userAddress: userAddress
                    ))
                }
            case .unknown:
                addItem(.otherUserWasRevokedAdministratorByUnknownUser(
                    userName: userName,
                    userAddress: userAddress
                ))
            }
        }
    }

    mutating func addUserLeftOrWasKickedOutOfGroup(
        address userAddress: SignalServiceAddress,
        tx: DBReadTransaction
    ) {
        if isLocalUser(address: userAddress) {
            switch updater {
            case .localUser:
                addItem(.localUserLeft)
            case let .otherUser(updaterName, updaterAddress):
                addItem(.localUserRemoved(
                    removerName: updaterName,
                    removerAddress: updaterAddress
                ))
            case .unknown:
                addItem(.localUserRemovedByUnknownUser)
            }
        } else {
            let userName = contactsManager.displayName(address: userAddress, tx: tx)

            switch updater {
            case .localUser:
                addItem(.otherUserRemovedByLocalUser(
                    userName: userName,
                    userAddress: userAddress
                ))
            case let .otherUser(updaterName, updaterAddress):
                if updaterAddress == userAddress {
                    addItem(.otherUserLeft(userName: userName, userAddress: userAddress))
                } else {
                    addItem(.otherUserRemoved(
                        removerName: updaterName,
                        removerAddress: updaterAddress,
                        userName: userName,
                        userAddress: userAddress
                    ))
                }
            case .unknown:
                addItem(.otherUserLeft(
                    userName: userName,
                    userAddress: userAddress
                ))
            }
        }
    }

    mutating func addUserLeftOrWasKickedOutOfGroupThenWasInvitedToTheGroup(
        address userAddress: SignalServiceAddress,
        tx: DBReadTransaction
    ) {
        if isLocalUser(address: userAddress) {
            addItem(.localUserRemovedByUnknownUser)

            switch updater {
            case .localUser:
                owsFailDebug("User invited themselves to the group!")
                addItem(.localUserWasInvitedByLocalUser)
            case let .otherUser(updaterName, updaterAddress):
                addItem(.localUserWasInvitedByOtherUser(
                    updaterName: updaterName,
                    updaterAddress: updaterAddress
                ))
            case .unknown:
                addItem(.localUserWasInvitedByUnknownUser)
            }
        } else {
            addItem(.otherUserLeft(
                userName: contactsManager.displayName(address: userAddress, tx: tx),
                userAddress: userAddress
            ))

            switch updater {
            case .localUser:
                addItem(.unnamedUsersWereInvitedByLocalUser(count: 1))
            case let .otherUser(updaterName, updaterAddress):
                addItem(.unnamedUsersWereInvitedByOtherUser(
                    updaterName: updaterName,
                    updaterAddress: updaterAddress,
                    count: 1
                ))
            case .unknown:
                addItem(.unnamedUsersWereInvitedByUnknownUser(count: 1))
            }
        }
    }

    mutating func addUserInviteWasAccepted(
        invitedAsAddress: SignalServiceAddress,
        acceptedAsAddress: SignalServiceAddress,
        oldGroupMembership: GroupMembership,
        tx: DBReadTransaction
    ) {
        var inviterName: String?
        var inviterAddress: SignalServiceAddress?

        if let inviterUuid = oldGroupMembership.addedByUuid(forInvitedMember: invitedAsAddress) {
            inviterAddress = SignalServiceAddress(uuid: inviterUuid)
            inviterName = contactsManager.displayName(
                address: SignalServiceAddress(uuid: inviterUuid),
                tx: tx
            )
        }

        if isLocalUser(address: acceptedAsAddress) {
            switch updater {
            case .localUser:
                if let inviterName, let inviterAddress {
                    addItem(.localUserAcceptedInviteFromInviter(
                        inviterName: inviterName,
                        inviterAddress: inviterAddress
                    ))
                } else {
                    owsFailDebug("Missing inviter name!")
                    addItem(.localUserAcceptedInviteFromUnknownUser)
                }
            case let .otherUser(updaterName, updaterAddress):
                addItem(.localUserAddedByOtherUser(
                    updaterName: updaterName,
                    updaterAddress: updaterAddress
                ))
            case .unknown:
                addItem(.localUserJoined)
            }
        } else {
            let acceptedAsName = contactsManager.displayName(address: acceptedAsAddress, tx: tx)

            switch updater {
            case .localUser:
                addItem(.otherUserAddedByLocalUser(
                    userName: acceptedAsName,
                    userAddress: acceptedAsAddress
                ))
            case let .otherUser(updaterName, updaterAddress):
                if invitedAsAddress == updaterAddress || acceptedAsAddress == updaterAddress {
                    // The update came from the person who was invited.

                    if isLocalUser(address: inviterAddress) {
                        addItem(.otherUserAcceptedInviteFromLocalUser(
                            userName: acceptedAsName,
                            userAddress: acceptedAsAddress
                        ))
                    } else if let inviterName, let inviterAddress {
                        addItem(.otherUserAcceptedInviteFromInviter(
                            userName: acceptedAsName,
                            userAddress: acceptedAsAddress,
                            inviterName: inviterName,
                            inviterAddress: inviterAddress
                        ))
                    } else {
                        owsFailDebug("Missing inviter name.")
                        addItem(.otherUserAcceptedInviteFromUnknownUser(
                            userName: acceptedAsName,
                            userAddress: acceptedAsAddress
                        ))
                    }
                } else {
                    addItem(.otherUserAddedByOtherUser(
                        updaterName: updaterName,
                        updaterAddress: updaterAddress,
                        userName: acceptedAsName,
                        userAddress: acceptedAsAddress
                    ))
                }
            case .unknown:
                addItem(.otherUserJoined(
                    userName: acceptedAsName,
                    userAddress: acceptedAsAddress
                ))
            }
        }
    }

    /// Add that the given invited address declined or had their invite revoked.
    /// - Parameter inviteeKnownToBeLocalUser
    /// Whether we know ahead of time that the invitee was the local user.
    mutating func addUserInviteWasDeclinedOrRevoked(
        inviteeAddress: SignalServiceAddress,
        inviteeKnownToBeLocalUser: Bool,
        oldGroupMembership: GroupMembership,
        unnamedInviteCounts: inout UnnamedInviteCounts,
        tx: DBReadTransaction
    ) {

        var inviterName: String?
        var inviterAddress: SignalServiceAddress?
        if let inviterUuid = oldGroupMembership.addedByUuid(forInvitedMember: inviteeAddress) {
            inviterAddress = SignalServiceAddress(uuid: inviterUuid)
            inviterName = contactsManager.displayName(
                address: SignalServiceAddress(uuid: inviterUuid),
                tx: tx
            )
        }

        if inviteeKnownToBeLocalUser || isLocalUser(address: inviteeAddress) {
            switch updater {
            case .localUser:
                if let inviterName, let inviterAddress {
                    addItem(.localUserDeclinedInviteFromInviter(
                        inviterName: inviterName,
                        inviterAddress: inviterAddress
                    ))
                } else {
                    owsFailDebug("Missing inviter name!")
                    addItem(.localUserDeclinedInviteFromUnknownUser)
                }
            case let .otherUser(updaterName, updaterAddress):
                addItem(.localUserInviteRevoked(
                    revokerName: updaterName,
                    revokerAddress: updaterAddress
                ))
            case .unknown:
                addItem(.localUserInviteRevokedByUnknownUser)
            }
        } else {
            let inviteeName = contactsManager.displayName(address: inviteeAddress, tx: tx)

            switch updater {
            case .localUser:
                addItem(.otherUserInviteRevokedByLocalUser(
                    userName: inviteeName,
                    userAddress: inviteeAddress
                ))
            case .otherUser(_, let updaterAddress):
                if inviteeAddress == updaterAddress {
                    if isLocalUser(address: inviterAddress) {
                        addItem(.otherUserDeclinedInviteFromLocalUser(
                            userName: inviteeName,
                            userAddress: inviteeAddress
                        ))
                    } else if let inviterName, let inviterAddress {
                        addItem(.otherUserDeclinedInviteFromInviter(
                            inviterName: inviterName,
                            inviterAddress: inviterAddress
                        ))
                    } else {
                        addItem(.otherUserDeclinedInviteFromUnknownUser)
                    }
                } else {
                    unnamedInviteCounts.revokedInviteCount += 1
                }
            case .unknown:
                unnamedInviteCounts.revokedInviteCount += 1
            }
        }
    }

    mutating func addUserWasAddedToTheGroup(
        address userAddress: SignalServiceAddress,
        newGroupModel: TSGroupModel,
        tx: DBReadTransaction
    ) {
        if newGroupModel.didJustAddSelfViaGroupLinkV2 {
            addItem(.localUserJoined)
        } else if isLocalUser(address: userAddress) {
            switch updater {
            case .localUser:
                owsFailDebug("User added themselves to the group and was updater - should not be possible.")
                addItem(.localUserAddedByLocalUser)
            case let .otherUser(updaterName, updaterAddress):
                addItem(.localUserAddedByOtherUser(
                    updaterName: updaterName,
                    updaterAddress: updaterAddress
                ))
            case .unknown:
                addItem(.localUserAddedByUnknownUser)
            }
        } else {
            let userName = contactsManager.displayName(address: userAddress, tx: tx)

            switch updater {
            case .localUser:
                addItem(.otherUserAddedByLocalUser(
                    userName: userName,
                    userAddress: userAddress
                ))
            case let .otherUser(updaterName, updaterAddress):
                if updaterAddress == userAddress {
                    owsFailDebug("Remote user added themselves to the group!")

                    addItem(.otherUserAddedByUnknownUser(
                        userName: userName,
                        userAddress: userAddress
                    ))
                } else {
                    addItem(.otherUserAddedByOtherUser(
                        updaterName: updaterName,
                        updaterAddress: updaterAddress,
                        userName: userName,
                        userAddress: userAddress
                    ))
                }
            case .unknown:
                addItem(.otherUserAddedByUnknownUser(
                    userName: userName,
                    userAddress: userAddress
                ))
            }
        }
    }

    mutating func addUserJoinedFromInviteLink(
        address: SignalServiceAddress,
        tx: DBReadTransaction
    ) {
        if isLocalUser(address: address) {
            switch updater {
            case .localUser:
                addItem(.localUserJoinedViaInviteLink)
            case .otherUser:
                owsFailDebug("A user should never join the group via invite link unless they are the updater.")
                addItem(.localUserJoined)
            case .unknown:
                addItem(.localUserJoined)
            }
        } else {
            let userName = contactsManager.displayName(address: address, tx: tx)

            switch updater {
            case .otherUser(let updaterName, let updaterAddress) where updaterAddress == address:
                addItem(.otherUserJoinedViaInviteLink(
                    userName: updaterName,
                    userAddress: updaterAddress
                ))
            default:
                owsFailDebug("If user joined via group link, they should be the updater!")
                addItem(.otherUserAddedByUnknownUser(
                    userName: userName,
                    userAddress: address
                ))
            }
        }
    }

    mutating func addUserWasInvitedToTheGroup(
        address userAddress: SignalServiceAddress,
        unnamedInviteCounts: inout UnnamedInviteCounts,
        tx: DBReadTransaction
    ) {
        if isLocalUser(address: userAddress) {
            switch updater {
            case .localUser:
                owsFailDebug("User invited themselves to the group!")

                addItem(.localUserWasInvitedByLocalUser)
            case let .otherUser(updaterName, updaterAddress):
                addItem(.localUserWasInvitedByOtherUser(
                    updaterName: updaterName,
                    updaterAddress: updaterAddress
                ))
            case .unknown:
                addItem(.localUserWasInvitedByUnknownUser)
            }
        } else {
            switch updater {
            case .localUser:
                addItem(.otherUserWasInvitedByLocalUser(
                    userName: contactsManager.displayName(address: userAddress, tx: tx),
                    userAddress: userAddress
                ))
            default:
                unnamedInviteCounts.newInviteCount += 1
            }
        }
    }

    mutating func addUnnamedInviteCounts(unnamedInviteCounts: UnnamedInviteCounts) {
        addUnnamedUsersWereInvited(count: unnamedInviteCounts.newInviteCount)
        addUnnamedUserInvitesWereRevoked(count: unnamedInviteCounts.revokedInviteCount)
    }

    mutating func addUnnamedUsersWereInvited(count: UInt) {
        guard count > 0 else {
            return
        }

        switch updater {
        case .localUser:
            owsFailDebug("Unexpected updater - if local user is inviter, should not be unnamed.")
            addItem(.unnamedUsersWereInvitedByLocalUser(count: count))
        case let .otherUser(updaterName, updaterAddress):
            addItem(.unnamedUsersWereInvitedByOtherUser(
                updaterName: updaterName,
                updaterAddress: updaterAddress,
                count: count
            ))
        case .unknown:
            addItem(.unnamedUsersWereInvitedByUnknownUser(count: count))
        }
    }

    mutating func addUnnamedUserInvitesWereRevoked(count: UInt) {
        guard count > 0 else {
            return
        }

        switch updater {
        case .localUser:
            owsFailDebug("When local user is updater, should have named invites!")
            addItem(.unnamedUserInvitesWereRevokedByLocalUser(count: count))
        case let .otherUser(updaterName, updaterAddress):
            addItem(.unnamedUserInvitesWereRevokedByOtherUser(
                updaterName: updaterName,
                updaterAddress: updaterAddress,
                count: count
            ))
        case .unknown:
            addItem(.unnamedUserInvitesWereRevokedByUnknownUser(count: count))
        }
    }

    // MARK: - Requesting Members

    mutating func addUserRequestedToJoinGroup(
        address requesterAddress: SignalServiceAddress,
        tx: DBReadTransaction
    ) {
        if isLocalUser(address: requesterAddress) {
            addItem(.localUserRequestedToJoin)
        } else {
            addItem(.otherUserRequestedToJoin(
                userName: contactsManager.displayName(address: requesterAddress, tx: tx),
                userAddress: requesterAddress
            ))
        }
    }

    mutating func addUserRequestWasApproved(
        address requesterAddress: SignalServiceAddress,
        oldGroupMembership: GroupMembership,
        tx: DBReadTransaction
    ) {
        if isLocalUser(address: requesterAddress) {
            switch updater {
            case .localUser:
                // This could happen if the user requested to join a group
                // and became a requesting member, then tried to join the
                // group again and was added because the group stopped
                // requiring approval in the interim.
                owsFailDebug("User added themselves to the group and was updater - should not be possible.")
                addItem(.localUserAddedByLocalUser)
            case .otherUser(let updaterName, let updaterAddress):
                // A requesting user can either be added or "approved". If the
                // updater is an admin, we go with approved.
                if oldGroupMembership.isFullMemberAndAdministrator(updaterAddress) {
                    addItem(.localUserRequestApproved(
                        approverName: updaterName,
                        approverAddress: updaterAddress
                    ))
                } else {
                    addItem(.localUserAddedByOtherUser(
                        updaterName: updaterName,
                        updaterAddress: updaterAddress
                    ))
                }
            case .unknown:
                addItem(.localUserRequestApprovedByUnknownUser)
            }
        } else {
            let requesterName = contactsManager.displayName(address: requesterAddress, tx: tx)

            switch updater {
            case .localUser:
                // A requesting user can either be added or "approved". If the
                // updater is an admin, we go with approved.
                if oldGroupMembership.isFullMemberAndAdministrator(localIdentifiers.aciAddress) {
                    addItem(.otherUserRequestApprovedByLocalUser(
                        userName: requesterName,
                        userAddress: requesterAddress
                    ))
                } else {
                    addItem(.otherUserAddedByLocalUser(
                        userName: requesterName,
                        userAddress: requesterAddress
                    ))
                }
            case .otherUser(let updaterName, let updaterAddress):
                // A requesting user can either be added or "approved". If the
                // updater is an admin, we go with approved.
                if oldGroupMembership.isFullMemberAndAdministrator(updaterAddress) {
                    addItem(.otherUserRequestApproved(
                        userName: requesterName,
                        userAddress: requesterAddress,
                        approverName: updaterName,
                        approverAddress: updaterAddress
                    ))
                } else {
                    addItem(.otherUserAddedByOtherUser(
                        updaterName: updaterName,
                        updaterAddress: updaterAddress,
                        userName: requesterName,
                        userAddress: requesterAddress
                    ))
                }
            case .unknown:
                // If we don't know the updater, we can't infer whether they
                // were added or approved.
                addItem(.otherUserJoined(
                    userName: requesterName,
                    userAddress: requesterAddress
                ))
            }
        }
    }

    mutating func addUserRequestWasRejected(
        address requesterAddress: SignalServiceAddress,
        tx: DBReadTransaction
    ) {
        if isLocalUser(address: requesterAddress) {
            switch updater {
            case .localUser:
                addItem(.localUserRequestCanceledByLocalUser)
            case .otherUser, .unknown:
                addItem(.localUserRequestRejectedByUnknownUser)
            }
        } else {
            switch updater {
            case .localUser:
                addItem(.otherUserRequestRejectedByLocalUser(
                    requesterName: contactsManager.displayName(address: requesterAddress, tx: tx),
                    requesterAddress: requesterAddress
                ))
            case let .otherUser(updaterName, updaterAddress):
                if updaterAddress == requesterAddress {
                    addItem(.otherUserRequestCanceledByOtherUser(
                        requesterName: contactsManager.displayName(address: requesterAddress, tx: tx),
                        requesterAddress: requesterAddress
                    ))
                } else {
                    addItem(.otherUserRequestRejectedByOtherUser(
                        updaterName: updaterName,
                        updaterAddress: updaterAddress,
                        requesterName: contactsManager.displayName(address: requesterAddress, tx: tx),
                        requesterAddress: requesterAddress
                    ))
                }
            case .unknown:
                addItem(.otherUserRequestRejectedByUnknownUser(
                    requesterName: contactsManager.displayName(address: requesterAddress, tx: tx),
                    requesterAddress: requesterAddress
                ))
            }
        }
    }

    // MARK: - Disappearing Messages

    mutating func addDisappearingMessageUpdates(oldToken: DisappearingMessageToken?,
                                                newToken: DisappearingMessageToken?) {

        guard let newToken = newToken else {
            // This info message was created before we embedded DM state.
            return
        }

        // This might be zero if DMs are not enabled.
        let durationString = newToken.durationString

        guard let oldToken else {
            if newToken.isEnabled {
                switch updater {
                case .localUser:
                    addItem(.disappearingMessagesUpdatedNoOldTokenByLocalUser(
                        duration: durationString
                    ))
                case .otherUser, .unknown:
                    addItem(.disappearingMessagesUpdatedNoOldTokenByUnknownUser(
                        duration: durationString
                    ))
                }
            }

            return
        }

        guard newToken != oldToken else {
            // No change to disappearing message configuration occurred.
            return
        }

        if newToken.isEnabled {
            switch updater {
            case .localUser:
                addItem(.disappearingMessagesEnabledByLocalUser(duration: durationString))
            case let .otherUser(updaterName, updaterAddress):
                addItem(.disappearingMessagesEnabledByOtherUser(
                    updaterName: updaterName,
                    updaterAddress: updaterAddress,
                    duration: durationString
                ))
            case .unknown:
                addItem(.disappearingMessagesEnabledByUnknownUser(duration: durationString))
            }
        } else {
            switch updater {
            case .localUser:
                addItem(.disappearingMessagesDisabledByLocalUser)
            case let .otherUser(updaterName, updaterAddress):
                addItem(.disappearingMessagesDisabledByOtherUser(
                    updaterName: updaterName,
                    updaterAddress: updaterAddress
                ))
            case .unknown:
                addItem(.disappearingMessagesDisabledByUnknownUser)
            }
        }
    }

    // MARK: - Group Invite Links

    mutating func addGroupInviteLinkUpdates(
        oldGroupModel: TSGroupModel,
        newGroupModel: TSGroupModel
    ) {
        guard let oldGroupModel = oldGroupModel as? TSGroupModelV2 else {
            return
        }
        guard let newGroupModel = newGroupModel as? TSGroupModelV2 else {
            owsFailDebug("Invalid group model.")
            return
        }
        let oldGroupInviteLinkMode = oldGroupModel.groupInviteLinkMode
        let newGroupInviteLinkMode = newGroupModel.groupInviteLinkMode

        guard oldGroupInviteLinkMode != newGroupInviteLinkMode else {
            if
                let oldInviteLinkPassword = oldGroupModel.inviteLinkPassword,
                let newInviteLinkPassword = newGroupModel.inviteLinkPassword,
                oldInviteLinkPassword != newInviteLinkPassword
            {
                switch updater {
                case .localUser:
                    addItem(.inviteLinkResetByLocalUser)
                case let .otherUser(updaterName, updaterAddress):
                    addItem(.inviteLinkResetByOtherUser(
                        updaterName: updaterName,
                        updaterAddress: updaterAddress
                    ))
                case .unknown:
                    addItem(.inviteLinkResetByUnknownUser)
                }
            }

            return
        }

        switch oldGroupInviteLinkMode {
        case .disabled:
            switch newGroupInviteLinkMode {
            case .disabled:
                owsFailDebug("State did not change.")
            case .enabledWithoutApproval:
                switch updater {
                case .localUser:
                    addItem(.inviteLinkEnabledWithoutApprovalByLocalUser)
                case let .otherUser(updaterName, updaterAddress):
                    addItem(.inviteLinkEnabledWithoutApprovalByOtherUser(
                        updaterName: updaterName,
                        updaterAddress: updaterAddress
                    ))
                case .unknown:
                    addItem(.inviteLinkEnabledWithoutApprovalByUnknownUser)
                }
            case .enabledWithApproval:
                switch updater {
                case .localUser:
                    addItem(.inviteLinkEnabledWithApprovalByLocalUser)
                case let .otherUser(updaterName, updaterAddress):
                    addItem(.inviteLinkEnabledWithApprovalByOtherUser(
                        updaterName: updaterName,
                        updaterAddress: updaterAddress
                    ))
                case .unknown:
                    addItem(.inviteLinkEnabledWithApprovalByUnknownUser)
                }
            }
        case .enabledWithoutApproval, .enabledWithApproval:
            switch newGroupInviteLinkMode {
            case .disabled:
                switch updater {
                case .localUser:
                    addItem(.inviteLinkDisabledByLocalUser)
                case let .otherUser(updaterName, updaterAddress):
                    addItem(.inviteLinkDisabledByOtherUser(
                        updaterName: updaterName,
                        updaterAddress: updaterAddress
                    ))
                case .unknown:
                    addItem(.inviteLinkDisabledByUnknownUser)
                }
            case .enabledWithoutApproval:
                switch updater {
                case .localUser:
                    addItem(.inviteLinkApprovalDisabledByLocalUser)
                case let .otherUser(updaterName, updaterAddress):
                    addItem(.inviteLinkApprovalDisabledByOtherUser(
                        updaterName: updaterName,
                        updaterAddress: updaterAddress
                    ))
                case .unknown:
                    addItem(.inviteLinkApprovalDisabledByUnknownUser)
                }
            case .enabledWithApproval:
                switch updater {
                case .localUser:
                    addItem(.inviteLinkApprovalEnabledByLocalUser)
                case let .otherUser(updaterName, updaterAddress):
                    addItem(.inviteLinkApprovalEnabledByOtherUser(
                        updaterName: updaterName,
                        updaterAddress: updaterAddress
                    ))
                case .unknown:
                    addItem(.inviteLinkApprovalEnabledByUnknownUser)
                }
            }
        }
    }

    // MARK: - Announcement-Only Groups

    mutating func addIsAnnouncementOnlyLinkUpdates(
        oldGroupModel: TSGroupModel,
        newGroupModel: TSGroupModel
    ) {
        guard let oldGroupModel = oldGroupModel as? TSGroupModelV2 else {
            return
        }
        guard let newGroupModel = newGroupModel as? TSGroupModelV2 else {
            owsFailDebug("Invalid group model.")
            return
        }
        let oldIsAnnouncementsOnly = oldGroupModel.isAnnouncementsOnly
        let newIsAnnouncementsOnly = newGroupModel.isAnnouncementsOnly

        guard oldIsAnnouncementsOnly != newIsAnnouncementsOnly else {
            return
        }

        if newIsAnnouncementsOnly {
            switch updater {
            case .localUser:
                addItem(.announcementOnlyEnabledByLocalUser)
            case let .otherUser(updaterName, updaterAddress):
                addItem(.announcementOnlyEnabledByOtherUser(
                    updaterName: updaterName,
                    updaterAddress: updaterAddress
                ))
            case .unknown:
                addItem(.announcementOnlyEnabledByUnknownUser)
            }
        } else {
            switch updater {
            case .localUser:
                addItem(.announcementOnlyDisabledByLocalUser)
            case let .otherUser(updaterName, updaterAddress):
                addItem(.announcementOnlyDisabledByOtherUser(
                    updaterName: updaterName,
                    updaterAddress: updaterAddress
                ))
            case .unknown:
                addItem(.announcementOnlyDisabledByUnknownUser)
            }
        }
    }

    // MARK: -

    mutating func addGroupWasInserted(
        newGroupModel: TSGroupModel,
        newGroupMembership: GroupMembership,
        tx: DBReadTransaction
    ) {
        guard let newGroupModel = newGroupModel as? TSGroupModelV2 else {
            // This is a V1 group. While we may be able to be more specific, we
            // shouldn't stress over V1 group update messages.
            addItem(.createdByUnknownUser)
            return
        }

        let wasGroupJustCreated = newGroupModel.revision == 0
        if wasGroupJustCreated {
            switch updater {
            case .localUser:
                addItem(.createdByLocalUser)
            case let .otherUser(updaterName, updaterAddress):
                addItem(.createdByOtherUser(
                    updaterName: updaterName,
                    updaterAddress: updaterAddress
                ))
            case .unknown:
                addItem(.createdByUnknownUser)
            }
        }

        switch localMembershipStatus(for: newGroupMembership) {
        case .normalMember:
            guard !wasGroupJustCreated else {
                // If group was just created, it's implicit that we were added.
                return
            }

            switch updater {
            case let .otherUser(updaterName, updaterAddress):
                addItem(.localUserAddedByOtherUser(
                    updaterName: updaterName,
                    updaterAddress: updaterAddress
                ))
            default:
                if newGroupModel.didJustAddSelfViaGroupLink {
                    addItem(.localUserJoined)
                } else {
                    addItem(.localUserAddedByUnknownUser)
                }
            }
        case .invited(let inviterUuid):
            if let inviterUuid {
                let inviterAddress = SignalServiceAddress(uuid: inviterUuid)

                addItem(.localUserWasInvitedByOtherUser(
                    updaterName: contactsManager.displayName(address: inviterAddress, tx: tx),
                    updaterAddress: inviterAddress
                ))
            } else {
                addItem(.localUserWasInvitedByUnknownUser)
            }
        case .requesting:
            addUserRequestedToJoinGroup(address: localIdentifiers.aciAddress, tx: tx)
        case .none:
            owsFailDebug("Group was inserted without local membership!")
        }
    }

    mutating func addWasJustCreatedByLocalUserUpdates() {
        addItem(.wasJustCreatedByLocalUser)
    }

    // MARK: - Migration

    private func wasJustMigrated(newGroupModel: TSGroupModel) -> Bool {
        guard let newGroupModelV2 = newGroupModel as? TSGroupModelV2,
            newGroupModelV2.wasJustMigrated else {
                return false
        }
        return true
    }

    mutating func addMigrationUpdates(
        oldGroupMembership: GroupMembership,
        newGroupMembership: GroupMembership,
        newGroupModel: TSGroupModel
    ) {
        owsAssertDebug(wasJustMigrated(newGroupModel: newGroupModel))
        addItem(.wasMigrated)
    }

    // MARK: - Membership Status

    enum MembershipStatus {
        case normalMember
        case invited(invitedBy: UUID?)
        case requesting
        case none
    }

    func localMembershipStatus(for groupMembership: GroupMembership) -> MembershipStatus {
        let aciMembership = Self.membershipStatus(serviceId: localIdentifiers.aci, in: groupMembership)

        switch aciMembership {
        case .invited, .requesting, .normalMember:
            return aciMembership
        case .none:
            break
        }

        if let localPni = localIdentifiers.pni {
            return Self.membershipStatus(serviceId: localPni, in: groupMembership)
        }

        return .none
    }

    static func membershipStatus(
        of address: SignalServiceAddress,
        in groupMembership: GroupMembership
    ) -> MembershipStatus {
        guard let serviceId = address.untypedServiceId else {
            return .none
        }

        return membershipStatus(serviceId: serviceId, in: groupMembership)
    }

    static func membershipStatus(
        serviceId: UntypedServiceId,
        in groupMembership: GroupMembership
    ) -> MembershipStatus {
        if groupMembership.isFullMember(serviceId.uuidValue) {
            return .normalMember
        } else if groupMembership.isInvitedMember(serviceId.uuidValue) {
            return .invited(invitedBy: groupMembership.addedByUuid(forInvitedMember: serviceId.uuidValue))
        } else if groupMembership.isRequestingMember(serviceId.uuidValue) {
            return .requesting
        } else {
            return .none
        }
    }

    // MARK: - Updater

    enum Updater {
        case localUser
        case otherUser(updaterName: String, updaterAddress: SignalServiceAddress)
        case unknown
    }

    // MARK: - Defaults

    static func defaultGroupUpdateItem(
        groupUpdateSourceAddress: SignalServiceAddress?,
        localIdentifiers: LocalIdentifiers?,
        contactsManager: Shims.ContactsManager,
        tx: DBReadTransaction
    ) -> GroupUpdateItem {
        let updater = buildUpdater(
            groupUpdateSourceAddress: groupUpdateSourceAddress,
            updaterKnownToBeLocalUser: false,
            localIdentifiers: localIdentifiers,
            contactsManager: contactsManager,
            tx: tx
        )

        switch updater {
        case .localUser:
            return .genericUpdateByLocalUser
        case let .otherUser(updaterName, updaterAddress):
            return .genericUpdateByOtherUser(
                updaterName: updaterName,
                updaterAddress: updaterAddress
            )
        case .unknown:
            return .genericUpdateByUnknownUser
        }
    }
}

// MARK: - Dependencies

extension GroupUpdateItemBuilderImpl {
    enum Shims {
        typealias ContactsManager = _GroupUpdateCopy_ContactsManager_Shim
    }

    enum Wrappers {
        typealias ContactsManager = _GroupUpdateCopy_ContactsManager_Wrapper
    }
}

protocol _GroupUpdateCopy_ContactsManager_Shim {
    func displayName(address: SignalServiceAddress, tx: DBReadTransaction) -> String
}

class _GroupUpdateCopy_ContactsManager_Wrapper: _GroupUpdateCopy_ContactsManager_Shim {
    private let contactsManager: ContactsManagerProtocol

    init(_ contactsManager: ContactsManagerProtocol) {
        self.contactsManager = contactsManager
    }

    func displayName(address: SignalServiceAddress, tx: DBReadTransaction) -> String {
        return contactsManager.displayName(for: address, transaction: SDSDB.shimOnlyBridge(tx))
    }
}
