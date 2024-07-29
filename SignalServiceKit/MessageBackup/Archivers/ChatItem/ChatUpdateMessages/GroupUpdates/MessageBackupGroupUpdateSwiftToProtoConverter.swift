//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

final class MessageBackupGroupUpdateSwiftToProtoConverter {

    private init() {}

    // MARK: - Helpers

    private static func buildEmptyRevokedInvitees(
        count: UInt
    ) -> [BackupProto_GroupInvitationRevokedUpdate.Invitee] {
        // All the invitees are empty; only their count matters.
        return (0..<count).map { _ in
            return BackupProto_GroupInvitationRevokedUpdate.Invitee()
        }
    }

    // MARK: - Enum cases

    static func archiveGroupUpdate(
        groupUpdate: TSInfoMessage.PersistableGroupUpdateItem,
        // We should never be putting our pni in the backup as it can change,
        // we only ever insert our aci and use special cases for our pni.
        localUserAci: Aci,
        interactionId: MessageBackup.InteractionUniqueId
    ) -> MessageBackup.ArchiveInteractionResult<BackupProto_GroupChangeChatUpdate.Update> {
        let localAciData = localUserAci.rawUUID.data
        func aciData(_ aci: AciUuid) -> Data {
            return aci.wrappedValue.rawUUID.data
        }
        func pniData(_ pni: Pni) -> Data {
            return pni.rawUUID.data
        }
        func serviceIdData(_ serviceId: ServiceIdUppercaseString) -> Data {
            return serviceId.wrappedValue.serviceIdBinary.asData
        }

        var update = BackupProto_GroupChangeChatUpdate.Update()

        func setUpdate<Proto>(
            _ proto: Proto,
            setFields: ((inout Proto) -> Void)?,
            asUpdate: (Proto) -> BackupProto_GroupChangeChatUpdate.Update.OneOf_Update
        ) {
            var proto = proto
            setFields?(&proto)
            update.update = asUpdate(proto)
        }

        switch groupUpdate {
        case .sequenceOfInviteLinkRequestAndCancels(let requester, let count, _):
            // Note: isTail is dropped from the backup.
            // It is reconstructed at restore time from the presence, or lack thereof,
            // of a subsequent join request.
            if count == 0 {
                // If the count is 0, its actually just a request to join.
                setUpdate(
                    BackupProto_GroupJoinRequestUpdate(),
                    setFields: {
                        $0.requestorAci = aciData(requester)
                    },
                    asUpdate: { .groupJoinRequestUpdate($0) }
                )
            } else {
                setUpdate(
                    BackupProto_GroupSequenceOfRequestsAndCancelsUpdate(),
                    setFields: {
                        $0.requestorAci = aciData(requester)
                        $0.count = .init(clamping: count)
                    },
                    asUpdate: { .groupSequenceOfRequestsAndCancelsUpdate($0) }
                )
            }
        case .invitedPniPromotedToFullMemberAci(let newMember, let inviter):
            setUpdate(
                BackupProto_GroupInvitationAcceptedUpdate(),
                setFields: {
                    $0.newMemberAci = aciData(newMember)

                    if let inviter {
                        $0.inviterAci = aciData(inviter)
                    }
                },
                asUpdate: { .groupInvitationAcceptedUpdate($0) }
            )
        case .genericUpdateByLocalUser:
            setUpdate(
                BackupProto_GenericGroupUpdate(),
                setFields: {
                    $0.updaterAci = localAciData
                },
                asUpdate: { .genericGroupUpdate($0) }
            )
        case .genericUpdateByOtherUser(let updaterAci):
            setUpdate(
                BackupProto_GenericGroupUpdate(),
                setFields: {
                    $0.updaterAci = aciData(updaterAci)
                },
                asUpdate: { .genericGroupUpdate($0) }
            )
        case .genericUpdateByUnknownUser:
            setUpdate(
                BackupProto_GenericGroupUpdate(),
                setFields: { _ in },
                asUpdate: { .genericGroupUpdate($0) }
            )
        case .createdByLocalUser:
            setUpdate(
                BackupProto_GroupCreationUpdate(),
                setFields: {
                    $0.updaterAci = localAciData
                },
                asUpdate: { .groupCreationUpdate($0) }
            )
        case .createdByOtherUser(let updaterAci):
            setUpdate(
                BackupProto_GroupCreationUpdate(),
                setFields: {
                    $0.updaterAci = aciData(updaterAci)
                },
                asUpdate: { .groupCreationUpdate($0) }
            )
        case .createdByUnknownUser:
            setUpdate(
                BackupProto_GroupCreationUpdate(),
                setFields: { _ in },
                asUpdate: { .groupCreationUpdate($0) }
            )
        case .inviteFriendsToNewlyCreatedGroup:
            // This specific one is ignored for purposes of backups.
            // At restore time, it is created alongside the `createdByLocalUser`
            // case if we find that in the backup.
            return .skippableChatUpdate(.skippableGroupUpdate(.inviteFriendsToNewlyCreatedGroup))
        case .wasMigrated:
            setUpdate(
                BackupProto_GroupV2MigrationUpdate(),
                setFields: { _ in },
                asUpdate: { .groupV2MigrationUpdate($0) }
            )
        case .localUserInvitedAfterMigration:
            setUpdate(
                BackupProto_GroupV2MigrationSelfInvitedUpdate(),
                setFields: { _ in },
                asUpdate: { .groupV2MigrationSelfInvitedUpdate($0) }
            )
        case .otherUsersInvitedAfterMigration(let count):
            setUpdate(
                BackupProto_GroupV2MigrationInvitedMembersUpdate(),
                setFields: {
                    $0.invitedMembersCount = .init(clamping: count)
                },
                asUpdate: { .groupV2MigrationInvitedMembersUpdate($0) }
            )
        case .otherUsersDroppedAfterMigration(let count):
            setUpdate(
                BackupProto_GroupV2MigrationDroppedMembersUpdate(),
                setFields: {
                    $0.droppedMembersCount = .init(clamping: count)
                },
                asUpdate: { .groupV2MigrationDroppedMembersUpdate($0) }
            )
        case .nameChangedByLocalUser(let newGroupName):
            setUpdate(
                BackupProto_GroupNameUpdate(),
                setFields: {
                    $0.newGroupName = newGroupName
                    $0.updaterAci = localAciData
                },
                asUpdate: { .groupNameUpdate($0) }
            )
        case .nameChangedByOtherUser(let updaterAci, let newGroupName):
            setUpdate(
                BackupProto_GroupNameUpdate(),
                setFields: {
                    $0.newGroupName = newGroupName
                    $0.updaterAci = aciData(updaterAci)
                },
                asUpdate: { .groupNameUpdate($0) }
            )
        case .nameChangedByUnknownUser(let newGroupName):
            setUpdate(
                BackupProto_GroupNameUpdate(),
                setFields: {
                    $0.newGroupName = newGroupName
                },
                asUpdate: { .groupNameUpdate($0) }
            )
        case .nameRemovedByLocalUser:
            setUpdate(
                BackupProto_GroupNameUpdate(),
                setFields: {
                    // nil group name means removed.
                    $0.updaterAci = localAciData
                },
                asUpdate: { .groupNameUpdate($0) }
            )
        case .nameRemovedByOtherUser(let updaterAci):
            setUpdate(
                BackupProto_GroupNameUpdate(),
                setFields: {
                    // nil group name means removed.
                    $0.updaterAci = aciData(updaterAci)
                },
                asUpdate: { .groupNameUpdate($0) }
            )
        case .nameRemovedByUnknownUser:
            setUpdate(
                BackupProto_GroupNameUpdate(),
                setFields: { _ in },
                // nil group name means removed, updater unknown.
                // nothing to set.
                asUpdate: { .groupNameUpdate($0) }
            )
        case .avatarChangedByLocalUser:
            setUpdate(
                BackupProto_GroupAvatarUpdate(),
                setFields: {
                    $0.wasRemoved = false
                    $0.updaterAci = localAciData
                },
                asUpdate: { .groupAvatarUpdate($0) }
            )
        case .avatarChangedByOtherUser(let updaterAci):
            setUpdate(
                BackupProto_GroupAvatarUpdate(),
                setFields: {
                    $0.wasRemoved = false
                    $0.updaterAci = aciData(updaterAci)
                },
                asUpdate: { .groupAvatarUpdate($0) }
            )
        case .avatarChangedByUnknownUser:
            setUpdate(
                BackupProto_GroupAvatarUpdate(),
                setFields: {
                    $0.wasRemoved = false
                },
                asUpdate: { .groupAvatarUpdate($0) }
            )
        case .avatarRemovedByLocalUser:
            setUpdate(
                BackupProto_GroupAvatarUpdate(),
                setFields: {
                    $0.wasRemoved = true
                    $0.updaterAci = localAciData
                },
                asUpdate: { .groupAvatarUpdate($0) }
            )
        case .avatarRemovedByOtherUser(let updaterAci):
            setUpdate(
                BackupProto_GroupAvatarUpdate(),
                setFields: {
                    $0.wasRemoved = true
                    $0.updaterAci = aciData(updaterAci)
                },
                asUpdate: { .groupAvatarUpdate($0) }
            )
        case .avatarRemovedByUnknownUser:
            setUpdate(
                BackupProto_GroupAvatarUpdate(),
                setFields: {
                    $0.wasRemoved = true
                },
                asUpdate: { .groupAvatarUpdate($0) }
            )
        case .descriptionChangedByLocalUser(let newDescription):
            setUpdate(
                BackupProto_GroupDescriptionUpdate(),
                setFields: {
                    $0.newDescription = newDescription
                    $0.updaterAci = localAciData
                },
                asUpdate: { .groupDescriptionUpdate($0) }
            )
        case .descriptionChangedByOtherUser(let updaterAci, let newDescription):
            setUpdate(
                BackupProto_GroupDescriptionUpdate(),
                setFields: {
                    $0.newDescription = newDescription
                    $0.updaterAci = aciData(updaterAci)
                },
                asUpdate: { .groupDescriptionUpdate($0) }
            )
        case .descriptionChangedByUnknownUser(let newDescription):
            setUpdate(
                BackupProto_GroupDescriptionUpdate(),
                setFields: {
                    $0.newDescription = newDescription
                },
                asUpdate: { .groupDescriptionUpdate($0) }
            )
        case .descriptionRemovedByLocalUser:
            setUpdate(
                BackupProto_GroupDescriptionUpdate(),
                setFields: {
                    // nil group description means removed.
                    $0.updaterAci = localAciData
                },
                asUpdate: { .groupDescriptionUpdate($0) }
            )
        case .descriptionRemovedByOtherUser(let updaterAci):
            setUpdate(
                BackupProto_GroupDescriptionUpdate(),
                setFields: {
                    // nil group name means removed.
                    $0.updaterAci = aciData(updaterAci)
                },
                asUpdate: { .groupDescriptionUpdate($0) }
            )
        case .descriptionRemovedByUnknownUser:
            setUpdate(
                BackupProto_GroupDescriptionUpdate(),
                setFields: { _ in },
                // nil group description means removed, updater unknown.
                // nothing to set.
                asUpdate: { .groupDescriptionUpdate($0) }
            )
        case .membersAccessChangedByLocalUser(let newAccess):
            setUpdate(
                BackupProto_GroupMembershipAccessLevelChangeUpdate(),
                setFields: {
                    $0.accessLevel = newAccess.backupAccessLevel
                    $0.updaterAci = localAciData
                },
                asUpdate: { .groupMembershipAccessLevelChangeUpdate($0) }
            )
        case .membersAccessChangedByOtherUser(let updaterAci, let newAccess):
            setUpdate(
                BackupProto_GroupMembershipAccessLevelChangeUpdate(),
                setFields: {
                    $0.accessLevel = newAccess.backupAccessLevel
                    $0.updaterAci = aciData(updaterAci)
                },
                asUpdate: { .groupMembershipAccessLevelChangeUpdate($0) }
            )
        case .membersAccessChangedByUnknownUser(let newAccess):
            setUpdate(
                BackupProto_GroupMembershipAccessLevelChangeUpdate(),
                setFields: {
                    $0.accessLevel = newAccess.backupAccessLevel
                },
                asUpdate: { .groupMembershipAccessLevelChangeUpdate($0) }
            )
        case .attributesAccessChangedByLocalUser(let newAccess):
            setUpdate(
                BackupProto_GroupAttributesAccessLevelChangeUpdate(),
                setFields: {
                    $0.accessLevel = newAccess.backupAccessLevel
                    $0.updaterAci = localAciData
                },
                asUpdate: { .groupAttributesAccessLevelChangeUpdate($0) }
            )
        case .attributesAccessChangedByOtherUser(let updaterAci, let newAccess):
            setUpdate(
                BackupProto_GroupAttributesAccessLevelChangeUpdate(),
                setFields: {
                    $0.accessLevel = newAccess.backupAccessLevel
                    $0.updaterAci = aciData(updaterAci)
                },
                asUpdate: { .groupAttributesAccessLevelChangeUpdate($0) }
            )
        case .attributesAccessChangedByUnknownUser(let newAccess):
            setUpdate(
                BackupProto_GroupAttributesAccessLevelChangeUpdate(),
                setFields: {
                    $0.accessLevel = newAccess.backupAccessLevel
                },
                asUpdate: { .groupAttributesAccessLevelChangeUpdate($0) }
            )
        case .announcementOnlyEnabledByLocalUser:
            setUpdate(
                BackupProto_GroupAnnouncementOnlyChangeUpdate(),
                setFields: {
                    $0.isAnnouncementOnly = true
                    $0.updaterAci = localAciData
                },
                asUpdate: { .groupAnnouncementOnlyChangeUpdate($0) }
            )
        case .announcementOnlyEnabledByOtherUser(let updaterAci):
            setUpdate(
                BackupProto_GroupAnnouncementOnlyChangeUpdate(),
                setFields: {
                    $0.isAnnouncementOnly = true
                    $0.updaterAci = aciData(updaterAci)
                },
                asUpdate: { .groupAnnouncementOnlyChangeUpdate($0) }
            )
        case .announcementOnlyEnabledByUnknownUser:
            setUpdate(
                BackupProto_GroupAnnouncementOnlyChangeUpdate(),
                setFields: {
                    $0.isAnnouncementOnly = true
                },
                asUpdate: { .groupAnnouncementOnlyChangeUpdate($0) }
            )
        case .announcementOnlyDisabledByLocalUser:
            setUpdate(
                BackupProto_GroupAnnouncementOnlyChangeUpdate(),
                setFields: {
                    $0.isAnnouncementOnly = false
                    $0.updaterAci = localAciData
                },
                asUpdate: { .groupAnnouncementOnlyChangeUpdate($0) }
            )
        case .announcementOnlyDisabledByOtherUser(let updaterAci):
            setUpdate(
                BackupProto_GroupAnnouncementOnlyChangeUpdate(),
                setFields: {
                    $0.isAnnouncementOnly = false
                    $0.updaterAci = aciData(updaterAci)
                },
                asUpdate: { .groupAnnouncementOnlyChangeUpdate($0) }
            )
        case .announcementOnlyDisabledByUnknownUser:
            setUpdate(
                BackupProto_GroupAnnouncementOnlyChangeUpdate(),
                setFields: {
                    $0.isAnnouncementOnly = false
                },
                asUpdate: { .groupAnnouncementOnlyChangeUpdate($0) }
            )
        case .localUserWasGrantedAdministratorByLocalUser:
            setUpdate(
                BackupProto_GroupAdminStatusUpdate(),
                setFields: {
                    $0.memberAci = localAciData
                    $0.wasAdminStatusGranted = true
                    $0.updaterAci = localAciData
                },
                asUpdate: { .groupAdminStatusUpdate($0) }
            )
        case .localUserWasGrantedAdministratorByOtherUser(let updaterAci):
            setUpdate(
                BackupProto_GroupAdminStatusUpdate(),
                setFields: {
                    $0.memberAci = localAciData
                    $0.wasAdminStatusGranted = true
                    $0.updaterAci = aciData(updaterAci)
                },
                asUpdate: { .groupAdminStatusUpdate($0) }
            )
        case .localUserWasGrantedAdministratorByUnknownUser:
            setUpdate(
                BackupProto_GroupAdminStatusUpdate(),
                setFields: {
                    $0.memberAci = localAciData
                    $0.wasAdminStatusGranted = true
                },
                asUpdate: { .groupAdminStatusUpdate($0) }
            )
        case .otherUserWasGrantedAdministratorByLocalUser(let userAci):
            setUpdate(
                BackupProto_GroupAdminStatusUpdate(),
                setFields: {
                    $0.memberAci = aciData(userAci)
                    $0.wasAdminStatusGranted = true
                    $0.updaterAci = localAciData
                },
                asUpdate: { .groupAdminStatusUpdate($0) }
            )
        case .otherUserWasGrantedAdministratorByOtherUser(let updaterAci, let userAci):
            setUpdate(
                BackupProto_GroupAdminStatusUpdate(),
                setFields: {
                    $0.memberAci = aciData(userAci)
                    $0.wasAdminStatusGranted = true
                    $0.updaterAci = aciData(updaterAci)
                },
                asUpdate: { .groupAdminStatusUpdate($0) }
            )
        case .otherUserWasGrantedAdministratorByUnknownUser(let userAci):
            setUpdate(
                BackupProto_GroupAdminStatusUpdate(),
                setFields: {
                    $0.memberAci = aciData(userAci)
                    $0.wasAdminStatusGranted = true
                },
                asUpdate: { .groupAdminStatusUpdate($0) }
            )
        case .localUserWasRevokedAdministratorByLocalUser:
            setUpdate(
                BackupProto_GroupAdminStatusUpdate(),
                setFields: {
                    $0.memberAci = localAciData
                    $0.wasAdminStatusGranted = false
                    $0.updaterAci = localAciData
                },
                asUpdate: { .groupAdminStatusUpdate($0) }
            )
        case .localUserWasRevokedAdministratorByOtherUser(let updaterAci):
            setUpdate(
                BackupProto_GroupAdminStatusUpdate(),
                setFields: {
                    $0.memberAci = localAciData
                    $0.wasAdminStatusGranted = false
                    $0.updaterAci = aciData(updaterAci)
                },
                asUpdate: { .groupAdminStatusUpdate($0) }
            )
        case .localUserWasRevokedAdministratorByUnknownUser:
            setUpdate(
                BackupProto_GroupAdminStatusUpdate(),
                setFields: {
                    $0.memberAci = localAciData
                    $0.wasAdminStatusGranted = false
                },
                asUpdate: { .groupAdminStatusUpdate($0) }
            )
        case .otherUserWasRevokedAdministratorByLocalUser(let userAci):
            setUpdate(
                BackupProto_GroupAdminStatusUpdate(),
                setFields: {
                    $0.memberAci = aciData(userAci)
                    $0.wasAdminStatusGranted = false
                    $0.updaterAci = localAciData
                },
                asUpdate: { .groupAdminStatusUpdate($0) }
            )
        case .otherUserWasRevokedAdministratorByOtherUser(let updaterAci, let userAci):
            setUpdate(
                BackupProto_GroupAdminStatusUpdate(),
                setFields: {
                    $0.memberAci = aciData(userAci)
                    $0.wasAdminStatusGranted = false
                    $0.updaterAci = aciData(updaterAci)
                },
                asUpdate: { .groupAdminStatusUpdate($0) }
            )
        case .otherUserWasRevokedAdministratorByUnknownUser(let userAci):
            setUpdate(
                BackupProto_GroupAdminStatusUpdate(),
                setFields: {
                    $0.memberAci = aciData(userAci)
                    $0.wasAdminStatusGranted = false
                },
                asUpdate: { .groupAdminStatusUpdate($0) }
            )
        case .localUserLeft:
            setUpdate(
                BackupProto_GroupMemberLeftUpdate(),
                setFields: {
                    $0.aci = localAciData
                },
                asUpdate: { .groupMemberLeftUpdate($0) }
            )
        case .localUserRemoved(let removerAci):
            setUpdate(
                BackupProto_GroupMemberRemovedUpdate(),
                setFields: {
                    $0.removedAci = localAciData
                    $0.removerAci = aciData(removerAci)
                },
                asUpdate: { .groupMemberRemovedUpdate($0) }
            )
        case .localUserRemovedByUnknownUser:
            setUpdate(
                BackupProto_GroupMemberRemovedUpdate(),
                setFields: {
                    $0.removedAci = localAciData
                },
                asUpdate: { .groupMemberRemovedUpdate($0) }
            )
        case .otherUserLeft(let userAci):
            setUpdate(
                BackupProto_GroupMemberLeftUpdate(),
                setFields: {
                    $0.aci = aciData(userAci)
                },
                asUpdate: { .groupMemberLeftUpdate($0) }
            )
        case .otherUserRemovedByLocalUser(let userAci):
            setUpdate(
                BackupProto_GroupMemberRemovedUpdate(),
                setFields: {
                    $0.removedAci = aciData(userAci)
                    $0.removerAci = localAciData
                },
                asUpdate: { .groupMemberRemovedUpdate($0) }
            )
        case .otherUserRemoved(let removerAci, let userAci):
            setUpdate(
                BackupProto_GroupMemberRemovedUpdate(),
                setFields: {
                    $0.removedAci = aciData(userAci)
                    $0.removerAci = aciData(removerAci)
                },
                asUpdate: { .groupMemberRemovedUpdate($0) }
            )
        case .otherUserRemovedByUnknownUser(let userAci):
            setUpdate(
                BackupProto_GroupMemberRemovedUpdate(),
                setFields: {
                    $0.removedAci = aciData(userAci)
                },
                asUpdate: { .groupMemberRemovedUpdate($0) }
            )
        case .localUserWasInvitedByLocalUser:
            setUpdate(
                BackupProto_SelfInvitedToGroupUpdate(),
                setFields: {
                    $0.inviterAci = localAciData
                },
                asUpdate: { .selfInvitedToGroupUpdate($0) }
            )
        case .localUserWasInvitedByOtherUser(let updaterAci):
            setUpdate(
                BackupProto_SelfInvitedToGroupUpdate(),
                setFields: {
                    $0.inviterAci = aciData(updaterAci)
                },
                asUpdate: { .selfInvitedToGroupUpdate($0) }
            )
        case .localUserWasInvitedByUnknownUser:
            setUpdate(
                BackupProto_SelfInvitedToGroupUpdate(),
                setFields: { _ in },
                asUpdate: { .selfInvitedToGroupUpdate($0) }
            )
        case .otherUserWasInvitedByLocalUser(let inviteeServiceId):
            setUpdate(
                BackupProto_SelfInvitedOtherUserToGroupUpdate(),
                setFields: {
                    $0.inviteeServiceID = serviceIdData(inviteeServiceId)
                },
                asUpdate: { .selfInvitedOtherUserToGroupUpdate($0) }
            )
        case .unnamedUsersWereInvitedByLocalUser(let count):
            setUpdate(
                BackupProto_GroupUnknownInviteeUpdate(),
                setFields: {
                    $0.inviteeCount = UInt32(clamping: count)
                    $0.inviterAci = localAciData
                },
                asUpdate: { .groupUnknownInviteeUpdate($0) }
            )
        case .unnamedUsersWereInvitedByOtherUser(let updaterAci, let count):
            setUpdate(
                BackupProto_GroupUnknownInviteeUpdate(),
                setFields: {
                    $0.inviteeCount = UInt32(clamping: count)
                    $0.inviterAci = aciData(updaterAci)
                },
                asUpdate: { .groupUnknownInviteeUpdate($0) }
            )
        case .unnamedUsersWereInvitedByUnknownUser(let count):
            setUpdate(
                BackupProto_GroupUnknownInviteeUpdate(),
                setFields: {
                    $0.inviteeCount = UInt32(clamping: count)
                },
                asUpdate: { .groupUnknownInviteeUpdate($0) }
            )
        case .localUserAcceptedInviteFromInviter(let inviterAci):
            setUpdate(
                BackupProto_GroupInvitationAcceptedUpdate(),
                setFields: {
                    $0.newMemberAci = localAciData
                    $0.inviterAci = aciData(inviterAci)
                },
                asUpdate: { .groupInvitationAcceptedUpdate($0) }
            )
        case .localUserAcceptedInviteFromUnknownUser:
            setUpdate(
                BackupProto_GroupInvitationAcceptedUpdate(),
                setFields: {
                    $0.newMemberAci = localAciData
                },
                asUpdate: { .groupInvitationAcceptedUpdate($0) }
            )
        case .otherUserAcceptedInviteFromLocalUser(let userAci):
            setUpdate(
                BackupProto_GroupInvitationAcceptedUpdate(),
                setFields: {
                    $0.newMemberAci = aciData(userAci)
                    $0.inviterAci = localAciData
                },
                asUpdate: { .groupInvitationAcceptedUpdate($0) }
            )
        case .otherUserAcceptedInviteFromInviter(let userAci, let inviterAci):
            setUpdate(
                BackupProto_GroupInvitationAcceptedUpdate(),
                setFields: {
                    $0.newMemberAci = aciData(userAci)
                    $0.inviterAci = aciData(inviterAci)
                },
                asUpdate: { .groupInvitationAcceptedUpdate($0) }
            )
        case .otherUserAcceptedInviteFromUnknownUser(let userAci):
            setUpdate(
                BackupProto_GroupInvitationAcceptedUpdate(),
                setFields: {
                    $0.newMemberAci = aciData(userAci)
                },
                asUpdate: { .groupInvitationAcceptedUpdate($0) }
            )
        case .localUserJoined:
            setUpdate(
                BackupProto_GroupMemberJoinedUpdate(),
                setFields: {
                    $0.newMemberAci = localAciData
                },
                asUpdate: { .groupMemberJoinedUpdate($0) }
            )
        case .otherUserJoined(let userAci):
            setUpdate(
                BackupProto_GroupMemberJoinedUpdate(),
                setFields: {
                    $0.newMemberAci = aciData(userAci)
                },
                asUpdate: { .groupMemberJoinedUpdate($0) }
            )
        case .localUserAddedByLocalUser:
            setUpdate(
                BackupProto_GroupMemberAddedUpdate(),
                setFields: {
                    $0.newMemberAci = localAciData
                    // Note: on iOS we don't track if there was an invitation
                    // or who the inviter was.
                    $0.hadOpenInvitation = false
                    $0.updaterAci = localAciData
                },
                asUpdate: { .groupMemberAddedUpdate($0) }
            )
        case .localUserAddedByOtherUser(let updaterAci):
            setUpdate(
                BackupProto_GroupMemberAddedUpdate(),
                setFields: {
                    $0.newMemberAci = localAciData
                    // Note: on iOS we don't track if there was an invitation
                    // or who the inviter was.
                    $0.hadOpenInvitation = false
                    $0.updaterAci = aciData(updaterAci)
                },
                asUpdate: { .groupMemberAddedUpdate($0) }
            )
        case .localUserAddedByUnknownUser:
            setUpdate(
                BackupProto_GroupMemberAddedUpdate(),
                setFields: {
                    $0.newMemberAci = localAciData
                    // Note: on iOS we don't track if there was an invitation
                    // or who the inviter was.
                    $0.hadOpenInvitation = false
                },
                asUpdate: { .groupMemberAddedUpdate($0) }
            )
        case .otherUserAddedByLocalUser(let userAci):
            setUpdate(
                BackupProto_GroupMemberAddedUpdate(),
                setFields: {
                    $0.newMemberAci = aciData(userAci)
                    // Note: on iOS we don't track if there was an invitation
                    // or who the inviter was.
                    $0.hadOpenInvitation = false
                    $0.updaterAci = localAciData
                },
                asUpdate: { .groupMemberAddedUpdate($0) }
            )
        case .otherUserAddedByOtherUser(let updaterAci, let userAci):
            setUpdate(
                BackupProto_GroupMemberAddedUpdate(),
                setFields: {
                    $0.newMemberAci = aciData(userAci)
                    // Note: on iOS we don't track if there was an invitation
                    // or who the inviter was.
                    $0.hadOpenInvitation = false
                    $0.updaterAci = aciData(updaterAci)
                },
                asUpdate: { .groupMemberAddedUpdate($0) }
            )
        case .otherUserAddedByUnknownUser(let userAci):
            setUpdate(
                BackupProto_GroupMemberAddedUpdate(),
                setFields: {
                    $0.newMemberAci = aciData(userAci)
                    // Note: on iOS we don't track if there was an invitation
                    // or who the inviter was.
                    $0.hadOpenInvitation = false
                },
                asUpdate: { .groupMemberAddedUpdate($0) }
            )
        case .localUserDeclinedInviteFromInviter(let inviterAci):
            setUpdate(
                BackupProto_GroupInvitationDeclinedUpdate(),
                setFields: {
                    $0.inviteeAci = localAciData
                    $0.inviterAci = aciData(inviterAci)
                },
                asUpdate: { .groupInvitationDeclinedUpdate($0) }
            )
        case .localUserDeclinedInviteFromUnknownUser:
            setUpdate(
                BackupProto_GroupInvitationDeclinedUpdate(),
                setFields: {
                    $0.inviteeAci = localAciData
                },
                asUpdate: { .groupInvitationDeclinedUpdate($0) }
            )
        case .otherUserDeclinedInviteFromLocalUser(let invitee):
            setUpdate(
                BackupProto_GroupInvitationDeclinedUpdate(),
                setFields: {
                    switch invitee.wrappedValue.concreteType {
                    case .pni:
                        // Per spec we drop pnis for declined invites.
                        // They become unknown invitees.
                        break
                    case .aci(let aci):
                        $0.inviteeAci = aciData(aci.codableUuid)
                    }
                    $0.inviterAci = localAciData
                },
                asUpdate: { .groupInvitationDeclinedUpdate($0) }
            )
        case .otherUserDeclinedInviteFromInviter(let invitee, let inviterAci):
            setUpdate(
                BackupProto_GroupInvitationDeclinedUpdate(),
                setFields: {
                    switch invitee.wrappedValue.concreteType {
                    case .pni:
                        // Per spec we drop pnis for declined invites.
                        // They become unknown invitees.
                        break
                    case .aci(let aci):
                        $0.inviteeAci = aciData(aci.codableUuid)
                    }
                    $0.inviterAci = aciData(inviterAci)
                },
                asUpdate: { .groupInvitationDeclinedUpdate($0) }
            )
        case .otherUserDeclinedInviteFromUnknownUser(let invitee):
            setUpdate(
                BackupProto_GroupInvitationDeclinedUpdate(),
                setFields: {
                    switch invitee.wrappedValue.concreteType {
                    case .pni:
                        // Per spec we drop pnis for declined invites.
                        // They become unknown invitees.
                        break
                    case .aci(let aci):
                        $0.inviteeAci = aciData(aci.codableUuid)
                    }
                },
                asUpdate: { .groupInvitationDeclinedUpdate($0) }
            )
        case .unnamedUserDeclinedInviteFromInviter(let inviterAci):
            setUpdate(
                BackupProto_GroupInvitationDeclinedUpdate(),
                setFields: {
                    $0.inviterAci = aciData(inviterAci)
                },
                asUpdate: { .groupInvitationDeclinedUpdate($0) }
            )
        case .unnamedUserDeclinedInviteFromUnknownUser:
            setUpdate(
                BackupProto_GroupInvitationDeclinedUpdate(),
                setFields: { _ in },
                asUpdate: { .groupInvitationDeclinedUpdate($0) }
            )
        case .localUserInviteRevoked(let revokerAci):
            setUpdate(
                BackupProto_GroupSelfInvitationRevokedUpdate(),
                setFields: {
                    $0.revokerAci = aciData(revokerAci)
                },
                asUpdate: { .groupSelfInvitationRevokedUpdate($0) }
            )
        case .localUserInviteRevokedByUnknownUser:
            setUpdate(
                BackupProto_GroupSelfInvitationRevokedUpdate(),
                setFields: { _ in },
                asUpdate: { .groupSelfInvitationRevokedUpdate($0) }
            )
        case .otherUserInviteRevokedByLocalUser(let invitee):
            var inviteeProto = BackupProto_GroupInvitationRevokedUpdate.Invitee()
            switch invitee.wrappedValue.concreteType {
            case .aci(let aci):
                inviteeProto.inviteeAci = aciData(aci.codableUuid)
            case .pni(let pni):
                inviteeProto.inviteePni = pniData(pni)
            }
            // Note: on iOS we don't keep who the inviter was.
            setUpdate(
                BackupProto_GroupInvitationRevokedUpdate(),
                setFields: {
                    $0.updaterAci = localAciData
                    $0.invitees = [inviteeProto]
                },
                asUpdate: { .groupInvitationRevokedUpdate($0) }
            )
        case .unnamedUserInvitesWereRevokedByLocalUser(let count):
            // All the invitees are empty; only their count matters.
            let invitees = buildEmptyRevokedInvitees(count: count)
            setUpdate(
                BackupProto_GroupInvitationRevokedUpdate(),
                setFields: {
                    $0.updaterAci = localAciData
                    $0.invitees = invitees
                },
                asUpdate: { .groupInvitationRevokedUpdate($0) }
            )
        case .unnamedUserInvitesWereRevokedByOtherUser(let updaterAci, let count):
            // All the invitees are empty; only their count matters.
            let invitees = buildEmptyRevokedInvitees(count: count)
            setUpdate(
                BackupProto_GroupInvitationRevokedUpdate(),
                setFields: {
                    $0.updaterAci = aciData(updaterAci)
                    $0.invitees = invitees
                },
                asUpdate: { .groupInvitationRevokedUpdate($0) }
            )
        case .unnamedUserInvitesWereRevokedByUnknownUser(let count):
            // All the invitees are empty; only their count matters.
            let invitees = buildEmptyRevokedInvitees(count: count)
            setUpdate(
                BackupProto_GroupInvitationRevokedUpdate(),
                setFields: {
                    $0.invitees = invitees
                },
                asUpdate: { .groupInvitationRevokedUpdate($0) }
            )
        case .localUserRequestedToJoin:
            setUpdate(
                BackupProto_GroupJoinRequestUpdate(),
                setFields: {
                    $0.requestorAci = localAciData
                },
                asUpdate: { .groupJoinRequestUpdate($0) }
            )
        case .otherUserRequestedToJoin(let userAci):
            setUpdate(
                BackupProto_GroupJoinRequestUpdate(),
                setFields: {
                    $0.requestorAci = aciData(userAci)
                },
                asUpdate: { .groupJoinRequestUpdate($0) }
            )
        case .localUserRequestApproved(let approverAci):
            setUpdate(
                BackupProto_GroupJoinRequestApprovalUpdate(),
                setFields: {
                    $0.requestorAci = localAciData
                    $0.wasApproved = true
                    $0.updaterAci = aciData(approverAci)
                },
                asUpdate: { .groupJoinRequestApprovalUpdate($0) }
            )
        case .localUserRequestApprovedByUnknownUser:
            setUpdate(
                BackupProto_GroupJoinRequestApprovalUpdate(),
                setFields: {
                    $0.requestorAci = localAciData
                    $0.wasApproved = true
                },
                asUpdate: { .groupJoinRequestApprovalUpdate($0) }
            )
        case .otherUserRequestApprovedByLocalUser(let userAci):
            setUpdate(
                BackupProto_GroupJoinRequestApprovalUpdate(),
                setFields: {
                    $0.requestorAci = aciData(userAci)
                    $0.wasApproved = true
                    $0.updaterAci = localAciData
                },
                asUpdate: { .groupJoinRequestApprovalUpdate($0) }
            )
        case .otherUserRequestApproved(let userAci, let approverAci):
            setUpdate(
                BackupProto_GroupJoinRequestApprovalUpdate(),
                setFields: {
                    $0.requestorAci = aciData(userAci)
                    $0.wasApproved = true
                    $0.updaterAci = aciData(approverAci)
                },
                asUpdate: { .groupJoinRequestApprovalUpdate($0) }
            )
        case .otherUserRequestApprovedByUnknownUser(let userAci):
            setUpdate(
                BackupProto_GroupJoinRequestApprovalUpdate(),
                setFields: {
                    $0.requestorAci = aciData(userAci)
                    $0.wasApproved = true
                },
                asUpdate: { .groupJoinRequestApprovalUpdate($0) }
            )
        case .localUserRequestCanceledByLocalUser:
            setUpdate(
                BackupProto_GroupJoinRequestCanceledUpdate(),
                setFields: {
                    $0.requestorAci = localAciData
                },
                asUpdate: { .groupJoinRequestCanceledUpdate($0) }
            )
        case .localUserRequestRejectedByUnknownUser:
            setUpdate(
                BackupProto_GroupJoinRequestApprovalUpdate(),
                setFields: {
                    $0.requestorAci = localAciData
                    $0.wasApproved = false
                },
                asUpdate: { .groupJoinRequestApprovalUpdate($0) }
            )
        case .otherUserRequestRejectedByLocalUser(let requesterAci):
            setUpdate(
                BackupProto_GroupJoinRequestApprovalUpdate(),
                setFields: {
                    $0.requestorAci = aciData(requesterAci)
                    $0.wasApproved = false
                    $0.updaterAci = localAciData
                },
                asUpdate: { .groupJoinRequestApprovalUpdate($0) }
            )
        case .otherUserRequestRejectedByOtherUser(let updaterAci, let requesterAci):
            setUpdate(
                BackupProto_GroupJoinRequestApprovalUpdate(),
                setFields: {
                    $0.requestorAci = aciData(requesterAci)
                    $0.wasApproved = false
                    $0.updaterAci = aciData(updaterAci)
                },
                asUpdate: { .groupJoinRequestApprovalUpdate($0) }
            )
        case .otherUserRequestCanceledByOtherUser(let requesterAci):
            setUpdate(
                BackupProto_GroupJoinRequestCanceledUpdate(),
                setFields: {
                    $0.requestorAci = aciData(requesterAci)
                },
                asUpdate: { .groupJoinRequestCanceledUpdate($0) }
            )
        case .otherUserRequestRejectedByUnknownUser(let requesterAci):
            setUpdate(
                BackupProto_GroupJoinRequestApprovalUpdate(),
                setFields: {
                    $0.requestorAci = aciData(requesterAci)
                    $0.wasApproved = false
                },
                asUpdate: { .groupJoinRequestApprovalUpdate($0) }
            )
        case .disappearingMessagesEnabledByLocalUser(let durationMs):
            setUpdate(
                BackupProto_GroupExpirationTimerUpdate(),
                setFields: {
                    $0.expiresInMs = durationMs
                    $0.updaterAci = localAciData
                },
                asUpdate: { .groupExpirationTimerUpdate($0) }
            )
        case .disappearingMessagesEnabledByOtherUser(let updaterAci, let durationMs):
            setUpdate(
                BackupProto_GroupExpirationTimerUpdate(),
                setFields: {
                    $0.expiresInMs = durationMs
                    $0.updaterAci = aciData(updaterAci)
                },
                asUpdate: { .groupExpirationTimerUpdate($0) }
            )
        case .disappearingMessagesEnabledByUnknownUser(let durationMs):
            setUpdate(
                BackupProto_GroupExpirationTimerUpdate(),
                setFields: {
                    $0.expiresInMs = durationMs
                },
                asUpdate: { .groupExpirationTimerUpdate($0) }
            )
        case .disappearingMessagesDisabledByLocalUser:
            setUpdate(
                BackupProto_GroupExpirationTimerUpdate(),
                setFields: {
                    // 0 means disabled.
                    $0.expiresInMs = 0
                    $0.updaterAci = localAciData
                },
                asUpdate: { .groupExpirationTimerUpdate($0) }
            )
        case .disappearingMessagesDisabledByOtherUser(let updaterAci):
            setUpdate(
                BackupProto_GroupExpirationTimerUpdate(),
                setFields: {
                    // 0 means disabled.
                    $0.expiresInMs = 0
                    $0.updaterAci = aciData(updaterAci)
                },
                asUpdate: { .groupExpirationTimerUpdate($0) }
            )
        case .disappearingMessagesDisabledByUnknownUser:
            setUpdate(
                BackupProto_GroupExpirationTimerUpdate(),
                setFields: {
                    // 0 means disabled.
                    $0.expiresInMs = 0
                },
                asUpdate: { .groupExpirationTimerUpdate($0) }
            )
        case .inviteLinkResetByLocalUser:
            setUpdate(
                BackupProto_GroupInviteLinkResetUpdate(),
                setFields: {
                    $0.updaterAci = localAciData
                },
                asUpdate: { .groupInviteLinkResetUpdate($0) }
            )
        case .inviteLinkResetByOtherUser(let updaterAci):
            setUpdate(
                BackupProto_GroupInviteLinkResetUpdate(),
                setFields: {
                    $0.updaterAci = aciData(updaterAci)
                },
                asUpdate: { .groupInviteLinkResetUpdate($0) }
            )
        case .inviteLinkResetByUnknownUser:
            setUpdate(
                BackupProto_GroupInviteLinkResetUpdate(),
                setFields: { _ in },
                asUpdate: { .groupInviteLinkResetUpdate($0) }
            )
        case .inviteLinkEnabledWithoutApprovalByLocalUser:
            setUpdate(
                BackupProto_GroupInviteLinkEnabledUpdate(),
                setFields: {
                    $0.linkRequiresAdminApproval = false
                    $0.updaterAci = localAciData
                },
                asUpdate: { .groupInviteLinkEnabledUpdate($0) }
            )
        case .inviteLinkEnabledWithoutApprovalByOtherUser(let updaterAci):
            setUpdate(
                BackupProto_GroupInviteLinkEnabledUpdate(),
                setFields: {
                    $0.linkRequiresAdminApproval = false
                    $0.updaterAci = aciData(updaterAci)
                },
                asUpdate: { .groupInviteLinkEnabledUpdate($0) }
            )
        case .inviteLinkEnabledWithoutApprovalByUnknownUser:
            setUpdate(
                BackupProto_GroupInviteLinkEnabledUpdate(),
                setFields: {
                    $0.linkRequiresAdminApproval = false
                },
                asUpdate: { .groupInviteLinkEnabledUpdate($0) }
            )
        case .inviteLinkEnabledWithApprovalByLocalUser:
            setUpdate(
                BackupProto_GroupInviteLinkEnabledUpdate(),
                setFields: {
                    $0.linkRequiresAdminApproval = true
                    $0.updaterAci = localAciData
                },
                asUpdate: { .groupInviteLinkEnabledUpdate($0) }
            )
        case .inviteLinkEnabledWithApprovalByOtherUser(let updaterAci):
            setUpdate(
                BackupProto_GroupInviteLinkEnabledUpdate(),
                setFields: {
                    $0.linkRequiresAdminApproval = true
                    $0.updaterAci = aciData(updaterAci)
                },
                asUpdate: { .groupInviteLinkEnabledUpdate($0) }
            )
        case .inviteLinkEnabledWithApprovalByUnknownUser:
            setUpdate(
                BackupProto_GroupInviteLinkEnabledUpdate(),
                setFields: {
                    $0.linkRequiresAdminApproval = true
                },
                asUpdate: { .groupInviteLinkEnabledUpdate($0) }
            )
        case .inviteLinkDisabledByLocalUser:
            setUpdate(
                BackupProto_GroupInviteLinkDisabledUpdate(),
                setFields: {
                    $0.updaterAci = localAciData
                },
                asUpdate: { .groupInviteLinkDisabledUpdate($0) }
            )
        case .inviteLinkDisabledByOtherUser(let updaterAci):
            setUpdate(
                BackupProto_GroupInviteLinkDisabledUpdate(),
                setFields: {
                    $0.updaterAci = aciData(updaterAci)
                },
                asUpdate: { .groupInviteLinkDisabledUpdate($0) }
            )
        case .inviteLinkDisabledByUnknownUser:
            setUpdate(
                BackupProto_GroupInviteLinkDisabledUpdate(),
                setFields: { _ in },
                asUpdate: { .groupInviteLinkDisabledUpdate($0) }
            )
        case .inviteLinkApprovalDisabledByLocalUser:
            setUpdate(
                BackupProto_GroupInviteLinkAdminApprovalUpdate(),
                setFields: {
                    $0.linkRequiresAdminApproval = false
                    $0.updaterAci = localAciData
                },
                asUpdate: { .groupInviteLinkAdminApprovalUpdate($0) }
            )
        case .inviteLinkApprovalDisabledByOtherUser(let updaterAci):
            setUpdate(
                BackupProto_GroupInviteLinkAdminApprovalUpdate(),
                setFields: {
                    $0.linkRequiresAdminApproval = false
                    $0.updaterAci = aciData(updaterAci)
                },
                asUpdate: { .groupInviteLinkAdminApprovalUpdate($0) }
            )
        case .inviteLinkApprovalDisabledByUnknownUser:
            setUpdate(
                BackupProto_GroupInviteLinkAdminApprovalUpdate(),
                setFields: {
                    $0.linkRequiresAdminApproval = false
                },
                asUpdate: { .groupInviteLinkAdminApprovalUpdate($0) }
            )
        case .inviteLinkApprovalEnabledByLocalUser:
            setUpdate(
                BackupProto_GroupInviteLinkAdminApprovalUpdate(),
                setFields: {
                    $0.linkRequiresAdminApproval = true
                    $0.updaterAci = localAciData
                },
                asUpdate: { .groupInviteLinkAdminApprovalUpdate($0) }
            )
        case .inviteLinkApprovalEnabledByOtherUser(let updaterAci):
            setUpdate(
                BackupProto_GroupInviteLinkAdminApprovalUpdate(),
                setFields: {
                    $0.linkRequiresAdminApproval = true
                    $0.updaterAci = aciData(updaterAci)
                },
                asUpdate: { .groupInviteLinkAdminApprovalUpdate($0) }
            )
        case .inviteLinkApprovalEnabledByUnknownUser:
            setUpdate(
                BackupProto_GroupInviteLinkAdminApprovalUpdate(),
                setFields: {
                    $0.linkRequiresAdminApproval = true
                },
                asUpdate: { .groupInviteLinkAdminApprovalUpdate($0) }
            )
        case .localUserJoinedViaInviteLink:
            setUpdate(
                BackupProto_GroupMemberJoinedByLinkUpdate(),
                setFields: {
                    $0.newMemberAci = localAciData
                },
                asUpdate: { .groupMemberJoinedByLinkUpdate($0) }
            )
        case .otherUserJoinedViaInviteLink(let userAci):
            setUpdate(
                BackupProto_GroupMemberJoinedByLinkUpdate(),
                setFields: {
                    $0.newMemberAci = aciData(userAci)
                },
                asUpdate: { .groupMemberJoinedByLinkUpdate($0) }
            )
        }

        return .success(update)
    }
}

extension GroupV2Access {

    fileprivate var backupAccessLevel: BackupProto_GroupV2AccessLevel {
        switch self {
        case .unknown:
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
