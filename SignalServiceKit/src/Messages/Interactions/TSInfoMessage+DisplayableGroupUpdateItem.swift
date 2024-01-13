//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

/// Represents a specific update made to a group that can be presented to the
/// user as part of a ``TSInfoMessage``.
///
/// Legacy info messages produce these by "diffing" group models from
/// "before/after" the update, while new info messages produce these from
/// ``TSInfoMessage/PersistableGroupUpdateItem``s that are "precomputed" when the
/// info message is created.
public enum DisplayableGroupUpdateItem {
    case genericUpdateByLocalUser
    case genericUpdateByOtherUser(updaterName: String, updaterAddress: SignalServiceAddress)
    case genericUpdateByUnknownUser

    case createdByLocalUser
    case createdByOtherUser(updaterName: String, updaterAddress: SignalServiceAddress)
    case createdByUnknownUser

    case nameChangedByLocalUser(newGroupName: String)
    case nameChangedByOtherUser(updaterName: String, updaterAddress: SignalServiceAddress, newGroupName: String)
    case nameChangedByUnknownUser(newGroupName: String)

    case nameRemovedByLocalUser
    case nameRemovedByOtherUser(updaterName: String, updaterAddress: SignalServiceAddress)
    case nameRemovedByUnknownUser

    case avatarChangedByLocalUser
    case avatarChangedByOtherUser(updaterName: String, updaterAddress: SignalServiceAddress)
    case avatarChangedByUnknownUser

    case avatarRemovedByLocalUser
    case avatarRemovedByOtherUser(updaterName: String, updaterAddress: SignalServiceAddress)
    case avatarRemovedByUnknownUser

    case descriptionChangedByLocalUser(newDescription: String)
    case descriptionChangedByOtherUser(newDescription: String, updaterName: String, updaterAddress: SignalServiceAddress)
    case descriptionChangedByUnknownUser(newDescription: String)

    case descriptionRemovedByLocalUser
    case descriptionRemovedByOtherUser(updaterName: String, updaterAddress: SignalServiceAddress)
    case descriptionRemovedByUnknownUser

    case membersAccessChangedByLocalUser(newAccess: GroupV2Access)
    case membersAccessChangedByOtherUser(updaterName: String, updaterAddress: SignalServiceAddress, newAccess: GroupV2Access)
    case membersAccessChangedByUnknownUser(newAccess: GroupV2Access)

    case attributesAccessChangedByLocalUser(newAccess: GroupV2Access)
    case attributesAccessChangedByOtherUser(updaterName: String, updaterAddress: SignalServiceAddress, newAccess: GroupV2Access)
    case attributesAccessChangedByUnknownUser(newAccess: GroupV2Access)

    case announcementOnlyEnabledByLocalUser
    case announcementOnlyEnabledByOtherUser(updaterName: String, updaterAddress: SignalServiceAddress)
    case announcementOnlyEnabledByUnknownUser

    case announcementOnlyDisabledByLocalUser
    case announcementOnlyDisabledByOtherUser(updaterName: String, updaterAddress: SignalServiceAddress)
    case announcementOnlyDisabledByUnknownUser

    case inviteFriendsToNewlyCreatedGroup
    case wasMigrated

    case localUserWasGrantedAdministratorByLocalUser
    case localUserWasGrantedAdministratorByOtherUser(updaterName: String, updaterAddress: SignalServiceAddress)
    case localUserWasGrantedAdministratorByUnknownUser

    case otherUserWasGrantedAdministratorByLocalUser(userName: String, userAddress: SignalServiceAddress)
    case otherUserWasGrantedAdministratorByOtherUser(updaterName: String, updaterAddress: SignalServiceAddress, userName: String, userAddress: SignalServiceAddress)
    case otherUserWasGrantedAdministratorByUnknownUser(userName: String, userAddress: SignalServiceAddress)

    case localUserWasRevokedAdministratorByLocalUser
    case localUserWasRevokedAdministratorByOtherUser(updaterName: String, updaterAddress: SignalServiceAddress)
    case localUserWasRevokedAdministratorByUnknownUser

    case otherUserWasRevokedAdministratorByLocalUser(userName: String, userAddress: SignalServiceAddress)
    case otherUserWasRevokedAdministratorByOtherUser(updaterName: String, updaterAddress: SignalServiceAddress, userName: String, userAddress: SignalServiceAddress)
    case otherUserWasRevokedAdministratorByUnknownUser(userName: String, userAddress: SignalServiceAddress)

    case localUserLeft
    case localUserRemoved(removerName: String, removerAddress: SignalServiceAddress)
    case localUserRemovedByUnknownUser

    case otherUserLeft(userName: String, userAddress: SignalServiceAddress)
    case otherUserRemovedByLocalUser(userName: String, userAddress: SignalServiceAddress)
    case otherUserRemoved(removerName: String, removerAddress: SignalServiceAddress, userName: String, userAddress: SignalServiceAddress)
    case otherUserRemovedByUnknownUser(userName: String, userAddress: SignalServiceAddress)

    case localUserWasInvitedByLocalUser
    case localUserWasInvitedByOtherUser(updaterName: String, updaterAddress: SignalServiceAddress)
    case localUserWasInvitedByUnknownUser

    case otherUserWasInvitedByLocalUser(userName: String, userAddress: SignalServiceAddress)

    case unnamedUsersWereInvitedByLocalUser(count: UInt)
    case unnamedUsersWereInvitedByOtherUser(updaterName: String, updaterAddress: SignalServiceAddress, count: UInt)
    case unnamedUsersWereInvitedByUnknownUser(count: UInt)

    case localUserAcceptedInviteFromInviter(inviterName: String, inviterAddress: SignalServiceAddress)
    case localUserAcceptedInviteFromUnknownUser
    case otherUserAcceptedInviteFromLocalUser(userName: String, userAddress: SignalServiceAddress)
    case otherUserAcceptedInviteFromInviter(userName: String, userAddress: SignalServiceAddress, inviterName: String, inviterAddress: SignalServiceAddress)
    case otherUserAcceptedInviteFromUnknownUser(userName: String, userAddress: SignalServiceAddress)

    case localUserJoined
    case otherUserJoined(userName: String, userAddress: SignalServiceAddress)

    case localUserAddedByLocalUser
    case localUserAddedByOtherUser(updaterName: String, updaterAddress: SignalServiceAddress)
    case localUserAddedByUnknownUser

    case otherUserAddedByLocalUser(userName: String, userAddress: SignalServiceAddress)
    case otherUserAddedByOtherUser(updaterName: String, updaterAddress: SignalServiceAddress, userName: String, userAddress: SignalServiceAddress)
    case otherUserAddedByUnknownUser(userName: String, userAddress: SignalServiceAddress)

    case localUserDeclinedInviteFromInviter(inviterName: String, inviterAddress: SignalServiceAddress)
    case localUserDeclinedInviteFromUnknownUser
    case localUserInviteRevoked(revokerName: String, revokerAddress: SignalServiceAddress)
    case localUserInviteRevokedByUnknownUser

    case otherUserInviteRevokedByLocalUser(userName: String, userAddress: SignalServiceAddress)
    case otherUserDeclinedInviteFromLocalUser(userName: String, userAddress: SignalServiceAddress)
    case otherUserDeclinedInviteFromInviter(inviterName: String, inviterAddress: SignalServiceAddress)
    case otherUserDeclinedInviteFromUnknownUser

    case unnamedUserInvitesWereRevokedByLocalUser(count: UInt)
    case unnamedUserInvitesWereRevokedByOtherUser(updaterName: String, updaterAddress: SignalServiceAddress, count: UInt)
    case unnamedUserInvitesWereRevokedByUnknownUser(count: UInt)

    case localUserRequestedToJoin
    case otherUserRequestedToJoin(userName: String, userAddress: SignalServiceAddress)

    case localUserRequestApproved(approverName: String, approverAddress: SignalServiceAddress)
    case localUserRequestApprovedByUnknownUser
    case otherUserRequestApprovedByLocalUser(userName: String, userAddress: SignalServiceAddress)
    case otherUserRequestApproved(userName: String, userAddress: SignalServiceAddress, approverName: String, approverAddress: SignalServiceAddress)
    case otherUserRequestApprovedByUnknownUser(userName: String, userAddress: SignalServiceAddress)

    case localUserRequestCanceledByLocalUser
    case localUserRequestRejectedByUnknownUser

    case otherUserRequestRejectedByLocalUser(requesterName: String, requesterAddress: SignalServiceAddress)
    case otherUserRequestRejectedByOtherUser(updaterName: String, updaterAddress: SignalServiceAddress, requesterName: String, requesterAddress: SignalServiceAddress)
    case otherUserRequestCanceledByOtherUser(requesterName: String, requesterAddress: SignalServiceAddress)
    case otherUserRequestRejectedByUnknownUser(requesterName: String, requesterAddress: SignalServiceAddress)

    case disappearingMessagesEnabledByLocalUser(durationMs: UInt64)
    case disappearingMessagesEnabledByOtherUser(updaterName: String, updaterAddress: SignalServiceAddress, durationMs: UInt64)
    case disappearingMessagesEnabledByUnknownUser(durationMs: UInt64)

    case disappearingMessagesDisabledByLocalUser
    case disappearingMessagesDisabledByOtherUser(updaterName: String, updaterAddress: SignalServiceAddress)
    case disappearingMessagesDisabledByUnknownUser

    case inviteLinkResetByLocalUser
    case inviteLinkResetByOtherUser(updaterName: String, updaterAddress: SignalServiceAddress)
    case inviteLinkResetByUnknownUser

    case inviteLinkEnabledWithoutApprovalByLocalUser
    case inviteLinkEnabledWithoutApprovalByOtherUser(updaterName: String, updaterAddress: SignalServiceAddress)
    case inviteLinkEnabledWithoutApprovalByUnknownUser

    case inviteLinkEnabledWithApprovalByLocalUser
    case inviteLinkEnabledWithApprovalByOtherUser(updaterName: String, updaterAddress: SignalServiceAddress)
    case inviteLinkEnabledWithApprovalByUnknownUser

    case inviteLinkDisabledByLocalUser
    case inviteLinkDisabledByOtherUser(updaterName: String, updaterAddress: SignalServiceAddress)
    case inviteLinkDisabledByUnknownUser

    case inviteLinkApprovalDisabledByLocalUser
    case inviteLinkApprovalDisabledByOtherUser(updaterName: String, updaterAddress: SignalServiceAddress)
    case inviteLinkApprovalDisabledByUnknownUser

    case inviteLinkApprovalEnabledByLocalUser
    case inviteLinkApprovalEnabledByOtherUser(updaterName: String, updaterAddress: SignalServiceAddress)
    case inviteLinkApprovalEnabledByUnknownUser

    case localUserJoinedViaInviteLink
    case otherUserJoinedViaInviteLink(userName: String, userAddress: SignalServiceAddress)

    case sequenceOfInviteLinkRequestAndCancels(userName: String, userAddress: SignalServiceAddress, count: UInt, isTail: Bool)
}

public extension TSInfoMessage.PersistableGroupUpdateItem {

    /// Should this update appear as a group preview in the inbox?
    var shouldAppearInInbox: Bool {
        switch self {
        case
                .wasMigrated,
                .localUserLeft,
                .otherUserLeft:
            return false
        default:
            return true
        }
    }
}

extension DisplayableGroupUpdateItem {

    /// Localized text representing this update.
    public var localizedText: NSAttributedString {
        switch self {
        case .genericUpdateByLocalUser:
            return OWSLocalizedString(
                "GROUP_UPDATED_BY_LOCAL_USER",
                comment: "Info message indicating that the group was updated by the local user."
            ).attributed
        case let .genericUpdateByOtherUser(updaterName, updaterAddress):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_UPDATED_BY_REMOTE_USER_FORMAT",
                    comment: "Info message indicating that the group was updated by another user. Embeds {{remote user name}}."
                ),
                groupUpdateFormatArgs: [.name(updaterName, updaterAddress)]
            )
        case .genericUpdateByUnknownUser:
            return OWSLocalizedString(
                "GROUP_UPDATED",
                comment: "Info message indicating that the group was updated by an unknown user."
            ).attributed
        case .createdByLocalUser:
            return OWSLocalizedString(
                "GROUP_CREATED_BY_LOCAL_USER",
                comment: "Message indicating that group was created by the local user."
            ).attributed
        case let .createdByOtherUser(updaterName, updaterAddress):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_CREATED_BY_REMOTE_USER_FORMAT",
                    comment: "Message indicating that group was created by another user. Embeds {{remote user name}}."
                ),
                groupUpdateFormatArgs: [.name(updaterName, updaterAddress)]
            )
        case .createdByUnknownUser:
            return OWSLocalizedString(
                "GROUP_CREATED_BY_UNKNOWN_USER",
                comment: "Message indicating that group was created by an unknown user."
            ).attributed
        case let .nameChangedByLocalUser(newGroupName):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_UPDATED_NAME_UPDATED_BY_LOCAL_USER_FORMAT",
                    comment: "Message indicating that the group's name was changed by the local user. Embeds {{new group name}}."
                ),
                groupUpdateFormatArgs: [.raw(newGroupName)]
            )
        case let .nameChangedByOtherUser(updaterName, updaterAddress, newGroupName):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_UPDATED_NAME_UPDATED_BY_REMOTE_USER_FORMAT",
                    comment: "Message indicating that the group's name was changed by a remote user. Embeds {{ %1$@ user who changed the name, %2$@ new group name}}."
                ),
                groupUpdateFormatArgs: [.name(updaterName, updaterAddress), .raw(newGroupName)]
            )
        case let .nameChangedByUnknownUser(newGroupName):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_UPDATED_NAME_UPDATED_FORMAT",
                    comment: "Message indicating that the group's name was changed. Embeds {{new group name}}."
                ),
                groupUpdateFormatArgs: [.raw(newGroupName)]
            )
        case .nameRemovedByLocalUser:
            return OWSLocalizedString(
                "GROUP_UPDATED_NAME_REMOVED_BY_LOCAL_USER",
                comment: "Message indicating that the group's name was removed by the local user."
            ).attributed
        case let .nameRemovedByOtherUser(updaterName, updaterAddress):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_UPDATED_NAME_REMOVED_BY_REMOTE_USER_FORMAT",
                    comment: "Message indicating that the group's name was removed by a remote user. Embeds {{user who removed the name}}."
                ),
                groupUpdateFormatArgs: [.name(updaterName, updaterAddress)]
            )
        case .nameRemovedByUnknownUser:
            return OWSLocalizedString(
                "GROUP_UPDATED_NAME_REMOVED",
                comment: "Message indicating that the group's name was removed."
            ).attributed
        case .avatarChangedByLocalUser:
            return OWSLocalizedString(
                "GROUP_UPDATED_AVATAR_UPDATED_BY_LOCAL_USER",
                comment: "Message indicating that the group's avatar was changed."
            ).attributed
        case let .avatarChangedByOtherUser(updaterName, updaterAddress):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_UPDATED_AVATAR_UPDATED_BY_REMOTE_USER_FORMAT",
                    comment: "Message indicating that the group's avatar was changed by a remote user. Embeds {{user who changed the avatar}}."
                ),
                groupUpdateFormatArgs: [.name(updaterName, updaterAddress)]
            )
        case .avatarChangedByUnknownUser:
            return OWSLocalizedString(
                "GROUP_UPDATED_AVATAR_UPDATED",
                comment: "Message indicating that the group's avatar was changed."
            ).attributed
        case .avatarRemovedByLocalUser:
            return OWSLocalizedString(
                "GROUP_UPDATED_AVATAR_REMOVED_BY_LOCAL_USER",
                comment: "Message indicating that the group's avatar was removed."
            ).attributed
        case let .avatarRemovedByOtherUser(updaterName, updaterAddress):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_UPDATED_AVATAR_REMOVED_BY_REMOTE_USER_FORMAT",
                    comment: "Message indicating that the group's avatar was removed by a remote user. Embeds {{user who removed the avatar}}."
                ),
                groupUpdateFormatArgs: [.name(updaterName, updaterAddress)]
            )
        case .avatarRemovedByUnknownUser:
            return OWSLocalizedString(
                "GROUP_UPDATED_AVATAR_REMOVED",
                comment: "Message indicating that the group's avatar was removed."
            ).attributed
        case .descriptionChangedByLocalUser:
            return OWSLocalizedString(
                "GROUP_UPDATED_DESCRIPTION_UPDATED_BY_LOCAL_USER",
                comment: "Message indicating that the group's description was changed by the local user.."
            ).attributed
        case let .descriptionChangedByOtherUser(_, updaterName, updaterAddress):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_UPDATED_DESCRIPTION_UPDATED_BY_REMOTE_USER_FORMAT",
                    comment: "Message indicating that the group's description was changed by a remote user. Embeds {{ user who changed the name }}."
                ),
                groupUpdateFormatArgs: [.name(updaterName, updaterAddress)]
            )
        case .descriptionChangedByUnknownUser:
            return OWSLocalizedString(
                "GROUP_UPDATED_DESCRIPTION_UPDATED",
                comment: "Message indicating that the group's description was changed."
            ).attributed
        case .descriptionRemovedByLocalUser:
            return OWSLocalizedString(
                "GROUP_UPDATED_DESCRIPTION_REMOVED_BY_LOCAL_USER",
                comment: "Message indicating that the group's description was removed by the local user."
            ).attributed
        case let .descriptionRemovedByOtherUser(updaterName, updaterAddress):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_UPDATED_DESCRIPTION_REMOVED_BY_REMOTE_USER_FORMAT",
                    comment: "Message indicating that the group's description was removed by a remote user. Embeds {{user who removed the name}}."
                ),
                groupUpdateFormatArgs: [.name(updaterName, updaterAddress)]
            )
        case .descriptionRemovedByUnknownUser:
            return OWSLocalizedString(
                "GROUP_UPDATED_DESCRIPTION_REMOVED",
                comment: "Message indicating that the group's description was removed."
            ).attributed
        case let .membersAccessChangedByLocalUser(newAccess):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_ACCESS_MEMBERS_UPDATED_BY_LOCAL_USER_FORMAT",
                    comment: "Message indicating that the access to the group's members was changed by the local user. Embeds {{new access level}}."
                ),
                groupUpdateFormatArgs: [.raw(newAccess.descriptionForCopy)]
            )
        case let .membersAccessChangedByOtherUser(updaterName, updaterAddress, newAccess):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_ACCESS_MEMBERS_UPDATED_BY_REMOTE_USER_FORMAT",
                    comment: "Message indicating that the access to the group's members was changed by a remote user. Embeds {{ %1$@ user who changed the access, %2$@ new access level}}."
                ),
                groupUpdateFormatArgs: [
                    .name(updaterName, updaterAddress),
                    .raw(newAccess.descriptionForCopy)
                ]
            )
        case let .membersAccessChangedByUnknownUser(newAccess):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_ACCESS_MEMBERS_UPDATED_FORMAT",
                    comment: "Message indicating that the access to the group's members was changed. Embeds {{new access level}}."
                ),
                groupUpdateFormatArgs: [.raw(newAccess.descriptionForCopy)]
            )
        case let .attributesAccessChangedByLocalUser(newAccess):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_ACCESS_ATTRIBUTES_UPDATED_BY_LOCAL_USER_FORMAT",
                    comment: "Message indicating that the access to the group's attributes was changed by the local user. Embeds {{new access level}}."
                ),
                groupUpdateFormatArgs: [.raw(newAccess.descriptionForCopy)]
            )
        case let .attributesAccessChangedByOtherUser(updaterName, updaterAddress, newAccess):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_ACCESS_ATTRIBUTES_UPDATED_BY_REMOTE_USER_FORMAT",
                    comment: "Message indicating that the access to the group's attributes was changed by a remote user. Embeds {{ %1$@ user who changed the access, %2$@ new access level}}."
                ),
                groupUpdateFormatArgs: [
                    .name(updaterName, updaterAddress),
                    .raw(newAccess.descriptionForCopy)
                ]
            )
        case let .attributesAccessChangedByUnknownUser(newAccess):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_ACCESS_ATTRIBUTES_UPDATED_FORMAT",
                    comment: "Message indicating that the access to the group's attributes was changed. Embeds {{new access level}}."
                ),
                groupUpdateFormatArgs: [.raw(newAccess.descriptionForCopy)]
            )
        case .announcementOnlyEnabledByLocalUser:
            return OWSLocalizedString(
                "GROUP_IS_ANNOUNCEMENT_ONLY_ENABLED_BY_LOCAL_USER",
                comment: "Message indicating that 'announcement-only' mode was enabled by the local user."
            ).attributed
        case let .announcementOnlyEnabledByOtherUser(updaterName, updaterAddress):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_IS_ANNOUNCEMENT_ONLY_ENABLED_BY_REMOTE_USER_FORMAT",
                    comment: "Message indicating that 'announcement-only' mode was enabled by a remote user. Embeds {{ user who enabled 'announcement-only' mode }}."
                ),
                groupUpdateFormatArgs: [.name(updaterName, updaterAddress)]
            )
        case .announcementOnlyEnabledByUnknownUser:
            return OWSLocalizedString(
                "GROUP_IS_ANNOUNCEMENT_ONLY_ENABLED",
                comment: "Message indicating that 'announcement-only' mode was enabled."
            ).attributed
        case .announcementOnlyDisabledByLocalUser:
            return OWSLocalizedString(
                "GROUP_IS_ANNOUNCEMENT_ONLY_DISABLED_BY_LOCAL_USER",
                comment: "Message indicating that 'announcement-only' mode was disabled by the local user."
            ).attributed
        case let .announcementOnlyDisabledByOtherUser(updaterName, updaterAddress):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_IS_ANNOUNCEMENT_ONLY_DISABLED_BY_REMOTE_USER_FORMAT",
                    comment: "Message indicating that 'announcement-only' mode was disabled by a remote user. Embeds {{ user who disabled 'announcement-only' mode }}."
                ),
                groupUpdateFormatArgs: [.name(updaterName, updaterAddress)]
            )
        case .announcementOnlyDisabledByUnknownUser:
            return OWSLocalizedString(
                "GROUP_IS_ANNOUNCEMENT_ONLY_DISABLED",
                comment: "Message indicating that 'announcement-only' mode was disabled."
            ).attributed
        case .inviteFriendsToNewlyCreatedGroup:
            return OWSLocalizedString(
                "GROUP_LINK_PROMOTION_UPDATE",
                comment: "Suggestion to invite more group members via the group invite link."
            ).attributed
        case .wasMigrated:
            return OWSLocalizedString(
                "GROUP_WAS_MIGRATED",
                comment: "Message indicating that the group was migrated."
            ).attributed
        case .localUserWasGrantedAdministratorByLocalUser:
            return OWSLocalizedString(
                "GROUP_LOCAL_USER_GRANTED_ADMINISTRATOR",
                comment: "Message indicating that the local user was granted administrator role."
            ).attributed
        case let .localUserWasGrantedAdministratorByOtherUser(updaterName, updaterAddress):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_LOCAL_USER_GRANTED_ADMINISTRATOR_BY_REMOTE_USER_FORMAT",
                    comment: "Message indicating that the local user was granted administrator role by another user. Embeds {{remote user name}}."
                ),
                groupUpdateFormatArgs: [.name(updaterName, updaterAddress)]
            )
        case .localUserWasGrantedAdministratorByUnknownUser:
            return OWSLocalizedString(
                "GROUP_LOCAL_USER_GRANTED_ADMINISTRATOR",
                comment: "Message indicating that the local user was granted administrator role."
            ).attributed
        case let .otherUserWasGrantedAdministratorByLocalUser(userName, userAddress):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_REMOTE_USER_GRANTED_ADMINISTRATOR_BY_LOCAL_USER",
                    comment: "Message indicating that a remote user was granted administrator role by local user. Embeds {{remote user name}}."
                ),
                groupUpdateFormatArgs: [.name(userName, userAddress)]
            )
        case let .otherUserWasGrantedAdministratorByOtherUser(updaterName, updaterAddress, userName, userAddress):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_REMOTE_USER_GRANTED_ADMINISTRATOR_BY_REMOTE_USER_FORMAT",
                    comment: "Message indicating that a remote user was granted administrator role by another user. Embeds {{ %1$@ user who granted, %2$@ user who was granted administrator role}}."
                ),
                groupUpdateFormatArgs: [
                    .name(updaterName, updaterAddress),
                    .name(userName, userAddress)
                ]
            )
        case let .otherUserWasGrantedAdministratorByUnknownUser(userName, userAddress):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_REMOTE_USER_GRANTED_ADMINISTRATOR",
                    comment: "Message indicating that a remote user was granted administrator role. Embeds {{remote user name}}."
                ),
                groupUpdateFormatArgs: [.name(userName, userAddress)]
            )
        case .localUserWasRevokedAdministratorByLocalUser:
            return OWSLocalizedString(
                "GROUP_LOCAL_USER_REVOKED_ADMINISTRATOR",
                comment: "Message indicating that the local user had their administrator role revoked."
            ).attributed
        case let .localUserWasRevokedAdministratorByOtherUser(updaterName, updaterAddress):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_LOCAL_USER_REVOKED_ADMINISTRATOR_BY_REMOTE_USER_FORMAT",
                    comment: "Message indicating that the local user had their administrator role revoked by another user. Embeds {{remote user name}}."
                ),
                groupUpdateFormatArgs: [.name(updaterName, updaterAddress)]
            )
        case .localUserWasRevokedAdministratorByUnknownUser:
            return OWSLocalizedString(
                "GROUP_LOCAL_USER_REVOKED_ADMINISTRATOR",
                comment: "Message indicating that the local user had their administrator role revoked."
            ).attributed
        case let .otherUserWasRevokedAdministratorByLocalUser(userName, userAddress):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_REMOTE_USER_REVOKED_ADMINISTRATOR_BY_LOCAL_USER",
                    comment: "Message indicating that a remote user had their administrator role revoked by local user. Embeds {{remote user name}}."
                ),
                groupUpdateFormatArgs: [.name(userName, userAddress)]
            )
        case let .otherUserWasRevokedAdministratorByOtherUser(updaterName, updaterAddress, userName, userAddress):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_REMOTE_USER_REVOKED_ADMINISTRATOR_BY_REMOTE_USER_FORMAT",
                    comment: "Message indicating that a remote user had their administrator role revoked by another user. Embeds {{ %1$@ user who revoked, %2$@ user who was granted administrator role}}."
                ),
                groupUpdateFormatArgs: [
                    .name(updaterName, updaterAddress),
                    .name(userName, userAddress)
                ]
            )
        case let .otherUserWasRevokedAdministratorByUnknownUser(userName, userAddress):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_REMOTE_USER_REVOKED_ADMINISTRATOR",
                    comment: "Message indicating that a remote user had their administrator role revoked. Embeds {{remote user name}}."
                ),
                groupUpdateFormatArgs: [.name(userName, userAddress)]
            )
        case .localUserLeft:
            return OWSLocalizedString(
                "GROUP_YOU_LEFT",
                comment: "Message indicating that the local user left the group."
            ).attributed
        case let .localUserRemoved(removerName, removerAddress):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_LOCAL_USER_REMOVED_BY_REMOTE_USER_FORMAT",
                    comment: "Message indicating that the local user was removed from the group by another user. Embeds {{remote user name}}."
                ),
                groupUpdateFormatArgs: [.name(removerName, removerAddress)]
            )
        case .localUserRemovedByUnknownUser:
            return OWSLocalizedString(
                "GROUP_LOCAL_USER_REMOVED_BY_UNKNOWN_USER",
                comment: "Message indicating that the local user was removed from the group by an unknown user."
            ).attributed
        case let .otherUserLeft(userName, userAddress):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_REMOTE_USER_LEFT_GROUP_FORMAT",
                    comment: "Message indicating that a remote user has left the group. Embeds {{remote user name}}."
                ),
                groupUpdateFormatArgs: [.name(userName, userAddress)]
            )
        case let .otherUserRemovedByLocalUser(userName, userAddress):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_REMOTE_USER_REMOVED_BY_LOCAL_USER_FORMAT",
                    comment: "Message indicating that a remote user was removed from the group by the local user. Embeds {{remote user name}}."
                ),
                groupUpdateFormatArgs: [.name(userName, userAddress)]
            )
        case let .otherUserRemoved(removerName, removerAddress, userName, userAddress):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_REMOTE_USER_REMOVED_FROM_GROUP_BY_REMOTE_USER_FORMAT",
                    comment: "Message indicating that the remote user was removed from the group. Embeds {{ %1$@ user who removed the user, %2$@ user who was removed}}."
                ),
                groupUpdateFormatArgs: [
                    .name(removerName, removerAddress),
                    .name(userName, userAddress)
                ]
            )
        case let .otherUserRemovedByUnknownUser(userName, userAddress):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_REMOTE_USER_REMOVED_BY_UNKNOWN_USER_FORMAT",
                    comment: "Message indicating that a remote user was removed from the group by an unknown user. Embeds {{remote user name}}."
                ),
                groupUpdateFormatArgs: [.name(userName, userAddress)]
            )
        case .localUserWasInvitedByLocalUser:
            return OWSLocalizedString(
                "GROUP_LOCAL_USER_INVITED_TO_THE_GROUP",
                comment: "Message indicating that the local user was invited to the group."
            ).attributed
        case let .localUserWasInvitedByOtherUser(updaterName, updaterAddress):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_LOCAL_USER_INVITED_BY_REMOTE_USER_FORMAT",
                    comment: "Message indicating that the local user was invited to the group by another user. Embeds {{remote user name}}."
                ),
                groupUpdateFormatArgs: [.name(updaterName, updaterAddress)]
            )
        case .localUserWasInvitedByUnknownUser:
            return OWSLocalizedString(
                "GROUP_LOCAL_USER_INVITED_TO_THE_GROUP",
                comment: "Message indicating that the local user was invited to the group."
            ).attributed
        case let .otherUserWasInvitedByLocalUser(userName, userAddress):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_REMOTE_USER_INVITED_BY_LOCAL_USER_FORMAT",
                    comment: "Message indicating that a remote user was invited to the group by the local user. Embeds {{remote user name}}."
                ),
                groupUpdateFormatArgs: [.name(userName, userAddress)]
            )
        case let .unnamedUsersWereInvitedByLocalUser(count):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_REMOTE_USER_INVITED_%d",
                    tableName: "PluralAware",
                    comment: "Message indicating that a group of remote users were invited to the group. Embeds {{number of invited users}}."
                ),
                groupUpdateFormatArgs: [.raw(count)]
            )
        case let .unnamedUsersWereInvitedByOtherUser(updaterName, updaterAddress, count):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_REMOTE_USER_INVITED_BY_REMOTE_USER_%d",
                    tableName: "PluralAware",
                    comment: "Message indicating that a group of remote users were invited to the group by the local user. Embeds {{ %1$@ number of invited users, %2$@ user who invited the user }}."
                ),
                groupUpdateFormatArgs: [.raw(count), .name(updaterName, updaterAddress)]
            )
        case let .unnamedUsersWereInvitedByUnknownUser(count):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_REMOTE_USER_INVITED_%d",
                    tableName: "PluralAware",
                    comment: "Message indicating that a group of remote users were invited to the group. Embeds {{number of invited users}}."
                ),
                groupUpdateFormatArgs: [.raw(count)]
            )
        case let .localUserAcceptedInviteFromInviter(inviterName, inviterAddress):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_LOCAL_USER_INVITE_ACCEPTED_FORMAT",
                    comment: "Message indicating that the local user accepted an invite to the group. Embeds {{user who invited the local user}}."
                ),
                groupUpdateFormatArgs: [.name(inviterName, inviterAddress)]
            )
        case .localUserAcceptedInviteFromUnknownUser:
            return OWSLocalizedString(
                "GROUP_LOCAL_USER_INVITE_ACCEPTED",
                comment: "Message indicating that the local user accepted an invite to the group."
            ).attributed
        case let .otherUserAcceptedInviteFromLocalUser(userName, userAddress):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_REMOTE_USER_ACCEPTED_INVITE_FROM_LOCAL_USER_FORMAT",
                    comment: "Message indicating that a remote user has accepted an invite from the local user. Embeds {{remote user name}}."
                ),
                groupUpdateFormatArgs: [.name(userName, userAddress)]
            )
        case let .otherUserAcceptedInviteFromInviter(userName, userAddress, inviterName, inviterAddress):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_REMOTE_USER_ACCEPTED_INVITE_FROM_REMOTE_USER_FORMAT",
                    comment: "Message indicating that a remote user has accepted their invite. Embeds {{ %1$@ user who accepted their invite, %2$@ user who invited the user}}."
                ),
                groupUpdateFormatArgs: [
                    .name(userName, userAddress),
                    .name(inviterName, inviterAddress)
                ]
            )
        case let .otherUserAcceptedInviteFromUnknownUser(userName, userAddress):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_REMOTE_USER_ACCEPTED_INVITE_FORMAT",
                    comment: "Message indicating that a remote user has accepted their invite. Embeds {{remote user name}}."
                ),
                groupUpdateFormatArgs: [.name(userName, userAddress)]
            )
        case .localUserJoined:
            return OWSLocalizedString(
                "GROUP_LOCAL_USER_JOINED_THE_GROUP",
                comment: "Message indicating that the local user has joined the group."
            ).attributed
        case let .otherUserJoined(userName, userAddress):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_REMOTE_USER_JOINED_GROUP_FORMAT",
                    comment: "Message indicating that a remote user was added to the group. Embeds {{remote user name}}."
                ),
                groupUpdateFormatArgs: [.name(userName, userAddress)]
            )
        case .localUserAddedByLocalUser:
            return OWSLocalizedString(
                "GROUP_LOCAL_USER_WAS_ADDED_TO_THE_GROUP",
                comment: "Message indicating that the local user was added to the group."
            ).attributed
        case let .localUserAddedByOtherUser(updaterName, updaterAddress):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_LOCAL_USER_ADDED_TO_GROUP_BY_REMOTE_USER_FORMAT",
                    comment: "Message indicating that the local user was added to the group by another user. Embeds {{remote user name}}."
                ),
                groupUpdateFormatArgs: [.name(updaterName, updaterAddress)]
            )
        case .localUserAddedByUnknownUser:
            return OWSLocalizedString(
                "GROUP_LOCAL_USER_WAS_ADDED_TO_THE_GROUP",
                comment: "Message indicating that the local user was added to the group."
            ).attributed
        case let .otherUserAddedByLocalUser(userName, userAddress):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_REMOTE_USER_ADDED_TO_GROUP_BY_LOCAL_USER_FORMAT",
                    comment: "Message indicating that a remote user was added to the group by the local user. Embeds {{remote user name}}."
                ),
                groupUpdateFormatArgs: [.name(userName, userAddress)]
            )
        case let .otherUserAddedByOtherUser(updaterName, updaterAddress, userName, userAddress):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_REMOTE_USER_ADDED_TO_GROUP_BY_REMOTE_USER_FORMAT",
                    comment: "Message indicating that a remote user was added to the group by another user. Embeds {{ %1$@ user who added the user, %2$@ user who was added}}."
                ),
                groupUpdateFormatArgs: [
                    .name(updaterName, updaterAddress),
                    .name(userName, userAddress)
                ]
            )
        case let .otherUserAddedByUnknownUser(userName, userAddress):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_REMOTE_USER_ADDED_TO_GROUP_FORMAT",
                    comment: "Message indicating that a remote user was added to the group. Embeds {{remote user name}}."
                ),
                groupUpdateFormatArgs: [.name(userName, userAddress)]
            )
        case let .localUserDeclinedInviteFromInviter(inviterName, inviterAddress):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_LOCAL_USER_INVITE_DECLINED_FORMAT",
                    comment: "Message indicating that the local user declined an invite to the group. Embeds {{user who invited the local user}}."
                ),
                groupUpdateFormatArgs: [.name(inviterName, inviterAddress)]
            )
        case .localUserDeclinedInviteFromUnknownUser:
            return OWSLocalizedString(
                "GROUP_LOCAL_USER_INVITE_DECLINED_BY_LOCAL_USER",
                comment: "Message indicating that the local user declined an invite to the group."
            ).attributed
        case let .localUserInviteRevoked(revokerName, revokerAddress):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_LOCAL_USER_INVITE_REVOKED_BY_REMOTE_USER_FORMAT",
                    comment: "Message indicating that the local user's invite was revoked by another user. Embeds {{remote user name}}."
                ),
                groupUpdateFormatArgs: [.name(revokerName, revokerAddress)]
            )
        case .localUserInviteRevokedByUnknownUser:
            return OWSLocalizedString(
                "GROUP_LOCAL_USER_INVITE_REVOKED_BY_UNKNOWN_USER",
                comment: "Message indicating that the local user's invite was revoked by an unknown user."
            ).attributed
        case let .otherUserInviteRevokedByLocalUser(userName, userAddress):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_REMOTE_USER_INVITE_REVOKED_BY_LOCAL_USER_FORMAT",
                    comment: "Message indicating that a remote user's invite was revoked by the local user. Embeds {{remote user name}}."
                ),
                groupUpdateFormatArgs: [.name(userName, userAddress)]
            )
        case let .otherUserDeclinedInviteFromLocalUser(userName, userAddress):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_REMOTE_USER_DECLINED_INVITE_FROM_LOCAL_USER_FORMAT",
                    comment: "Message indicating that a remote user has declined an invite to the group from the local user. Embeds {{remote user name}}."
                ),
                groupUpdateFormatArgs: [.name(userName, userAddress)]
            )
        case let .otherUserDeclinedInviteFromInviter(inviterName, inviterAddress):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_REMOTE_USER_DECLINED_INVITE_FORMAT",
                    comment: "Message indicating that a remote user has declined their invite. Embeds {{ user who invited them }}."
                ),
                groupUpdateFormatArgs: [.name(inviterName, inviterAddress)]
            )
        case .otherUserDeclinedInviteFromUnknownUser:
            return OWSLocalizedString(
                "GROUP_REMOTE_USER_DECLINED_INVITE",
                comment: "Message indicating that a remote user has declined their invite."
            ).attributed
        case let .unnamedUserInvitesWereRevokedByLocalUser(count):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_REMOTE_USER_INVITE_REVOKED_%d",
                    tableName: "PluralAware",
                    comment: "Message indicating that a group of remote users' invites were revoked. Embeds {{ number of users }}."
                ),
                groupUpdateFormatArgs: [.raw(count)]
            )
        case let .unnamedUserInvitesWereRevokedByOtherUser(updaterName, updaterAddress, count):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_REMOTE_USER_INVITE_REVOKED_BY_REMOTE_USER_%d",
                    tableName: "PluralAware",
                    comment: "Message indicating that a group of remote users' invites were revoked by a remote user. Embeds {{ %1$@ number of users, %2$@ user who revoked the invite }}."
                ),
                groupUpdateFormatArgs: [
                    .raw(count),
                    .name(updaterName, updaterAddress)
                ]
            )
        case let .unnamedUserInvitesWereRevokedByUnknownUser(count):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_REMOTE_USER_INVITE_REVOKED_%d",
                    tableName: "PluralAware",
                    comment: "Message indicating that a group of remote users' invites were revoked. Embeds {{ number of users }}."
                ),
                groupUpdateFormatArgs: [.raw(count)]
            )
        case .localUserRequestedToJoin:
            return OWSLocalizedString(
                "GROUP_LOCAL_USER_REQUESTED_TO_JOIN_TO_THE_GROUP",
                comment: "Message indicating that the local user requested to join the group."
            ).attributed
        case let .otherUserRequestedToJoin(userName, userAddress):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_REMOTE_USER_REQUESTED_TO_JOIN_THE_GROUP_FORMAT",
                    comment: "Message indicating that a remote user requested to join the group. Embeds {{requesting user name}}."
                ),
                groupUpdateFormatArgs: [.name(userName, userAddress)]
            )
        case let .localUserRequestApproved(approverName, approverAddress):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_LOCAL_USER_REQUEST_APPROVED_BY_REMOTE_USER_FORMAT",
                    comment: "Message indicating that the local user's request to join the group was approved by another user. Embeds {{ %@ the name of the user who approved the request }}."
                ),
                groupUpdateFormatArgs: [.name(approverName, approverAddress)]
            )
        case .localUserRequestApprovedByUnknownUser:
            return OWSLocalizedString(
                "GROUP_LOCAL_USER_REQUEST_APPROVED",
                comment: "Message indicating that the local user's request to join the group was approved."
            ).attributed
        case let .otherUserRequestApprovedByLocalUser(userName, userAddress):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_REMOTE_USER_REQUEST_APPROVED_BY_LOCAL_USER_FORMAT",
                    comment: "Message indicating that a remote user's request to join the group was approved by the local user. Embeds {{requesting user name}}."
                ),
                groupUpdateFormatArgs: [.name(userName, userAddress)]
            )
        case let .otherUserRequestApproved(userName, userAddress, approverName, approverAddress):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_REMOTE_USER_REQUEST_APPROVED_BY_REMOTE_USER_FORMAT",
                    comment: "Message indicating that a remote user's request to join the group was approved by another user. Embeds {{ %1$@ requesting user name, %2$@ approving user name }}."
                ),
                groupUpdateFormatArgs: [
                    .name(userName, userAddress),
                    .name(approverName, approverAddress)
                ]
            )
        case let .otherUserRequestApprovedByUnknownUser(userName, userAddress):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_REMOTE_USER_REQUEST_APPROVED_BY_UNKNOWN_USER_FORMAT",
                    comment: "Message indicating that a remote user's request to join the group was approved by an unknown user. Embeds {{ %1$@ requesting user name }}."
                ),
                groupUpdateFormatArgs: [
                    .name(userName, userAddress)
                ]
            )
        case .localUserRequestCanceledByLocalUser:
            return OWSLocalizedString(
                "GROUP_LOCAL_USER_REQUEST_CANCELLED_BY_LOCAL_USER",
                comment: "Message indicating that the local user cancelled their request to join the group."
            ).attributed
        case .localUserRequestRejectedByUnknownUser:
            return OWSLocalizedString(
                "GROUP_LOCAL_USER_REQUEST_REJECTED",
                comment: "Message indicating that the local user's request to join the group was rejected."
            ).attributed
        case let .otherUserRequestRejectedByLocalUser(requesterName, requesterAddress):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_REMOTE_USER_REQUEST_REJECTED_BY_LOCAL_USER_FORMAT",
                    comment: "Message indicating that a remote user's request to join the group was rejected by the local user. Embeds {{requesting user name}}."
                ),
                groupUpdateFormatArgs: [.name(requesterName, requesterAddress)]
            )
        case let .otherUserRequestRejectedByOtherUser(updaterName, updaterAddress, requesterName, requesterAddress):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_REMOTE_USER_REQUEST_REJECTED_BY_REMOTE_USER_FORMAT",
                    comment: "Message indicating that a remote user's request to join the group was rejected by another user. Embeds {{ %1$@ requesting user name, %2$@ rejecting user name }}."
                ),
                groupUpdateFormatArgs: [
                    .name(requesterName, requesterAddress),
                    .name(updaterName, updaterAddress)
                ]
            )
        case let .otherUserRequestCanceledByOtherUser(requesterName, requesterAddress):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_REMOTE_USER_REQUEST_CANCELLED_BY_REMOTE_USER_FORMAT",
                    comment: "Message indicating that a remote user cancelled their request to join the group. Embeds {{ the name of the requesting user }}."
                ),
                groupUpdateFormatArgs: [.name(requesterName, requesterAddress)]
            )
        case let .otherUserRequestRejectedByUnknownUser(requesterName, requesterAddress):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_REMOTE_USER_REQUEST_REJECTED_FORMAT",
                    comment: "Message indicating that a remote user's request to join the group was rejected. Embeds {{requesting user name}}."
                ),
                groupUpdateFormatArgs: [.name(requesterName, requesterAddress)]
            )
        case let .disappearingMessagesEnabledByLocalUser(durationMs):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "YOU_UPDATED_DISAPPEARING_MESSAGES_CONFIGURATION",
                    comment: "Info Message when you update disappearing messages duration. Embeds a {{time amount}} before messages disappear. see the *_TIME_AMOUNT strings for context."
                ),
                groupUpdateFormatArgs: [.durationMs(durationMs)]
            )
        case .disappearingMessagesDisabledByLocalUser:
            return OWSLocalizedString(
                "YOU_DISABLED_DISAPPEARING_MESSAGES_CONFIGURATION",
                comment: "Info Message when you disabled disappearing messages."
            ).attributed
        case let .disappearingMessagesEnabledByOtherUser(updaterName, updaterAddress, durationMs):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "OTHER_UPDATED_DISAPPEARING_MESSAGES_CONFIGURATION",
                    comment: "Info Message when another user enabled disappearing messages. Embeds {{name of other user}} and {{time amount}} before messages disappear. See the *_TIME_AMOUNT strings for context."
                ),
                groupUpdateFormatArgs: [
                    .name(updaterName, updaterAddress),
                    .durationMs(durationMs)
                ]
            )
        case let .disappearingMessagesDisabledByOtherUser(updaterName, updaterAddress):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "OTHER_DISABLED_DISAPPEARING_MESSAGES_CONFIGURATION",
                    comment: "Info Message when another user disabled disappearing messages. Embeds {{name of other user}}."
                ),
                groupUpdateFormatArgs: [.name(updaterName, updaterAddress)]
            )
        case let .disappearingMessagesEnabledByUnknownUser(durationMs):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "UNKNOWN_USER_UPDATED_DISAPPEARING_MESSAGES_CONFIGURATION",
                    comment: "Info Message when an unknown user enabled disappearing messages. Embeds {{time amount}} before messages disappear. see the *_TIME_AMOUNT strings for context."
                ),
                groupUpdateFormatArgs: [.durationMs(durationMs)]
            )
        case .disappearingMessagesDisabledByUnknownUser:
            return OWSLocalizedString(
                "UNKNOWN_USER_DISABLED_DISAPPEARING_MESSAGES_CONFIGURATION",
                comment: "Info Message when an unknown user disabled disappearing messages."
            ).attributed
        case .inviteLinkResetByLocalUser:
            return OWSLocalizedString(
                "GROUP_INVITE_LINK_RESET_BY_LOCAL_USER",
                comment: "Message indicating that the group invite link was reset by the local user."
            ).attributed
        case let .inviteLinkResetByOtherUser(updaterName, updaterAddress):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_INVITE_LINK_RESET_BY_REMOTE_USER_FORMAT",
                    comment: "Message indicating that the group invite link was reset by a remote user. Embeds {{ user who reset the group invite link }}."
                ),
                groupUpdateFormatArgs: [.name(updaterName, updaterAddress)]
            )
        case .inviteLinkResetByUnknownUser:
            return OWSLocalizedString(
                "GROUP_INVITE_LINK_RESET",
                comment: "Message indicating that the group invite link was reset."
            ).attributed
        case .inviteLinkEnabledWithoutApprovalByLocalUser:
            return OWSLocalizedString(
                "GROUP_INVITE_LINK_ENABLED_WITHOUT_APPROVAL_BY_LOCAL_USER",
                comment: "Message indicating that the group invite link was enabled by the local user."
            ).attributed
        case let .inviteLinkEnabledWithoutApprovalByOtherUser(updaterName, updaterAddress):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_INVITE_LINK_ENABLED_WITHOUT_APPROVAL_BY_REMOTE_USER_FORMAT",
                    comment: "Message indicating that the group invite link was enabled by a remote user. Embeds {{ user who enabled the group invite link }}."
                ),
                groupUpdateFormatArgs: [.name(updaterName, updaterAddress)]
            )
        case .inviteLinkEnabledWithoutApprovalByUnknownUser:
            return OWSLocalizedString(
                "GROUP_INVITE_LINK_ENABLED_WITHOUT_APPROVAL",
                comment: "Message indicating that the group invite link was enabled."
            ).attributed
        case .inviteLinkEnabledWithApprovalByLocalUser:
            return OWSLocalizedString(
                "GROUP_INVITE_LINK_ENABLED_WITH_APPROVAL_BY_LOCAL_USER",
                comment: "Message indicating that the group invite link was enabled by the local user."
            ).attributed
        case let .inviteLinkEnabledWithApprovalByOtherUser(updaterName, updaterAddress):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_INVITE_LINK_ENABLED_WITH_APPROVAL_BY_REMOTE_USER_FORMAT",
                    comment: "Message indicating that the group invite link was enabled by a remote user. Embeds {{ user who enabled the group invite link }}."
                ),
                groupUpdateFormatArgs: [.name(updaterName, updaterAddress)]
            )
        case .inviteLinkEnabledWithApprovalByUnknownUser:
            return OWSLocalizedString(
                "GROUP_INVITE_LINK_ENABLED_WITH_APPROVAL",
                comment: "Message indicating that the group invite link was enabled."
            ).attributed
        case .inviteLinkDisabledByLocalUser:
            return OWSLocalizedString(
                "GROUP_INVITE_LINK_DISABLED_BY_LOCAL_USER",
                comment: "Message indicating that the group invite link was disabled by the local user."
            ).attributed
        case let .inviteLinkDisabledByOtherUser(updaterName, updaterAddress):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_INVITE_LINK_DISABLED_BY_REMOTE_USER_FORMAT",
                    comment: "Message indicating that the group invite link was disabled by a remote user. Embeds {{ user who disabled the group invite link }}."
                ),
                groupUpdateFormatArgs: [.name(updaterName, updaterAddress)]
            )
        case .inviteLinkDisabledByUnknownUser:
            return OWSLocalizedString(
                "GROUP_INVITE_LINK_DISABLED",
                comment: "Message indicating that the group invite link was disabled."
            ).attributed
        case .inviteLinkApprovalDisabledByLocalUser:
            return OWSLocalizedString(
                "GROUP_INVITE_LINK_SET_TO_NOT_REQUIRE_APPROVAL_BY_LOCAL_USER",
                comment: "Message indicating that the group invite link was set to not require approval by the local user."
            ).attributed
        case let .inviteLinkApprovalDisabledByOtherUser(updaterName, updaterAddress):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_INVITE_LINK_SET_TO_NOT_REQUIRE_APPROVAL_BY_REMOTE_USER_FORMAT",
                    comment: "Message indicating that the group invite link was set to not require approval by a remote user. Embeds {{ user who set the group invite link to not require approval }}."
                ),
                groupUpdateFormatArgs: [.name(updaterName, updaterAddress)]
            )
        case .inviteLinkApprovalDisabledByUnknownUser:
            return OWSLocalizedString(
                "GROUP_INVITE_LINK_SET_TO_NOT_REQUIRE_APPROVAL",
                comment: "Message indicating that the group invite link was set to not require approval."
            ).attributed
        case .inviteLinkApprovalEnabledByLocalUser:
            return OWSLocalizedString(
                "GROUP_INVITE_LINK_SET_TO_REQUIRE_APPROVAL_BY_LOCAL_USER",
                comment: "Message indicating that the group invite link was set to require approval by the local user."
            ).attributed
        case let .inviteLinkApprovalEnabledByOtherUser(updaterName, updaterAddress):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_INVITE_LINK_SET_TO_REQUIRE_APPROVAL_BY_REMOTE_USER_FORMAT",
                    comment: "Message indicating that the group invite link was set to require approval by a remote user. Embeds {{ user who set the group invite link to require approval }}."
                ),
                groupUpdateFormatArgs: [.name(updaterName, updaterAddress)]
            )
        case .inviteLinkApprovalEnabledByUnknownUser:
            return OWSLocalizedString(
                "GROUP_INVITE_LINK_SET_TO_REQUIRE_APPROVAL",
                comment: "Message indicating that the group invite link was set to require approval."
            ).attributed
        case .localUserJoinedViaInviteLink:
            return OWSLocalizedString(
                "GROUP_LOCAL_USER_JOINED_THE_GROUP_VIA_GROUP_INVITE_LINK",
                comment: "Message indicating that the local user has joined the group."
            ).attributed
        case let .otherUserJoinedViaInviteLink(userName, userAddress):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_REMOTE_USER_JOINED_THE_GROUP_VIA_GROUP_INVITE_LINK_FORMAT",
                    comment: "Message indicating that another user has joined the group. Embeds {{remote user name}}."
                ),
                groupUpdateFormatArgs: [.name(userName, userAddress)]
            )
        case let .sequenceOfInviteLinkRequestAndCancels(userName, userAddress, count, _):
            return NSAttributedString.make(
                fromFormat: OWSLocalizedString(
                    "GROUP_REMOTE_USER_REQUESTED_TO_JOIN_THE_GROUP_AND_CANCELED_%d",
                    tableName: "PluralAware",
                    comment: "Message indicating that a remote user requested to join the group and then canceled, some number of times. Embeds {{ %1$@ the number of times, %2$@ the requesting user's name }}."
                ),
                groupUpdateFormatArgs: [
                    .raw(count),
                    .name(userName, userAddress)
                ]
            )
        }
    }
}

// MARK: - NSAttributedString

extension DisplayableGroupUpdateItem {
    enum FormatArg {
        case raw(_ value: CVarArg)
        case durationMs(_ value: UInt64)
        case name(_ string: String, _ address: SignalServiceAddress)

        var asAttributedFormatArg: AttributedFormatArg {
            switch self {
            case let .raw(value):
                return .raw(value)
            case let .durationMs(value):
                return .raw(String.formatDurationLossless(durationMs: value))
            case let .name(value, address):
                return .string(value, attributes: [.addressOfName: address])
            }
        }
    }
}

public extension NSAttributedString.Key {
    /// An attribute keying to the `SignalServiceAddress` of a user whose name
    /// is being displayed in the associated range in the string.
    static let addressOfName = NSAttributedString.Key(rawValue: "org.whispersystems.signal.addressOfName")
}

/// Note that this extension is used in tests as well as this file.
extension NSAttributedString {
    static func make(
        fromFormat format: String,
        groupUpdateFormatArgs: [DisplayableGroupUpdateItem.FormatArg]
    ) -> NSAttributedString {
        make(
            fromFormat: format,
            attributedFormatArgs: groupUpdateFormatArgs.map { $0.asAttributedFormatArg }
        )
    }
}

public extension NSAttributedString {
    func enumerateAddressesOfNames(
        in range: NSRange? = nil,
        handler: (SignalServiceAddress?, NSRange, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {
        enumerateAttribute(
            .addressOfName,
            in: range ?? entireRange,
            options: []
        ) { handler($0 as? SignalServiceAddress, $1, $2) }
    }
}

// MARK: -

private extension GroupV2Access {
    var descriptionForCopy: String {
        switch self {
        case .unknown:
            owsFailDebug("Unknown access level!")

            return OWSLocalizedString(
                "GROUP_ACCESS_LEVEL_UNKNOWN",
                comment: "Description of the 'unknown' access level."
            )
        case .any:
            return OWSLocalizedString(
                "GROUP_ACCESS_LEVEL_ANY",
                comment: "Description of the 'all users' access level."
            )
        case .member:
            return OWSLocalizedString(
                "GROUP_ACCESS_LEVEL_MEMBER",
                comment: "Description of the 'all members' access level."
            )
        case .administrator:
            return OWSLocalizedString(
                "GROUP_ACCESS_LEVEL_ADMINISTRATORS",
                comment: "Description of the 'admins only' access level."
            )
        case .unsatisfiable:
            return OWSLocalizedString(
                "GROUP_ACCESS_LEVEL_UNSATISFIABLE",
                comment: "Description of the 'unsatisfiable' access level."
            )
        }
    }
}

private extension String {
    var attributed: NSAttributedString {
        NSAttributedString(string: self)
    }
}
