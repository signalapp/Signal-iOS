//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

extension TSInfoMessage.PersistableGroupUpdateItem {

    /// When rendering a notification for a group upate, if the update has a specific
    /// "sender", we render the notification UI as if sent from that sender.
    public var senderForNotification: SignalServiceAddress? {
        let serviceId: ServiceId? = {
            switch self {
            case .sequenceOfInviteLinkRequestAndCancels(let requester, _, _):
                return requester.wrappedValue
            case .invitedPniPromotedToFullMemberAci(let newMember, _):
                return newMember.wrappedValue
            case .localUserDeclinedInviteFromInviter:
                return nil
            case .localUserDeclinedInviteFromUnknownUser:
                return nil
            case .otherUserDeclinedInviteFromLocalUser(let invitee):
                return invitee.wrappedValue
            case .otherUserDeclinedInviteFromInviter(let invitee, _):
                return invitee.wrappedValue
            case .otherUserDeclinedInviteFromUnknownUser(let invitee):
                return invitee.wrappedValue
            case .localUserInviteRevoked(let revokerAci):
                return revokerAci.wrappedValue
            case .localUserInviteRevokedByUnknownUser:
                return nil
            case .otherUserInviteRevokedByLocalUser:
                return nil
            case .unnamedUserInvitesWereRevokedByLocalUser:
                return nil
            case .unnamedUserInvitesWereRevokedByOtherUser(let updaterAci, _):
                return updaterAci.wrappedValue
            case .unnamedUserInvitesWereRevokedByUnknownUser:
                return nil
            case .unnamedUserDeclinedInviteFromInviter:
                return nil
            case .unnamedUserDeclinedInviteFromUnknownUser:
                return nil
            case .genericUpdateByLocalUser:
                return nil
            case .genericUpdateByOtherUser(let aci):
                return aci.wrappedValue
            case .genericUpdateByUnknownUser:
                return nil
            case .createdByLocalUser:
                return nil
            case .createdByOtherUser(let updaterAci):
                return updaterAci.wrappedValue
            case .createdByUnknownUser:
                return nil
            case .inviteFriendsToNewlyCreatedGroup:
                return nil
            case .wasMigrated:
                return nil
            case .localUserInvitedAfterMigration:
                return nil
            case .otherUsersInvitedAfterMigration:
                return nil
            case .otherUsersDroppedAfterMigration:
                return nil
            case .nameChangedByLocalUser:
                return nil
            case .nameChangedByOtherUser(let updaterAci, _):
                return updaterAci.wrappedValue
            case .nameChangedByUnknownUser:
                return nil
            case .nameRemovedByLocalUser:
                return nil
            case .nameRemovedByOtherUser(let updaterAci):
                return updaterAci.wrappedValue
            case .nameRemovedByUnknownUser:
                return nil
            case .avatarChangedByLocalUser:
                return nil
            case .avatarChangedByOtherUser(let updaterAci):
                return updaterAci.wrappedValue
            case .avatarChangedByUnknownUser:
                return nil
            case .avatarRemovedByLocalUser:
                return nil
            case .avatarRemovedByOtherUser(let updaterAci):
                return updaterAci.wrappedValue
            case .avatarRemovedByUnknownUser:
                return nil
            case .descriptionChangedByLocalUser:
                return nil
            case .descriptionChangedByOtherUser(let updaterAci, _):
                return updaterAci.wrappedValue
            case .descriptionChangedByUnknownUser:
                return nil
            case .descriptionRemovedByLocalUser:
                return nil
            case .descriptionRemovedByOtherUser(let updaterAci):
                return updaterAci.wrappedValue
            case .descriptionRemovedByUnknownUser:
                return nil
            case .membersAccessChangedByLocalUser:
                return nil
            case .membersAccessChangedByOtherUser(let updaterAci, _):
                return updaterAci.wrappedValue
            case .membersAccessChangedByUnknownUser:
                return nil
            case .attributesAccessChangedByLocalUser:
                return nil
            case .attributesAccessChangedByOtherUser(let updaterAci, _):
                return updaterAci.wrappedValue
            case .attributesAccessChangedByUnknownUser:
                return nil
            case .announcementOnlyEnabledByLocalUser:
                return nil
            case .announcementOnlyEnabledByOtherUser(let updaterAci):
                return updaterAci.wrappedValue
            case .announcementOnlyEnabledByUnknownUser:
                return nil
            case .announcementOnlyDisabledByLocalUser:
                return nil
            case .announcementOnlyDisabledByOtherUser(let updaterAci):
                return updaterAci.wrappedValue
            case .announcementOnlyDisabledByUnknownUser:
                return nil
            case .localUserWasGrantedAdministratorByLocalUser:
                return nil
            case .localUserWasGrantedAdministratorByOtherUser(let updaterAci):
                return updaterAci.wrappedValue
            case .localUserWasGrantedAdministratorByUnknownUser:
                return nil
            case .otherUserWasGrantedAdministratorByLocalUser:
                return nil
            case .otherUserWasGrantedAdministratorByOtherUser(let updaterAci, _):
                return updaterAci.wrappedValue
            case .otherUserWasGrantedAdministratorByUnknownUser:
                return nil
            case .localUserWasRevokedAdministratorByLocalUser:
                return nil
            case .localUserWasRevokedAdministratorByOtherUser(let updaterAci):
                return updaterAci.wrappedValue
            case .localUserWasRevokedAdministratorByUnknownUser:
                return nil
            case .otherUserWasRevokedAdministratorByLocalUser:
                return nil
            case .otherUserWasRevokedAdministratorByOtherUser(let updaterAci, _):
                return updaterAci.wrappedValue
            case .otherUserWasRevokedAdministratorByUnknownUser:
                return nil
            case .localUserLeft:
                return nil
            case .localUserRemoved(removerAci: let removerAci):
                return removerAci.wrappedValue
            case .localUserRemovedByUnknownUser:
                return nil
            case .otherUserLeft(let userAci):
                return userAci.wrappedValue
            case .otherUserRemovedByLocalUser:
                return nil
            case .otherUserRemoved(removerAci: let removerAci, _):
                return removerAci.wrappedValue
            case .otherUserRemovedByUnknownUser:
                return nil
            case .localUserWasInvitedByLocalUser:
                return nil
            case .localUserWasInvitedByOtherUser(let updaterAci):
                return updaterAci.wrappedValue
            case .localUserWasInvitedByUnknownUser:
                return nil
            case .otherUserWasInvitedByLocalUser:
                return nil
            case .unnamedUsersWereInvitedByLocalUser:
                return nil
            case .unnamedUsersWereInvitedByOtherUser(let updaterAci, _):
                return updaterAci.wrappedValue
            case .unnamedUsersWereInvitedByUnknownUser:
                return nil
            case .localUserAcceptedInviteFromInviter:
                return nil
            case .localUserAcceptedInviteFromUnknownUser:
                return nil
            case .otherUserAcceptedInviteFromLocalUser(let userAci):
                return userAci.wrappedValue
            case .otherUserAcceptedInviteFromInviter(let userAci, _):
                return userAci.wrappedValue
            case .otherUserAcceptedInviteFromUnknownUser(let userAci):
                return userAci.wrappedValue
            case .localUserJoined:
                return nil
            case .otherUserJoined(let userAci):
                return userAci.wrappedValue
            case .localUserAddedByLocalUser:
                return nil
            case .localUserAddedByOtherUser(let updaterAci):
                return updaterAci.wrappedValue
            case .localUserAddedByUnknownUser:
                return nil
            case .otherUserAddedByLocalUser:
                return nil
            case .otherUserAddedByOtherUser(let updaterAci, _):
                return updaterAci.wrappedValue
            case .otherUserAddedByUnknownUser:
                return nil
            case .localUserRequestedToJoin:
                return nil
            case .otherUserRequestedToJoin(let userAci):
                return userAci.wrappedValue
            case .localUserRequestApproved(approverAci: let approverAci):
                return approverAci.wrappedValue
            case .localUserRequestApprovedByUnknownUser:
                return nil
            case .otherUserRequestApprovedByLocalUser:
                return nil
            case .otherUserRequestApproved(_, let approverAci):
                return approverAci.wrappedValue
            case .otherUserRequestApprovedByUnknownUser:
                return nil
            case .localUserRequestCanceledByLocalUser:
                return nil
            case .localUserRequestRejectedByUnknownUser:
                return nil
            case .otherUserRequestRejectedByLocalUser:
                return nil
            case .otherUserRequestRejectedByOtherUser(let updaterAci, _):
                return updaterAci.wrappedValue
            case .otherUserRequestCanceledByOtherUser(requesterAci: let requesterAci):
                return requesterAci.wrappedValue
            case .otherUserRequestRejectedByUnknownUser:
                return nil
            case .disappearingMessagesEnabledByLocalUser:
                return nil
            case .disappearingMessagesEnabledByOtherUser(let updaterAci, _):
                return updaterAci.wrappedValue
            case .disappearingMessagesEnabledByUnknownUser:
                return nil
            case .disappearingMessagesDisabledByLocalUser:
                return nil
            case .disappearingMessagesDisabledByOtherUser(let updaterAci):
                return updaterAci.wrappedValue
            case .disappearingMessagesDisabledByUnknownUser:
                return nil
            case .inviteLinkResetByLocalUser:
                return nil
            case .inviteLinkResetByOtherUser(let updaterAci):
                return updaterAci.wrappedValue
            case .inviteLinkResetByUnknownUser:
                return nil
            case .inviteLinkEnabledWithoutApprovalByLocalUser:
                return nil
            case .inviteLinkEnabledWithoutApprovalByOtherUser(let updaterAci):
                return updaterAci.wrappedValue
            case .inviteLinkEnabledWithoutApprovalByUnknownUser:
                return nil
            case .inviteLinkEnabledWithApprovalByLocalUser:
                return nil
            case .inviteLinkEnabledWithApprovalByOtherUser(let updaterAci):
                return updaterAci.wrappedValue
            case .inviteLinkEnabledWithApprovalByUnknownUser:
                return nil
            case .inviteLinkDisabledByLocalUser:
                return nil
            case .inviteLinkDisabledByOtherUser(let updaterAci):
                return updaterAci.wrappedValue
            case .inviteLinkDisabledByUnknownUser:
                return nil
            case .inviteLinkApprovalDisabledByLocalUser:
                return nil
            case .inviteLinkApprovalDisabledByOtherUser(let updaterAci):
                return updaterAci.wrappedValue
            case .inviteLinkApprovalDisabledByUnknownUser:
                return nil
            case .inviteLinkApprovalEnabledByLocalUser:
                return nil
            case .inviteLinkApprovalEnabledByOtherUser(let updaterAci):
                return updaterAci.wrappedValue
            case .inviteLinkApprovalEnabledByUnknownUser:
                return nil
            case .localUserJoinedViaInviteLink:
                return nil
            case .otherUserJoinedViaInviteLink(let userAci):
                return userAci.wrappedValue
            }
        }()

        return serviceId.map { SignalServiceAddress($0) }
    }
}
