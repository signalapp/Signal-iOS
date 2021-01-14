//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objcMembers
public class GroupUpdateCopyItem: NSObject {
    public let type: GroupUpdateType
    public let text: String

    init(type: GroupUpdateType, text: String) {
        self.type = type
        self.text = text
    }
}

@objc
public enum GroupUpdateType: Int {
    case groupCreated
    case userMembershipState
    case userMembershipState_left
    case userMembershipState_removed
    case userMembershipState_invited
    case userMembershipState_added
    case userMembershipState_invitesNew
    case userMembershipState_invitesDeclined
    case userMembershipState_invitesRevoked
    case userMembershipState_invalidInvitesAdded
    case userMembershipState_invalidInvitesRemoved
    case userRole
    case groupName
    case groupAvatar
    case accessMembers
    case accessAttributes
    case disappearingMessagesState
    case disappearingMessagesState_enabled
    case disappearingMessagesState_disabled
    case groupInviteLink
    case generic
    case groupMigrated
    case groupMigrated_usersDropped
    case groupMigrated_usersInvited
    case groupGroupLinkPromotion
    case debug

    var typeForDeduplication: GroupUpdateType {
        switch self {
        // A given user can only have one of these states per update,
        // so for deduplication purposes we treat them as all the same
        case .userMembershipState_left,
             .userMembershipState_removed,
             .userMembershipState_invited,
             .userMembershipState_added:
            return .userMembershipState
        case .disappearingMessagesState_enabled,
             .disappearingMessagesState_disabled:
            return .disappearingMessagesState
        default:
            return self
        }
    }
}

struct GroupUpdateCopy {

    // MARK: - Dependencies

    private static var contactsManager: ContactsManagerProtocol {
        return SSKEnvironment.shared.contactsManager
    }

    private var contactsManager: ContactsManagerProtocol {
        return SSKEnvironment.shared.contactsManager
    }

    private static var tsAccountManager: TSAccountManager {
        return TSAccountManager.shared()
    }

    // MARK: -

    struct UpdateItem: Hashable {
        let type: GroupUpdateType
        let address: SignalServiceAddress?

        init(type: GroupUpdateType, address: SignalServiceAddress?) {
            self.type = type
            self.address = address
        }
    }

    // MARK: -

    let newGroupModel: TSGroupModel
    let newGroupMembership: GroupMembership
    let localAddress: SignalServiceAddress
    let groupUpdateSourceAddress: SignalServiceAddress?
    let updater: Updater
    let transaction: SDSAnyReadTransaction
    let isReplacingJoinRequestPlaceholder: Bool

    // The update items, in order.
    public private(set) var itemList = [GroupUpdateCopyItem]()

    // We use this set to check for duplicate/conflicting items.
    // It will not affect production UI, but yield asserts in
    // debug builds and logging in production.
    private var itemSet = Set<UpdateItem>()

    init(newGroupModel: TSGroupModel,
         oldGroupModel: TSGroupModel?,
         oldDisappearingMessageToken: DisappearingMessageToken?,
         newDisappearingMessageToken: DisappearingMessageToken?,
         localAddress: SignalServiceAddress,
         groupUpdateSourceAddress: SignalServiceAddress?,
         transaction: SDSAnyReadTransaction) {
        self.newGroupModel = newGroupModel
        self.localAddress = localAddress
        self.groupUpdateSourceAddress = groupUpdateSourceAddress
        self.transaction = transaction
        self.newGroupMembership = newGroupModel.groupMembership
        self.updater = GroupUpdateCopy.updater(groupUpdateSourceAddress: groupUpdateSourceAddress,
                                               transaction: transaction)
        if let oldGroupModelV2 = oldGroupModel as? TSGroupModelV2 {
            self.isReplacingJoinRequestPlaceholder = oldGroupModelV2.isPlaceholderModel
        } else {
            self.isReplacingJoinRequestPlaceholder = false
        }

        switch updater {
        case .unknown:
            if oldGroupModel != nil,
                newGroupModel.groupsVersion == .V2 {
                if !newGroupModel.groupMembership.isLocalUserFullOrInvitedMember {
                    // There's a number of valid scenarios where we will not
                    // have the updater info if we are not a full or invited member.
                    Logger.warn("Missing updater info.")
                } else if !DebugFlags.permissiveGroupUpdateInfoMessages {
                    // This can happen due to a number of valid scenarios.
                    Logger.warn("Missing updater info.")
                } else {
                    addItem(.debug, copy: "Error: Missing updater info.")
                }
            }
        default:
            break
        }

        populate(oldGroupModel: oldGroupModel,
                 oldDisappearingMessageToken: oldDisappearingMessageToken,
                 newDisappearingMessageToken: newDisappearingMessageToken)
    }

    // MARK: -

    mutating func populate(oldGroupModel: TSGroupModel?,
                           oldDisappearingMessageToken: DisappearingMessageToken?,
                           newDisappearingMessageToken: DisappearingMessageToken?) {

        if let oldGroupModel = oldGroupModel {

            let oldGroupMembership = oldGroupModel.groupMembership

            if isReplacingJoinRequestPlaceholder {
                addMembershipUpdates(oldGroupMembership: oldGroupMembership,
                                     forLocalUserOnly: true)
            } else if wasJustMigrated {
                addMigrationUpdates(oldGroupMembership: oldGroupMembership)
            } else {
                addMembershipUpdates(oldGroupMembership: oldGroupMembership)

                addAttributesUpdates(oldGroupModel: oldGroupModel)

                addAccessUpdates(oldGroupModel: oldGroupModel)

                addDisappearingMessageUpdates(oldToken: oldDisappearingMessageToken,
                                              newToken: newDisappearingMessageToken)

                addGroupInviteLinkUpdates(oldGroupModel: oldGroupModel)
            }
        } else {
            // We're just learning of the group.
            addGroupWasInserted()

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
            if newGroupModel.groupsVersion == .V2 {
                if !DebugFlags.permissiveGroupUpdateInfoMessages {
                    owsFailDebug("Group update without any items.")
                } else {
                    addItem(.debug, copy: "Error: Group update without any items.")
                }
            }
            addItem(.generic, copy: defaultGroupUpdateDescription)
        }
    }

    // MARK: -

    mutating func addItem(_ type: GroupUpdateType,
                          address: SignalServiceAddress? = nil,
                          copy: String) {
        let item = UpdateItem(type: type.typeForDeduplication, address: address)
        if itemSet.contains(item),
            item.type != .debug {
            Logger.verbose("item: \(item)")
            owsFailDebug("Duplicate items.")
        }
        itemSet.insert(item)
        itemList.append(.init(type: type, text: copy))
    }

    mutating func addItem(_ type: GroupUpdateType,
                          address: SignalServiceAddress? = nil,
                          format: String, _ formatArgs: CVarArg...) {
        let copy = String(format: format, arguments: formatArgs)
        addItem(type, address: address, copy: copy)
    }

    var updateDescription: String {
        return itemList.map { $0.text }.joined(separator: "\n")
    }

    func wasUpdaterSameAs(_ address: SignalServiceAddress) -> Bool {
        switch updater {
        case .localUser:
            return false
        case .otherUser(_, let updaterAddress):
            return updaterAddress == address
        case .unknown:
            return false
        }
    }

    func wasUpdaterLocalUser() -> Bool {
        return wasUpdaterSameAs(localAddress)
    }
}

// MARK: -

// When deciding which copy to render and how to format it, we usually take into account 3-5 pieces of information:
//
// * The old state
// * The new state
// * Who made the update (the updater)
// * Which user was affected (often the local variable "account")
// * Whether or not the updater or "account" is the local user.
// * Some other info like "who did the inviting".
//
// e.g. if Alice sees that Bob declined his invite (invited by Carol) to a group...
//
// * The old state was "invited to the group".
// * The new state is "in the group".
//
// ...We infer that Bob declined an invite OR had their invite revoked.
//
// * "Bob" made the update.
// * "Bob" was affected.
//
// ...We infer that Bob declined the invite; it wasn't revoked by another user.
//
// * Neither the updater or "account" is the local user.
//
// ...So we don't want to special-case and say something like "You declined..." or "Your invite was revoked...", etc.
//
// * Carol "did the inviting".
//
// ...So the final copy should be something like "Bob declined his invitation from Carol."
extension GroupUpdateCopy {

    // MARK: - Attributes

    mutating func addAttributesUpdates(oldGroupModel: TSGroupModel) {

        let groupName = { (groupModel: TSGroupModel) -> String? in
            if let name = groupModel.groupName?.stripped, name.count > 0 {
                return name
            }
            return nil
        }
        let oldGroupName = groupName(oldGroupModel)
        let newGroupName = groupName(newGroupModel)
        if oldGroupName != newGroupName {
            if let name = newGroupName {
                switch updater {
                case .localUser:
                    let format = NSLocalizedString("GROUP_UPDATED_NAME_UPDATED_BY_LOCAL_USER_FORMAT",
                                                   comment: "Message indicating that the group's name was changed by the local user. Embeds {{new group name}}.")
                    addItem(.groupName, format: format, name)
                case .otherUser(let updaterName, _):
                    let format = NSLocalizedString("GROUP_UPDATED_NAME_UPDATED_BY_REMOTE_USER_FORMAT",
                                                   comment: "Message indicating that the group's name was changed by a remote user. Embeds {{ %1$@ user who changed the name, %2$@ new group name}}.")
                    addItem(.groupName, format: format, updaterName, name)
                case .unknown:
                    let format = NSLocalizedString("GROUP_UPDATED_NAME_UPDATED_FORMAT",
                                                   comment: "Message indicating that the group's name was changed. Embeds {{new group name}}.")
                    addItem(.groupName, format: format, name)
                }
            } else {
                switch updater {
                case .localUser:
                    addItem(.groupName, copy: NSLocalizedString("GROUP_UPDATED_NAME_REMOVED_BY_LOCAL_USER",
                                                                comment: "Message indicating that the group's name was removed by the local user."))
                case .otherUser(let updaterName, _):
                    let format = NSLocalizedString("GROUP_UPDATED_NAME_REMOVED_BY_REMOTE_USER_FORMAT",
                                                   comment: "Message indicating that the group's name was removed by a remote user. Embeds {{user who removed the name}}.")
                    addItem(.groupName, format: format, updaterName)
                case .unknown:
                    addItem(.groupName, copy: NSLocalizedString("GROUP_UPDATED_NAME_REMOVED",
                                                                comment: "Message indicating that the group's name was removed."))
                }
            }
        }

        if oldGroupModel.groupAvatarData != newGroupModel.groupAvatarData {
            if let toGroupAvatarData = newGroupModel.groupAvatarData, toGroupAvatarData.count > 0 {
                switch updater {
                case .localUser:
                    addItem(.groupAvatar, copy: NSLocalizedString("GROUP_UPDATED_AVATAR_UPDATED_BY_LOCAL_USER",
                                                                  comment: "Message indicating that the group's avatar was changed."))
                case .otherUser(let updaterName, _):
                    let format = NSLocalizedString("GROUP_UPDATED_AVATAR_UPDATED_BY_REMOTE_USER_FORMAT",
                                                   comment: "Message indicating that the group's avatar was changed by a remote user. Embeds {{user who changed the avatar}}.")
                    addItem(.groupAvatar, format: format, updaterName)
                case .unknown:
                    addItem(.groupAvatar, copy: NSLocalizedString("GROUP_UPDATED_AVATAR_UPDATED",
                                                                  comment: "Message indicating that the group's avatar was changed."))
                }
            } else {
                switch updater {
                case .localUser:
                    addItem(.groupAvatar, copy: NSLocalizedString("GROUP_UPDATED_AVATAR_REMOVED_BY_LOCAL_USER",
                                                                  comment: "Message indicating that the group's avatar was removed."))
                case .otherUser(let updaterName, _):
                    let format = NSLocalizedString("GROUP_UPDATED_AVATAR_REMOVED_BY_REMOTE_USER_FORMAT",
                                                   comment: "Message indicating that the group's avatar was removed by a remote user. Embeds {{user who removed the avatar}}.")
                    addItem(.groupAvatar, format: format, updaterName)
                case .unknown:
                    addItem(.groupAvatar, copy: NSLocalizedString("GROUP_UPDATED_AVATAR_REMOVED",
                                                                  comment: "Message indicating that the group's avatar was removed."))
                }
            }
        }
    }

    // MARK: - Access

    mutating func description(for access: GroupV2Access) -> String {
        switch access {
        case .unknown:
            if !DebugFlags.permissiveGroupUpdateInfoMessages {
                owsFailDebug("Unknown access level.")
            } else {
                addItem(.debug, copy: "Error: Unknown access level.")
            }
            return NSLocalizedString("GROUP_ACCESS_LEVEL_UNKNOWN",
                                     comment: "Description of the 'unknown' access level.")
        case .any:
            return NSLocalizedString("GROUP_ACCESS_LEVEL_ANY",
                                     comment: "Description of the 'all users' access level.")
        case .member:
            return NSLocalizedString("GROUP_ACCESS_LEVEL_MEMBER",
                                     comment: "Description of the 'all members' access level.")
        case .administrator:
            return NSLocalizedString("GROUP_ACCESS_LEVEL_ADMINISTRATORS",
                                     comment: "Description of the 'admins only' access level.")
        case .unsatisfiable:
            // TODO:
            return NSLocalizedString("GROUP_ACCESS_LEVEL_UNSATISFIABLE",
                                     comment: "Description of the 'unsatisfiable' access level.")
        }
    }

    mutating func addAccessUpdates(oldGroupModel: TSGroupModel) {
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
            let accessName = description(for: newAccess.members)

            switch updater {
            case .localUser:
                let format = NSLocalizedString("GROUP_ACCESS_MEMBERS_UPDATED_BY_LOCAL_USER_FORMAT",
                                               comment: "Message indicating that the access to the group's members was changed by the local user. Embeds {{new access level}}.")
                addItem(.accessMembers, format: format, accessName)
            case .otherUser(let updaterName, _):
                let format = NSLocalizedString("GROUP_ACCESS_MEMBERS_UPDATED_BY_REMOTE_USER_FORMAT",
                                               comment: "Message indicating that the access to the group's members was changed by a remote user. Embeds {{ %1$@ user who changed the access, %2$@ new access level}}.")
                addItem(.accessMembers, format: format, updaterName, accessName)
            case .unknown:
                let format = NSLocalizedString("GROUP_ACCESS_MEMBERS_UPDATED_FORMAT",
                                               comment: "Message indicating that the access to the group's members was changed. Embeds {{new access level}}.")
                addItem(.accessMembers, format: format, accessName)
            }
        }

        if oldAccess.attributes != newAccess.attributes {
            let accessName = description(for: newAccess.attributes)

            switch updater {
            case .localUser:
                let format = NSLocalizedString("GROUP_ACCESS_ATTRIBUTES_UPDATED_BY_LOCAL_USER_FORMAT",
                                               comment: "Message indicating that the access to the group's attributes was changed by the local user. Embeds {{new access level}}.")
                addItem(.accessAttributes, format: format, accessName)
            case .otherUser(let updaterName, _):
                let format = NSLocalizedString("GROUP_ACCESS_ATTRIBUTES_UPDATED_BY_REMOTE_USER_FORMAT",
                                               comment: "Message indicating that the access to the group's attributes was changed by a remote user. Embeds {{ %1$@ user who changed the access, %2$@ new access level}}.")
                addItem(.accessAttributes, format: format, updaterName, accessName)
            case .unknown:
                let format = NSLocalizedString("GROUP_ACCESS_ATTRIBUTES_UPDATED_FORMAT",
                                               comment: "Message indicating that the access to the group's attributes was changed. Embeds {{new access level}}.")
                addItem(.accessAttributes, format: format, accessName)
            }
        }
    }

    // MARK: - Membership

    // If Alice and Bob are in a group, and Alice invites Carol,
    // Bob is likely to have no info about Carol and won't be
    // able to render her name/id.  So in some cases we just
    // render user "counts", e.g. Bob might see:
    // "Alice invited 1 person to the group."
    struct MembershipCounts {
        var invitedUserCount: UInt = 0
        var inviteRevokedCount: UInt = 0
    }

    mutating func addMembershipUpdates(oldGroupMembership: GroupMembership, forLocalUserOnly: Bool = false) {
        var membershipCounts = MembershipCounts()

        let allUsersUnsorted = oldGroupMembership.allMembersOfAnyKind.union(newGroupMembership.allMembersOfAnyKind)
        var allUsersSorted = Array(allUsersUnsorted).stableSort()
        // If local user had a membership update, ensure it appears _first_.
        if allUsersSorted.contains(localAddress) {
            allUsersSorted = [localAddress] + allUsersSorted.filter { $0 != localAddress}
        }
        // If the updater has changed their membership status, ensure it appears _last_.
        // This trumps the re-ordering of the local user above.
        if let groupUpdateSourceAddress = groupUpdateSourceAddress {
            allUsersSorted = allUsersSorted.filter { $0 != groupUpdateSourceAddress} + [groupUpdateSourceAddress]
        }

        for address in allUsersSorted {
            if forLocalUserOnly, address != localAddress {
                continue
            }

            let oldMembershipStatus = membershipStatus(of: address, in: oldGroupMembership)
            let newMembershipStatus = membershipStatus(of: address, in: newGroupMembership)

            switch oldMembershipStatus {
            case .normalMember:
                switch newMembershipStatus {
                case .normalMember:
                    // Membership status didn't change.
                    // Check for role changes.
                    addMemberRoleUpdates(for: address, oldGroupMembership: oldGroupMembership)
                case .invited:
                    addUserLeftOrWasKickedOutOfGroupThenWasInvitedToTheGroup(for: address)
                case .requesting:
                    // This could happen if a user leaves a group, the requests to rejoin
                    // and we do have access to the intervening revisions.
                    addUserRequestedToJoinGroup(for: address)
                case .none:
                    addUserLeftOrWasKickedOutOfGroup(for: address)
                }
            case .invited:
                switch newMembershipStatus {
                case .normalMember:
                    var wasInviteAccepted = false
                    switch updater {
                    case .localUser:
                        wasInviteAccepted = localAddress == address
                    case .otherUser(_, let updaterAddress):
                        wasInviteAccepted = updaterAddress == address
                    case .unknown:
                        wasInviteAccepted = false
                    }

                    if wasInviteAccepted {
                        addUserInviteWasAccepted(for: address,
                                                 oldGroupMembership: oldGroupMembership)
                    } else {
                        addUserWasAddedToTheGroup(for: address)
                    }
                case .invited:
                    // Membership status didn't change.
                    break
                case .requesting:
                    addUserRequestedToJoinGroup(for: address)
                case .none:
                    addUserInviteWasDeclinedOrRevoked(for: address,
                                                      oldGroupMembership: oldGroupMembership,
                                                      membershipCounts: &membershipCounts)
                }
            case .requesting:
                switch newMembershipStatus {
                case .normalMember:
                    addUserRequestWasApproved(for: address)
                case .invited:
                    addUserWasInvitedToTheGroup(for: address,
                                                membershipCounts: &membershipCounts)
                case .requesting:
                    // Membership status didn't change.
                    break
                case .none:
                    addUserRequestWasRejected(for: address)
                }
            case .none:
                switch newMembershipStatus {
                case .normalMember:
                    if newGroupMembership.didJoinFromInviteLink(forFullMember: address) {
                        addUserJoinedFromInviteLink(for: address)
                    } else {
                        addUserWasAddedToTheGroup(for: address)
                    }
                case .invited:
                    addUserWasInvitedToTheGroup(for: address,
                                                membershipCounts: &membershipCounts)
                case .requesting:
                    addUserRequestedToJoinGroup(for: address)
                case .none:
                    // Membership status didn't change.
                    break
                }
            }
        }

        // We don't necessarily have profile/contact info for invited
        // members, so we render these as counts.
        addUnnamedUsersWereInvited(count: membershipCounts.invitedUserCount)
        addUnnamedUserInvitesWereRevoked(count: membershipCounts.inviteRevokedCount)

        addInvalidInviteUpdates(oldGroupMembership: oldGroupMembership,
                                newGroupMembership: newGroupMembership)
    }

    mutating func addInvalidInviteUpdates(oldGroupMembership: GroupMembership,
                                          newGroupMembership: GroupMembership) {
        let oldInvalidInviteUserIds = Set(oldGroupMembership.invalidInvites.map { $0.userId })
        let newInvalidInviteUserIds = Set(newGroupMembership.invalidInvites.map { $0.userId })
        let addedInvalidInviteCount = newInvalidInviteUserIds.subtracting(oldInvalidInviteUserIds).count
        let removedInvalidInviteCount = oldInvalidInviteUserIds.subtracting(newInvalidInviteUserIds).count

        if addedInvalidInviteCount > 0 {
            switch updater {
            case .localUser:
                let copy: String
                if addedInvalidInviteCount > 1 {
                    copy = NSLocalizedString("GROUP_INVALID_INVITES_ADDED_BY_LOCAL_USER_N",
                                             comment: "Message indicating that multiple invalid invites were added by the local user.")
                } else {
                    copy = NSLocalizedString("GROUP_INVALID_INVITES_ADDED_BY_LOCAL_USER_1",
                                             comment: "Message indicating that 1 invalid invite was added by the local user.")
                }
                addItem(.userMembershipState_invalidInvitesAdded, copy: copy)
            case .otherUser(let updaterName, _):
                let format: String
                if addedInvalidInviteCount > 1 {
                    format = NSLocalizedString("GROUP_INVALID_INVITES_ADDED_BY_REMOTE_USER_FORMAT_N",
                                               comment: "Message indicating that multiple invalid invites were added by another user. Embeds {{remote user name}}.")
                } else {
                    format = NSLocalizedString("GROUP_INVALID_INVITES_ADDED_BY_REMOTE_USER_FORMAT_1",
                                               comment: "Message indicating that 1 invalid invite was added by another user. Embeds {{remote user name}}.")
                }
                addItem(.userMembershipState_invalidInvitesAdded,
                        format: format, updaterName)
            case .unknown:
                let copy: String
                if addedInvalidInviteCount > 1 {
                    copy = NSLocalizedString("GROUP_INVALID_INVITES_ADDED_N",
                                             comment: "Message indicating that multiple invalid invites were added to the group.")
                } else {
                    copy = NSLocalizedString("GROUP_INVALID_INVITES_ADDED_1",
                                             comment: "Message indicating that 1 invalid invite was added to the group.")
                }
                addItem(.userMembershipState_invalidInvitesAdded, copy: copy)
            }
        }

        if removedInvalidInviteCount > 0 {
            switch updater {
            case .localUser:
                let copy: String
                if removedInvalidInviteCount > 1 {
                    copy = NSLocalizedString("GROUP_INVALID_INVITES_REMOVED_BY_LOCAL_USER_N",
                                             comment: "Message indicating that multiple invalid invites were revoked by the local user.")
                } else {
                    copy = NSLocalizedString("GROUP_INVALID_INVITES_REMOVED_BY_LOCAL_USER_1",
                                             comment: "Message indicating that 1 invalid invite was revoked by the local user.")
                }
                addItem(.userMembershipState_invalidInvitesRemoved, copy: copy)
            case .otherUser(let updaterName, _):
                let format: String
                if removedInvalidInviteCount > 1 {
                    format = NSLocalizedString("GROUP_INVALID_INVITES_REMOVED_BY_REMOTE_USER_FORMAT_N",
                                               comment: "Message indicating that multiple invalid invites were revoked by another user. Embeds {{remote user name}}.")
                } else {
                    format = NSLocalizedString("GROUP_INVALID_INVITES_REMOVED_BY_REMOTE_USER_FORMAT_1",
                                               comment: "Message indicating that 1 invalid invite was revoked by another user. Embeds {{remote user name}}.")
                }
                addItem(.userMembershipState_invalidInvitesRemoved,
                        format: format, updaterName)
            case .unknown:
                let copy: String
                if removedInvalidInviteCount > 1 {
                    copy = NSLocalizedString("GROUP_INVALID_INVITES_REMOVED_N",
                                             comment: "Message indicating that multiple invalid invites were revoked.")
                } else {
                    copy = NSLocalizedString("GROUP_INVALID_INVITES_REMOVED_1",
                                             comment: "Message indicating that 1 invalid invite was revoked.")
                }
                addItem(.userMembershipState_invalidInvitesRemoved, copy: copy)
            }
        }
    }

    mutating func addMemberRoleUpdates(for address: SignalServiceAddress,
                                       oldGroupMembership: GroupMembership) {

        let oldIsAdministrator = oldGroupMembership.isFullMemberAndAdministrator(address)
        let newIsAdministrator = newGroupMembership.isFullMemberAndAdministrator(address)

        guard oldIsAdministrator != newIsAdministrator else {
            // Role didn't change.
            return
        }

        if newIsAdministrator {
            addUserWasGrantedAdministrator(for: address)
        } else {
            addUserWasRevokedAdministrator(for: address)
        }
    }

    mutating func addUserWasGrantedAdministrator(for address: SignalServiceAddress) {

        if let newGroupModelV2 = newGroupModel as? TSGroupModelV2,
            newGroupModelV2.wasJustMigrated {
            // All v1 group members become admins when the
            // group is migrated to v2. We don't need to
            // surface this to the user.
            return
        }

        let isLocalUser = localAddress == address
        if isLocalUser {
            switch updater {
            case .localUser:
                if !DebugFlags.permissiveGroupUpdateInfoMessages {
                    owsFailDebug("Local user made themself administrator.")
                } else {
                    addItem(.debug, copy: "Error: Local user made themself administrator.")
                }
                addItem(.userRole,
                        address: address,
                        copy: NSLocalizedString("GROUP_LOCAL_USER_GRANTED_ADMINISTRATOR",
                                                comment: "Message indicating that the local user was granted administrator role."))
            case .otherUser(let updaterName, let updaterAddress):
                if updaterAddress == address {
                    if !DebugFlags.permissiveGroupUpdateInfoMessages {
                        owsFailDebug("Remote user made themself administrator.")
                    } else {
                        addItem(.debug, copy: "Error: Remote user made themself administrator.")
                    }
                    addItem(.userRole,
                            address: address,
                            copy: NSLocalizedString("GROUP_LOCAL_USER_GRANTED_ADMINISTRATOR",
                                                    comment: "Message indicating that the local user was granted administrator role."))
                } else {
                    let format = NSLocalizedString("GROUP_LOCAL_USER_GRANTED_ADMINISTRATOR_BY_REMOTE_USER_FORMAT",
                                                   comment: "Message indicating that the local user was granted administrator role by another user. Embeds {{remote user name}}.")
                    addItem(.userRole,
                            address: address,
                            format: format, updaterName)
                }
            case .unknown:
                addItem(.userRole,
                        address: address,
                        copy: NSLocalizedString("GROUP_LOCAL_USER_GRANTED_ADMINISTRATOR",
                                                comment: "Message indicating that the local user was granted administrator role."))
            }
        } else {
            let userName = self.contactsManager.displayName(for: address, transaction: transaction)

            switch updater {
            case .localUser:
                let format = NSLocalizedString("GROUP_REMOTE_USER_GRANTED_ADMINISTRATOR_BY_LOCAL_USER",
                                               comment: "Message indicating that a remote user was granted administrator role by local user. Embeds {{remote user name}}.")
                addItem(.userRole,
                        address: address,
                        format: format, userName)
            case .otherUser(let updaterName, let updaterAddress):
                if updaterAddress == address {
                    if !DebugFlags.permissiveGroupUpdateInfoMessages {
                        owsFailDebug("Remote user made themself administrator.")
                    } else {
                        addItem(.debug, copy: "Error: Remote user made themself administrator.")
                    }
                    let format = NSLocalizedString("GROUP_REMOTE_USER_GRANTED_ADMINISTRATOR",
                                                   comment: "Message indicating that a remote user was granted administrator role. Embeds {{remote user name}}.")
                    addItem(.userRole,
                            address: address,
                            format: format, userName)
                } else {
                    let format = NSLocalizedString("GROUP_REMOTE_USER_GRANTED_ADMINISTRATOR_BY_REMOTE_USER_FORMAT",
                                                   comment: "Message indicating that a remote user was granted administrator role by another user. Embeds {{ %1$@ user who granted, %2$@ user who was granted administrator role}}.")
                    addItem(.userRole,
                            address: address,
                            format: format, updaterName, userName)
                }
            case .unknown:
                let format = NSLocalizedString("GROUP_REMOTE_USER_GRANTED_ADMINISTRATOR",
                                               comment: "Message indicating that a remote user was granted administrator role. Embeds {{remote user name}}.")
                addItem(.userRole,
                        address: address,
                        format: format, userName)
            }
        }
    }

    mutating func addUserWasRevokedAdministrator(for address: SignalServiceAddress) {
        let isLocalUser = localAddress == address
        if isLocalUser {
            switch updater {
            case .localUser:
                addItem(.userRole,
                        address: address,
                        copy: NSLocalizedString("GROUP_LOCAL_USER_REVOKED_ADMINISTRATOR",
                                                comment: "Message indicating that the local user had their administrator role revoked."))
            case .otherUser(let updaterName, let updaterAddress):
                if updaterAddress == address {
                    addItem(.userRole,
                            address: address,
                            copy: NSLocalizedString("GROUP_LOCAL_USER_REVOKED_ADMINISTRATOR",
                                                    comment: "Message indicating that the local user had their administrator role revoked."))
                } else {
                    let format = NSLocalizedString("GROUP_LOCAL_USER_REVOKED_ADMINISTRATOR_BY_REMOTE_USER_FORMAT",
                                                   comment: "Message indicating that the local user had their administrator role revoked by another user. Embeds {{remote user name}}.")
                    addItem(.userRole,
                            address: address,
                            format: format, updaterName)
                }
            case .unknown:
                addItem(.userRole,
                        address: address,
                        copy: NSLocalizedString("GROUP_LOCAL_USER_REVOKED_ADMINISTRATOR",
                                                comment: "Message indicating that the local user had their administrator role revoked."))
            }
        } else {
            let userName = contactsManager.displayName(for: address, transaction: transaction)

            switch updater {
            case .localUser:
                let format = NSLocalizedString("GROUP_REMOTE_USER_REVOKED_ADMINISTRATOR_BY_LOCAL_USER",
                                               comment: "Message indicating that a remote user had their administrator role revoked by local user. Embeds {{remote user name}}.")
                addItem(.userRole,
                        address: address,
                        format: format, userName)
            case .otherUser(let updaterName, let updaterAddress):
                if updaterAddress == address {
                    let format = NSLocalizedString("GROUP_REMOTE_USER_REVOKED_ADMINISTRATOR",
                                                   comment: "Message indicating that a remote user had their administrator role revoked. Embeds {{remote user name}}.")
                    addItem(.userRole,
                            address: address,
                            format: format, userName)
                } else {
                    let format = NSLocalizedString("GROUP_REMOTE_USER_REVOKED_ADMINISTRATOR_BY_REMOTE_USER_FORMAT",
                                                   comment: "Message indicating that a remote user had their administrator role revoked by another user. Embeds {{ %1$@ user who revoked, %2$@ user who was granted administrator role}}.")
                    addItem(.userRole,
                            address: address,
                            format: format, updaterName, userName)
                }
            case .unknown:
                let format = NSLocalizedString("GROUP_REMOTE_USER_REVOKED_ADMINISTRATOR",
                                               comment: "Message indicating that a remote user had their administrator role revoked. Embeds {{remote user name}}.")
                addItem(.userRole,
                        address: address,
                        format: format, userName)
            }
        }
    }

    mutating func addUserLeftOrWasKickedOutOfGroup(for address: SignalServiceAddress) {

        let isLocalUser = localAddress == address
        if isLocalUser {
            // Local user has left or been kicked out of the group.
            switch updater {
            case .localUser:
                addItem(.userMembershipState_left,
                        address: address,
                        copy: NSLocalizedString("GROUP_YOU_LEFT",
                                                comment: "Message indicating that the local user left the group."))
            case .otherUser(let updaterName, _):
                let format = NSLocalizedString("GROUP_LOCAL_USER_REMOVED_BY_REMOTE_USER_FORMAT",
                                               comment: "Message indicating that the local user was removed from the group by another user. Embeds {{remote user name}}.")
                addItem(.userMembershipState_removed,
                        address: address,
                        format: format, updaterName)
            case .unknown:
                addItem(.userMembershipState_removed,
                        address: address,
                        copy: NSLocalizedString("GROUP_LOCAL_USER_REMOVED_BY_UNKNOWN_USER",
                                                comment: "Message indicating that the local user was removed from the group by an unknown user."))
            }
        } else {
            let userName = contactsManager.displayName(for: address, transaction: transaction)

            switch updater {
            case .localUser:
                let format = NSLocalizedString("GROUP_REMOTE_USER_REMOVED_BY_LOCAL_USER_FORMAT",
                                               comment: "Message indicating that a remote user was removed from the group by the local user. Embeds {{remote user name}}.")
                addItem(.userMembershipState_removed,
                        address: address,
                        format: format, userName)
            case .otherUser(let updaterName, let updaterAddress):
                if updaterAddress == address {
                    let format = NSLocalizedString("GROUP_REMOTE_USER_LEFT_GROUP_FORMAT",
                                                   comment: "Message indicating that a remote user has left the group. Embeds {{remote user name}}.")
                    addItem(.userMembershipState_left,
                            address: address,
                            format: format, userName)
                } else {
                    let format = NSLocalizedString("GROUP_REMOTE_USER_REMOVED_FROM_GROUP_BY_REMOTE_USER_FORMAT",
                                                   comment: "Message indicating that the remote user was removed from the group. Embeds {{ %1$@ user who removed the user, %2$@ user who was removed}}.")
                    addItem(.userMembershipState_removed,
                            address: address,
                            format: format, updaterName, userName)
                }
            case .unknown:
                let format = NSLocalizedString("GROUP_REMOTE_USER_LEFT_GROUP_FORMAT",
                                               comment: "Message indicating that a remote user has left the group. Embeds {{remote user name}}.")
                addItem(.userMembershipState_left,
                        address: address,
                        format: format, userName)
            }
        }
    }

    mutating func addUserLeftOrWasKickedOutOfGroupThenWasInvitedToTheGroup(for address: SignalServiceAddress) {

        let isLocalUser = localAddress == address
        if isLocalUser {
            addItem(.userMembershipState_removed,
                    address: address,
                    copy: NSLocalizedString("GROUP_LOCAL_USER_REMOVED_BY_UNKNOWN_USER",
                                            comment: "Message indicating that the local user was removed from the group by an unknown user."))
            addItem(.userMembershipState_invited,
                    address: address,
                    copy: NSLocalizedString("GROUP_LOCAL_USER_INVITED_TO_THE_GROUP",
                                            comment: "Message indicating that the local user was invited to the group."))
        } else {
            let userName = contactsManager.displayName(for: address, transaction: transaction)
            do {
                let format = NSLocalizedString("GROUP_REMOTE_USER_LEFT_GROUP_FORMAT",
                                               comment: "Message indicating that a remote user has left the group. Embeds {{remote user name}}.")
                addItem(.userMembershipState_left,
                        address: address,
                        format: format, userName)
            }
            do {
                let format = NSLocalizedString("GROUP_REMOTE_USER_INVITED_1_FORMAT",
                                               comment: "Message indicating that a single remote user was invited to the group. Embeds {{remote user name}}.")
                addItem(.userMembershipState_invited,
                        address: address,
                        format: format, userName)
            }
        }
    }

    mutating func addUserInviteWasAccepted(for address: SignalServiceAddress,
                                           oldGroupMembership: GroupMembership) {

        var inviterName: String?
        var inviterAddress: SignalServiceAddress?
        if let inviterUuid = oldGroupMembership.addedByUuid(forInvitedMember: address) {
            inviterAddress = SignalServiceAddress(uuid: inviterUuid)
            inviterName = contactsManager.displayName(for: SignalServiceAddress(uuid: inviterUuid),
                                                      transaction: transaction)
        }

        let isLocalUser = localAddress == address
        if isLocalUser {
            switch updater {
            case .localUser:
                if let inviterName = inviterName {
                    let format = NSLocalizedString("GROUP_LOCAL_USER_INVITE_ACCEPTED_FORMAT",
                                                   comment: "Message indicating that the local user accepted an invite to the group. Embeds {{user who invited the local user}}.")
                    addItem(.userMembershipState_added,
                            address: address,
                            format: format, inviterName)
                } else {
                    if !DebugFlags.permissiveGroupUpdateInfoMessages {
                        owsFailDebug("Missing inviter name.")
                    } else {
                        addItem(.debug, copy: "Error: Missing inviter name.")
                    }
                    addItem(.userMembershipState_added,
                            address: address,
                            copy: NSLocalizedString("GROUP_LOCAL_USER_INVITE_ACCEPTED",
                                                    comment: "Message indicating that the local user accepted an invite to the group."))
                }
            case .otherUser(let updaterName, _):
                let format = NSLocalizedString("GROUP_LOCAL_USER_ADDED_TO_GROUP_BY_REMOTE_USER_FORMAT",
                                               comment: "Message indicating that the local user was added to the group by another user. Embeds {{remote user name}}.")
                addItem(.userMembershipState_added,
                        address: address,
                        format: format, updaterName)
            case .unknown:
                addItem(.userMembershipState_added,
                        address: address,
                        copy: NSLocalizedString("GROUP_LOCAL_USER_JOINED_THE_GROUP",
                                                comment: "Message indicating that the local user has joined the group."))
            }
        } else {
            let userName = contactsManager.displayName(for: address, transaction: transaction)

            switch updater {
            case .localUser:
                let format = NSLocalizedString("GROUP_REMOTE_USER_ADDED_TO_GROUP_BY_LOCAL_USER_FORMAT",
                                               comment: "Message indicating that a remote user was added to the group by the local user. Embeds {{remote user name}}.")
                addItem(.userMembershipState_added,
                        address: address,
                        format: format, userName)
            case .otherUser(let updaterName, let updaterAddress):
                if address == updaterAddress {
                    if inviterAddress == localAddress {
                        let format = NSLocalizedString("GROUP_REMOTE_USER_ACCEPTED_INVITE_FROM_LOCAL_USER_FORMAT",
                                                       comment: "Message indicating that a remote user has accepted an invite from the local user. Embeds {{remote user name}}.")
                        addItem(.userMembershipState_added,
                                address: address,
                                format: format, updaterName)
                    } else if let inviterName = inviterName {
                        let format = NSLocalizedString("GROUP_REMOTE_USER_ACCEPTED_INVITE_FROM_REMOTE_USER_FORMAT",
                                                       comment: "Message indicating that a remote user has accepted their invite. Embeds {{ %1$@ user who accepted their invite, %2$@ user who invited the user}}.")
                        addItem(.userMembershipState_added,
                                address: address,
                                format: format, updaterName, inviterName)
                    } else {
                        if !DebugFlags.permissiveGroupUpdateInfoMessages {
                            owsFailDebug("Missing inviter name.")
                        } else {
                            addItem(.debug, copy: "Error: Missing inviter name.")
                        }
                        let format = NSLocalizedString("GROUP_REMOTE_USER_ACCEPTED_INVITE_FORMAT",
                                                       comment: "Message indicating that a remote user has accepted their invite. Embeds {{remote user name}}.")
                        addItem(.userMembershipState_added,
                                address: address,
                                format: format, updaterName)
                    }
                } else {
                    let format = NSLocalizedString("GROUP_REMOTE_USER_ADDED_TO_GROUP_BY_REMOTE_USER_FORMAT",
                                                   comment: "Message indicating that a remote user was added to the group by another user. Embeds {{ %1$@ user who added the user, %2$@ user who was added}}.")
                    addItem(.userMembershipState_added,
                            address: address,
                            format: format, updaterName, userName)
                }
            case .unknown:
                let format = NSLocalizedString("GROUP_REMOTE_USER_JOINED_GROUP_FORMAT",
                                               comment: "Message indicating that a remote user was added to the group. Embeds {{remote user name}}.")
                addItem(.userMembershipState_added,
                        address: address,
                        format: format, userName)
            }
        }
    }

    mutating func addUserInviteWasDeclinedOrRevoked(for address: SignalServiceAddress,
                                                    oldGroupMembership: GroupMembership,
                                                    membershipCounts: inout MembershipCounts) {

        var inviterName: String?
        var inviterAddress: SignalServiceAddress?
        if let inviterUuid = oldGroupMembership.addedByUuid(forInvitedMember: address) {
            inviterAddress = SignalServiceAddress(uuid: inviterUuid)
            inviterName = contactsManager.displayName(for: SignalServiceAddress(uuid: inviterUuid),
                                                      transaction: transaction)
        }

        let isLocalUser = localAddress == address
        if isLocalUser {
            switch updater {
            case .localUser:
                if let inviterName = inviterName {
                    let format = NSLocalizedString("GROUP_LOCAL_USER_INVITE_DECLINED_FORMAT",
                                                   comment: "Message indicating that the local user declined an invite to the group. Embeds {{user who invited the local user}}.")
                    addItem(.userMembershipState,
                            address: address,
                            format: format, inviterName)
                } else {
                    if !DebugFlags.permissiveGroupUpdateInfoMessages {
                        owsFailDebug("Missing inviter name.")
                    } else {
                        addItem(.debug, copy: "Error: Missing inviter name.")
                    }
                    addItem(.userMembershipState,
                            address: address,
                            copy: NSLocalizedString("GROUP_LOCAL_USER_INVITE_DECLINED_BY_LOCAL_USER",
                                                    comment: "Message indicating that the local user declined an invite to the group."))
                }
            case .otherUser(let updaterName, _):
                let format = NSLocalizedString("GROUP_LOCAL_USER_INVITE_REVOKED_BY_REMOTE_USER_FORMAT",
                                               comment: "Message indicating that the local user's invite was revoked by another user. Embeds {{remote user name}}.")
                addItem(.userMembershipState,
                        address: address,
                        format: format, updaterName)
            case .unknown:
                addItem(.userMembershipState,
                        address: address,
                        copy: NSLocalizedString("GROUP_LOCAL_USER_INVITE_REVOKED_BY_UNKNOWN_USER",
                                                comment: "Message indicating that the local user's invite was revoked by an unknown user."))
            }
        } else {
            let userName = contactsManager.displayName(for: address, transaction: transaction)

            switch updater {
            case .localUser:
                let format = NSLocalizedString("GROUP_REMOTE_USER_INVITE_REVOKED_BY_LOCAL_USER_FORMAT",
                                               comment: "Message indicating that a remote user's invite was revoked by the local user. Embeds {{remote user name}}.")
                addItem(.userMembershipState,
                        address: address,
                        format: format, userName)
            case .otherUser(let updaterName, let updaterAddress):
                if address == updaterAddress {
                    if inviterAddress == localAddress {
                        let format = NSLocalizedString("GROUP_REMOTE_USER_DECLINED_INVITE_FROM_LOCAL_USER_FORMAT",
                                                       comment: "Message indicating that a remote user has declined an invite to the group from the local user. Embeds {{remote user name}}.")
                        addItem(.userMembershipState,
                                address: address,
                                format: format, updaterName)
                    } else if let inviterName = inviterName {
                        let format = NSLocalizedString("GROUP_REMOTE_USER_DECLINED_INVITE_FORMAT",
                                                       comment: "Message indicating that a remote user has declined their invite. Embeds {{ user who invited them }}.")
                        addItem(.userMembershipState,
                                address: address,
                                format: format, inviterName)
                    } else {
                        addItem(.userMembershipState,
                                address: address,
                                copy: NSLocalizedString("GROUP_REMOTE_USER_DECLINED_INVITE",
                                                        comment: "Message indicating that a remote user has declined their invite."))
                    }
                } else {
                    membershipCounts.inviteRevokedCount += 1
                }
            case .unknown:
                membershipCounts.inviteRevokedCount += 1
            }
        }
    }

    mutating func addUnnamedUserInvitesWereRevoked(count: UInt) {
        guard count > 0 else {
            return
        }
        let countString = OWSFormat.formatUInt(count)

        switch updater {
        case .localUser:
            if !DebugFlags.permissiveGroupUpdateInfoMessages {
                owsFailDebug("Unexpected updater.")
            } else {
                addItem(.debug, copy: "Error: Unexpected updater.")
            }
        case .otherUser(let updaterName, _):
            if count == 1 {
                let format = NSLocalizedString("GROUP_REMOTE_USER_INVITE_REVOKED_BY_REMOTE_USER_1_FORMAT",
                                               comment: "Message indicating that a single remote user's invite was revoked by a remote user. Embeds {{ user who revoked the invite }}.")
                addItem(.userMembershipState_invitesRevoked,
                        format: format, updaterName, countString)
            } else {
                let format = NSLocalizedString("GROUP_REMOTE_USER_INVITE_REVOKED_BY_REMOTE_USER_N_FORMAT",
                                               comment: "Message indicating that a group of remote users' invites were revoked by a remote user. Embeds {{ %1$@ user who revoked the invite, %2$@ number of users }}.")
                addItem(.userMembershipState_invitesRevoked,
                        format: format, updaterName, countString)
            }
        case .unknown:
            if count == 1 {
                addItem(.userMembershipState_invitesRevoked,
                        copy: NSLocalizedString("GROUP_REMOTE_USER_INVITE_REVOKED_1",
                                                comment: "Message indicating that a single remote user's invite was revoked."))
            } else {
                let format = NSLocalizedString("GROUP_REMOTE_USER_INVITE_REVOKED_N_FORMAT",
                                               comment: "Message indicating that a group of remote users' invites were revoked. Embeds {{ number of users }}.")
                addItem(.userMembershipState_invitesRevoked,
                        format: format, countString)
            }
        }
    }

    mutating func addUserWasAddedToTheGroup(for address: SignalServiceAddress) {

        let isLocalUser = localAddress == address
        if isLocalUser {
            switch updater {
            case .localUser:
                if !DebugFlags.permissiveGroupUpdateInfoMessages {
                    owsFailDebug("User added themself to the group.")
                } else {
                    addItem(.debug, copy: "Error: User added themself to the group.")
                }
                addItem(.userMembershipState_added,
                        address: address,
                        copy: NSLocalizedString("GROUP_LOCAL_USER_WAS_ADDED_TO_THE_GROUP",
                                                comment: "Message indicating that the local user was added to the group."))
            case .otherUser(let updaterName, _):
                let format = NSLocalizedString("GROUP_LOCAL_USER_ADDED_TO_GROUP_BY_REMOTE_USER_FORMAT",
                                               comment: "Message indicating that the local user was added to the group by another user. Embeds {{remote user name}}.")
                addItem(.userMembershipState_added,
                        address: address,
                        format: format, updaterName)
            case .unknown:
                addItem(.userMembershipState_added,
                        address: address,
                        copy: NSLocalizedString("GROUP_LOCAL_USER_WAS_ADDED_TO_THE_GROUP",
                                                comment: "Message indicating that the local user was added to the group."))
            }
        } else {
            let userName = contactsManager.displayName(for: address, transaction: transaction)

            switch updater {
            case .localUser:
                let format = NSLocalizedString("GROUP_REMOTE_USER_ADDED_TO_GROUP_BY_LOCAL_USER_FORMAT",
                                               comment: "Message indicating that a remote user was added to the group by the local user. Embeds {{remote user name}}.")
                addItem(.userMembershipState_added,
                        address: address,
                        format: format, userName)
            case .otherUser(let updaterName, let updaterAddress):
                if address == updaterAddress {
                    if newGroupModel.groupsVersion == .V2 {
                        if !DebugFlags.permissiveGroupUpdateInfoMessages {
                            owsFailDebug("Remote user added themself to the group.")
                        } else {
                            addItem(.debug, copy: "Error: Remote user added themself to the group.")
                        }
                    }
                    let format = NSLocalizedString("GROUP_REMOTE_USER_ADDED_TO_GROUP_FORMAT",
                                                   comment: "Message indicating that a remote user was added to the group. Embeds {{remote user name}}.")
                    addItem(.userMembershipState_added,
                            address: address,
                            format: format, userName)
                } else {
                    let format = NSLocalizedString("GROUP_REMOTE_USER_ADDED_TO_GROUP_BY_REMOTE_USER_FORMAT",
                                                   comment: "Message indicating that a remote user was added to the group by another user. Embeds {{ %1$@ user who added the user, %2$@ user who was added}}.")
                    addItem(.userMembershipState_added,
                            address: address,
                            format: format, updaterName, userName)
                }
            case .unknown:
                let format = NSLocalizedString("GROUP_REMOTE_USER_ADDED_TO_GROUP_FORMAT",
                                               comment: "Message indicating that a remote user was added to the group. Embeds {{remote user name}}.")
                addItem(.userMembershipState_added,
                        address: address,
                        format: format, userName)
            }
        }
    }

    mutating func addUserJoinedFromInviteLink(for address: SignalServiceAddress) {

        let isLocalUser = localAddress == address
        if isLocalUser {
            switch updater {
            case .localUser:
                addItem(.userMembershipState_added,
                        address: address,
                        copy: NSLocalizedString("GROUP_LOCAL_USER_JOINED_THE_GROUP_VIA_GROUP_INVITE_LINK",
                                                comment: "Message indicating that the local user has joined the group."))
            case .otherUser:
                owsFailDebug("A user should never join the group via invite link unless they are the updater.")
                addItem(.userMembershipState_added,
                        address: address,
                        copy: NSLocalizedString("GROUP_LOCAL_USER_JOINED_THE_GROUP",
                                                comment: "Message indicating that the local user has joined the group."))
            case .unknown:
                addItem(.userMembershipState_added,
                        address: address,
                        copy: NSLocalizedString("GROUP_LOCAL_USER_JOINED_THE_GROUP",
                                                comment: "Message indicating that the local user has joined the group."))
            }
        } else {
            let userName = contactsManager.displayName(for: address, transaction: transaction)

            switch updater {
            case .otherUser(let updaterName, let updaterAddress):
                if address == updaterAddress {
                    let format = NSLocalizedString("GROUP_REMOTE_USER_JOINED_THE_GROUP_VIA_GROUP_INVITE_LINK_FORMAT",
                                                   comment: "Message indicating that another user has joined the group. Embeds {{remote user name}}.")
                    addItem(.userMembershipState_added,
                            address: address,
                            format: format,
                            updaterName)
                    return
                }
            default:
                break
            }

            owsFailDebug("A user should not be able to join the group directly via group invite link unless they are the updater.")
            let format = NSLocalizedString("GROUP_REMOTE_USER_ADDED_TO_GROUP_FORMAT",
                                           comment: "Message indicating that a remote user was added to the group. Embeds {{remote user name}}.")
            addItem(.userMembershipState_added,
                    address: address,
                    format: format, userName)
        }
    }

    mutating func addUserWasInvitedToTheGroup(for address: SignalServiceAddress,
                                              membershipCounts: inout MembershipCounts) {

        let isLocalUser = localAddress == address
        if isLocalUser {
            switch updater {
            case .localUser:
                if !DebugFlags.permissiveGroupUpdateInfoMessages {
                    owsFailDebug("User invited themself to the group.")
                } else {
                    addItem(.debug, copy: "Error: User invited themself to the group.")
                }
                addItem(.userMembershipState_invited,
                        address: address,
                        copy: NSLocalizedString("GROUP_LOCAL_USER_INVITED_TO_THE_GROUP",
                                                comment: "Message indicating that the local user was invited to the group."))
            case .otherUser(let updaterName, _):
                let format = NSLocalizedString("GROUP_LOCAL_USER_INVITED_BY_REMOTE_USER_FORMAT",
                                               comment: "Message indicating that the local user was invited to the group by another user. Embeds {{remote user name}}.")
                addItem(.userMembershipState_invited,
                        address: address,
                        format: format, updaterName)
            case .unknown:
                addItem(.userMembershipState_invited,
                        address: address,
                        copy: NSLocalizedString("GROUP_LOCAL_USER_INVITED_TO_THE_GROUP",
                                                comment: "Message indicating that the local user was invited to the group."))
            }
        } else {
            let userName = contactsManager.displayName(for: address, transaction: transaction)

            switch updater {
            case .localUser:
                let format = NSLocalizedString("GROUP_REMOTE_USER_INVITED_BY_LOCAL_USER_FORMAT",
                                               comment: "Message indicating that a remote user was invited to the group by the local user. Embeds {{remote user name}}.")
                addItem(.userMembershipState_invited,
                        address: address,
                        format: format, userName)
            default:
                membershipCounts.invitedUserCount += 1
            }
        }
    }

    mutating func addUnnamedUsersWereInvited(count: UInt) {
        guard count > 0 else {
            return
        }

        switch updater {
        case .localUser:
            if !DebugFlags.permissiveGroupUpdateInfoMessages {
                owsFailDebug("Unexpected updater.")
            } else {
                addItem(.debug, copy: "Error: Unexpected updater.")
            }
            addUnnamedUsersWereInvitedPassiveTense(count: count)
        case .otherUser(let updaterName, _):
            let countString = OWSFormat.formatUInt(count)
            if count == 1 {
                let format = NSLocalizedString("GROUP_REMOTE_USER_INVITED_BY_REMOTE_USER_1_FORMAT",
                                               comment: "Message indicating that a single remote user was invited to the group by the local user. Embeds {{ user who invited the user }}.")
                addItem(.userMembershipState_invitesNew,
                        format: format, updaterName, countString)
            } else {
                let format = NSLocalizedString("GROUP_REMOTE_USER_INVITED_BY_REMOTE_USER_N_FORMAT",
                                               comment: "Message indicating that a group of remote users were invited to the group by the local user. Embeds {{ %1$@ user who invited the user, %2$@ number of invited users }}.")
                addItem(.userMembershipState_invitesNew,
                        format: format, updaterName, countString)
            }
        case .unknown:
            addUnnamedUsersWereInvitedPassiveTense(count: count)
        }
    }

    mutating func addUnnamedUsersWereInvitedPassiveTense(count: UInt) {
        let countString = OWSFormat.formatUInt(count)
        if count == 1 {
            self.addItem(.userMembershipState_invitesNew,
                         copy: NSLocalizedString("GROUP_REMOTE_USER_INVITED_1",
                                                 comment: "Message indicating that a single remote user was invited to the group."))
        } else {
            let format = NSLocalizedString("GROUP_REMOTE_USER_INVITED_N_FORMAT",
                                           comment: "Message indicating that a group of remote users were invited to the group. Embeds {{number of invited users}}.")
            self.addItem(.userMembershipState_invitesNew,
                         format: format, countString)
        }
    }

    // MARK: - Requesting Members

    mutating func addUserRequestedToJoinGroup(for address: SignalServiceAddress) {
        let isLocalUser = localAddress == address
        if isLocalUser {
            addItem(.userMembershipState,
                    address: address,
                    copy: NSLocalizedString("GROUP_LOCAL_USER_REQUESTED_TO_JOIN_TO_THE_GROUP",
                                            comment: "Message indicating that the local user requested to join the group."))
        } else {
            let requesterName = contactsManager.displayName(for: address, transaction: transaction)
            let format = NSLocalizedString("GROUP_REMOTE_USER_REQUESTED_TO_JOIN_THE_GROUP_FORMAT",
                                           comment: "Message indicating that a remote user requested to join the group. Embeds {{requesting user name}}.")
            addItem(.userMembershipState, address: address, format: format, requesterName)
        }
    }

    mutating func addUserRequestWasApproved(for address: SignalServiceAddress) {
        let isLocalUser = localAddress == address
        if isLocalUser {
            switch updater {
            case .localUser:
                // This could happen if the user requested to join a group
                // and became a requesting member, then tried to join the
                // group again and was added because the group stopped
                // requiring approval in the interim.
                addItem(.userMembershipState_added,
                        address: address,
                        copy: NSLocalizedString("GROUP_LOCAL_USER_WAS_ADDED_TO_THE_GROUP",
                                                comment: "Message indicating that the local user was added to the group."))
            case .otherUser(let updaterName, _):
                let format = NSLocalizedString("GROUP_LOCAL_USER_REQUEST_APPROVED_BY_REMOTE_USER_FORMAT",
                                               comment: "Message indicating that the local user's request to join the group was approved by another user. Embeds {{ %@ the name of the user who approved the reuqest }}.")
                addItem(.userMembershipState, address: address, format: format, updaterName)
            case .unknown:
                addItem(.userMembershipState_added,
                        address: address,
                        copy: NSLocalizedString("GROUP_LOCAL_USER_WAS_ADDED_TO_THE_GROUP",
                                                comment: "Message indicating that the local user was added to the group."))
            }
        } else {
            let requesterName = contactsManager.displayName(for: address, transaction: transaction)
            switch updater {
            case .localUser:
                let format = NSLocalizedString("GROUP_REMOTE_USER_REQUEST_APPROVED_BY_LOCAL_USER_FORMAT",
                                               comment: "Message indicating that a remote user's request to join the group was approved by the local user. Embeds {{requesting user name}}.")
                addItem(.userMembershipState, address: address, format: format, requesterName)
            case .otherUser(let updaterName, _):
                let format = NSLocalizedString("GROUP_REMOTE_USER_REQUEST_APPROVED_BY_REMOTE_USER_FORMAT",
                                               comment: "Message indicating that a remote user's request to join the group was approved by another user. Embeds {{ %1$@ requesting user name, %2$@ approving user name }}.")
                addItem(.userMembershipState, address: address, format: format, requesterName, updaterName)
            case .unknown:
                let format = NSLocalizedString("GROUP_REMOTE_USER_REQUEST_APPROVED_FORMAT",
                                               comment: "Message indicating that a remote user's request to join the group was approved. Embeds {{requesting user name}}.")
                addItem(.userMembershipState, address: address, format: format, requesterName)
            }
        }
    }

    mutating func addUserRequestWasRejected(for address: SignalServiceAddress) {
        let isLocalUser = localAddress == address
        if isLocalUser {
            switch updater {
            case .localUser:
                let copy = NSLocalizedString("GROUP_LOCAL_USER_REQUEST_CANCELLED_BY_LOCAL_USER",
                                               comment: "Message indicating that the local user cancelled their request to join the group.")
                addItem(.userMembershipState, address: address, copy: copy)
            case .otherUser, .unknown:
                addItem(.userMembershipState,
                        address: address,
                        copy: NSLocalizedString("GROUP_LOCAL_USER_REQUEST_REJECTED",
                                                comment: "Message indicating that the local user's request to join the group was rejected."))
            }
        } else {
            let requesterName = contactsManager.displayName(for: address, transaction: transaction)
            switch updater {
            case .localUser:
                let format = NSLocalizedString("GROUP_REMOTE_USER_REQUEST_REJECTED_BY_LOCAL_USER_FORMAT",
                                               comment: "Message indicating that a remote user's request to join the group was rejected by the local user. Embeds {{requesting user name}}.")
                addItem(.userMembershipState, address: address, format: format, requesterName)
            case .otherUser(let updaterName, let updaterAddress):
                if address == updaterAddress {
                    let format = NSLocalizedString("GROUP_REMOTE_USER_REQUEST_CANCELLED_BY_REMOTE_USER_FORMAT",
                                                   comment: "Message indicating that a remote user cancelled their request to join the group. Embeds {{ the name of the requesting user }}.")
                    addItem(.userMembershipState, address: address, format: format, updaterName)
                } else {
                    let format = NSLocalizedString("GROUP_REMOTE_USER_REQUEST_REJECTED_BY_REMOTE_USER_FORMAT",
                                                   comment: "Message indicating that a remote user's request to join the group was rejected by another user. Embeds {{ %1$@ requesting user name, %2$@ approving user name }}.")
                    addItem(.userMembershipState, address: address, format: format, requesterName, updaterName)
                }
            case .unknown:
                let format = NSLocalizedString("GROUP_REMOTE_USER_REQUEST_REJECTED_FORMAT",
                                               comment: "Message indicating that a remote user's request to join the group was rejected. Embeds {{requesting user name}}.")
                addItem(.userMembershipState, address: address, format: format, requesterName)
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

        guard let oldToken = oldToken else {
            if newToken.isEnabled {
                let format = NSLocalizedString("DISAPPEARING_MESSAGES_CONFIGURATION_GROUP_EXISTING_FORMAT",
                                               comment: "Info Message when added to a group which has enabled disappearing messages. Embeds {{time amount}} before messages disappear. See the *_TIME_AMOUNT strings for context.")
                addItem(.disappearingMessagesState_enabled, format: format, durationString)
            }
            return
        }

        guard newToken != oldToken else {
            // No change to disappearing message configuration occurred.
            return
        }

        switch updater {
        case .localUser:
            // Changed by localNumber on this device or via synced transcript
            if newToken.isEnabled {
                let format = NSLocalizedString("YOU_UPDATED_DISAPPEARING_MESSAGES_CONFIGURATION",
                                               comment: "Info Message when you update disappearing messages duration. Embeds a {{time amount}} before messages disappear. see the *_TIME_AMOUNT strings for context.")
                addItem(.disappearingMessagesState_enabled, format: format, durationString)
            } else {
                addItem(.disappearingMessagesState_disabled,
                        copy: NSLocalizedString("YOU_DISABLED_DISAPPEARING_MESSAGES_CONFIGURATION",
                                                comment: "Info Message when you disabled disappearing messages."))
            }
        case .otherUser(let updaterName, _):
            if newToken.isEnabled {
                let format = NSLocalizedString("OTHER_UPDATED_DISAPPEARING_MESSAGES_CONFIGURATION",
                                               comment: "Info Message when another user enabled disappearing messages. Embeds {{name of other user}} and {{time amount}} before messages disappear. See the *_TIME_AMOUNT strings for context.")
                addItem(.disappearingMessagesState_enabled, format: format, updaterName, durationString)
            } else {
                let format = NSLocalizedString("OTHER_DISABLED_DISAPPEARING_MESSAGES_CONFIGURATION",
                                               comment: "Info Message when another user disabled disappearing messages. Embeds {{name of other user}}.")
                addItem(.disappearingMessagesState_disabled, format: format, updaterName)
            }
        case .unknown:
            // Changed by unknown user.
            if newToken.isEnabled {
                let format = NSLocalizedString("UNKNOWN_USER_UPDATED_DISAPPEARING_MESSAGES_CONFIGURATION",
                                               comment: "Info Message when an unknown user enabled disappearing messages. Embeds {{time amount}} before messages disappear. see the *_TIME_AMOUNT strings for context.")
                addItem(.disappearingMessagesState_enabled, format: format, durationString)
            } else {
                addItem(.disappearingMessagesState_disabled,
                        copy: NSLocalizedString("UNKNOWN_USER_DISABLED_DISAPPEARING_MESSAGES_CONFIGURATION",
                                                comment: "Info Message when an unknown user disabled disappearing messages."))
            }
        }
    }

    // MARK: - Group Invite Links

    mutating func addGroupInviteLinkUpdates(oldGroupModel: TSGroupModel) {
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
            if let oldInviteLinkPassword = oldGroupModel.inviteLinkPassword,
                let newInviteLinkPassword = newGroupModel.inviteLinkPassword,
                oldInviteLinkPassword != newInviteLinkPassword {
                switch updater {
                case .localUser:
                    let format = NSLocalizedString("GROUP_INVITE_LINK_RESET_BY_LOCAL_USER",
                                                   comment: "Message indicating that the group invite link was reset by the local user.")
                    addItem(.groupInviteLink, format: format)
                case .otherUser(let updaterName, _):
                    let format = NSLocalizedString("GROUP_INVITE_LINK_RESET_BY_REMOTE_USER_FORMAT",
                                                   comment: "Message indicating that the group invite link was reset by a remote user. Embeds {{ user who reset the group invite link }}.")
                    addItem(.groupInviteLink, format: format, updaterName)
                case .unknown:
                    let format = NSLocalizedString("GROUP_INVITE_LINK_RESET",
                                                   comment: "Message indicating that the group invite link was reset.")
                    addItem(.groupInviteLink, format: format)
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
                    let format = NSLocalizedString("GROUP_INVITE_LINK_ENABLED_WITHOUT_APPROVAL_BY_LOCAL_USER",
                                                   comment: "Message indicating that the group invite link was enabled by the local user.")
                    addItem(.groupInviteLink, format: format)
                case .otherUser(let updaterName, _):
                    let format = NSLocalizedString("GROUP_INVITE_LINK_ENABLED_WITHOUT_APPROVAL_BY_REMOTE_USER_FORMAT",
                                                   comment: "Message indicating that the group invite link was enabled by a remote user. Embeds {{ user who enabled the group invite link }}.")
                    addItem(.groupInviteLink, format: format, updaterName)
                case .unknown:
                    let format = NSLocalizedString("GROUP_INVITE_LINK_ENABLED_WITHOUT_APPROVAL",
                                                   comment: "Message indicating that the group invite link was enabled.")
                    addItem(.groupInviteLink, format: format)
                }
            case .enabledWithApproval:
                switch updater {
                case .localUser:
                    let format = NSLocalizedString("GROUP_INVITE_LINK_ENABLED_WITH_APPROVAL_BY_LOCAL_USER",
                                                   comment: "Message indicating that the group invite link was enabled by the local user.")
                    addItem(.groupInviteLink, format: format)
                case .otherUser(let updaterName, _):
                    let format = NSLocalizedString("GROUP_INVITE_LINK_ENABLED_WITH_APPROVAL_BY_REMOTE_USER_FORMAT",
                                                   comment: "Message indicating that the group invite link was enabled by a remote user. Embeds {{ user who enabled the group invite link }}.")
                    addItem(.groupInviteLink, format: format, updaterName)
                case .unknown:
                    let format = NSLocalizedString("GROUP_INVITE_LINK_ENABLED_WITH_APPROVAL",
                                                   comment: "Message indicating that the group invite link was enabled.")
                    addItem(.groupInviteLink, format: format)
                }
            }
        case .enabledWithoutApproval, .enabledWithApproval:
            switch newGroupInviteLinkMode {
            case .disabled:
                switch updater {
                case .localUser:
                    let format = NSLocalizedString("GROUP_INVITE_LINK_DISABLED_BY_LOCAL_USER",
                                                   comment: "Message indicating that the group invite link was disabled by the local user.")
                    addItem(.groupInviteLink, format: format)
                case .otherUser(let updaterName, _):
                    let format = NSLocalizedString("GROUP_INVITE_LINK_DISABLED_BY_REMOTE_USER_FORMAT",
                                                   comment: "Message indicating that the group invite link was disabled by a remote user. Embeds {{ user who disabled the group invite link }}.")
                    addItem(.groupInviteLink, format: format, updaterName)
                case .unknown:
                    let format = NSLocalizedString("GROUP_INVITE_LINK_DISABLED",
                                                   comment: "Message indicating that the group invite link was disabled.")
                    addItem(.groupInviteLink, format: format)
                }
            case .enabledWithoutApproval:
                switch updater {
                case .localUser:
                    let format = NSLocalizedString("GROUP_INVITE_LINK_SET_TO_NOT_REQUIRE_APPROVAL_BY_LOCAL_USER",
                                                   comment: "Message indicating that the group invite link was set to not require approval by the local user.")
                    addItem(.groupInviteLink, format: format)
                case .otherUser(let updaterName, _):
                    let format = NSLocalizedString("GROUP_INVITE_LINK_SET_TO_NOT_REQUIRE_APPROVAL_BY_REMOTE_USER_FORMAT",
                                                   comment: "Message indicating that the group invite link was set to not require approval by a remote user. Embeds {{ user who set the group invite link to not require approval }}.")
                    addItem(.groupInviteLink, format: format, updaterName)
                case .unknown:
                    let format = NSLocalizedString("GROUP_INVITE_LINK_SET_TO_NOT_REQUIRE_APPROVAL",
                                                   comment: "Message indicating that the group invite link was set to not require approval.")
                    addItem(.groupInviteLink, format: format)
                }
            case .enabledWithApproval:
                switch updater {
                case .localUser:
                    let format = NSLocalizedString("GROUP_INVITE_LINK_SET_TO_REQUIRE_APPROVAL_BY_LOCAL_USER",
                                                   comment: "Message indicating that the group invite link was set to require approval by the local user.")
                    addItem(.groupInviteLink, format: format)
                case .otherUser(let updaterName, _):
                    let format = NSLocalizedString("GROUP_INVITE_LINK_SET_TO_REQUIRE_APPROVAL_BY_REMOTE_USER_FORMAT",
                                                   comment: "Message indicating that the group invite link was set to require approval by a remote user. Embeds {{ user who set the group invite link to require approval }}.")
                    addItem(.groupInviteLink, format: format, updaterName)
                case .unknown:
                    let format = NSLocalizedString("GROUP_INVITE_LINK_SET_TO_REQUIRE_APPROVAL",
                                                   comment: "Message indicating that the group invite link was set to require approval.")
                    addItem(.groupInviteLink, format: format)
                }
            }
        }
    }

    // MARK: -

    mutating func addGroupWasInserted() {
        guard let newGroupModel = newGroupModel as? TSGroupModelV2 else {
            // Group was just upserted.
            switch updater {
            case .localUser:
                addItem(.groupCreated,
                        copy: NSLocalizedString("GROUP_CREATED_BY_LOCAL_USER",
                                                comment: "Message indicating that group was created by the local user."))
            default:
                // Unless we know we created the group,
                // we don't know if the group was just created
                // or if we were just added to it, so use the
                // old generic description.
                addItem(.groupCreated,
                        copy: defaultGroupUpdateDescription)
            }
            return
        }

        let wasGroupJustCreated = newGroupModel.revision == 0
        if wasGroupJustCreated {
            // Group was just created.
            switch updater {
            case .localUser:
                addItem(.groupCreated,
                        copy: NSLocalizedString("GROUP_CREATED_BY_LOCAL_USER",
                                                comment: "Message indicating that group was created by the local user."))
            case .otherUser(let updaterName, _):
                let format = NSLocalizedString("GROUP_CREATED_BY_REMOTE_USER_FORMAT",
                                               comment: "Message indicating that group was created by another user. Embeds {{remote user name}}.")
                addItem(.groupCreated, format: format, updaterName)
            case .unknown:
                addItem(.groupCreated,
                        copy: NSLocalizedString("GROUP_CREATED_BY_UNKNOWN_USER",
                                                comment: "Message indicating that group was created by an unknown user."))
            }
        }

        switch localMembershipStatus(for: newGroupMembership) {
        case .normalMember:
            guard !wasGroupJustCreated else {
                // If group was just created, it's implicit that we were added.
                return
            }

            // TODO:
            switch updater {
            case .otherUser(let updaterName, _):
                let format = NSLocalizedString("GROUP_LOCAL_USER_ADDED_TO_GROUP_BY_REMOTE_USER_FORMAT",
                                               comment: "Message indicating that the local user was added to the group by another user. Embeds {{remote user name}}.")
                addItem(.userMembershipState_added,
                        address: localAddress,
                        format: format, updaterName)
            default:
                addItem(.userMembershipState_added,
                        address: localAddress,
                        copy: NSLocalizedString("GROUP_LOCAL_USER_WAS_ADDED_TO_THE_GROUP",
                                                comment: "Message indicating that the local user was added to the group."))
            }
        case .invited:
            if let localAddress = Self.tsAccountManager.localAddress,
               let inviterUuid = newGroupMembership.addedByUuid(forInvitedMember: localAddress) {
                let inviterAddress = SignalServiceAddress(uuid: inviterUuid)
                let inviterName = contactsManager.displayName(for: inviterAddress, transaction: transaction)
                let format = NSLocalizedString("GROUP_LOCAL_USER_INVITED_BY_REMOTE_USER_FORMAT",
                                               comment: "Message indicating that the local user was invited to the group by another user. Embeds {{remote user name}}.")
                addItem(.userMembershipState_invited,
                        address: localAddress,
                        format: format, inviterName)
            } else {
                addItem(.userMembershipState_invited,
                        address: localAddress,
                        copy: NSLocalizedString("GROUP_LOCAL_USER_INVITED_TO_THE_GROUP",
                                                comment: "Message indicating that the local user was invited to the group."))
            }
        case .requesting:
            if let localAddress = Self.tsAccountManager.localAddress {
                addUserRequestedToJoinGroup(for: localAddress)
            } else {
                owsFailDebug("Missing localAddress.")
            }
        case .none:
            if !DebugFlags.permissiveGroupUpdateInfoMessages {
                owsFailDebug("Learned of group without any membership status.")
            } else {
                addItem(.debug, copy: "Error: Learned of group without any membership status.")
            }
        }
    }

    mutating func addWasJustCreatedByLocalUserUpdates() {
        addItem(.groupGroupLinkPromotion,
                copy: NSLocalizedString("GROUP_LINK_PROMOTION_UPDATE",
                                        comment: "Suggestion to invite more group members via the group invite link."))
    }

    // MARK: - Migration

    var wasJustMigrated: Bool {
        guard let newGroupModelV2 = newGroupModel as? TSGroupModelV2,
            newGroupModelV2.wasJustMigrated else {
                return false
        }
        return true
    }

    mutating func addMigrationUpdates(oldGroupMembership: GroupMembership) {
        owsAssertDebug(wasJustMigrated)

        addItem(.groupMigrated,
                copy: NSLocalizedString("GROUP_WAS_MIGRATED",
                                        comment: "Message indicating that the group was migrated."))

        let invitedMembers = oldGroupMembership.allMembersOfAnyKind.intersection(newGroupMembership.invitedMembers)
        let droppedMembers = oldGroupMembership.allMembersOfAnyKind.subtracting(newGroupMembership.allMembersOfAnyKind)

        if invitedMembers.contains(localAddress) {
            let copy = NSLocalizedString("GROUP_WAS_MIGRATED_USERS_INVITED_LOCAL_USER",
                                         comment: "Message indicating that the local user was invited while migrating the group.")
            addItem(.groupMigrated_usersInvited, copy: copy)
            return
        } else if droppedMembers.contains(localAddress) {
            let copy = NSLocalizedString("GROUP_WAS_MIGRATED_USERS_DROPPED_LOCAL_USER",
                                         comment: "Message indicating that the local user was dropped while migrating the group.")
            addItem(.groupMigrated_usersDropped, copy: copy)
            return
        }

        if !invitedMembers.isEmpty {
            if invitedMembers.count == 1 {
                let copy = NSLocalizedString("GROUP_WAS_MIGRATED_USERS_INVITED_1",
                                             comment: "Message indicating that 1 user was invited while migrating the group.")
                addItem(.groupMigrated_usersInvited, copy: copy)
            } else {
                let format = NSLocalizedString("GROUP_WAS_MIGRATED_USERS_INVITED_N_FORMAT",
                                               comment: "Message indicating that N users were invited while migrating the group. Embeds {{ the number of invited users }}.")
                let countString = OWSFormat.formatInt(invitedMembers.count)
                addItem(.groupMigrated_usersInvited, format: format, countString)
            }
        }

        if !droppedMembers.isEmpty {
            if droppedMembers.count == 1 {
                let copy = NSLocalizedString("GROUP_WAS_MIGRATED_USERS_DROPPED_1",
                                             comment: "Message indicating that 1 user was dropped while migrating the group.")
                addItem(.groupMigrated_usersDropped, copy: copy)
            } else {
                let format = NSLocalizedString("GROUP_WAS_MIGRATED_USERS_DROPPED_N_FORMAT",
                                               comment: "Message indicating that N users were dropped while migrating the group. Embeds {{ the number of dropped users }}.")
                let countString = OWSFormat.formatInt(droppedMembers.count)
                addItem(.groupMigrated_usersDropped, format: format, countString)
            }
        }
    }

    // MARK: - Membership Status

    fileprivate enum MembershipStatus {
        case normalMember
        case invited
        case requesting
        case none
    }

    fileprivate func localMembershipStatus(for groupMembership: GroupMembership) -> MembershipStatus {
        return membershipStatus(of: localAddress, in: groupMembership)
    }

    fileprivate func membershipStatus(of address: SignalServiceAddress,
                                      in groupMembership: GroupMembership) -> MembershipStatus {
        if groupMembership.isFullMember(address) {
            return .normalMember
        } else if groupMembership.isInvitedMember(address) {
            return .invited
        } else if groupMembership.isRequestingMember(address) {
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

    static func updater(groupUpdateSourceAddress: SignalServiceAddress?,
                        transaction: SDSAnyReadTransaction) -> Updater {
        guard let updaterAddress = groupUpdateSourceAddress else {
            return .unknown
        }
        guard let localAddress = tsAccountManager.localAddress else {
            owsFailDebug("missing local address")
            return .unknown
        }
        if localAddress == updaterAddress {
            return .localUser
        }

        let updaterName = contactsManager.displayName(for: updaterAddress, transaction: transaction)
        return .otherUser(updaterName: updaterName, updaterAddress: updaterAddress)
    }

    // MARK: - Defaults

    var defaultGroupUpdateDescription: String {
        return GroupUpdateCopy.defaultGroupUpdateDescription(groupUpdateSourceAddress: groupUpdateSourceAddress,
                                                             transaction: transaction)
    }

    static func defaultGroupUpdateDescription(groupUpdateSourceAddress: SignalServiceAddress?,
                                              transaction: SDSAnyReadTransaction) -> String {
        let updater = GroupUpdateCopy.updater(groupUpdateSourceAddress: groupUpdateSourceAddress,
                                              transaction: transaction)
        switch updater {
        case .localUser:
            return NSLocalizedString("GROUP_UPDATED_BY_LOCAL_USER",
                                     comment: "Info message indicating that the group was updated by the local user.")
        case .otherUser(let updaterName, _):
            let format = NSLocalizedString("GROUP_UPDATED_BY_REMOTE_USER_FORMAT",
                                           comment: "Info message indicating that the group was updated by another user. Embeds {{remote user name}}.")
            return String(format: format, updaterName)
        case .unknown:
            return NSLocalizedString("GROUP_UPDATED",
                                     comment: "Info message indicating that the group was updated by an unknown user.")
        }
    }
}
