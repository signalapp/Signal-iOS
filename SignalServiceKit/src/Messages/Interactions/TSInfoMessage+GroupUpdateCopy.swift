//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

struct GroupUpdateCopy {

    // MARK: - Dependencies

    private static var contactsManager: ContactsManagerProtocol {
        return SSKEnvironment.shared.contactsManager
    }

    private static var tsAccountManager: TSAccountManager {
        return TSAccountManager.sharedInstance()
    }

    private static var profileManager: ProfileManagerProtocol {
        return SSKEnvironment.shared.profileManager
    }

    // MARK: -

    enum UpdateType {
        case groupCreated
        case userMembershipState
        case userMembershipState_invitesNew
        case userMembershipState_invitesDeclined
        case userMembershipState_invitesRevoked
        case userRole
        case groupName
        case groupAvatar
        case accessMembers
        case accessAttributes
        case disappearingMessagesState
        case generic
        case debug
    }

    // MARK: -

    struct UpdateItem: Hashable {
        let type: UpdateType
        let address: SignalServiceAddress?

        init(type: UpdateType, address: SignalServiceAddress?) {
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

    // The update items, in order.
    private var itemCopyList = [String]()
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

        switch updater {
        case .unknown:
            if oldGroupModel != nil,
                newGroupModel.groupsVersion == .V2 {
                if !DebugFlags.permissiveGroupUpdateInfoMessages {
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
            addMembershipUpdates(oldGroupMembership: oldGroupMembership)

            addAttributesUpdates(oldGroupModel: oldGroupModel)

            addAccessUpdates(oldGroupModel: oldGroupModel)

            addDisappearingMessageUpdates(oldToken: oldDisappearingMessageToken,
                                          newToken: newDisappearingMessageToken)
        } else {
            // We're just learning of the group.
            addGroupWasInserted()

            // Skip description of overall group state (current name, avatar, members, etc.).
            //
            // Include a description of current DM state, if necessary.
            addDisappearingMessageUpdates(oldToken: oldDisappearingMessageToken,
                                          newToken: newDisappearingMessageToken)
        }

        if itemCopyList.count < 1 {
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

    mutating func addItem(_ type: UpdateType,
                          address: SignalServiceAddress? = nil,
                          copy: String) {
        let item = UpdateItem(type: type,
                              address: address)
        if itemSet.contains(item),
            item.type != .debug {
            Logger.verbose("item: \(item)")
            owsFailDebug("Duplicate items.")
        }
        itemSet.insert(item)
        itemCopyList.append(copy)
    }

    mutating func addItem(_ type: UpdateType,
                          address: SignalServiceAddress? = nil,
                          format: String, _ formatArgs: CVarArg...) {
        let copy = String(format: format, arguments: formatArgs)
        addItem(type, address: address, copy: copy)
    }

    var updateDescription: String {
        return itemCopyList.joined(separator: "\n")
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

    mutating func addMembershipUpdates(oldGroupMembership: GroupMembership) {
        var membershipCounts = MembershipCounts()

        let allUsers = oldGroupMembership.allUsers.union(newGroupMembership.allUsers)
        for address in allUsers {
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
                    if !DebugFlags.permissiveGroupUpdateInfoMessages {
                        owsFailDebug("Invalid membership status transition: \(oldMembershipStatus) -> \(newMembershipStatus).")
                    } else {
                        addItem(.debug, copy: "Error: Invalid membership status transition: \(oldMembershipStatus) -> \(newMembershipStatus).")
                    }
                    break
                case .none:
                    addUserLeftOrWasKickedOutOfGroup(for: address)
                }
            case .invited:
                switch newMembershipStatus {
                case .normalMember:
                    addUserInviteWasAccepted(for: address,
                                             oldGroupMembership: oldGroupMembership)
                case .invited:
                    // Membership status didn't change.
                    break
                case .none:
                    addUserInviteWasDeclinedOrRevoked(for: address,
                                                      oldGroupMembership: oldGroupMembership,
                                                      membershipCounts: &membershipCounts)
                }
            case .none:
                switch newMembershipStatus {
                case .normalMember:
                    addUserWasAddedToTheGroup(for: address)
                case .invited:
                    addUserWasInvitedToTheGroup(for: address,
                                                membershipCounts: &membershipCounts)
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
    }

    mutating func addMemberRoleUpdates(for address: SignalServiceAddress,
                                       oldGroupMembership: GroupMembership) {

        let oldIsAdministrator = oldGroupMembership.isAdministrator(address)
        let newIsAdministrator = newGroupMembership.isAdministrator(address)

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
            let userName = Self.displayName(for: address, transaction: transaction)

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
            let userName = Self.displayName(for: address, transaction: transaction)

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
                addItem(.userMembershipState,
                        address: address,
                        copy: NSLocalizedString("GROUP_YOU_LEFT",
                                                comment: "Message indicating that the local user left the group."))
            case .otherUser(let updaterName, _):
                let format = NSLocalizedString("GROUP_LOCAL_USER_REMOVED_BY_REMOTE_USER_FORMAT",
                                               comment: "Message indicating that the local user was removed from the group by another user. Embeds {{remote user name}}.")
                addItem(.userMembershipState,
                        address: address,
                        format: format, updaterName)
            case .unknown:
                addItem(.userMembershipState,
                        address: address,
                        copy: NSLocalizedString("GROUP_LOCAL_USER_REMOVED_BY_UNKNOWN_USER",
                                                comment: "Message indicating that the local user was removed from the group by an unknown user."))
            }
        } else {
            let userName = Self.displayName(for: address, transaction: transaction)

            switch updater {
            case .localUser:
                let format = NSLocalizedString("GROUP_REMOTE_USER_REMOVED_BY_LOCAL_USER_FORMAT",
                                               comment: "Message indicating that a remote user was removed from the group by the local user. Embeds {{remote user name}}.")
                addItem(.userMembershipState,
                        address: address,
                        format: format, userName)
            case .otherUser(let updaterName, let updaterAddress):
                if updaterAddress == address {
                    let format = NSLocalizedString("GROUP_REMOTE_USER_LEFT_GROUP_FORMAT",
                                                   comment: "Message indicating that a remote user has left the group. Embeds {{remote user name}}.")
                    addItem(.userMembershipState,
                            address: address,
                            format: format, userName)
                } else {
                    let format = NSLocalizedString("GROUP_REMOTE_USER_REMOVED_FROM_GROUP_BY_REMOTE_USER_FORMAT",
                                                   comment: "Message indicating that the remote user was removed from the group. Embeds {{ %1$@ user who removed the user, %2$@ user who was removed}}.")
                    addItem(.userMembershipState,
                            address: address,
                            format: format, updaterName, userName)
                }
            case .unknown:
                let format = NSLocalizedString("GROUP_REMOTE_USER_LEFT_GROUP_FORMAT",
                                               comment: "Message indicating that a remote user has left the group. Embeds {{remote user name}}.")
                addItem(.userMembershipState,
                        address: address,
                        format: format, userName)
            }
        }
    }

    mutating func addUserInviteWasAccepted(for address: SignalServiceAddress,
                                           oldGroupMembership: GroupMembership) {

        var inviterName: String?
        var inviterAddress: SignalServiceAddress?
        if let inviterUuid = oldGroupMembership.addedByUuid(forPendingMember: address) {
            inviterAddress = SignalServiceAddress(uuid: inviterUuid)
            inviterName = Self.displayName(for: SignalServiceAddress(uuid: inviterUuid),
                                                      transaction: transaction)
        }

        let isLocalUser = localAddress == address
        if isLocalUser {
            switch updater {
            case .localUser:
                if let inviterName = inviterName {
                    let format = NSLocalizedString("GROUP_LOCAL_USER_INVITE_ACCEPTED_FORMAT",
                                                   comment: "Message indicating that the local user accepted an invite to the group. Embeds {{user who invited the local user}}.")
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
                            copy: NSLocalizedString("GROUP_LOCAL_USER_INVITE_ACCEPTED",
                                                    comment: "Message indicating that the local user accepted an invite to the group."))
                }
            case .otherUser(let updaterName, _):
                if !DebugFlags.permissiveGroupUpdateInfoMessages {
                    owsFailDebug("Invite accepted on our behalf.")
                } else {
                    addItem(.debug, copy: "Error: Invite accepted on our behalf.")
                }
                let format = NSLocalizedString("GROUP_LOCAL_USER_ADDED_TO_GROUP_BY_REMOTE_USER_FORMAT",
                                               comment: "Message indicating that the local user was added to the group by another user. Embeds {{remote user name}}.")
                addItem(.userMembershipState,
                        address: address,
                        format: format, updaterName)
            case .unknown:
                addItem(.userMembershipState,
                        address: address,
                        copy: NSLocalizedString("GROUP_LOCAL_USER_JOINED_THE_GROUP",
                                                comment: "Message indicating that the local user has joined the group."))
            }
        } else {
            let userName = Self.displayName(for: address, transaction: transaction)

            switch updater {
            case .localUser:
                if !DebugFlags.permissiveGroupUpdateInfoMessages {
                    owsFailDebug("Invite not accepted by invitee.")
                } else {
                    addItem(.debug, copy: "Error: Invite not accepted by invitee.")
                }
                let format = NSLocalizedString("GROUP_REMOTE_USER_ADDED_TO_GROUP_BY_LOCAL_USER_FORMAT",
                                               comment: "Message indicating that a remote user was added to the group by the local user. Embeds {{remote user name}}.")
                addItem(.userMembershipState,
                        address: address,
                        format: format, userName)
            case .otherUser(let updaterName, let updaterAddress):
                if address == updaterAddress {
                    if inviterAddress == localAddress {
                        let format = NSLocalizedString("GROUP_REMOTE_USER_ACCEPTED_INVITE_FROM_LOCAL_USER_FORMAT",
                                                       comment: "Message indicating that a remote user has accepted an invite from the local user. Embeds {{remote user name}}.")
                        addItem(.userMembershipState,
                                address: address,
                                format: format, updaterName)
                    } else if let inviterName = inviterName {
                        let format = NSLocalizedString("GROUP_REMOTE_USER_ACCEPTED_INVITE_FROM_REMOTE_USER_FORMAT",
                                                       comment: "Message indicating that a remote user has accepted their invite. Embeds {{ %1$@ user who accepted their invite, %2$@ user who invited the user}}.")
                        addItem(.userMembershipState,
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
                        addItem(.userMembershipState,
                                address: address,
                                format: format, updaterName)
                    }
                } else {
                    if !DebugFlags.permissiveGroupUpdateInfoMessages {
                        owsFailDebug("Invite accepted by someone other than invitee.")
                    } else {
                        addItem(.debug, copy: "Error: Invite accepted by someone other than invitee.")
                    }
                    let format = NSLocalizedString("GROUP_REMOTE_USER_ADDED_TO_GROUP_BY_REMOTE_USER_FORMAT",
                                                   comment: "Message indicating that a remote user was added to the group by another user. Embeds {{ %1$@ user who added the user, %2$@ user who was added}}.")
                    addItem(.userMembershipState,
                            address: address,
                            format: format, updaterName, userName)
                }
            case .unknown:
                let format = NSLocalizedString("GROUP_REMOTE_USER_JOINED_GROUP_FORMAT",
                                               comment: "Message indicating that a remote user was added to the group. Embeds {{remote user name}}.")
                addItem(.userMembershipState,
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
        if let inviterUuid = oldGroupMembership.addedByUuid(forPendingMember: address) {
            inviterAddress = SignalServiceAddress(uuid: inviterUuid)
            inviterName = Self.displayName(for: SignalServiceAddress(uuid: inviterUuid),
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
            let userName = Self.displayName(for: address, transaction: transaction)

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
        let countString = String.localizedStringWithFormat("%d", count)

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
                addItem(.userMembershipState,
                        address: address,
                        copy: NSLocalizedString("GROUP_LOCAL_USER_JOINED_THE_GROUP",
                                                comment: "Message indicating that the local user has joined the group."))
            case .otherUser(let updaterName, _):
                let format = NSLocalizedString("GROUP_LOCAL_USER_ADDED_TO_GROUP_BY_REMOTE_USER_FORMAT",
                                               comment: "Message indicating that the local user was added to the group by another user. Embeds {{remote user name}}.")
                addItem(.userMembershipState,
                        address: address,
                        format: format, updaterName)
            case .unknown:
                addItem(.userMembershipState,
                        address: address,
                        copy: NSLocalizedString("GROUP_LOCAL_USER_JOINED_THE_GROUP",
                                                comment: "Message indicating that the local user has joined the group."))
            }
        } else {
            let userName = Self.displayName(for: address, transaction: transaction)

            switch updater {
            case .localUser:
                let format = NSLocalizedString("GROUP_REMOTE_USER_ADDED_TO_GROUP_BY_LOCAL_USER_FORMAT",
                                               comment: "Message indicating that a remote user was added to the group by the local user. Embeds {{remote user name}}.")
                addItem(.userMembershipState,
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
                    addItem(.userMembershipState,
                            address: address,
                            format: format, userName)
                } else {
                    let format = NSLocalizedString("GROUP_REMOTE_USER_ADDED_TO_GROUP_BY_REMOTE_USER_FORMAT",
                                                   comment: "Message indicating that a remote user was added to the group by another user. Embeds {{ %1$@ user who added the user, %2$@ user who was added}}.")
                    addItem(.userMembershipState,
                            address: address,
                            format: format, updaterName, userName)
                }
            case .unknown:
                let format = NSLocalizedString("GROUP_REMOTE_USER_ADDED_TO_GROUP_FORMAT",
                                               comment: "Message indicating that a remote user was added to the group. Embeds {{remote user name}}.")
                addItem(.userMembershipState,
                        address: address,
                        format: format, userName)
            }
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
                addItem(.userMembershipState,
                        address: address,
                        copy: NSLocalizedString("GROUP_LOCAL_USER_INVITED_TO_THE_GROUP",
                                                comment: "Message indicating that the local user was invited to the group."))
            case .otherUser(let updaterName, _):
                let format = NSLocalizedString("GROUP_LOCAL_USER_INVITED_BY_REMOTE_USER_FORMAT",
                                               comment: "Message indicating that the local user was invited to the group by another user. Embeds {{remote user name}}.")
                addItem(.userMembershipState,
                        address: address,
                        format: format, updaterName)
            case .unknown:
                addItem(.userMembershipState,
                        address: address,
                        copy: NSLocalizedString("GROUP_LOCAL_USER_INVITED_TO_THE_GROUP",
                                                comment: "Message indicating that the local user was invited to the group."))
            }
        } else {
            let userName = Self.displayName(for: address, transaction: transaction)

            switch updater {
            case .localUser:
                let format = NSLocalizedString("GROUP_REMOTE_USER_INVITED_BY_LOCAL_USER_FORMAT",
                                               comment: "Message indicating that a remote user was invited to the group by the local user. Embeds {{remote user name}}.")
                addItem(.userMembershipState,
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
        let countString = String.localizedStringWithFormat("%d", count)

        switch updater {
        case .localUser:
            if !DebugFlags.permissiveGroupUpdateInfoMessages {
                owsFailDebug("Unexpected updater.")
            } else {
                addItem(.debug, copy: "Error: Unexpected updater.")
            }
        case .otherUser(let updaterName, _):
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
            if count == 1 {
                addItem(.userMembershipState_invitesNew,
                        copy: NSLocalizedString("GROUP_REMOTE_USER_INVITED_1",
                                                comment: "Message indicating that a single remote user was invited to the group."))
            } else {
                let format = NSLocalizedString("GROUP_REMOTE_USER_INVITED_N_FORMAT",
                                               comment: "Message indicating that a group of remote users were invited to the group. Embeds {{number of invited users}}.")
                addItem(.userMembershipState_invitesNew,
                        format: format, countString)
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
        let durationString = NSString.formatDurationSeconds(newToken.durationSeconds, useShortFormat: false)

        guard let oldToken = oldToken else {
            if newToken.isEnabled {
                let format = NSLocalizedString("DISAPPEARING_MESSAGES_CONFIGURATION_GROUP_EXISTING_FORMAT",
                                               comment: "Info Message when added to a group which has enabled disappearing messages. Embeds {{time amount}} before messages disappear. See the *_TIME_AMOUNT strings for context.")
                addItem(.disappearingMessagesState, format: format, durationString)
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
                                               comment: "Info Message when you disabled disappearing messages. Embeds a {{time amount}} before messages disappear. see the *_TIME_AMOUNT strings for context.")
                addItem(.disappearingMessagesState, format: format, durationString)
            } else {
                addItem(.disappearingMessagesState,
                        copy: NSLocalizedString("YOU_DISABLED_DISAPPEARING_MESSAGES_CONFIGURATION",
                                                comment: "Info Message when you disabled disappearing messages."))
            }
        case .otherUser(let updaterName, _):
            if newToken.isEnabled {
                let format = NSLocalizedString("OTHER_UPDATED_DISAPPEARING_MESSAGES_CONFIGURATION",
                                               comment: "Info Message when another user enabled disappearing messages. Embeds {{name of other user}} and {{time amount}} before messages disappear. See the *_TIME_AMOUNT strings for context.")
                addItem(.disappearingMessagesState, format: format, updaterName, durationString)
            } else {
                let format = NSLocalizedString("OTHER_DISABLED_DISAPPEARING_MESSAGES_CONFIGURATION",
                                               comment: "Info Message when another user disabled disappearing messages. Embeds {{name of other user}}.")
                addItem(.disappearingMessagesState, format: format, updaterName)
            }
        case .unknown:
            // Changed by unknown user.
            if newToken.isEnabled {
                let format = NSLocalizedString("UNKNOWN_USER_UPDATED_DISAPPEARING_MESSAGES_CONFIGURATION",
                                               comment: "Info Message when an unknown user enabled disappearing messages. Embeds {{time amount}} before messages disappear. see the *_TIME_AMOUNT strings for context.")
                addItem(.disappearingMessagesState, format: format, durationString)
            } else {
                addItem(.disappearingMessagesState,
                        copy: NSLocalizedString("UNKNOWN_USER_DISABLED_DISAPPEARING_MESSAGES_CONFIGURATION",
                                                comment: "Info Message when an unknown user disabled disappearing messages."))
            }
        }
    }

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
            addItem(.userMembershipState,
                    address: localAddress,
                    copy: NSLocalizedString("GROUP_LOCAL_USER_JOINED_THE_GROUP",
                                            comment: "Message indicating that the local user has joined the group."))
        case .invited:
            if let localAddress = Self.tsAccountManager.localAddress,
                let inviterUuid = newGroupMembership.addedByUuid(forPendingMember: localAddress) {
                let inviterAddress = SignalServiceAddress(uuid: inviterUuid)
                let inviterName = Self.displayName(for: inviterAddress, transaction: transaction)
                let format = NSLocalizedString("GROUP_LOCAL_USER_INVITED_BY_REMOTE_USER_FORMAT",
                                               comment: "Message indicating that the local user was invited to the group by another user. Embeds {{remote user name}}.")
                addItem(.userMembershipState,
                        address: localAddress,
                        format: format, inviterName)
            } else {
                addItem(.userMembershipState,
                        address: localAddress,
                        copy: NSLocalizedString("GROUP_LOCAL_USER_INVITED_TO_THE_GROUP",
                                                comment: "Message indicating that the local user was invited to the group."))
            }
        case .none:
            if !DebugFlags.permissiveGroupUpdateInfoMessages {
                owsFailDebug("Learned of group without any membership status.")
            } else {
                addItem(.debug, copy: "Error: Learned of group without any membership status.")
            }
        }
    }

    // MARK: - Membership Status

    enum MembershipStatus {
        case normalMember
        case invited
        case none
    }

    func localMembershipStatus(for groupMembership: GroupMembership) -> MembershipStatus {
        return membershipStatus(of: localAddress, in: groupMembership)
    }

    func membershipStatus(of address: SignalServiceAddress,
                          in groupMembership: GroupMembership) -> MembershipStatus {
        if groupMembership.isNonPendingMember(address) {
            return .normalMember
        } else if groupMembership.isPending(address) {
            return .invited
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

        let updaterName = Self.displayName(for: updaterAddress, transaction: transaction)
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

    private static func displayName(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> String {
        // TODO: Remove this after we enable the message request feature flag.
        assert(!FeatureFlags.messageRequest)
        var displayName = contactsManager.displayName(for: address, transaction: transaction).filterForDisplay ?? ""
        if displayName == contactsManager.unknownUserLabel,
            let profileName = profileManager.fullName(for: address, transaction: transaction) {
            displayName = profileName.filterForDisplay ?? ""
        }
        if displayName.isEmpty {
            return contactsManager.unknownUserLabel
        } else {
            return displayName
        }
    }
}
