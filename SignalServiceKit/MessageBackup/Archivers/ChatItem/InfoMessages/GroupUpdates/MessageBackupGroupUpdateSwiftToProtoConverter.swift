//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

internal final class MessageBackupGroupUpdateSwiftToProtoConverter {

    private init() {}

    // MARK: - Helpers

    private static func buildEmptyRevokedInvitees(
        count: UInt
    ) -> [BackupProtoGroupInvitationRevokedUpdate.BackupProtoInvitee] {
        // All the invitees are empty; only their count matters.
        return (0..<count).map { _ in
            return BackupProtoGroupInvitationRevokedUpdate.BackupProtoInvitee()
        }
    }

    // MARK: - Enum cases

    internal static func archiveGroupUpdate(
        groupUpdate: TSInfoMessage.PersistableGroupUpdateItem,
        // We should never be putting our pni in the backup as it can change,
        // we only ever insert our aci and use special cases for our pni.
        localUserAci: Aci,
        interactionId: MessageBackup.InteractionUniqueId
    ) -> MessageBackup.ArchiveInteractionResult<BackupProtoGroupChangeChatUpdate.BackupProtoUpdate> {
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

        var update = BackupProtoGroupChangeChatUpdate.BackupProtoUpdate()

        func setUpdate<Proto>(
            _ proto: Proto,
            setOptionalFields: ((inout Proto) -> Void)? = nil,
            asUpdate: (Proto) -> BackupProtoGroupChangeChatUpdate.BackupProtoUpdate.Update
        ) {
            var proto = proto
            setOptionalFields?(&proto)
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
                    BackupProtoGroupJoinRequestUpdate(
                        requestorAci: aciData(requester)
                    ),
                    asUpdate: { .groupJoinRequestUpdate($0) }
                )
            } else {
                setUpdate(
                    BackupProtoGroupSequenceOfRequestsAndCancelsUpdate(
                        requestorAci: aciData(requester),
                        count: .init(clamping: count)
                    ),
                    asUpdate: { .groupSequenceOfRequestsAndCancelsUpdate($0) }
                )
            }
        case .invitedPniPromotedToFullMemberAci(let newMember, let inviter):
            setUpdate(
                BackupProtoGroupInvitationAcceptedUpdate(
                    newMemberAci: aciData(newMember)
                ),
                setOptionalFields: {
                    if let inviter {
                        $0.inviterAci = aciData(inviter)
                    }
                },
                asUpdate: { .groupInvitationAcceptedUpdate($0) }
            )
        case .genericUpdateByLocalUser:
            setUpdate(
                BackupProtoGenericGroupUpdate(),
                setOptionalFields: {
                    $0.updaterAci = localAciData
                },
                asUpdate: { .genericGroupUpdate($0) }
            )
        case .genericUpdateByOtherUser(let updaterAci):
            setUpdate(
                BackupProtoGenericGroupUpdate(),
                setOptionalFields: {
                    $0.updaterAci = aciData(updaterAci)
                },
                asUpdate: { .genericGroupUpdate($0) }
            )
        case .genericUpdateByUnknownUser:
            setUpdate(
                BackupProtoGenericGroupUpdate(),
                asUpdate: { .genericGroupUpdate($0) }
            )
        case .createdByLocalUser:
            setUpdate(
                BackupProtoGroupCreationUpdate(),
                setOptionalFields: {
                    $0.updaterAci = localAciData
                },
                asUpdate: { .groupCreationUpdate($0) }
            )
        case .createdByOtherUser(let updaterAci):
            setUpdate(
                BackupProtoGroupCreationUpdate(),
                setOptionalFields: {
                    $0.updaterAci = aciData(updaterAci)
                },
                asUpdate: { .groupCreationUpdate($0) }
            )
        case .createdByUnknownUser:
            setUpdate(
                BackupProtoGroupCreationUpdate(),
                asUpdate: { .groupCreationUpdate($0) }
            )
        case .inviteFriendsToNewlyCreatedGroup:
            // This specific one is ignored for purposes of backups.
            // At restore time, it is created alongside the `createdByLocalUser`
            // case if we find that in the backup.
            return .skippableGroupUpdate(.inviteFriendsToNewlyCreatedGroup)
        case .wasMigrated:
            setUpdate(
                BackupProtoGroupV2MigrationUpdate(),
                asUpdate: { .groupV2MigrationUpdate($0) }
            )
        case .localUserInvitedAfterMigration:
            setUpdate(
                BackupProtoGroupV2MigrationSelfInvitedUpdate(),
                asUpdate: { .groupV2MigrationSelfInvitedUpdate($0) }
            )
        case .otherUsersInvitedAfterMigration(let count):
            setUpdate(
                BackupProtoGroupV2MigrationInvitedMembersUpdate(
                    invitedMembersCount: .init(clamping: count)
                ),
                asUpdate: { .groupV2MigrationInvitedMembersUpdate($0) }
            )
        case .otherUsersDroppedAfterMigration(let count):
            setUpdate(
                BackupProtoGroupV2MigrationDroppedMembersUpdate(
                    droppedMembersCount: .init(clamping: count)
                ),
                asUpdate: { .groupV2MigrationDroppedMembersUpdate($0) }
            )
        case .nameChangedByLocalUser(let newGroupName):
            setUpdate(
                BackupProtoGroupNameUpdate(),
                setOptionalFields: {
                    $0.newGroupName = newGroupName
                    $0.updaterAci = localAciData
                },
                asUpdate: { .groupNameUpdate($0) }
            )
        case .nameChangedByOtherUser(let updaterAci, let newGroupName):
            setUpdate(
                BackupProtoGroupNameUpdate(),
                setOptionalFields: {
                    $0.newGroupName = newGroupName
                    $0.updaterAci = aciData(updaterAci)
                },
                asUpdate: { .groupNameUpdate($0) }
            )
        case .nameChangedByUnknownUser(let newGroupName):
            setUpdate(
                BackupProtoGroupNameUpdate(),
                setOptionalFields: {
                    $0.newGroupName = newGroupName
                },
                asUpdate: { .groupNameUpdate($0) }
            )
        case .nameRemovedByLocalUser:
            setUpdate(
                BackupProtoGroupNameUpdate(),
                setOptionalFields: {
                    // nil group name means removed.
                    $0.updaterAci = localAciData
                },
                asUpdate: { .groupNameUpdate($0) }
            )
        case .nameRemovedByOtherUser(let updaterAci):
            setUpdate(
                BackupProtoGroupNameUpdate(),
                setOptionalFields: {
                    // nil group name means removed.
                    $0.updaterAci = aciData(updaterAci)
                },
                asUpdate: { .groupNameUpdate($0) }
            )
        case .nameRemovedByUnknownUser:
            setUpdate(
                BackupProtoGroupNameUpdate(),
                // nil group name means removed, updater unknown.
                // nothing to set.
                asUpdate: { .groupNameUpdate($0) }
            )
        case .avatarChangedByLocalUser:
            setUpdate(
                BackupProtoGroupAvatarUpdate(wasRemoved: false),
                setOptionalFields: {
                    $0.updaterAci = localAciData
                },
                asUpdate: { .groupAvatarUpdate($0) }
            )
        case .avatarChangedByOtherUser(let updaterAci):
            setUpdate(
                BackupProtoGroupAvatarUpdate(wasRemoved: false),
                setOptionalFields: {
                    $0.updaterAci = aciData(updaterAci)
                },
                asUpdate: { .groupAvatarUpdate($0) }
            )
        case .avatarChangedByUnknownUser:
            setUpdate(
                BackupProtoGroupAvatarUpdate(wasRemoved: false),
                asUpdate: { .groupAvatarUpdate($0) }
            )
        case .avatarRemovedByLocalUser:
            setUpdate(
                BackupProtoGroupAvatarUpdate(wasRemoved: true),
                setOptionalFields: {
                    $0.updaterAci = localAciData
                },
                asUpdate: { .groupAvatarUpdate($0) }
            )
        case .avatarRemovedByOtherUser(let updaterAci):
            setUpdate(
                BackupProtoGroupAvatarUpdate(wasRemoved: true),
                setOptionalFields: {
                    $0.updaterAci = aciData(updaterAci)
                },
                asUpdate: { .groupAvatarUpdate($0) }
            )
        case .avatarRemovedByUnknownUser:
            setUpdate(
                BackupProtoGroupAvatarUpdate(wasRemoved: true),
                asUpdate: { .groupAvatarUpdate($0) }
            )
        case .descriptionChangedByLocalUser(let newDescription):
            setUpdate(
                BackupProtoGroupDescriptionUpdate(),
                setOptionalFields: {
                    $0.newDescription = newDescription
                    $0.updaterAci = localAciData
                },
                asUpdate: { .groupDescriptionUpdate($0) }
            )
        case .descriptionChangedByOtherUser(let updaterAci, let newDescription):
            setUpdate(
                BackupProtoGroupDescriptionUpdate(),
                setOptionalFields: {
                    $0.newDescription = newDescription
                    $0.updaterAci = aciData(updaterAci)
                },
                asUpdate: { .groupDescriptionUpdate($0) }
            )
        case .descriptionChangedByUnknownUser(let newDescription):
            setUpdate(
                BackupProtoGroupDescriptionUpdate(),
                setOptionalFields: {
                    $0.newDescription = newDescription
                },
                asUpdate: { .groupDescriptionUpdate($0) }
            )
        case .descriptionRemovedByLocalUser:
            setUpdate(
                BackupProtoGroupDescriptionUpdate(),
                setOptionalFields: {
                    // nil group description means removed.
                    $0.updaterAci = localAciData
                },
                asUpdate: { .groupDescriptionUpdate($0) }
            )
        case .descriptionRemovedByOtherUser(let updaterAci):
            setUpdate(
                BackupProtoGroupDescriptionUpdate(),
                setOptionalFields: {
                    // nil group name means removed.
                    $0.updaterAci = aciData(updaterAci)
                },
                asUpdate: { .groupDescriptionUpdate($0) }
            )
        case .descriptionRemovedByUnknownUser:
            setUpdate(
                BackupProtoGroupDescriptionUpdate(),
                // nil group description means removed, updater unknown.
                // nothing to set.
                asUpdate: { .groupDescriptionUpdate($0) }
            )
        case .membersAccessChangedByLocalUser(let newAccess):
            setUpdate(
                BackupProtoGroupMembershipAccessLevelChangeUpdate(),
                setOptionalFields: {
                    $0.updaterAci = localAciData
                    $0.accessLevel = newAccess.backupAccessLevel
                },
                asUpdate: { .groupMembershipAccessLevelChangeUpdate($0) }
            )
        case .membersAccessChangedByOtherUser(let updaterAci, let newAccess):
            setUpdate(
                BackupProtoGroupMembershipAccessLevelChangeUpdate(),
                setOptionalFields: {
                    $0.updaterAci = aciData(updaterAci)
                    $0.accessLevel = newAccess.backupAccessLevel
                },
                asUpdate: { .groupMembershipAccessLevelChangeUpdate($0) }
            )
        case .membersAccessChangedByUnknownUser(let newAccess):
            setUpdate(
                BackupProtoGroupMembershipAccessLevelChangeUpdate(),
                setOptionalFields: {
                    $0.accessLevel = newAccess.backupAccessLevel
                },
                asUpdate: { .groupMembershipAccessLevelChangeUpdate($0) }
            )
        case .attributesAccessChangedByLocalUser(let newAccess):
            setUpdate(
                BackupProtoGroupAttributesAccessLevelChangeUpdate(),
                setOptionalFields: {
                    $0.updaterAci = localAciData
                    $0.accessLevel = newAccess.backupAccessLevel
                },
                asUpdate: { .groupAttributesAccessLevelChangeUpdate($0) }
            )
        case .attributesAccessChangedByOtherUser(let updaterAci, let newAccess):
            setUpdate(
                BackupProtoGroupAttributesAccessLevelChangeUpdate(),
                setOptionalFields: {
                    $0.updaterAci = aciData(updaterAci)
                    $0.accessLevel = newAccess.backupAccessLevel
                },
                asUpdate: { .groupAttributesAccessLevelChangeUpdate($0) }
            )
        case .attributesAccessChangedByUnknownUser(let newAccess):
            setUpdate(
                BackupProtoGroupAttributesAccessLevelChangeUpdate(),
                setOptionalFields: {
                    $0.accessLevel = newAccess.backupAccessLevel
                },
                asUpdate: { .groupAttributesAccessLevelChangeUpdate($0) }
            )
        case .announcementOnlyEnabledByLocalUser:
            setUpdate(
                BackupProtoGroupAnnouncementOnlyChangeUpdate(isAnnouncementOnly: true),
                setOptionalFields: {
                    $0.updaterAci = localAciData
                },
                asUpdate: { .groupAnnouncementOnlyChangeUpdate($0) }
            )
        case .announcementOnlyEnabledByOtherUser(let updaterAci):
            setUpdate(
                BackupProtoGroupAnnouncementOnlyChangeUpdate(isAnnouncementOnly: true),
                setOptionalFields: {
                    $0.updaterAci = aciData(updaterAci)
                },
                asUpdate: { .groupAnnouncementOnlyChangeUpdate($0) }
            )
        case .announcementOnlyEnabledByUnknownUser:
            setUpdate(
                BackupProtoGroupAnnouncementOnlyChangeUpdate(isAnnouncementOnly: true),
                asUpdate: { .groupAnnouncementOnlyChangeUpdate($0) }
            )
        case .announcementOnlyDisabledByLocalUser:
            setUpdate(
                BackupProtoGroupAnnouncementOnlyChangeUpdate(isAnnouncementOnly: false),
                setOptionalFields: {
                    $0.updaterAci = localAciData
                },
                asUpdate: { .groupAnnouncementOnlyChangeUpdate($0) }
            )
        case .announcementOnlyDisabledByOtherUser(let updaterAci):
            setUpdate(
                BackupProtoGroupAnnouncementOnlyChangeUpdate(isAnnouncementOnly: false),
                setOptionalFields: {
                    $0.updaterAci = aciData(updaterAci)
                },
                asUpdate: { .groupAnnouncementOnlyChangeUpdate($0) }
            )
        case .announcementOnlyDisabledByUnknownUser:
            setUpdate(
                BackupProtoGroupAnnouncementOnlyChangeUpdate(isAnnouncementOnly: false),
                asUpdate: { .groupAnnouncementOnlyChangeUpdate($0) }
            )
        case .localUserWasGrantedAdministratorByLocalUser:
            setUpdate(
                BackupProtoGroupAdminStatusUpdate(
                    memberAci: localAciData,
                    wasAdminStatusGranted: true
                ),
                setOptionalFields: {
                    $0.updaterAci = localAciData
                },
                asUpdate: { .groupAdminStatusUpdate($0) }
            )
        case .localUserWasGrantedAdministratorByOtherUser(let updaterAci):
            setUpdate(
                BackupProtoGroupAdminStatusUpdate(
                    memberAci: localAciData,
                    wasAdminStatusGranted: true
                ),
                setOptionalFields: {
                    $0.updaterAci = aciData(updaterAci)
                },
                asUpdate: { .groupAdminStatusUpdate($0) }
            )
        case .localUserWasGrantedAdministratorByUnknownUser:
            setUpdate(
                BackupProtoGroupAdminStatusUpdate(
                    memberAci: localAciData,
                    wasAdminStatusGranted: true
                ),
                asUpdate: { .groupAdminStatusUpdate($0) }
            )
        case .otherUserWasGrantedAdministratorByLocalUser(let userAci):
            setUpdate(
                BackupProtoGroupAdminStatusUpdate(
                    memberAci: aciData(userAci),
                    wasAdminStatusGranted: true
                ),
                setOptionalFields: {
                    $0.updaterAci = localAciData
                },
                asUpdate: { .groupAdminStatusUpdate($0) }
            )
        case .otherUserWasGrantedAdministratorByOtherUser(let updaterAci, let userAci):
            setUpdate(
                BackupProtoGroupAdminStatusUpdate(
                    memberAci: aciData(userAci),
                    wasAdminStatusGranted: true
                ),
                setOptionalFields: {
                    $0.updaterAci = aciData(updaterAci)
                },
                asUpdate: { .groupAdminStatusUpdate($0) }
            )
        case .otherUserWasGrantedAdministratorByUnknownUser(let userAci):
            setUpdate(
                BackupProtoGroupAdminStatusUpdate(
                    memberAci: aciData(userAci),
                    wasAdminStatusGranted: true
                ),
                asUpdate: { .groupAdminStatusUpdate($0) }
            )
        case .localUserWasRevokedAdministratorByLocalUser:
            setUpdate(
                BackupProtoGroupAdminStatusUpdate(
                    memberAci: localAciData,
                    wasAdminStatusGranted: false
                ),
                setOptionalFields: {
                    $0.updaterAci = localAciData
                },
                asUpdate: { .groupAdminStatusUpdate($0) }
            )
        case .localUserWasRevokedAdministratorByOtherUser(let updaterAci):
            setUpdate(
                BackupProtoGroupAdminStatusUpdate(
                    memberAci: localAciData,
                    wasAdminStatusGranted: false
                ),
                setOptionalFields: {
                    $0.updaterAci = aciData(updaterAci)
                },
                asUpdate: { .groupAdminStatusUpdate($0) }
            )
        case .localUserWasRevokedAdministratorByUnknownUser:
            setUpdate(
                BackupProtoGroupAdminStatusUpdate(
                    memberAci: localAciData,
                    wasAdminStatusGranted: false
                ),
                asUpdate: { .groupAdminStatusUpdate($0) }
            )
        case .otherUserWasRevokedAdministratorByLocalUser(let userAci):
            setUpdate(
                BackupProtoGroupAdminStatusUpdate(
                    memberAci: aciData(userAci),
                    wasAdminStatusGranted: false
                ),
                setOptionalFields: {
                    $0.updaterAci = localAciData
                },
                asUpdate: { .groupAdminStatusUpdate($0) }
            )
        case .otherUserWasRevokedAdministratorByOtherUser(let updaterAci, let userAci):
            setUpdate(
                BackupProtoGroupAdminStatusUpdate(
                    memberAci: aciData(userAci),
                    wasAdminStatusGranted: false
                ),
                setOptionalFields: {
                    $0.updaterAci = aciData(updaterAci)
                },
                asUpdate: { .groupAdminStatusUpdate($0) }
            )
        case .otherUserWasRevokedAdministratorByUnknownUser(let userAci):
            setUpdate(
                BackupProtoGroupAdminStatusUpdate(
                    memberAci: aciData(userAci),
                    wasAdminStatusGranted: false
                ),
                asUpdate: { .groupAdminStatusUpdate($0) }
            )
        case .localUserLeft:
            setUpdate(
                BackupProtoGroupMemberLeftUpdate(
                    aci: localAciData
                ),
                asUpdate: { .groupMemberLeftUpdate($0) }
            )
        case .localUserRemoved(let removerAci):
            setUpdate(
                BackupProtoGroupMemberRemovedUpdate(
                    removedAci: localAciData
                ),
                setOptionalFields: {
                    $0.removerAci = aciData(removerAci)
                },
                asUpdate: { .groupMemberRemovedUpdate($0) }
            )
        case .localUserRemovedByUnknownUser:
            setUpdate(
                BackupProtoGroupMemberRemovedUpdate(
                    removedAci: localAciData
                ),
                asUpdate: { .groupMemberRemovedUpdate($0) }
            )
        case .otherUserLeft(let userAci):
            setUpdate(
                BackupProtoGroupMemberLeftUpdate(
                    aci: aciData(userAci)
                ),
                asUpdate: { .groupMemberLeftUpdate($0) }
            )
        case .otherUserRemovedByLocalUser(let userAci):
            setUpdate(
                BackupProtoGroupMemberRemovedUpdate(
                    removedAci: aciData(userAci)
                ),
                setOptionalFields: {
                    $0.removerAci = localAciData
                },
                asUpdate: { .groupMemberRemovedUpdate($0) }
            )
        case .otherUserRemoved(let removerAci, let userAci):
            setUpdate(
                BackupProtoGroupMemberRemovedUpdate(
                    removedAci: aciData(userAci)
                ),
                setOptionalFields: {
                    $0.removerAci = aciData(removerAci)
                },
                asUpdate: { .groupMemberRemovedUpdate($0) }
            )
        case .otherUserRemovedByUnknownUser(let userAci):
            setUpdate(
                BackupProtoGroupMemberRemovedUpdate(
                    removedAci: aciData(userAci)
                ),
                asUpdate: { .groupMemberRemovedUpdate($0) }
            )
        case .localUserWasInvitedByLocalUser:
            setUpdate(
                BackupProtoSelfInvitedToGroupUpdate(),
                setOptionalFields: {
                    $0.inviterAci = localAciData
                },
                asUpdate: { .selfInvitedToGroupUpdate($0) }
            )
        case .localUserWasInvitedByOtherUser(let updaterAci):
            setUpdate(
                BackupProtoSelfInvitedToGroupUpdate(),
                setOptionalFields: {
                    $0.inviterAci = aciData(updaterAci)
                },
                asUpdate: { .selfInvitedToGroupUpdate($0) }
            )
        case .localUserWasInvitedByUnknownUser:
            setUpdate(
                BackupProtoSelfInvitedToGroupUpdate(),
                asUpdate: { .selfInvitedToGroupUpdate($0) }
            )
        case .otherUserWasInvitedByLocalUser(let inviteeServiceId):
            setUpdate(
                BackupProtoSelfInvitedOtherUserToGroupUpdate(
                    inviteeServiceId: serviceIdData(inviteeServiceId)
                ),
                asUpdate: { .selfInvitedOtherUserToGroupUpdate($0) }
            )
        case .unnamedUsersWereInvitedByLocalUser(let count):
            setUpdate(
                BackupProtoGroupUnknownInviteeUpdate(
                    inviteeCount: UInt32(clamping: count)
                ),
                setOptionalFields: {
                    $0.inviterAci = localAciData
                },
                asUpdate: { .groupUnknownInviteeUpdate($0) }
            )
        case .unnamedUsersWereInvitedByOtherUser(let updaterAci, let count):
            setUpdate(
                BackupProtoGroupUnknownInviteeUpdate(
                    inviteeCount: UInt32(clamping: count)
                ),
                setOptionalFields: {
                    $0.inviterAci = aciData(updaterAci)
                },
                asUpdate: { .groupUnknownInviteeUpdate($0) }
            )
        case .unnamedUsersWereInvitedByUnknownUser(let count):
            setUpdate(
                BackupProtoGroupUnknownInviteeUpdate(
                    inviteeCount: UInt32(clamping: count)
                ),
                asUpdate: { .groupUnknownInviteeUpdate($0) }
            )
        case .localUserAcceptedInviteFromInviter(let inviterAci):
            setUpdate(
                BackupProtoGroupInvitationAcceptedUpdate(
                    newMemberAci: localAciData
                ),
                setOptionalFields: {
                    $0.inviterAci = aciData(inviterAci)
                },
                asUpdate: { .groupInvitationAcceptedUpdate($0) }
            )
        case .localUserAcceptedInviteFromUnknownUser:
            setUpdate(
                BackupProtoGroupInvitationAcceptedUpdate(
                    newMemberAci: localAciData
                ),
                asUpdate: { .groupInvitationAcceptedUpdate($0) }
            )
        case .otherUserAcceptedInviteFromLocalUser(let userAci):
            setUpdate(
                BackupProtoGroupInvitationAcceptedUpdate(
                    newMemberAci: aciData(userAci)
                ),
                setOptionalFields: {
                    $0.inviterAci = localAciData
                },
                asUpdate: { .groupInvitationAcceptedUpdate($0) }
            )
        case .otherUserAcceptedInviteFromInviter(let userAci, let inviterAci):
            setUpdate(
                BackupProtoGroupInvitationAcceptedUpdate(
                    newMemberAci: aciData(userAci)
                ),
                setOptionalFields: {
                    $0.inviterAci = aciData(inviterAci)
                },
                asUpdate: { .groupInvitationAcceptedUpdate($0) }
            )
        case .otherUserAcceptedInviteFromUnknownUser(let userAci):
            setUpdate(
                BackupProtoGroupInvitationAcceptedUpdate(
                    newMemberAci: aciData(userAci)
                ),
                asUpdate: { .groupInvitationAcceptedUpdate($0) }
            )
        case .localUserJoined:
            setUpdate(
                BackupProtoGroupMemberJoinedUpdate(
                    newMemberAci: localAciData
                ),
                asUpdate: { .groupMemberJoinedUpdate($0) }
            )
        case .otherUserJoined(let userAci):
            setUpdate(
                BackupProtoGroupMemberJoinedUpdate(
                    newMemberAci: aciData(userAci)
                ),
                asUpdate: { .groupMemberJoinedUpdate($0) }
            )
        case .localUserAddedByLocalUser:
            setUpdate(
                BackupProtoGroupMemberAddedUpdate(
                    newMemberAci: localAciData,
                    // Note: on iOS we don't track if there was an invitation
                    // or who the inviter was.
                    hadOpenInvitation: false
                ),
                setOptionalFields: {
                    $0.updaterAci = localAciData
                },
                asUpdate: { .groupMemberAddedUpdate($0) }
            )
        case .localUserAddedByOtherUser(let updaterAci):
            setUpdate(
                BackupProtoGroupMemberAddedUpdate(
                    newMemberAci: localAciData,
                    // Note: on iOS we don't track if there was an invitation
                    // or who the inviter was.
                    hadOpenInvitation: false
                ),
                setOptionalFields: {
                    $0.updaterAci = aciData(updaterAci)
                },
                asUpdate: { .groupMemberAddedUpdate($0) }
            )
        case .localUserAddedByUnknownUser:
            setUpdate(
                BackupProtoGroupMemberAddedUpdate(
                    newMemberAci: localAciData,
                    // Note: on iOS we don't track if there was an invitation
                    // or who the inviter was.
                    hadOpenInvitation: false
                ),
                asUpdate: { .groupMemberAddedUpdate($0) }
            )
        case .otherUserAddedByLocalUser(let userAci):
            setUpdate(
                BackupProtoGroupMemberAddedUpdate(
                    newMemberAci: aciData(userAci),
                    // Note: on iOS we don't track if there was an invitation
                    // or who the inviter was.
                    hadOpenInvitation: false
                ),
                setOptionalFields: {
                    $0.updaterAci = localAciData
                },
                asUpdate: { .groupMemberAddedUpdate($0) }
            )
        case .otherUserAddedByOtherUser(let updaterAci, let userAci):
            setUpdate(
                BackupProtoGroupMemberAddedUpdate(
                    newMemberAci: aciData(userAci),
                    // Note: on iOS we don't track if there was an invitation
                    // or who the inviter was.
                    hadOpenInvitation: false
                ),
                setOptionalFields: {
                    $0.updaterAci = aciData(updaterAci)
                },
                asUpdate: { .groupMemberAddedUpdate($0) }
            )
        case .otherUserAddedByUnknownUser(let userAci):
            setUpdate(
                BackupProtoGroupMemberAddedUpdate(
                    newMemberAci: aciData(userAci),
                    // Note: on iOS we don't track if there was an invitation
                    // or who the inviter was.
                    hadOpenInvitation: false
                ),
                asUpdate: { .groupMemberAddedUpdate($0) }
            )
        case .localUserDeclinedInviteFromInviter(let inviterAci):
            setUpdate(
                BackupProtoGroupInvitationDeclinedUpdate(),
                setOptionalFields: {
                    $0.inviteeAci = localAciData
                    $0.inviterAci = aciData(inviterAci)
                },
                asUpdate: { .groupInvitationDeclinedUpdate($0) }
            )
        case .localUserDeclinedInviteFromUnknownUser:
            setUpdate(
                BackupProtoGroupInvitationDeclinedUpdate(),
                setOptionalFields: {
                    $0.inviteeAci = localAciData
                },
                asUpdate: { .groupInvitationDeclinedUpdate($0) }
            )
        case .otherUserDeclinedInviteFromLocalUser(let invitee):
            setUpdate(
                BackupProtoGroupInvitationDeclinedUpdate(),
                setOptionalFields: {
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
                BackupProtoGroupInvitationDeclinedUpdate(),
                setOptionalFields: {
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
                BackupProtoGroupInvitationDeclinedUpdate(),
                setOptionalFields: {
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
                BackupProtoGroupInvitationDeclinedUpdate(),
                setOptionalFields: {
                    $0.inviterAci = aciData(inviterAci)
                },
                asUpdate: { .groupInvitationDeclinedUpdate($0) }
            )
        case .unnamedUserDeclinedInviteFromUnknownUser:
            setUpdate(
                BackupProtoGroupInvitationDeclinedUpdate(),
                asUpdate: { .groupInvitationDeclinedUpdate($0) }
            )
        case .localUserInviteRevoked(let revokerAci):
            setUpdate(
                BackupProtoGroupSelfInvitationRevokedUpdate(),
                setOptionalFields: {
                    $0.revokerAci = aciData(revokerAci)
                },
                asUpdate: { .groupSelfInvitationRevokedUpdate($0) }
            )
        case .localUserInviteRevokedByUnknownUser:
            setUpdate(
                BackupProtoGroupSelfInvitationRevokedUpdate(),
                asUpdate: { .groupSelfInvitationRevokedUpdate($0) }
            )
        case .otherUserInviteRevokedByLocalUser(let invitee):
            var inviteeProto = BackupProtoGroupInvitationRevokedUpdate.BackupProtoInvitee()
            switch invitee.wrappedValue.concreteType {
            case .aci(let aci):
                inviteeProto.inviteeAci = aciData(aci.codableUuid)
            case .pni(let pni):
                inviteeProto.inviteePni = pniData(pni)
            }
            // Note: on iOS we don't keep who the inviter was.
            setUpdate(
                BackupProtoGroupInvitationRevokedUpdate(),
                setOptionalFields: {
                    $0.updaterAci = localAciData
                    $0.invitees = [inviteeProto]
                },
                asUpdate: { .groupInvitationRevokedUpdate($0) }
            )
        case .unnamedUserInvitesWereRevokedByLocalUser(let count):
            // All the invitees are empty; only their count matters.
            let invitees = buildEmptyRevokedInvitees(count: count)
            setUpdate(
                BackupProtoGroupInvitationRevokedUpdate(),
                setOptionalFields: {
                    $0.updaterAci = localAciData
                    $0.invitees = invitees
                },
                asUpdate: { .groupInvitationRevokedUpdate($0) }
            )
        case .unnamedUserInvitesWereRevokedByOtherUser(let updaterAci, let count):
            // All the invitees are empty; only their count matters.
            let invitees = buildEmptyRevokedInvitees(count: count)
            setUpdate(
                BackupProtoGroupInvitationRevokedUpdate(),
                setOptionalFields: {
                    $0.updaterAci = aciData(updaterAci)
                    $0.invitees = invitees
                },
                asUpdate: { .groupInvitationRevokedUpdate($0) }
            )
        case .unnamedUserInvitesWereRevokedByUnknownUser(let count):
            // All the invitees are empty; only their count matters.
            let invitees = buildEmptyRevokedInvitees(count: count)
            setUpdate(
                BackupProtoGroupInvitationRevokedUpdate(),
                setOptionalFields: {
                    $0.invitees = invitees
                },
                asUpdate: { .groupInvitationRevokedUpdate($0) }
            )
        case .localUserRequestedToJoin:
            setUpdate(
                BackupProtoGroupJoinRequestUpdate(
                    requestorAci: localAciData
                ),
                asUpdate: { .groupJoinRequestUpdate($0) }
            )
        case .otherUserRequestedToJoin(let userAci):
            setUpdate(
                BackupProtoGroupJoinRequestUpdate(
                    requestorAci: aciData(userAci)
                ),
                asUpdate: { .groupJoinRequestUpdate($0) }
            )
        case .localUserRequestApproved(let approverAci):
            setUpdate(
                BackupProtoGroupJoinRequestApprovalUpdate(
                    requestorAci: localAciData,
                    wasApproved: true
                ),
                setOptionalFields: {
                    $0.updaterAci = aciData(approverAci)
                },
                asUpdate: { .groupJoinRequestApprovalUpdate($0) }
            )
        case .localUserRequestApprovedByUnknownUser:
            setUpdate(
                BackupProtoGroupJoinRequestApprovalUpdate(
                    requestorAci: localAciData,
                    wasApproved: true
                ),
                asUpdate: { .groupJoinRequestApprovalUpdate($0) }
            )
        case .otherUserRequestApprovedByLocalUser(let userAci):
            setUpdate(
                BackupProtoGroupJoinRequestApprovalUpdate(
                    requestorAci: aciData(userAci),
                    wasApproved: true
                ),
                setOptionalFields: {
                    $0.updaterAci = localAciData
                },
                asUpdate: { .groupJoinRequestApprovalUpdate($0) }
            )
        case .otherUserRequestApproved(let userAci, let approverAci):
            setUpdate(
                BackupProtoGroupJoinRequestApprovalUpdate(
                    requestorAci: aciData(userAci),
                    wasApproved: true
                ),
                setOptionalFields: {
                    $0.updaterAci = aciData(approverAci)
                },
                asUpdate: { .groupJoinRequestApprovalUpdate($0) }
            )
        case .otherUserRequestApprovedByUnknownUser(let userAci):
            setUpdate(
                BackupProtoGroupJoinRequestApprovalUpdate(
                    requestorAci: aciData(userAci),
                    wasApproved: true
                ),
                asUpdate: { .groupJoinRequestApprovalUpdate($0) }
            )
        case .localUserRequestCanceledByLocalUser:
            setUpdate(
                BackupProtoGroupJoinRequestCanceledUpdate(
                    requestorAci: localAciData
                ),
                asUpdate: { .groupJoinRequestCanceledUpdate($0) }
            )
        case .localUserRequestRejectedByUnknownUser:
            setUpdate(
                BackupProtoGroupJoinRequestApprovalUpdate(
                    requestorAci: localAciData,
                    wasApproved: false
                ),
                asUpdate: { .groupJoinRequestApprovalUpdate($0) }
            )
        case .otherUserRequestRejectedByLocalUser(let requesterAci):
            setUpdate(
                BackupProtoGroupJoinRequestApprovalUpdate(
                    requestorAci: aciData(requesterAci),
                    wasApproved: false
                ),
                setOptionalFields: {
                    $0.updaterAci = localAciData
                },
                asUpdate: { .groupJoinRequestApprovalUpdate($0) }
            )
        case .otherUserRequestRejectedByOtherUser(let updaterAci, let requesterAci):
            setUpdate(
                BackupProtoGroupJoinRequestApprovalUpdate(
                    requestorAci: aciData(requesterAci),
                    wasApproved: false
                ),
                setOptionalFields: {
                    $0.updaterAci = aciData(updaterAci)
                },
                asUpdate: { .groupJoinRequestApprovalUpdate($0) }
            )
        case .otherUserRequestCanceledByOtherUser(let requesterAci):
            setUpdate(
                BackupProtoGroupJoinRequestCanceledUpdate(
                    requestorAci: aciData(requesterAci)
                ),
                asUpdate: { .groupJoinRequestCanceledUpdate($0) }
            )
        case .otherUserRequestRejectedByUnknownUser(let requesterAci):
            setUpdate(
                BackupProtoGroupJoinRequestApprovalUpdate(
                    requestorAci: aciData(requesterAci),
                    wasApproved: false
                ),
                asUpdate: { .groupJoinRequestApprovalUpdate($0) }
            )
        case .disappearingMessagesEnabledByLocalUser(let durationMs):
            let expiresInMs = UInt32(clamping: durationMs)
            setUpdate(
                BackupProtoGroupExpirationTimerUpdate(
                    expiresInMs: expiresInMs
                ),
                setOptionalFields: {
                    $0.updaterAci = localAciData
                },
                asUpdate: { .groupExpirationTimerUpdate($0) }
            )
        case .disappearingMessagesEnabledByOtherUser(let updaterAci, let durationMs):
            let expiresInMs = UInt32(clamping: durationMs)
            setUpdate(
                BackupProtoGroupExpirationTimerUpdate(
                    expiresInMs: expiresInMs
                ),
                setOptionalFields: {
                    $0.updaterAci = aciData(updaterAci)
                },
                asUpdate: { .groupExpirationTimerUpdate($0) }
            )
        case .disappearingMessagesEnabledByUnknownUser(let durationMs):
            let expiresInMs = UInt32(clamping: durationMs)
            setUpdate(
                BackupProtoGroupExpirationTimerUpdate(
                    expiresInMs: expiresInMs
                ),
                asUpdate: { .groupExpirationTimerUpdate($0) }
            )
        case .disappearingMessagesDisabledByLocalUser:
            setUpdate(
                BackupProtoGroupExpirationTimerUpdate(
                    // 0 means disabled.
                    expiresInMs: 0
                ),
                setOptionalFields: {
                    $0.updaterAci = localAciData
                },
                asUpdate: { .groupExpirationTimerUpdate($0) }
            )
        case .disappearingMessagesDisabledByOtherUser(let updaterAci):
            setUpdate(
                BackupProtoGroupExpirationTimerUpdate(
                    // 0 means disabled.
                    expiresInMs: 0
                ),
                setOptionalFields: {
                    $0.updaterAci = aciData(updaterAci)
                },
                asUpdate: { .groupExpirationTimerUpdate($0) }
            )
        case .disappearingMessagesDisabledByUnknownUser:
            setUpdate(
                BackupProtoGroupExpirationTimerUpdate(
                    // 0 means disabled.
                    expiresInMs: 0
                ),
                asUpdate: { .groupExpirationTimerUpdate($0) }
            )
        case .inviteLinkResetByLocalUser:
            setUpdate(
                BackupProtoGroupInviteLinkResetUpdate(),
                setOptionalFields: {
                    $0.updaterAci = localAciData
                },
                asUpdate: { .groupInviteLinkResetUpdate($0) }
            )
        case .inviteLinkResetByOtherUser(let updaterAci):
            setUpdate(
                BackupProtoGroupInviteLinkResetUpdate(),
                setOptionalFields: {
                    $0.updaterAci = aciData(updaterAci)
                },
                asUpdate: { .groupInviteLinkResetUpdate($0) }
            )
        case .inviteLinkResetByUnknownUser:
            setUpdate(
                BackupProtoGroupInviteLinkResetUpdate(),
                asUpdate: { .groupInviteLinkResetUpdate($0) }
            )
        case .inviteLinkEnabledWithoutApprovalByLocalUser:
            setUpdate(
                BackupProtoGroupInviteLinkEnabledUpdate(
                    linkRequiresAdminApproval: false
                ),
                setOptionalFields: {
                    $0.updaterAci = localAciData
                },
                asUpdate: { .groupInviteLinkEnabledUpdate($0) }
            )
        case .inviteLinkEnabledWithoutApprovalByOtherUser(let updaterAci):
            setUpdate(
                BackupProtoGroupInviteLinkEnabledUpdate(
                    linkRequiresAdminApproval: false
                ),
                setOptionalFields: {
                    $0.updaterAci = aciData(updaterAci)
                },
                asUpdate: { .groupInviteLinkEnabledUpdate($0) }
            )
        case .inviteLinkEnabledWithoutApprovalByUnknownUser:
            setUpdate(
                BackupProtoGroupInviteLinkEnabledUpdate(
                    linkRequiresAdminApproval: false
                ),
                asUpdate: { .groupInviteLinkEnabledUpdate($0) }
            )
        case .inviteLinkEnabledWithApprovalByLocalUser:
            setUpdate(
                BackupProtoGroupInviteLinkEnabledUpdate(
                    linkRequiresAdminApproval: true
                ),
                setOptionalFields: {
                    $0.updaterAci = localAciData
                },
                asUpdate: { .groupInviteLinkEnabledUpdate($0) }
            )
        case .inviteLinkEnabledWithApprovalByOtherUser(let updaterAci):
            setUpdate(
                BackupProtoGroupInviteLinkEnabledUpdate(
                    linkRequiresAdminApproval: true
                ),
                setOptionalFields: {
                    $0.updaterAci = aciData(updaterAci)
                },
                asUpdate: { .groupInviteLinkEnabledUpdate($0) }
            )
        case .inviteLinkEnabledWithApprovalByUnknownUser:
            setUpdate(
                BackupProtoGroupInviteLinkEnabledUpdate(
                    linkRequiresAdminApproval: true
                ),
                asUpdate: { .groupInviteLinkEnabledUpdate($0) }
            )
        case .inviteLinkDisabledByLocalUser:
            setUpdate(
                BackupProtoGroupInviteLinkDisabledUpdate(),
                setOptionalFields: {
                    $0.updaterAci = localAciData
                },
                asUpdate: { .groupInviteLinkDisabledUpdate($0) }
            )
        case .inviteLinkDisabledByOtherUser(let updaterAci):
            setUpdate(
                BackupProtoGroupInviteLinkDisabledUpdate(),
                setOptionalFields: {
                    $0.updaterAci = aciData(updaterAci)
                },
                asUpdate: { .groupInviteLinkDisabledUpdate($0) }
            )
        case .inviteLinkDisabledByUnknownUser:
            setUpdate(
                BackupProtoGroupInviteLinkDisabledUpdate(),
                asUpdate: { .groupInviteLinkDisabledUpdate($0) }
            )
        case .inviteLinkApprovalDisabledByLocalUser:
            setUpdate(
                BackupProtoGroupInviteLinkAdminApprovalUpdate(
                    linkRequiresAdminApproval: false
                ),
                setOptionalFields: {
                    $0.updaterAci = localAciData
                },
                asUpdate: { .groupInviteLinkAdminApprovalUpdate($0) }
            )
        case .inviteLinkApprovalDisabledByOtherUser(let updaterAci):
            setUpdate(
                BackupProtoGroupInviteLinkAdminApprovalUpdate(
                    linkRequiresAdminApproval: false
                ),
                setOptionalFields: {
                    $0.updaterAci = aciData(updaterAci)
                },
                asUpdate: { .groupInviteLinkAdminApprovalUpdate($0) }
            )
        case .inviteLinkApprovalDisabledByUnknownUser:
            setUpdate(
                BackupProtoGroupInviteLinkAdminApprovalUpdate(
                    linkRequiresAdminApproval: false
                ),
                asUpdate: { .groupInviteLinkAdminApprovalUpdate($0) }
            )
        case .inviteLinkApprovalEnabledByLocalUser:
            setUpdate(
                BackupProtoGroupInviteLinkAdminApprovalUpdate(
                    linkRequiresAdminApproval: true
                ),
                setOptionalFields: {
                    $0.updaterAci = localAciData
                },
                asUpdate: { .groupInviteLinkAdminApprovalUpdate($0) }
            )
        case .inviteLinkApprovalEnabledByOtherUser(let updaterAci):
            setUpdate(
                BackupProtoGroupInviteLinkAdminApprovalUpdate(
                    linkRequiresAdminApproval: true
                ),
                setOptionalFields: {
                    $0.updaterAci = aciData(updaterAci)
                },
                asUpdate: { .groupInviteLinkAdminApprovalUpdate($0) }
            )
        case .inviteLinkApprovalEnabledByUnknownUser:
            setUpdate(
                BackupProtoGroupInviteLinkAdminApprovalUpdate(
                    linkRequiresAdminApproval: true
                ),
                asUpdate: { .groupInviteLinkAdminApprovalUpdate($0) }
            )
        case .localUserJoinedViaInviteLink:
            setUpdate(
                BackupProtoGroupMemberJoinedByLinkUpdate(
                    newMemberAci: localAciData
                ),
                asUpdate: { .groupMemberJoinedByLinkUpdate($0) }
            )
        case .otherUserJoinedViaInviteLink(let userAci):
            setUpdate(
                BackupProtoGroupMemberJoinedByLinkUpdate(
                    newMemberAci: aciData(userAci)
                ),
                asUpdate: { .groupMemberJoinedByLinkUpdate($0) }
            )
        }

        return .success(update)
    }
}

extension GroupV2Access {

    fileprivate var backupAccessLevel: BackupProtoGroupV2AccessLevel {
        switch self {
        case .unknown:
            return .UNKNOWN
        case .any:
            return .ANY
        case .member:
            return .MEMBER
        case .administrator:
            return .ADMINISTRATOR
        case .unsatisfiable:
            return .UNSATISFIABLE
        }
    }
}
