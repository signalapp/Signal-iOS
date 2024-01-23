//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

internal final class MessageBackupGroupUpdateProtoToSwiftConverter {

    private init() {}

    typealias PersistableGroupUpdateItem = TSInfoMessage.PersistableGroupUpdateItem

    internal static func restoreGroupUpdates(
        groupUpdates: [BackupProtoGroupChangeChatUpdateUpdate],
        // We should never be comparing our pni as it can change,
        // we only ever want to compare our unchanging aci.
        localUserAci: Aci,
        partialErrors: inout [MessageBackup.RestoreFrameError<MessageBackup.ChatItemId>],
        chatItemId: MessageBackup.ChatItemId
    ) -> MessageBackup.RestoreInteractionResult<[PersistableGroupUpdateItem]> {
        var persistableUpdates = [PersistableGroupUpdateItem]()
        for updateProto in groupUpdates {
            let result = Self.restoreGroupUpdate(
                groupUpdate: updateProto,
                localUserAci: localUserAci,
                chatItemId: chatItemId
            )
            if let persistableItems = result.unwrap(partialErrors: &partialErrors) {
                persistableUpdates.append(contentsOf: persistableItems)
            } else {
                return .messageFailure(partialErrors)
            }
        }
        return .success(persistableUpdates)
    }

    private static func restoreGroupUpdate(
        groupUpdate: BackupProtoGroupChangeChatUpdateUpdate,
        localUserAci: Aci,
        chatItemId: MessageBackup.ChatItemId
    ) -> MessageBackup.RestoreInteractionResult<[PersistableGroupUpdateItem]> {
        enum UnwrappedAci {
            case localUser
            case otherUser(AciUuid)
            case invalidAci(MessageBackup.RestoreFrameError<MessageBackup.ChatItemId>)
        }
        enum UnwrappedOptionalAci {
            case unknown
            case localUser
            case otherUser(AciUuid)
            case invalidAci(MessageBackup.RestoreFrameError<MessageBackup.ChatItemId>)
        }

        func unwrapAci<Proto>(
            _ proto: Proto,
            _ aciKeyPath: KeyPath<Proto, Data>
        ) -> UnwrappedAci {
            let aciData = proto[keyPath: aciKeyPath]
            guard let aciUuid = UUID(data: aciData) else {
                return .invalidAci(
                    .invalidProtoData(
                        chatItemId,
                        .invalidAci(protoClass: Proto.self)
                    )
                )
            }
            let aci = Aci(fromUUID: aciUuid)
            if aci == localUserAci {
                return .localUser
            } else {
                return .otherUser(aci.codableUuid)
            }
        }
        func unwrapAci<Proto>(
            _ proto: Proto,
            _ aciKeyPath: KeyPath<Proto, Data?>
        ) -> UnwrappedOptionalAci {
            guard let aciData = proto[keyPath: aciKeyPath] else {
                return .unknown
            }
            guard let aciUuid = UUID(data: aciData) else {
                return .invalidAci(
                    .invalidProtoData(
                        chatItemId,
                        .invalidAci(protoClass: Proto.self)
                    )
                )
            }
            let aci = Aci(fromUUID: aciUuid)
            if aci == localUserAci {
                return .localUser
            } else {
                return .otherUser(aci.codableUuid)
            }
        }

        switch groupUpdate.updateType {
        case .none:
            return .messageFailure([.invalidProtoData(chatItemId, .unrecognizedGroupUpdate)])
        case .genericGroupUpdate(let proto):
            switch unwrapAci(proto, \.updaterAci) {
            case .unknown:
                return .success([.genericUpdateByUnknownUser])
            case .localUser:
                return .success([.genericUpdateByLocalUser])
            case .otherUser(let aci):
                return .success([.genericUpdateByOtherUser(updaterAci: aci)])
            case .invalidAci(let error):
                return .messageFailure([error])
            }
        case .groupCreationUpdate(let proto):
            switch unwrapAci(proto, \.updaterAci) {
            case .unknown:
                return .success([.genericUpdateByUnknownUser])
            case .localUser:
                // When we see a `createdByLocalUser`, also include a
                // `inviteFriendsToNewlyCreatedGroup`.
                return .success([.genericUpdateByLocalUser, .inviteFriendsToNewlyCreatedGroup])
            case .otherUser(let aci):
                return .success([.genericUpdateByOtherUser(updaterAci: aci)])
            case .invalidAci(let error):
                return .messageFailure([error])
            }
        case .groupNameUpdate(let proto):
            if let newName = proto.newGroupName {
                switch unwrapAci(proto, \.updaterAci) {
                case .unknown:
                    return .success([.nameChangedByUnknownUser(newGroupName: newName)])
                case .localUser:
                    return .success([.nameChangedByLocalUser(newGroupName: newName)])
                case .otherUser(let aci):
                    return .success([.nameChangedByOtherUser(updaterAci: aci, newGroupName: newName)])
                case .invalidAci(let error):
                    return .messageFailure([error])
                }
            } else {
                switch unwrapAci(proto, \.updaterAci) {
                case .unknown:
                    return .success([.nameRemovedByUnknownUser])
                case .localUser:
                    return .success([.nameRemovedByLocalUser])
                case .otherUser(let aci):
                    return .success([.nameRemovedByOtherUser(updaterAci: aci)])
                case .invalidAci(let error):
                    return .messageFailure([error])
                }
            }
        case .groupAvatarUpdate(let proto):
            if proto.wasRemoved {
                switch unwrapAci(proto, \.updaterAci) {
                case .unknown:
                    return .success([.avatarRemovedByUnknownUser])
                case .localUser:
                    return .success([.avatarRemovedByLocalUser])
                case .otherUser(let aci):
                    return .success([.avatarRemovedByOtherUser(updaterAci: aci)])
                case .invalidAci(let error):
                    return .messageFailure([error])
                }
            } else {
                switch unwrapAci(proto, \.updaterAci) {
                case .unknown:
                    return .success([.avatarChangedByUnknownUser])
                case .localUser:
                    return .success([.avatarChangedByLocalUser])
                case .otherUser(let aci):
                    return .success([.avatarChangedByOtherUser(updaterAci: aci)])
                case .invalidAci(let error):
                    return .messageFailure([error])
                }
            }
        case .groupDescriptionUpdate(let proto):
            if let newDescription = proto.newDescription {
                switch unwrapAci(proto, \.updaterAci) {
                case .unknown:
                    return .success([.descriptionChangedByUnknownUser(newDescription: newDescription)])
                case .localUser:
                    return .success([.descriptionChangedByLocalUser(newDescription: newDescription)])
                case .otherUser(let aci):
                    return .success([.descriptionChangedByOtherUser(updaterAci: aci, newDescription: newDescription)])
                case .invalidAci(let error):
                    return .messageFailure([error])
                }
            } else {
                switch unwrapAci(proto, \.updaterAci) {
                case .unknown:
                    return .success([.descriptionRemovedByUnknownUser])
                case .localUser:
                    return .success([.descriptionRemovedByLocalUser])
                case .otherUser(let aci):
                    return .success([.descriptionRemovedByOtherUser(updaterAci: aci)])
                case .invalidAci(let error):
                    return .messageFailure([error])
                }
            }
        case .groupMembershipAccessLevelChangeUpdate(let proto):
            let newAccess = proto.accessLevel.swiftAccessLevel
            switch unwrapAci(proto, \.updaterAci) {
            case .unknown:
                return .success([.membersAccessChangedByUnknownUser(newAccess: newAccess)])
            case .localUser:
                return .success([.membersAccessChangedByLocalUser(newAccess: newAccess)])
            case .otherUser(let aci):
                return .success([.membersAccessChangedByOtherUser(updaterAci: aci, newAccess: newAccess)])
            case .invalidAci(let error):
                return .messageFailure([error])
            }
        case .groupAttributesAccessLevelChangeUpdate(let proto):
            let newAccess = proto.accessLevel.swiftAccessLevel
            switch unwrapAci(proto, \.updaterAci) {
            case .unknown:
                return .success([.attributesAccessChangedByUnknownUser(newAccess: newAccess)])
            case .localUser:
                return .success([.attributesAccessChangedByLocalUser(newAccess: newAccess)])
            case .otherUser(let aci):
                return .success([.attributesAccessChangedByOtherUser(updaterAci: aci, newAccess: newAccess)])
            case .invalidAci(let error):
                return .messageFailure([error])
            }
        case .groupAnnouncementOnlyChangeUpdate(let proto):
            if proto.isAnnouncementOnly {
                switch unwrapAci(proto, \.updaterAci) {
                case .unknown:
                    return .success([.announcementOnlyEnabledByUnknownUser])
                case .localUser:
                    return .success([.announcementOnlyEnabledByLocalUser])
                case .otherUser(let aci):
                    return .success([.announcementOnlyEnabledByOtherUser(updaterAci: aci)])
                case .invalidAci(let error):
                    return .messageFailure([error])
                }
            } else {
                switch unwrapAci(proto, \.updaterAci) {
                case .unknown:
                    return .success([.announcementOnlyDisabledByUnknownUser])
                case .localUser:
                    return .success([.announcementOnlyDisabledByLocalUser])
                case .otherUser(let aci):
                    return .success([.announcementOnlyDisabledByOtherUser(updaterAci: aci)])
                case .invalidAci(let error):
                    return .messageFailure([error])
                }
            }
        case .groupAdminStatusUpdate(let proto):
            let updaterAci = unwrapAci(proto, \.updaterAci)
            let memberAci = unwrapAci(proto, \.memberAci)
            if proto.wasAdminStatusGranted {
                switch (updaterAci, memberAci) {
                case (.unknown, .localUser):
                    return .success([.localUserWasGrantedAdministratorByUnknownUser])
                case (.localUser, .localUser):
                    return .success([.localUserWasGrantedAdministratorByLocalUser])
                case (.otherUser(let aci), .localUser):
                    return .success([.localUserWasGrantedAdministratorByOtherUser(updaterAci: aci)])
                case (.localUser, .otherUser(let aci)):
                    return .success([.otherUserWasGrantedAdministratorByLocalUser(userAci: aci)])
                case (.otherUser(let updaterAci), .otherUser(let memberAci)):
                    return .success([.otherUserWasGrantedAdministratorByOtherUser(updaterAci: updaterAci, userAci: memberAci)])
                case (.unknown, .otherUser(let aci)):
                    return .success([.otherUserWasGrantedAdministratorByUnknownUser(userAci: aci)])
                case (.invalidAci(let error), _), (_, .invalidAci(let error)):
                    return .messageFailure([error])
                }
            } else {
                switch (updaterAci, memberAci) {
                case (.unknown, .localUser):
                    return .success([.localUserWasRevokedAdministratorByLocalUser])
                case (.localUser, .localUser):
                    return .success([.localUserWasRevokedAdministratorByLocalUser])
                case (.otherUser(let aci), .localUser):
                    return .success([.localUserWasRevokedAdministratorByOtherUser(updaterAci: aci)])
                case (.localUser, .otherUser(let aci)):
                    return .success([.otherUserWasRevokedAdministratorByLocalUser(userAci: aci)])
                case (.otherUser(let updaterAci), .otherUser(let memberAci)):
                    return .success([.otherUserWasRevokedAdministratorByOtherUser(updaterAci: updaterAci, userAci: memberAci)])
                case (.unknown, .otherUser(let aci)):
                    return .success([.otherUserWasRevokedAdministratorByUnknownUser(userAci: aci)])
                case (.invalidAci(let error), _), (_, .invalidAci(let error)):
                    return .messageFailure([error])
                }
            }
        case .groupMemberLeftUpdate(let proto):
            switch unwrapAci(proto, \.aci) {
            case .localUser:
                return .success([.localUserLeft])
            case .otherUser(let aci):
                return .success([.otherUserLeft(userAci: aci)])
            case .invalidAci(let error):
                return .messageFailure([error])
            }
        case .groupMemberRemovedUpdate(let proto):
            switch (unwrapAci(proto, \.removerAci), unwrapAci(proto, \.removedAci)) {
            case (.unknown, .localUser):
                return .success([.localUserRemovedByUnknownUser])
            case (.localUser, .localUser):
                return .success([.localUserLeft])
            case (.otherUser(let removerAci), .localUser):
                return .success([.localUserRemoved(removerAci: removerAci)])
            case (.unknown, .otherUser(let removedAci)):
                return .success([.otherUserRemovedByUnknownUser(userAci: removedAci)])
            case (.localUser, .otherUser(let removedAci)):
                return .success([.otherUserRemovedByLocalUser(userAci: removedAci)])
            case (.otherUser(let removerAci), .otherUser(let removedAci)):
                return .success([.otherUserRemoved(removerAci: removerAci, userAci: removedAci)])
            case (_, .invalidAci(let error)), (.invalidAci(let error), _):
                return .messageFailure([error])
            }
        case .selfInvitedToGroupUpdate(let proto):
            switch unwrapAci(proto, \.inviterAci) {
            case .unknown:
                return .success([.localUserWasInvitedByUnknownUser])
            case .localUser:
                return .success([.localUserWasInvitedByLocalUser])
            case .otherUser(let aci):
                return .success([.localUserWasInvitedByOtherUser(updaterAci: aci)])
            case .invalidAci(let error):
                return .messageFailure([error])
            }
        case .selfInvitedOtherUserToGroupUpdate(let proto):
            switch (try? ServiceId.parseFrom(serviceIdBinary: proto.inviteeServiceID)) {
            case .some(let serviceId):
                return .success([.otherUserWasInvitedByLocalUser(inviteeServiceId: serviceId.codableUppercaseString)])
            case .none:
                return .messageFailure([.invalidProtoData(
                    chatItemId,
                    .invalidServiceId(
                        protoClass: BackupProtoSelfInvitedOtherUserToGroupUpdate.self
                    )
                )])
            }
        case .groupUnknownInviteeUpdate(let proto):
            let count = UInt(proto.inviteeCount)
            switch unwrapAci(proto, \.inviterAci) {
            case .unknown:
                return .success([.unnamedUsersWereInvitedByUnknownUser(count: count)])
            case .localUser:
                return .success([.unnamedUsersWereInvitedByLocalUser(count: count)])
            case .otherUser(let aci):
                return .success([.unnamedUsersWereInvitedByOtherUser(updaterAci: aci, count: count)])
            case .invalidAci(let error):
                return .messageFailure([error])
            }
        case .groupInvitationAcceptedUpdate(let proto):
            switch (unwrapAci(proto, \.inviterAci), unwrapAci(proto, \.newMemberAci)) {
            case (.unknown, .localUser):
                return .success([.localUserAcceptedInviteFromUnknownUser])
            case (.localUser, .localUser):
                return .success([.localUserJoined])
            case (.otherUser(let inviterAci), .localUser):
                return .success([.localUserAcceptedInviteFromInviter(inviterAci: inviterAci)])
            case (.unknown, .otherUser(let aci)):
                return .success([.otherUserAcceptedInviteFromUnknownUser(userAci: aci)])
            case (.localUser, .otherUser(let aci)):
                return .success([.otherUserAcceptedInviteFromLocalUser(userAci: aci)])
            case (.otherUser(let inviterAci), .otherUser(let aci)):
                return .success([.otherUserAcceptedInviteFromInviter(userAci: aci, inviterAci: inviterAci)])
            case (.invalidAci(let error), _), (_, .invalidAci(let error)):
                return .messageFailure([error])
            }
        case .groupInvitationDeclinedUpdate(let proto):
            switch (unwrapAci(proto, \.inviterAci), unwrapAci(proto, \.inviteeAci)) {
            case (.unknown, .localUser):
                return .success([.localUserDeclinedInviteFromUnknownUser])
            case (.localUser, .localUser):
                return .success([.localUserDeclinedInviteFromUnknownUser])
            case (.otherUser(let inviterAci), .localUser):
                return .success([.localUserDeclinedInviteFromInviter(inviterAci: inviterAci)])
            case (.unknown, .otherUser(let aci)):
                return .success([.otherUserDeclinedInviteFromUnknownUser(invitee: aci.wrappedValue.codableUppercaseString)])
            case (.localUser, .otherUser(let aci)):
                return .success([.otherUserDeclinedInviteFromLocalUser(invitee: aci.wrappedValue.codableUppercaseString)])
            case (.otherUser(let inviterAci), .otherUser(let aci)):
                return .success([.otherUserDeclinedInviteFromInviter(invitee: aci.wrappedValue.codableUppercaseString, inviterAci: inviterAci)])
            case (.unknown, .unknown):
                return .success([.unnamedUserDeclinedInviteFromUnknownUser])
            case (.localUser, .unknown):
                return .success([.unnamedUserDeclinedInviteFromUnknownUser])
            case (.otherUser(let inviterAci), .unknown):
                return .success([.unnamedUserDeclinedInviteFromInviter(inviterAci: inviterAci)])
            case (.invalidAci(let error), _), (_, .invalidAci(let error)):
                return .messageFailure([error])
            }
        case .groupMemberJoinedUpdate(let proto):
            switch unwrapAci(proto, \.newMemberAci) {
            case .localUser:
                return .success([.localUserJoined])
            case .otherUser(let aci):
                return .success([.otherUserJoined(userAci: aci)])
            case .invalidAci(let error):
                return .messageFailure([error])
            }
        case .groupMemberAddedUpdate(let proto):
            switch (unwrapAci(proto, \.inviterAci), unwrapAci(proto, \.newMemberAci)) {
            case (.unknown, .localUser):
                return .success([.localUserAddedByUnknownUser])
            case (.localUser, .localUser):
                return .success([.localUserAddedByLocalUser])
            case (.otherUser(let updaterAci), .localUser):
                return .success([.localUserAddedByOtherUser(updaterAci: updaterAci)])
            case (.unknown, .otherUser(let aci)):
                return .success([.otherUserAddedByUnknownUser(userAci: aci)])
            case (.localUser, .otherUser(let aci)):
                return .success([.otherUserAddedByLocalUser(userAci: aci)])
            case (.otherUser(let updaterAci), .otherUser(let aci)):
                return .success([.otherUserAddedByOtherUser(updaterAci: updaterAci, userAci: aci)])
            case (.invalidAci(let error), _), (_, .invalidAci(let error)):
                return .messageFailure([error])
            }
        case .groupSelfInvitationRevokedUpdate(let proto):
            switch unwrapAci(proto, \.revokerAci) {
            case .unknown:
                return .success([.localUserInviteRevokedByUnknownUser])
            case .localUser:
                return .success([.localUserDeclinedInviteFromUnknownUser])
            case .otherUser(let aci):
                return .success([.localUserInviteRevoked(revokerAci: aci)])
            case .invalidAci(let error):
                return .messageFailure([error])
            }
        case .groupInvitationRevokedUpdate(let proto):
            let updaterAci = unwrapAci(proto, \.updaterAci)
            if
                case .localUser = updaterAci,
                proto.invitees.count == 1,
                let inviteeServiceId: ServiceId = {
                    let invitee = proto.invitees[0]
                    if
                        let aciRaw = invitee.inviteeAci,
                        let aciUuid = UUID(data: aciRaw)
                    {
                        return Aci(fromUUID: aciUuid)
                    } else if
                        let pniRaw = invitee.inviteePni,
                        let pniUuid = UUID(data: pniRaw)
                    {
                        return Pni(fromUUID: pniUuid)
                    } else {
                        return nil
                    }
                }()
            {
                return .success([.otherUserInviteRevokedByLocalUser(
                    invitee: inviteeServiceId.codableUppercaseString
                )])
            } else {
                let count = UInt(proto.invitees.count)
                switch updaterAci {
                case .unknown:
                    return .success([.unnamedUserInvitesWereRevokedByUnknownUser(count: count)])
                case .localUser:
                    return .success([.unnamedUserInvitesWereRevokedByLocalUser(count: count)])
                case .otherUser(let aci):
                    return .success([.unnamedUserInvitesWereRevokedByOtherUser(updaterAci: aci, count: count)])
                case .invalidAci(let error):
                    return .messageFailure([error])
                }
            }
        case .groupJoinRequestUpdate(let proto):
            switch unwrapAci(proto, \.requestorAci) {
            case .localUser:
                return .success([.localUserRequestedToJoin])
            case .otherUser(let aci):
                return .success([.otherUserRequestedToJoin(userAci: aci)])
            case .invalidAci(let error):
                return .messageFailure([error])
            }
        case .groupJoinRequestApprovalUpdate(let proto):
            if proto.wasApproved {
                switch (unwrapAci(proto, \.requestorAci), unwrapAci(proto, \.updaterAci)) {
                case (.localUser, .unknown):
                    return .success([.localUserRequestApprovedByUnknownUser])
                case (.localUser, .localUser):
                    return .success([.localUserJoined])
                case (.localUser, .otherUser(let updaterAci)):
                    return .success([.localUserRequestApproved(approverAci: updaterAci)])
                case (.otherUser(let aci), .unknown):
                    return .success([.otherUserRequestApprovedByUnknownUser(userAci: aci)])
                case (.otherUser(let aci), .localUser):
                    return .success([.otherUserRequestApprovedByLocalUser(userAci: aci)])
                case (.otherUser(let aci), .otherUser(let approverAci)):
                    return .success([.otherUserRequestApproved(userAci: aci, approverAci: approverAci)])
                case (.invalidAci(let error), _), (_, .invalidAci(let error)):
                    return .messageFailure([error])
                }
            } else {
                switch (unwrapAci(proto, \.requestorAci), unwrapAci(proto, \.updaterAci)) {
                case (.localUser, .unknown):
                    return .success([.localUserRequestRejectedByUnknownUser])
                case (.localUser, .localUser):
                    return .success([.localUserRequestCanceledByLocalUser])
                case (.localUser, .otherUser(_)):
                    // We don't keep the rejector's information
                    return .success([.localUserRequestRejectedByUnknownUser])
                case (.otherUser(let aci), .unknown):
                    return .success([.otherUserRequestRejectedByUnknownUser(requesterAci: aci)])
                case (.otherUser(let aci), .localUser):
                    return .success([.otherUserRequestRejectedByLocalUser(requesterAci: aci)])
                case (.otherUser(let aci), .otherUser(let rejectorAci)):
                    return .success([.otherUserRequestRejectedByOtherUser(updaterAci: rejectorAci, requesterAci: aci)])
                case (.invalidAci(let error), _), (_, .invalidAci(let error)):
                    return .messageFailure([error])
                }
            }
        case .groupJoinRequestCanceledUpdate(let proto):
            switch unwrapAci(proto, \.requestorAci) {
            case .localUser:
                return .success([.localUserRequestCanceledByLocalUser])
            case .otherUser(let aci):
                return .success([.otherUserRequestCanceledByOtherUser(requesterAci: aci)])
            case .invalidAci(let error):
                return .messageFailure([error])
            }
        case .groupInviteLinkResetUpdate(let proto):
            switch unwrapAci(proto, \.updaterAci) {
            case .unknown:
                return .success([.inviteLinkResetByUnknownUser])
            case .localUser:
                return .success([.inviteLinkResetByLocalUser])
            case .otherUser(let aci):
                return .success([.inviteLinkResetByOtherUser(updaterAci: aci)])
            case .invalidAci(let error):
                return .messageFailure([error])
            }
        case .groupInviteLinkEnabledUpdate(let proto):
            if proto.linkRequiresAdminApproval {
                switch unwrapAci(proto, \.updaterAci) {
                case .unknown:
                    return .success([.inviteLinkEnabledWithApprovalByUnknownUser])
                case .localUser:
                    return .success([.inviteLinkEnabledWithApprovalByLocalUser])
                case .otherUser(let aci):
                    return .success([.inviteLinkEnabledWithApprovalByOtherUser(updaterAci: aci)])
                case .invalidAci(let error):
                    return .messageFailure([error])
                }
            } else {
                switch unwrapAci(proto, \.updaterAci) {
                case .unknown:
                    return .success([.inviteLinkEnabledWithoutApprovalByUnknownUser])
                case .localUser:
                    return .success([.inviteLinkEnabledWithoutApprovalByLocalUser])
                case .otherUser(let aci):
                    return .success([.inviteLinkEnabledWithoutApprovalByOtherUser(updaterAci: aci)])
                case .invalidAci(let error):
                    return .messageFailure([error])
                }
            }
        case .groupInviteLinkAdminApprovalUpdate(let proto):
            if proto.linkRequiresAdminApproval {
                switch unwrapAci(proto, \.updaterAci) {
                case .unknown:
                    return .success([.inviteLinkApprovalEnabledByUnknownUser])
                case .localUser:
                    return .success([.inviteLinkApprovalEnabledByLocalUser])
                case .otherUser(let aci):
                    return .success([.inviteLinkApprovalEnabledByOtherUser(updaterAci: aci)])
                case .invalidAci(let error):
                    return .messageFailure([error])
                }
            } else {
                switch unwrapAci(proto, \.updaterAci) {
                case .unknown:
                    return .success([.inviteLinkApprovalDisabledByUnknownUser])
                case .localUser:
                    return .success([.inviteLinkApprovalDisabledByLocalUser])
                case .otherUser(let aci):
                    return .success([.inviteLinkApprovalDisabledByOtherUser(updaterAci: aci)])
                case .invalidAci(let error):
                    return .messageFailure([error])
                }
            }
        case .groupInviteLinkDisabledUpdate(let proto):
            switch unwrapAci(proto, \.updaterAci) {
            case .unknown:
                return .success([.inviteLinkDisabledByUnknownUser])
            case .localUser:
                return .success([.inviteLinkDisabledByLocalUser])
            case .otherUser(let aci):
                return .success([.inviteLinkDisabledByOtherUser(updaterAci: aci)])
            case .invalidAci(let error):
                return .messageFailure([error])
            }
        case .groupMemberJoinedByLinkUpdate(let proto):
            switch unwrapAci(proto, \.newMemberAci) {
            case .localUser:
                return .success([.localUserJoinedViaInviteLink])
            case .otherUser(let aci):
                return .success([.otherUserJoinedViaInviteLink(userAci: aci)])
            case .invalidAci(let error):
                return .messageFailure([error])
            }
        case .groupV2MigrationUpdate(_):
            return .success([.wasMigrated])
        case .groupV2MigrationSelfInvitedUpdate(_):
            return .success([.localUserInvitedAfterMigration])
        case .groupV2MigrationInvitedMembersUpdate(let proto):
            return .success([.otherUsersInvitedAfterMigration(count: UInt(proto.invitedMembersCount))])
        case .groupV2MigrationDroppedMembersUpdate(let proto):
            return .success([.otherUsersDroppedAfterMigration(count: UInt(proto.droppedMembersCount))])
        case .groupSequenceOfRequestsAndCancelsUpdate(let proto):
            switch unwrapAci(proto, \.requestorAci) {
            case .localUser:
                return .messageFailure([
                    .invalidProtoData(chatItemId, .sequenceOfRequestsAndCancelsWithLocalAci)
                ])
            // We assume it is the tail to start out with; if we see a subsequent join request
            // from the same invite then we will mark it as not the tail.
            case .otherUser(let aci):
                return .success([.sequenceOfInviteLinkRequestAndCancels(requester: aci, count: UInt(proto.count), isTail: true)])
            case .invalidAci(let error):
                return .messageFailure([error])
            }
        case .groupExpirationTimerUpdate(let proto):
            let durationMs = UInt64(clamping: proto.expiresInMs)
            if durationMs > 0 {
                switch unwrapAci(proto, \.updaterAci) {
                case .unknown:
                    return .success([.disappearingMessagesEnabledByUnknownUser(durationMs: durationMs)])
                case .localUser:
                    return .success([.disappearingMessagesEnabledByLocalUser(durationMs: durationMs)])
                case .otherUser(let aci):
                    return .success([.disappearingMessagesEnabledByOtherUser(updaterAci: aci, durationMs: durationMs)])
                case .invalidAci(let error):
                    return .messageFailure([error])
                }
            } else {
                switch unwrapAci(proto, \.updaterAci) {
                case .unknown:
                    return .success([.disappearingMessagesDisabledByUnknownUser])
                case .localUser:
                    return .success([.disappearingMessagesDisabledByLocalUser])
                case .otherUser(let aci):
                    return .success([.disappearingMessagesDisabledByOtherUser(updaterAci: aci)])
                case .invalidAci(let error):
                    return .messageFailure([error])
                }
            }
        }
    }
}

extension BackupProtoGroupChangeChatUpdateUpdate {

    fileprivate enum UpdateType {
        case genericGroupUpdate(BackupProtoGenericGroupUpdate)
        case groupCreationUpdate(BackupProtoGroupCreationUpdate)
        case groupNameUpdate(BackupProtoGroupNameUpdate)
        case groupAvatarUpdate(BackupProtoGroupAvatarUpdate)
        case groupDescriptionUpdate(BackupProtoGroupDescriptionUpdate)
        case groupMembershipAccessLevelChangeUpdate(BackupProtoGroupMembershipAccessLevelChangeUpdate)
        case groupAttributesAccessLevelChangeUpdate(BackupProtoGroupAttributesAccessLevelChangeUpdate)
        case groupAnnouncementOnlyChangeUpdate(BackupProtoGroupAnnouncementOnlyChangeUpdate)
        case groupAdminStatusUpdate(BackupProtoGroupAdminStatusUpdate)
        case groupMemberLeftUpdate(BackupProtoGroupMemberLeftUpdate)
        case groupMemberRemovedUpdate(BackupProtoGroupMemberRemovedUpdate)
        case selfInvitedToGroupUpdate(BackupProtoSelfInvitedToGroupUpdate)
        case selfInvitedOtherUserToGroupUpdate(BackupProtoSelfInvitedOtherUserToGroupUpdate)
        case groupUnknownInviteeUpdate(BackupProtoGroupUnknownInviteeUpdate)
        case groupInvitationAcceptedUpdate(BackupProtoGroupInvitationAcceptedUpdate)
        case groupInvitationDeclinedUpdate(BackupProtoGroupInvitationDeclinedUpdate)
        case groupMemberJoinedUpdate(BackupProtoGroupMemberJoinedUpdate)
        case groupMemberAddedUpdate(BackupProtoGroupMemberAddedUpdate)
        case groupSelfInvitationRevokedUpdate(BackupProtoGroupSelfInvitationRevokedUpdate)
        case groupInvitationRevokedUpdate(BackupProtoGroupInvitationRevokedUpdate)
        case groupJoinRequestUpdate(BackupProtoGroupJoinRequestUpdate)
        case groupJoinRequestApprovalUpdate(BackupProtoGroupJoinRequestApprovalUpdate)
        case groupJoinRequestCanceledUpdate(BackupProtoGroupJoinRequestCanceledUpdate)
        case groupInviteLinkResetUpdate(BackupProtoGroupInviteLinkResetUpdate)
        case groupInviteLinkEnabledUpdate(BackupProtoGroupInviteLinkEnabledUpdate)
        case groupInviteLinkAdminApprovalUpdate(BackupProtoGroupInviteLinkAdminApprovalUpdate)
        case groupInviteLinkDisabledUpdate(BackupProtoGroupInviteLinkDisabledUpdate)
        case groupMemberJoinedByLinkUpdate(BackupProtoGroupMemberJoinedByLinkUpdate)
        case groupV2MigrationUpdate(BackupProtoGroupV2MigrationUpdate)
        case groupV2MigrationSelfInvitedUpdate(BackupProtoGroupV2MigrationSelfInvitedUpdate)
        case groupV2MigrationInvitedMembersUpdate(BackupProtoGroupV2MigrationInvitedMembersUpdate)
        case groupV2MigrationDroppedMembersUpdate(BackupProtoGroupV2MigrationDroppedMembersUpdate)
        case groupSequenceOfRequestsAndCancelsUpdate(BackupProtoGroupSequenceOfRequestsAndCancelsUpdate)
        case groupExpirationTimerUpdate(BackupProtoGroupExpirationTimerUpdate)
    }

    fileprivate var updateType: UpdateType? {
        if let genericGroupUpdate {
            return .genericGroupUpdate(genericGroupUpdate)
        } else if let groupCreationUpdate {
            return .groupCreationUpdate(groupCreationUpdate)
        } else if let groupNameUpdate {
            return .groupNameUpdate(groupNameUpdate)
        } else if let groupAvatarUpdate {
            return .groupAvatarUpdate(groupAvatarUpdate)
        } else if let groupDescriptionUpdate {
            return .groupDescriptionUpdate(groupDescriptionUpdate)
        } else if let groupMembershipAccessLevelChangeUpdate {
            return .groupMembershipAccessLevelChangeUpdate(groupMembershipAccessLevelChangeUpdate)
        } else if let groupAttributesAccessLevelChangeUpdate {
            return .groupAttributesAccessLevelChangeUpdate(groupAttributesAccessLevelChangeUpdate)
        } else if let groupAnnouncementOnlyChangeUpdate {
            return .groupAnnouncementOnlyChangeUpdate(groupAnnouncementOnlyChangeUpdate)
        } else if let groupAdminStatusUpdate {
            return .groupAdminStatusUpdate(groupAdminStatusUpdate)
        } else if let groupMemberLeftUpdate {
            return .groupMemberLeftUpdate(groupMemberLeftUpdate)
        } else if let groupMemberRemovedUpdate {
            return .groupMemberRemovedUpdate(groupMemberRemovedUpdate)
        } else if let selfInvitedToGroupUpdate {
            return .selfInvitedToGroupUpdate(selfInvitedToGroupUpdate)
        } else if let selfInvitedOtherUserToGroupUpdate {
            return .selfInvitedOtherUserToGroupUpdate(selfInvitedOtherUserToGroupUpdate)
        } else if let groupUnknownInviteeUpdate {
            return .groupUnknownInviteeUpdate(groupUnknownInviteeUpdate)
        } else if let groupInvitationAcceptedUpdate {
            return .groupInvitationAcceptedUpdate(groupInvitationAcceptedUpdate)
        } else if let groupInvitationDeclinedUpdate {
            return .groupInvitationDeclinedUpdate(groupInvitationDeclinedUpdate)
        } else if let groupMemberJoinedUpdate {
            return .groupMemberJoinedUpdate(groupMemberJoinedUpdate)
        } else if let groupMemberAddedUpdate {
            return .groupMemberAddedUpdate(groupMemberAddedUpdate)
        } else if let groupSelfInvitationRevokedUpdate {
            return .groupSelfInvitationRevokedUpdate(groupSelfInvitationRevokedUpdate)
        } else if let groupInvitationRevokedUpdate {
            return .groupInvitationRevokedUpdate(groupInvitationRevokedUpdate)
        } else if let groupJoinRequestUpdate {
            return .groupJoinRequestUpdate(groupJoinRequestUpdate)
        } else if let groupJoinRequestApprovalUpdate {
            return .groupJoinRequestApprovalUpdate(groupJoinRequestApprovalUpdate)
        } else if let groupJoinRequestCanceledUpdate {
            return .groupJoinRequestCanceledUpdate(groupJoinRequestCanceledUpdate)
        } else if let groupInviteLinkResetUpdate {
            return .groupInviteLinkResetUpdate(groupInviteLinkResetUpdate)
        } else if let groupInviteLinkEnabledUpdate {
            return .groupInviteLinkEnabledUpdate(groupInviteLinkEnabledUpdate)
        } else if let groupInviteLinkAdminApprovalUpdate {
            return .groupInviteLinkAdminApprovalUpdate(groupInviteLinkAdminApprovalUpdate)
        } else if let groupInviteLinkDisabledUpdate {
            return .groupInviteLinkDisabledUpdate(groupInviteLinkDisabledUpdate)
        } else if let groupMemberJoinedByLinkUpdate {
            return .groupMemberJoinedByLinkUpdate(groupMemberJoinedByLinkUpdate)
        } else if let groupV2MigrationUpdate {
            return .groupV2MigrationUpdate(groupV2MigrationUpdate)
        } else if let groupV2MigrationSelfInvitedUpdate {
            return .groupV2MigrationSelfInvitedUpdate(groupV2MigrationSelfInvitedUpdate)
        } else if let groupV2MigrationInvitedMembersUpdate {
            return .groupV2MigrationInvitedMembersUpdate(groupV2MigrationInvitedMembersUpdate)
        } else if let groupV2MigrationDroppedMembersUpdate {
            return .groupV2MigrationDroppedMembersUpdate(groupV2MigrationDroppedMembersUpdate)
        } else if let groupSequenceOfRequestsAndCancelsUpdate {
            return .groupSequenceOfRequestsAndCancelsUpdate(groupSequenceOfRequestsAndCancelsUpdate)
        } else if let groupExpirationTimerUpdate {
            return .groupExpirationTimerUpdate(groupExpirationTimerUpdate)
        } else {
            return nil
        }
    }
}

extension Optional where Wrapped == BackupProtoGroupV2AccessLevel {

    fileprivate var swiftAccessLevel: GroupV2Access {
        switch self {
        case .none, .unknown:
            return .unknown
        case .any:
            return .any
        case .member:
            return .member
        case .administrator:
            return .administrator
        case .unsatisfiable:
            return .unsatisfiable
        }
    }
}
