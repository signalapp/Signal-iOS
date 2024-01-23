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
    ) throws -> [BackupProtoGroupInvitationRevokedUpdateInvitee] {
        // All the invitees are empty; only their count matters.
        var invitees = [BackupProtoGroupInvitationRevokedUpdateInvitee]()
        for _ in 0..<count {
            let invitee = try BackupProtoGroupInvitationRevokedUpdateInvitee
                .builder()
                .build()
            invitees.append(invitee)
        }
        return invitees
    }

    // MARK: - Enum cases

    internal static func archiveGroupUpdate(
        groupUpdate: TSInfoMessage.PersistableGroupUpdateItem,
        // We should never be putting our pni in the backup as it can change,
        // we only ever insert our aci and use special cases for our pni.
        localUserAci: Aci,
        interactionId: MessageBackup.InteractionUniqueId
    ) -> MessageBackup.ArchiveInteractionResult<BackupProtoGroupChangeChatUpdateUpdate> {
        var localAciData = localUserAci.rawUUID.data
        func aciData(_ aci: AciUuid) -> Data {
            return aci.wrappedValue.rawUUID.data
        }
        func pniData(_ pni: Pni) -> Data {
            return pni.rawUUID.data
        }
        func serviceIdData(_ serviceId: ServiceIdUppercaseString) -> Data {
            return serviceId.wrappedValue.serviceIdBinary.asData
        }

        let updateBuilder = BackupProtoGroupChangeChatUpdateUpdate.builder()

        var protoBuildError: MessageBackup.RawError?

        func setUpdate<Proto, Builder>(
            _ builder: Builder,
            setOptionalFields: ((Builder) -> Void)? = nil,
            build: (Builder) -> () throws -> Proto,
            set: (BackupProtoGroupChangeChatUpdateUpdateBuilder) -> (Proto) -> Void
        ) {
            do {
                setOptionalFields?(builder)
                let proto = try build(builder)()
                set(updateBuilder)(proto)
            } catch let error {
                protoBuildError = error
            }
        }
        switch groupUpdate {
        case .sequenceOfInviteLinkRequestAndCancels(let requester, let count, _):
            // Note: isTail is dropped from the backup.
            // It is reconstructed at restore time from the presence, or lack thereof,
            // of a subsequent join request.
            if count == 0 {
                // If the count is 0, its actually just a request to join.
                setUpdate(
                    BackupProtoGroupJoinRequestUpdate.builder(
                        requestorAci: aciData(requester)
                    ),
                    build: { $0.build },
                    set: { $0.setGroupJoinRequestUpdate(_:) }
                )
            } else {
                setUpdate(
                    BackupProtoGroupSequenceOfRequestsAndCancelsUpdate.builder(
                        requestorAci: aciData(requester),
                        count: .init(clamping: count)
                    ),
                    build: { $0.build },
                    set: { $0.setGroupSequenceOfRequestsAndCancelsUpdate }
                )
            }
        case .invitedPniPromotedToFullMemberAci(let newMember, let inviter):
            setUpdate(
                BackupProtoGroupInvitationAcceptedUpdate.builder(
                    newMemberAci: aciData(newMember)
                ),
                setOptionalFields: {
                    if let inviter {
                        $0.setInviterAci(aciData(inviter))
                    }
                },
                build: { $0.build },
                set: { $0.setGroupInvitationAcceptedUpdate }
            )
        case .genericUpdateByLocalUser:
            setUpdate(
                BackupProtoGenericGroupUpdate.builder(),
                setOptionalFields: {
                    $0.setUpdaterAci(localAciData)
                },
                build: { $0.build },
                set: { $0.setGenericGroupUpdate(_:) }
            )
        case .genericUpdateByOtherUser(let updaterAci):
            setUpdate(
                BackupProtoGenericGroupUpdate.builder(),
                setOptionalFields: {
                    $0.setUpdaterAci(aciData(updaterAci))
                },
                build: { $0.build },
                set: { $0.setGenericGroupUpdate(_:) }
            )
        case .genericUpdateByUnknownUser:
            setUpdate(
                BackupProtoGenericGroupUpdate.builder(),
                build: { $0.build },
                set: { $0.setGenericGroupUpdate(_:) }
            )
        case .createdByLocalUser:
            setUpdate(
                BackupProtoGroupCreationUpdate.builder(),
                setOptionalFields: {
                    $0.setUpdaterAci(localAciData)
                },
                build: { $0.build },
                set: { $0.setGroupCreationUpdate(_:) }
            )
        case .createdByOtherUser(let updaterAci):
            setUpdate(
                BackupProtoGroupCreationUpdate.builder(),
                setOptionalFields: {
                    $0.setUpdaterAci(aciData(updaterAci))
                },
                build: { $0.build },
                set: { $0.setGroupCreationUpdate(_:) }
            )
        case .createdByUnknownUser:
            setUpdate(
                BackupProtoGroupCreationUpdate.builder(),
                build: { $0.build },
                set: { $0.setGroupCreationUpdate(_:) }
            )
        case .inviteFriendsToNewlyCreatedGroup:
            // This specific one is ignored for purposes of backups.
            // At restore time, it is created alongside the `createdByLocalUser`
            // case if we find that in the backup.
            return .skippableGroupUpdate(.inviteFriendsToNewlyCreatedGroup)
        case .wasMigrated:
            setUpdate(
                BackupProtoGroupV2MigrationUpdate.builder(),
                build: { $0.build },
                set: { $0.setGroupV2MigrationUpdate(_:) }
            )
        case .localUserInvitedAfterMigration:
            setUpdate(
                BackupProtoGroupV2MigrationSelfInvitedUpdate.builder(),
                build: { $0.build },
                set: { $0.setGroupV2MigrationSelfInvitedUpdate(_:) }
            )
        case .otherUsersInvitedAfterMigration(let count):
            setUpdate(
                BackupProtoGroupV2MigrationInvitedMembersUpdate.builder(
                    invitedMembersCount: .init(clamping: count)
                ),
                build: { $0.build },
                set: { $0.setGroupV2MigrationInvitedMembersUpdate(_:) }
            )
        case .otherUsersDroppedAfterMigration(let count):
            setUpdate(
                BackupProtoGroupV2MigrationDroppedMembersUpdate.builder(
                    droppedMembersCount: .init(clamping: count)
                ),
                build: { $0.build },
                set: { $0.setGroupV2MigrationDroppedMembersUpdate(_:) }
            )
        case .nameChangedByLocalUser(let newGroupName):
            setUpdate(
                BackupProtoGroupNameUpdate.builder(),
                setOptionalFields: {
                    $0.setNewGroupName(newGroupName)
                    $0.setUpdaterAci(localAciData)
                },
                build: { $0.build },
                set: { $0.setGroupNameUpdate(_:) }
            )
        case .nameChangedByOtherUser(let updaterAci, let newGroupName):
            setUpdate(
                BackupProtoGroupNameUpdate.builder(),
                setOptionalFields: {
                    $0.setNewGroupName(newGroupName)
                    $0.setUpdaterAci(aciData(updaterAci))
                },
                build: { $0.build },
                set: { $0.setGroupNameUpdate(_:) }
            )
        case .nameChangedByUnknownUser(let newGroupName):
            setUpdate(
                BackupProtoGroupNameUpdate.builder(),
                setOptionalFields: {
                    $0.setNewGroupName(newGroupName)
                },
                build: { $0.build },
                set: { $0.setGroupNameUpdate(_:) }
            )
        case .nameRemovedByLocalUser:
            setUpdate(
                BackupProtoGroupNameUpdate.builder(),
                setOptionalFields: {
                    // nil group name means removed.
                    $0.setUpdaterAci(localAciData)
                },
                build: { $0.build },
                set: { $0.setGroupNameUpdate(_:) }
            )
        case .nameRemovedByOtherUser(let updaterAci):
            setUpdate(
                BackupProtoGroupNameUpdate.builder(),
                setOptionalFields: {
                    // nil group name means removed.
                    $0.setUpdaterAci(aciData(updaterAci))
                },
                build: { $0.build },
                set: { $0.setGroupNameUpdate(_:) }
            )
        case .nameRemovedByUnknownUser:
            setUpdate(
                BackupProtoGroupNameUpdate.builder(),
                // nil group name means removed, updater unknown.
                // nothing to set.
                build: { $0.build },
                set: { $0.setGroupNameUpdate(_:) }
            )
        case .avatarChangedByLocalUser:
            setUpdate(
                BackupProtoGroupAvatarUpdate.builder(wasRemoved: false),
                setOptionalFields: {
                    $0.setUpdaterAci(localAciData)
                },
                build: { $0.build },
                set: { $0.setGroupAvatarUpdate(_:) }
            )
        case .avatarChangedByOtherUser(let updaterAci):
            setUpdate(
                BackupProtoGroupAvatarUpdate.builder(wasRemoved: false),
                setOptionalFields: {
                    $0.setUpdaterAci(aciData(updaterAci))
                },
                build: { $0.build },
                set: { $0.setGroupAvatarUpdate(_:) }
            )
        case .avatarChangedByUnknownUser:
            setUpdate(
                BackupProtoGroupAvatarUpdate.builder(wasRemoved: false),
                build: { $0.build },
                set: { $0.setGroupAvatarUpdate(_:) }
            )
        case .avatarRemovedByLocalUser:
            setUpdate(
                BackupProtoGroupAvatarUpdate.builder(wasRemoved: true),
                setOptionalFields: {
                    $0.setUpdaterAci(localAciData)
                },
                build: { $0.build },
                set: { $0.setGroupAvatarUpdate(_:) }
            )
        case .avatarRemovedByOtherUser(let updaterAci):
            setUpdate(
                BackupProtoGroupAvatarUpdate.builder(wasRemoved: true),
                setOptionalFields: {
                    $0.setUpdaterAci(aciData(updaterAci))
                },
                build: { $0.build },
                set: { $0.setGroupAvatarUpdate(_:) }
            )
        case .avatarRemovedByUnknownUser:
            setUpdate(
                BackupProtoGroupAvatarUpdate.builder(wasRemoved: true),
                build: { $0.build },
                set: { $0.setGroupAvatarUpdate(_:) }
            )
        case .descriptionChangedByLocalUser(let newDescription):
            setUpdate(
                BackupProtoGroupDescriptionUpdate.builder(),
                setOptionalFields: {
                    $0.setNewDescription(newDescription)
                    $0.setUpdaterAci(localAciData)
                },
                build: { $0.build },
                set: { $0.setGroupDescriptionUpdate(_:) }
            )
        case .descriptionChangedByOtherUser(let updaterAci, let newDescription):
            setUpdate(
                BackupProtoGroupDescriptionUpdate.builder(),
                setOptionalFields: {
                    $0.setNewDescription(newDescription)
                    $0.setUpdaterAci(aciData(updaterAci))
                },
                build: { $0.build },
                set: { $0.setGroupDescriptionUpdate(_:) }
            )
        case .descriptionChangedByUnknownUser(let newDescription):
            setUpdate(
                BackupProtoGroupDescriptionUpdate.builder(),
                setOptionalFields: {
                    $0.setNewDescription(newDescription)
                },
                build: { $0.build },
                set: { $0.setGroupDescriptionUpdate(_:) }
            )
        case .descriptionRemovedByLocalUser:
            setUpdate(
                BackupProtoGroupDescriptionUpdate.builder(),
                setOptionalFields: {
                    // nil group description means removed.
                    $0.setUpdaterAci(localAciData)
                },
                build: { $0.build },
                set: { $0.setGroupDescriptionUpdate(_:) }
            )
        case .descriptionRemovedByOtherUser(let updaterAci):
            setUpdate(
                BackupProtoGroupDescriptionUpdate.builder(),
                setOptionalFields: {
                    // nil group name means removed.
                    $0.setUpdaterAci(aciData(updaterAci))
                },
                build: { $0.build },
                set: { $0.setGroupDescriptionUpdate(_:) }
            )
        case .descriptionRemovedByUnknownUser:
            setUpdate(
                BackupProtoGroupDescriptionUpdate.builder(),
                // nil group description means removed, updater unknown.
                // nothing to set.
                build: { $0.build },
                set: { $0.setGroupDescriptionUpdate(_:) }
            )
        case .membersAccessChangedByLocalUser(let newAccess):
            setUpdate(
                BackupProtoGroupMembershipAccessLevelChangeUpdate.builder(),
                setOptionalFields: {
                    $0.setUpdaterAci(localAciData)
                    $0.setAccessLevel(newAccess.backupAccessLevel)
                },
                build: { $0.build },
                set: { $0.setGroupMembershipAccessLevelChangeUpdate(_:) }
            )
        case .membersAccessChangedByOtherUser(let updaterAci, let newAccess):
            setUpdate(
                BackupProtoGroupMembershipAccessLevelChangeUpdate.builder(),
                setOptionalFields: {
                    $0.setUpdaterAci(aciData(updaterAci))
                    $0.setAccessLevel(newAccess.backupAccessLevel)
                },
                build: { $0.build },
                set: { $0.setGroupMembershipAccessLevelChangeUpdate(_:) }
            )
        case .membersAccessChangedByUnknownUser(let newAccess):
            setUpdate(
                BackupProtoGroupMembershipAccessLevelChangeUpdate.builder(),
                setOptionalFields: {
                    $0.setAccessLevel(newAccess.backupAccessLevel)
                },
                build: { $0.build },
                set: { $0.setGroupMembershipAccessLevelChangeUpdate(_:) }
            )
        case .attributesAccessChangedByLocalUser(let newAccess):
            setUpdate(
                BackupProtoGroupAttributesAccessLevelChangeUpdate.builder(),
                setOptionalFields: {
                    $0.setUpdaterAci(localAciData)
                    $0.setAccessLevel(newAccess.backupAccessLevel)
                },
                build: { $0.build },
                set: { $0.setGroupAttributesAccessLevelChangeUpdate(_:) }
            )
        case .attributesAccessChangedByOtherUser(let updaterAci, let newAccess):
            setUpdate(
                BackupProtoGroupAttributesAccessLevelChangeUpdate.builder(),
                setOptionalFields: {
                    $0.setUpdaterAci(aciData(updaterAci))
                    $0.setAccessLevel(newAccess.backupAccessLevel)
                },
                build: { $0.build },
                set: { $0.setGroupAttributesAccessLevelChangeUpdate }
            )
        case .attributesAccessChangedByUnknownUser(let newAccess):
            setUpdate(
                BackupProtoGroupAttributesAccessLevelChangeUpdate.builder(),
                setOptionalFields: {
                    $0.setAccessLevel(newAccess.backupAccessLevel)
                },
                build: { $0.build },
                set: { $0.setGroupAttributesAccessLevelChangeUpdate }
            )
        case .announcementOnlyEnabledByLocalUser:
            setUpdate(
                BackupProtoGroupAnnouncementOnlyChangeUpdate.builder(isAnnouncementOnly: true),
                setOptionalFields: {
                    $0.setUpdaterAci(localAciData)
                },
                build: { $0.build },
                set: { $0.setGroupAnnouncementOnlyChangeUpdate(_:) }
            )
        case .announcementOnlyEnabledByOtherUser(let updaterAci):
            setUpdate(
                BackupProtoGroupAnnouncementOnlyChangeUpdate.builder(isAnnouncementOnly: true),
                setOptionalFields: {
                    $0.setUpdaterAci(aciData(updaterAci))
                },
                build: { $0.build },
                set: { $0.setGroupAnnouncementOnlyChangeUpdate(_:) }
            )
        case .announcementOnlyEnabledByUnknownUser:
            setUpdate(
                BackupProtoGroupAnnouncementOnlyChangeUpdate.builder(isAnnouncementOnly: true),
                build: { $0.build },
                set: { $0.setGroupAnnouncementOnlyChangeUpdate(_:) }
            )
        case .announcementOnlyDisabledByLocalUser:
            setUpdate(
                BackupProtoGroupAnnouncementOnlyChangeUpdate.builder(isAnnouncementOnly: false),
                setOptionalFields: {
                    $0.setUpdaterAci(localAciData)
                },
                build: { $0.build },
                set: { $0.setGroupAnnouncementOnlyChangeUpdate(_:) }
            )
        case .announcementOnlyDisabledByOtherUser(let updaterAci):
            setUpdate(
                BackupProtoGroupAnnouncementOnlyChangeUpdate.builder(isAnnouncementOnly: false),
                setOptionalFields: {
                    $0.setUpdaterAci(aciData(updaterAci))
                },
                build: { $0.build },
                set: { $0.setGroupAnnouncementOnlyChangeUpdate(_:) }
            )
        case .announcementOnlyDisabledByUnknownUser:
            setUpdate(
                BackupProtoGroupAnnouncementOnlyChangeUpdate.builder(isAnnouncementOnly: false),
                build: { $0.build },
                set: { $0.setGroupAnnouncementOnlyChangeUpdate(_:) }
            )
        case .localUserWasGrantedAdministratorByLocalUser:
            setUpdate(
                BackupProtoGroupAdminStatusUpdate.builder(
                    memberAci: localAciData,
                    wasAdminStatusGranted: true
                ),
                setOptionalFields: {
                    $0.setUpdaterAci(localAciData)
                },
                build: { $0.build },
                set: { $0.setGroupAdminStatusUpdate(_:) }
            )
        case .localUserWasGrantedAdministratorByOtherUser(let updaterAci):
            setUpdate(
                BackupProtoGroupAdminStatusUpdate.builder(
                    memberAci: localAciData,
                    wasAdminStatusGranted: true
                ),
                setOptionalFields: {
                    $0.setUpdaterAci(aciData(updaterAci))
                },
                build: { $0.build },
                set: { $0.setGroupAdminStatusUpdate(_:) }
            )
        case .localUserWasGrantedAdministratorByUnknownUser:
            setUpdate(
                BackupProtoGroupAdminStatusUpdate.builder(
                    memberAci: localAciData,
                    wasAdminStatusGranted: true
                ),
                build: { $0.build },
                set: { $0.setGroupAdminStatusUpdate(_:) }
            )
        case .otherUserWasGrantedAdministratorByLocalUser(let userAci):
            setUpdate(
                BackupProtoGroupAdminStatusUpdate.builder(
                    memberAci: aciData(userAci),
                    wasAdminStatusGranted: true
                ),
                setOptionalFields: {
                    $0.setUpdaterAci(localAciData)
                },
                build: { $0.build },
                set: { $0.setGroupAdminStatusUpdate(_:) }
            )
        case .otherUserWasGrantedAdministratorByOtherUser(let updaterAci, let userAci):
            setUpdate(
                BackupProtoGroupAdminStatusUpdate.builder(
                    memberAci: aciData(userAci),
                    wasAdminStatusGranted: true
                ),
                setOptionalFields: {
                    $0.setUpdaterAci(aciData(updaterAci))
                },
                build: { $0.build },
                set: { $0.setGroupAdminStatusUpdate(_:) }
            )
        case .otherUserWasGrantedAdministratorByUnknownUser(let userAci):
            setUpdate(
                BackupProtoGroupAdminStatusUpdate.builder(
                    memberAci: aciData(userAci),
                    wasAdminStatusGranted: true
                ),
                build: { $0.build },
                set: { $0.setGroupAdminStatusUpdate(_:) }
            )
        case .localUserWasRevokedAdministratorByLocalUser:
            setUpdate(
                BackupProtoGroupAdminStatusUpdate.builder(
                    memberAci: localAciData,
                    wasAdminStatusGranted: false
                ),
                setOptionalFields: {
                    $0.setUpdaterAci(localAciData)
                },
                build: { $0.build },
                set: { $0.setGroupAdminStatusUpdate(_:) }
            )
        case .localUserWasRevokedAdministratorByOtherUser(let updaterAci):
            setUpdate(
                BackupProtoGroupAdminStatusUpdate.builder(
                    memberAci: localAciData,
                    wasAdminStatusGranted: false
                ),
                setOptionalFields: {
                    $0.setUpdaterAci(aciData(updaterAci))
                },
                build: { $0.build },
                set: { $0.setGroupAdminStatusUpdate(_:) }
            )
        case .localUserWasRevokedAdministratorByUnknownUser:
            setUpdate(
                BackupProtoGroupAdminStatusUpdate.builder(
                    memberAci: localAciData,
                    wasAdminStatusGranted: false
                ),
                build: { $0.build },
                set: { $0.setGroupAdminStatusUpdate(_:) }
            )
        case .otherUserWasRevokedAdministratorByLocalUser(let userAci):
            setUpdate(
                BackupProtoGroupAdminStatusUpdate.builder(
                    memberAci: aciData(userAci),
                    wasAdminStatusGranted: false
                ),
                setOptionalFields: {
                    $0.setUpdaterAci(localAciData)
                },
                build: { $0.build },
                set: { $0.setGroupAdminStatusUpdate(_:) }
            )
        case .otherUserWasRevokedAdministratorByOtherUser(let updaterAci, let userAci):
            setUpdate(
                BackupProtoGroupAdminStatusUpdate.builder(
                    memberAci: aciData(userAci),
                    wasAdminStatusGranted: false
                ),
                setOptionalFields: {
                    $0.setUpdaterAci(aciData(updaterAci))
                },
                build: { $0.build },
                set: { $0.setGroupAdminStatusUpdate(_:) }
            )
        case .otherUserWasRevokedAdministratorByUnknownUser(let userAci):
            setUpdate(
                BackupProtoGroupAdminStatusUpdate.builder(
                    memberAci: aciData(userAci),
                    wasAdminStatusGranted: false
                ),
                build: { $0.build },
                set: { $0.setGroupAdminStatusUpdate(_:) }
            )
        case .localUserLeft:
            setUpdate(
                BackupProtoGroupMemberLeftUpdate.builder(
                    aci: localAciData
                ),
                build: { $0.build },
                set: { $0.setGroupMemberLeftUpdate(_:) }
            )
        case .localUserRemoved(let removerAci):
            setUpdate(
                BackupProtoGroupMemberRemovedUpdate.builder(
                    removedAci: localAciData
                ),
                setOptionalFields: {
                    $0.setRemoverAci(aciData(removerAci))
                },
                build: { $0.build },
                set: { $0.setGroupMemberRemovedUpdate(_:) }
            )
        case .localUserRemovedByUnknownUser:
            setUpdate(
                BackupProtoGroupMemberRemovedUpdate.builder(
                    removedAci: localAciData
                ),
                build: { $0.build },
                set: { $0.setGroupMemberRemovedUpdate(_:) }
            )
        case .otherUserLeft(let userAci):
            setUpdate(
                BackupProtoGroupMemberLeftUpdate.builder(
                    aci: aciData(userAci)
                ),
                build: { $0.build },
                set: { $0.setGroupMemberLeftUpdate(_:) }
            )
        case .otherUserRemovedByLocalUser(let userAci):
            setUpdate(
                BackupProtoGroupMemberRemovedUpdate.builder(
                    removedAci: aciData(userAci)
                ),
                setOptionalFields: {
                    $0.setRemoverAci(localAciData)
                },
                build: { $0.build },
                set: { $0.setGroupMemberRemovedUpdate(_:) }
            )
        case .otherUserRemoved(let removerAci, let userAci):
            setUpdate(
                BackupProtoGroupMemberRemovedUpdate.builder(
                    removedAci: aciData(userAci)
                ),
                setOptionalFields: {
                    $0.setRemoverAci(aciData(removerAci))
                },
                build: { $0.build },
                set: { $0.setGroupMemberRemovedUpdate(_:) }
            )
        case .otherUserRemovedByUnknownUser(let userAci):
            setUpdate(
                BackupProtoGroupMemberRemovedUpdate.builder(
                    removedAci: aciData(userAci)
                ),
                build: { $0.build },
                set: { $0.setGroupMemberRemovedUpdate(_:) }
            )
        case .localUserWasInvitedByLocalUser:
            setUpdate(
                BackupProtoSelfInvitedToGroupUpdate.builder(),
                setOptionalFields: {
                    $0.setInviterAci(localAciData)
                },
                build: { $0.build },
                set: { $0.setSelfInvitedToGroupUpdate(_:) }
            )
        case .localUserWasInvitedByOtherUser(let updaterAci):
            setUpdate(
                BackupProtoSelfInvitedToGroupUpdate.builder(),
                setOptionalFields: {
                    $0.setInviterAci(aciData(updaterAci))
                },
                build: { $0.build },
                set: { $0.setSelfInvitedToGroupUpdate(_:) }
            )
        case .localUserWasInvitedByUnknownUser:
            setUpdate(
                BackupProtoSelfInvitedToGroupUpdate.builder(),
                build: { $0.build },
                set: { $0.setSelfInvitedToGroupUpdate(_:) }
            )
        case .otherUserWasInvitedByLocalUser(let inviteeServiceId):
            setUpdate(
                BackupProtoSelfInvitedOtherUserToGroupUpdate.builder(
                    inviteeServiceID: serviceIdData(inviteeServiceId)
                ),
                build: { $0.build },
                set: { $0.setSelfInvitedOtherUserToGroupUpdate(_:) }
            )
        case .unnamedUsersWereInvitedByLocalUser(let count):
            setUpdate(
                BackupProtoGroupUnknownInviteeUpdate.builder(
                    inviteeCount: UInt32(clamping: count)
                ),
                setOptionalFields: {
                    $0.setInviterAci(localAciData)
                },
                build: { $0.build },
                set: { $0.setGroupUnknownInviteeUpdate(_:) }
            )
        case .unnamedUsersWereInvitedByOtherUser(let updaterAci, let count):
            setUpdate(
                BackupProtoGroupUnknownInviteeUpdate.builder(
                    inviteeCount: UInt32(clamping: count)
                ),
                setOptionalFields: {
                    $0.setInviterAci(aciData(updaterAci))
                },
                build: { $0.build },
                set: { $0.setGroupUnknownInviteeUpdate(_:) }
            )
        case .unnamedUsersWereInvitedByUnknownUser(let count):
            setUpdate(
                BackupProtoGroupUnknownInviteeUpdate.builder(
                    inviteeCount: UInt32(clamping: count)
                ),
                build: { $0.build },
                set: { $0.setGroupUnknownInviteeUpdate(_:) }
            )
        case .localUserAcceptedInviteFromInviter(let inviterAci):
            setUpdate(
                BackupProtoGroupInvitationAcceptedUpdate.builder(
                    newMemberAci: localAciData
                ),
                setOptionalFields: {
                    $0.setInviterAci(aciData(inviterAci))
                },
                build: { $0.build },
                set: { $0.setGroupInvitationAcceptedUpdate(_:) }
            )
        case .localUserAcceptedInviteFromUnknownUser:
            setUpdate(
                BackupProtoGroupInvitationAcceptedUpdate.builder(
                    newMemberAci: localAciData
                ),
                build: { $0.build },
                set: { $0.setGroupInvitationAcceptedUpdate(_:) }
            )
        case .otherUserAcceptedInviteFromLocalUser(let userAci):
            setUpdate(
                BackupProtoGroupInvitationAcceptedUpdate.builder(
                    newMemberAci: aciData(userAci)
                ),
                setOptionalFields: {
                    $0.setInviterAci(localAciData)
                },
                build: { $0.build },
                set: { $0.setGroupInvitationAcceptedUpdate(_:) }
            )
        case .otherUserAcceptedInviteFromInviter(let userAci, let inviterAci):
            setUpdate(
                BackupProtoGroupInvitationAcceptedUpdate.builder(
                    newMemberAci: aciData(userAci)
                ),
                setOptionalFields: {
                    $0.setInviterAci(aciData(inviterAci))
                },
                build: { $0.build },
                set: { $0.setGroupInvitationAcceptedUpdate(_:) }
            )
        case .otherUserAcceptedInviteFromUnknownUser(let userAci):
            setUpdate(
                BackupProtoGroupInvitationAcceptedUpdate.builder(
                    newMemberAci: aciData(userAci)
                ),
                build: { $0.build },
                set: { $0.setGroupInvitationAcceptedUpdate(_:) }
            )
        case .localUserJoined:
            setUpdate(
                BackupProtoGroupMemberJoinedUpdate.builder(
                    newMemberAci: localAciData
                ),
                build: { $0.build },
                set: { $0.setGroupMemberJoinedUpdate(_:) }
            )
        case .otherUserJoined(let userAci):
            setUpdate(
                BackupProtoGroupMemberJoinedUpdate.builder(
                    newMemberAci: aciData(userAci)
                ),
                build: { $0.build },
                set: { $0.setGroupMemberJoinedUpdate(_:) }
            )
        case .localUserAddedByLocalUser:
            setUpdate(
                BackupProtoGroupMemberAddedUpdate.builder(
                    newMemberAci: localAciData,
                    // Note: on iOS we don't track if there was an invitation
                    // or who the inviter was.
                    hadOpenInvitation: false
                ),
                setOptionalFields: {
                    $0.setUpdaterAci(localAciData)
                },
                build: { $0.build },
                set: { $0.setGroupMemberAddedUpdate(_:) }
            )
        case .localUserAddedByOtherUser(let updaterAci):
            setUpdate(
                BackupProtoGroupMemberAddedUpdate.builder(
                    newMemberAci: localAciData,
                    // Note: on iOS we don't track if there was an invitation
                    // or who the inviter was.
                    hadOpenInvitation: false
                ),
                setOptionalFields: {
                    $0.setUpdaterAci(aciData(updaterAci))
                },
                build: { $0.build },
                set: { $0.setGroupMemberAddedUpdate(_:) }
            )
        case .localUserAddedByUnknownUser:
            setUpdate(
                BackupProtoGroupMemberAddedUpdate.builder(
                    newMemberAci: localAciData,
                    // Note: on iOS we don't track if there was an invitation
                    // or who the inviter was.
                    hadOpenInvitation: false
                ),
                build: { $0.build },
                set: { $0.setGroupMemberAddedUpdate(_:) }
            )
        case .otherUserAddedByLocalUser(let userAci):
            setUpdate(
                BackupProtoGroupMemberAddedUpdate.builder(
                    newMemberAci: aciData(userAci),
                    // Note: on iOS we don't track if there was an invitation
                    // or who the inviter was.
                    hadOpenInvitation: false
                ),
                setOptionalFields: {
                    $0.setUpdaterAci(localAciData)
                },
                build: { $0.build },
                set: { $0.setGroupMemberAddedUpdate(_:) }
            )
        case .otherUserAddedByOtherUser(let updaterAci, let userAci):
            setUpdate(
                BackupProtoGroupMemberAddedUpdate.builder(
                    newMemberAci: aciData(userAci),
                    // Note: on iOS we don't track if there was an invitation
                    // or who the inviter was.
                    hadOpenInvitation: false
                ),
                setOptionalFields: {
                    $0.setUpdaterAci(aciData(updaterAci))
                },
                build: { $0.build },
                set: { $0.setGroupMemberAddedUpdate(_:) }
            )
        case .otherUserAddedByUnknownUser(let userAci):
            setUpdate(
                BackupProtoGroupMemberAddedUpdate.builder(
                    newMemberAci: aciData(userAci),
                    // Note: on iOS we don't track if there was an invitation
                    // or who the inviter was.
                    hadOpenInvitation: false
                ),
                build: { $0.build },
                set: { $0.setGroupMemberAddedUpdate(_:) }
            )
        case .localUserDeclinedInviteFromInviter(let inviterAci):
            setUpdate(
                BackupProtoGroupInvitationDeclinedUpdate.builder(),
                setOptionalFields: {
                    $0.setInviteeAci(localAciData)
                    $0.setInviterAci(aciData(inviterAci))
                },
                build: { $0.build },
                set: { $0.setGroupInvitationDeclinedUpdate(_:) }
            )
        case .localUserDeclinedInviteFromUnknownUser:
            setUpdate(
                BackupProtoGroupInvitationDeclinedUpdate.builder(),
                setOptionalFields: {
                    $0.setInviteeAci(localAciData)
                },
                build: { $0.build },
                set: { $0.setGroupInvitationDeclinedUpdate(_:) }
            )
        case .otherUserDeclinedInviteFromLocalUser(let invitee):
            setUpdate(
                BackupProtoGroupInvitationDeclinedUpdate.builder(),
                setOptionalFields: {
                    switch invitee.wrappedValue.concreteType {
                    case .pni:
                        // Per spec we drop pnis for declined invites.
                        // They become unknown invitees.
                        break
                    case .aci(let aci):
                        $0.setInviteeAci(aciData(aci.codableUuid))
                    }
                    $0.setInviterAci(localAciData)
                },
                build: { $0.build },
                set: { $0.setGroupInvitationDeclinedUpdate(_:) }
            )
        case .otherUserDeclinedInviteFromInviter(let invitee, let inviterAci):
            setUpdate(
                BackupProtoGroupInvitationDeclinedUpdate.builder(),
                setOptionalFields: {
                    switch invitee.wrappedValue.concreteType {
                    case .pni:
                        // Per spec we drop pnis for declined invites.
                        // They become unknown invitees.
                        break
                    case .aci(let aci):
                        $0.setInviteeAci(aciData(aci.codableUuid))
                    }
                    $0.setInviterAci(aciData(inviterAci))
                },
                build: { $0.build },
                set: { $0.setGroupInvitationDeclinedUpdate(_:) }
            )
        case .otherUserDeclinedInviteFromUnknownUser(let invitee):
            setUpdate(
                BackupProtoGroupInvitationDeclinedUpdate.builder(),
                setOptionalFields: {
                    switch invitee.wrappedValue.concreteType {
                    case .pni:
                        // Per spec we drop pnis for declined invites.
                        // They become unknown invitees.
                        break
                    case .aci(let aci):
                        $0.setInviteeAci(aciData(aci.codableUuid))
                    }
                },
                build: { $0.build },
                set: { $0.setGroupInvitationDeclinedUpdate(_:) }
            )
        case .unnamedUserDeclinedInviteFromInviter(let inviterAci):
            setUpdate(
                BackupProtoGroupInvitationDeclinedUpdate.builder(),
                setOptionalFields: {
                    $0.setInviterAci(aciData(inviterAci))
                },
                build: { $0.build },
                set: { $0.setGroupInvitationDeclinedUpdate(_:) }
            )
        case .unnamedUserDeclinedInviteFromUnknownUser:
            setUpdate(
                BackupProtoGroupInvitationDeclinedUpdate.builder(),
                build: { $0.build },
                set: { $0.setGroupInvitationDeclinedUpdate(_:) }
            )
        case .localUserInviteRevoked(let revokerAci):
            setUpdate(
                BackupProtoGroupSelfInvitationRevokedUpdate.builder(),
                setOptionalFields: {
                    $0.setRevokerAci(aciData(revokerAci))
                },
                build: { $0.build },
                set: { $0.setGroupSelfInvitationRevokedUpdate(_:) }
            )
        case .localUserInviteRevokedByUnknownUser:
            setUpdate(
                BackupProtoGroupSelfInvitationRevokedUpdate.builder(),
                build: { $0.build },
                set: { $0.setGroupSelfInvitationRevokedUpdate(_:) }
            )
        case .otherUserInviteRevokedByLocalUser(let invitee):
            let inviteeBuilder = BackupProtoGroupInvitationRevokedUpdateInvitee.builder()
            switch invitee.wrappedValue.concreteType {
            case .aci(let aci):
                inviteeBuilder.setInviteeAci(aciData(aci.codableUuid))
            case .pni(let pni):
                inviteeBuilder.setInviteePni(pniData(pni))
            }
            // Note: on iOS we don't keep who the inviter was.
            let invitee: BackupProtoGroupInvitationRevokedUpdateInvitee
            do {
                invitee = try inviteeBuilder.build()
            } catch let error {
                protoBuildError = error
                break
            }

            setUpdate(
                BackupProtoGroupInvitationRevokedUpdate.builder(),
                setOptionalFields: {
                    $0.setUpdaterAci(localAciData)
                    $0.setInvitees([invitee])
                },
                build: { $0.build },
                set: { $0.setGroupInvitationRevokedUpdate(_:) }
            )
        case .unnamedUserInvitesWereRevokedByLocalUser(let count):
            // All the invitees are empty; only their count matters.
            let invitees: [BackupProtoGroupInvitationRevokedUpdateInvitee]
            do {
                invitees = try buildEmptyRevokedInvitees(count: count)
            } catch let error {
                protoBuildError = error
                break
            }
            setUpdate(
                BackupProtoGroupInvitationRevokedUpdate.builder(),
                setOptionalFields: {
                    $0.setUpdaterAci(localAciData)
                    $0.setInvitees(invitees)
                },
                build: { $0.build },
                set: { $0.setGroupInvitationRevokedUpdate(_:) }
            )
        case .unnamedUserInvitesWereRevokedByOtherUser(let updaterAci, let count):
            // All the invitees are empty; only their count matters.
            let invitees: [BackupProtoGroupInvitationRevokedUpdateInvitee]
            do {
                invitees = try buildEmptyRevokedInvitees(count: count)
            } catch let error {
                protoBuildError = error
                break
            }
            setUpdate(
                BackupProtoGroupInvitationRevokedUpdate.builder(),
                setOptionalFields: {
                    $0.setUpdaterAci(aciData(updaterAci))
                    $0.setInvitees(invitees)
                },
                build: { $0.build },
                set: { $0.setGroupInvitationRevokedUpdate(_:) }
            )
        case .unnamedUserInvitesWereRevokedByUnknownUser(let count):
            // All the invitees are empty; only their count matters.
            let invitees: [BackupProtoGroupInvitationRevokedUpdateInvitee]
            do {
                invitees = try buildEmptyRevokedInvitees(count: count)
            } catch let error {
                protoBuildError = error
                break
            }
            setUpdate(
                BackupProtoGroupInvitationRevokedUpdate.builder(),
                setOptionalFields: {
                    $0.setInvitees(invitees)
                },
                build: { $0.build },
                set: { $0.setGroupInvitationRevokedUpdate(_:) }
            )
        case .localUserRequestedToJoin:
            setUpdate(
                BackupProtoGroupJoinRequestUpdate.builder(
                    requestorAci: localAciData
                ),
                build: { $0.build },
                set: { $0.setGroupJoinRequestUpdate(_:) }
            )
        case .otherUserRequestedToJoin(let userAci):
            setUpdate(
                BackupProtoGroupJoinRequestUpdate.builder(
                    requestorAci: aciData(userAci)
                ),
                build: { $0.build },
                set: { $0.setGroupJoinRequestUpdate(_:) }
            )
        case .localUserRequestApproved(let approverAci):
            setUpdate(
                BackupProtoGroupJoinRequestApprovalUpdate.builder(
                    requestorAci: localAciData,
                    wasApproved: true
                ),
                setOptionalFields: {
                    $0.setUpdaterAci(aciData(approverAci))
                },
                build: { $0.build },
                set: { $0.setGroupJoinRequestApprovalUpdate(_:) }
            )
        case .localUserRequestApprovedByUnknownUser:
            setUpdate(
                BackupProtoGroupJoinRequestApprovalUpdate.builder(
                    requestorAci: localAciData,
                    wasApproved: true
                ),
                build: { $0.build },
                set: { $0.setGroupJoinRequestApprovalUpdate(_:) }
            )
        case .otherUserRequestApprovedByLocalUser(let userAci):
            setUpdate(
                BackupProtoGroupJoinRequestApprovalUpdate.builder(
                    requestorAci: aciData(userAci),
                    wasApproved: true
                ),
                setOptionalFields: {
                    $0.setUpdaterAci(localAciData)
                },
                build: { $0.build },
                set: { $0.setGroupJoinRequestApprovalUpdate(_:) }
            )
        case .otherUserRequestApproved(let userAci, let approverAci):
            setUpdate(
                BackupProtoGroupJoinRequestApprovalUpdate.builder(
                    requestorAci: aciData(userAci),
                    wasApproved: true
                ),
                setOptionalFields: {
                    $0.setUpdaterAci(aciData(approverAci))
                },
                build: { $0.build },
                set: { $0.setGroupJoinRequestApprovalUpdate(_:) }
            )
        case .otherUserRequestApprovedByUnknownUser(let userAci):
            setUpdate(
                BackupProtoGroupJoinRequestApprovalUpdate.builder(
                    requestorAci: aciData(userAci),
                    wasApproved: true
                ),
                build: { $0.build },
                set: { $0.setGroupJoinRequestApprovalUpdate(_:) }
            )
        case .localUserRequestCanceledByLocalUser:
            setUpdate(
                BackupProtoGroupJoinRequestCanceledUpdate.builder(
                    requestorAci: localAciData
                ),
                build: { $0.build },
                set: { $0.setGroupJoinRequestCanceledUpdate(_:) }
            )
        case .localUserRequestRejectedByUnknownUser:
            setUpdate(
                BackupProtoGroupJoinRequestApprovalUpdate.builder(
                    requestorAci: localAciData,
                    wasApproved: false
                ),
                build: { $0.build },
                set: { $0.setGroupJoinRequestApprovalUpdate(_:) }
            )
        case .otherUserRequestRejectedByLocalUser(let requesterAci):
            setUpdate(
                BackupProtoGroupJoinRequestApprovalUpdate.builder(
                    requestorAci: aciData(requesterAci),
                    wasApproved: false
                ),
                setOptionalFields: {
                    $0.setUpdaterAci(localAciData)
                },
                build: { $0.build },
                set: { $0.setGroupJoinRequestApprovalUpdate(_:) }
            )
        case .otherUserRequestRejectedByOtherUser(let updaterAci, let requesterAci):
            setUpdate(
                BackupProtoGroupJoinRequestApprovalUpdate.builder(
                    requestorAci: aciData(requesterAci),
                    wasApproved: false
                ),
                setOptionalFields: {
                    $0.setUpdaterAci(aciData(updaterAci))
                },
                build: { $0.build },
                set: { $0.setGroupJoinRequestApprovalUpdate(_:) }
            )
        case .otherUserRequestCanceledByOtherUser(let requesterAci):
            setUpdate(
                BackupProtoGroupJoinRequestCanceledUpdate.builder(
                    requestorAci: aciData(requesterAci)
                ),
                build: { $0.build },
                set: { $0.setGroupJoinRequestCanceledUpdate(_:) }
            )
        case .otherUserRequestRejectedByUnknownUser(let requesterAci):
            setUpdate(
                BackupProtoGroupJoinRequestApprovalUpdate.builder(
                    requestorAci: aciData(requesterAci),
                    wasApproved: false
                ),
                build: { $0.build },
                set: { $0.setGroupJoinRequestApprovalUpdate(_:) }
            )
        case .disappearingMessagesEnabledByLocalUser(let durationMs):
            let expiresInMs = UInt32(clamping: durationMs)
            setUpdate(
                BackupProtoGroupExpirationTimerUpdate.builder(
                    expiresInMs: expiresInMs
                ),
                setOptionalFields: {
                    $0.setUpdaterAci(localAciData)
                },
                build: { $0.build },
                set: { $0.setGroupExpirationTimerUpdate(_:) }
            )
        case .disappearingMessagesEnabledByOtherUser(let updaterAci, let durationMs):
            let expiresInMs = UInt32(clamping: durationMs)
            setUpdate(
                BackupProtoGroupExpirationTimerUpdate.builder(
                    expiresInMs: expiresInMs
                ),
                setOptionalFields: {
                    $0.setUpdaterAci(aciData(updaterAci))
                },
                build: { $0.build },
                set: { $0.setGroupExpirationTimerUpdate(_:) }
            )
        case .disappearingMessagesEnabledByUnknownUser(let durationMs):
            let expiresInMs = UInt32(clamping: durationMs)
            setUpdate(
                BackupProtoGroupExpirationTimerUpdate.builder(
                    expiresInMs: expiresInMs
                ),
                build: { $0.build },
                set: { $0.setGroupExpirationTimerUpdate(_:) }
            )
        case .disappearingMessagesDisabledByLocalUser:
            setUpdate(
                BackupProtoGroupExpirationTimerUpdate.builder(
                    // 0 means disabled.
                    expiresInMs: 0
                ),
                setOptionalFields: {
                    $0.setUpdaterAci(localAciData)
                },
                build: { $0.build },
                set: { $0.setGroupExpirationTimerUpdate(_:) }
            )
        case .disappearingMessagesDisabledByOtherUser(let updaterAci):
            setUpdate(
                BackupProtoGroupExpirationTimerUpdate.builder(
                    // 0 means disabled.
                    expiresInMs: 0
                ),
                setOptionalFields: {
                    $0.setUpdaterAci(aciData(updaterAci))
                },
                build: { $0.build },
                set: { $0.setGroupExpirationTimerUpdate(_:) }
            )
        case .disappearingMessagesDisabledByUnknownUser:
            setUpdate(
                BackupProtoGroupExpirationTimerUpdate.builder(
                    // 0 means disabled.
                    expiresInMs: 0
                ),
                build: { $0.build },
                set: { $0.setGroupExpirationTimerUpdate(_:) }
            )
        case .inviteLinkResetByLocalUser:
            setUpdate(
                BackupProtoGroupInviteLinkResetUpdate.builder(),
                setOptionalFields: {
                    $0.setUpdaterAci(localAciData)
                },
                build: { $0.build },
                set: { $0.setGroupInviteLinkResetUpdate(_:) }
            )
        case .inviteLinkResetByOtherUser(let updaterAci):
            setUpdate(
                BackupProtoGroupInviteLinkResetUpdate.builder(),
                setOptionalFields: {
                    $0.setUpdaterAci(aciData(updaterAci))
                },
                build: { $0.build },
                set: { $0.setGroupInviteLinkResetUpdate(_:) }
            )
        case .inviteLinkResetByUnknownUser:
            setUpdate(
                BackupProtoGroupInviteLinkResetUpdate.builder(),
                build: { $0.build },
                set: { $0.setGroupInviteLinkResetUpdate(_:) }
            )
        case .inviteLinkEnabledWithoutApprovalByLocalUser:
            setUpdate(
                BackupProtoGroupInviteLinkEnabledUpdate.builder(
                    linkRequiresAdminApproval: false
                ),
                setOptionalFields: {
                    $0.setUpdaterAci(localAciData)
                },
                build: { $0.build },
                set: { $0.setGroupInviteLinkEnabledUpdate(_:) }
            )
        case .inviteLinkEnabledWithoutApprovalByOtherUser(let updaterAci):
            setUpdate(
                BackupProtoGroupInviteLinkEnabledUpdate.builder(
                    linkRequiresAdminApproval: false
                ),
                setOptionalFields: {
                    $0.setUpdaterAci(aciData(updaterAci))
                },
                build: { $0.build },
                set: { $0.setGroupInviteLinkEnabledUpdate(_:) }
            )
        case .inviteLinkEnabledWithoutApprovalByUnknownUser:
            setUpdate(
                BackupProtoGroupInviteLinkEnabledUpdate.builder(
                    linkRequiresAdminApproval: false
                ),
                build: { $0.build },
                set: { $0.setGroupInviteLinkEnabledUpdate(_:) }
            )
        case .inviteLinkEnabledWithApprovalByLocalUser:
            setUpdate(
                BackupProtoGroupInviteLinkEnabledUpdate.builder(
                    linkRequiresAdminApproval: true
                ),
                setOptionalFields: {
                    $0.setUpdaterAci(localAciData)
                },
                build: { $0.build },
                set: { $0.setGroupInviteLinkEnabledUpdate(_:) }
            )
        case .inviteLinkEnabledWithApprovalByOtherUser(let updaterAci):
            setUpdate(
                BackupProtoGroupInviteLinkEnabledUpdate.builder(
                    linkRequiresAdminApproval: true
                ),
                setOptionalFields: {
                    $0.setUpdaterAci(aciData(updaterAci))
                },
                build: { $0.build },
                set: { $0.setGroupInviteLinkEnabledUpdate(_:) }
            )
        case .inviteLinkEnabledWithApprovalByUnknownUser:
            setUpdate(
                BackupProtoGroupInviteLinkEnabledUpdate.builder(
                    linkRequiresAdminApproval: true
                ),
                build: { $0.build },
                set: { $0.setGroupInviteLinkEnabledUpdate(_:) }
            )
        case .inviteLinkDisabledByLocalUser:
            setUpdate(
                BackupProtoGroupInviteLinkDisabledUpdate.builder(),
                setOptionalFields: {
                    $0.setUpdaterAci(localAciData)
                },
                build: { $0.build },
                set: { $0.setGroupInviteLinkDisabledUpdate(_:) }
            )
        case .inviteLinkDisabledByOtherUser(let updaterAci):
            setUpdate(
                BackupProtoGroupInviteLinkDisabledUpdate.builder(),
                setOptionalFields: {
                    $0.setUpdaterAci(aciData(updaterAci))
                },
                build: { $0.build },
                set: { $0.setGroupInviteLinkDisabledUpdate(_:) }
            )
        case .inviteLinkDisabledByUnknownUser:
            setUpdate(
                BackupProtoGroupInviteLinkDisabledUpdate.builder(),
                build: { $0.build },
                set: { $0.setGroupInviteLinkDisabledUpdate(_:) }
            )
        case .inviteLinkApprovalDisabledByLocalUser:
            setUpdate(
                BackupProtoGroupInviteLinkAdminApprovalUpdate.builder(
                    linkRequiresAdminApproval: false
                ),
                setOptionalFields: {
                    $0.setUpdaterAci(localAciData)
                },
                build: { $0.build },
                set: { $0.setGroupInviteLinkAdminApprovalUpdate(_:) }
            )
        case .inviteLinkApprovalDisabledByOtherUser(let updaterAci):
            setUpdate(
                BackupProtoGroupInviteLinkAdminApprovalUpdate.builder(
                    linkRequiresAdminApproval: false
                ),
                setOptionalFields: {
                    $0.setUpdaterAci(aciData(updaterAci))
                },
                build: { $0.build },
                set: { $0.setGroupInviteLinkAdminApprovalUpdate(_:) }
            )
        case .inviteLinkApprovalDisabledByUnknownUser:
            setUpdate(
                BackupProtoGroupInviteLinkAdminApprovalUpdate.builder(
                    linkRequiresAdminApproval: false
                ),
                build: { $0.build },
                set: { $0.setGroupInviteLinkAdminApprovalUpdate(_:) }
            )
        case .inviteLinkApprovalEnabledByLocalUser:
            setUpdate(
                BackupProtoGroupInviteLinkAdminApprovalUpdate.builder(
                    linkRequiresAdminApproval: true
                ),
                setOptionalFields: {
                    $0.setUpdaterAci(localAciData)
                },
                build: { $0.build },
                set: { $0.setGroupInviteLinkAdminApprovalUpdate(_:) }
            )
        case .inviteLinkApprovalEnabledByOtherUser(let updaterAci):
            setUpdate(
                BackupProtoGroupInviteLinkAdminApprovalUpdate.builder(
                    linkRequiresAdminApproval: true
                ),
                setOptionalFields: {
                    $0.setUpdaterAci(aciData(updaterAci))
                },
                build: { $0.build },
                set: { $0.setGroupInviteLinkAdminApprovalUpdate(_:) }
            )
        case .inviteLinkApprovalEnabledByUnknownUser:
            setUpdate(
                BackupProtoGroupInviteLinkAdminApprovalUpdate.builder(
                    linkRequiresAdminApproval: true
                ),
                build: { $0.build },
                set: { $0.setGroupInviteLinkAdminApprovalUpdate(_:) }
            )
        case .localUserJoinedViaInviteLink:
            setUpdate(
                BackupProtoGroupMemberJoinedByLinkUpdate.builder(
                    newMemberAci: localAciData
                ),
                build: { $0.build },
                set: { $0.setGroupMemberJoinedByLinkUpdate(_:) }
            )
        case .otherUserJoinedViaInviteLink(let userAci):
            setUpdate(
                BackupProtoGroupMemberJoinedByLinkUpdate.builder(
                    newMemberAci: aciData(userAci)
                ),
                build: { $0.build },
                set: { $0.setGroupMemberJoinedByLinkUpdate(_:) }
            )
        }

        if let protoBuildError {
            return .messageFailure([
                .protoSerializationError(interactionId, protoBuildError)
            ])
        }

        let update: BackupProtoGroupChangeChatUpdateUpdate
        do {
            update = try updateBuilder.build()
        } catch let error {
            return .messageFailure([
                .protoSerializationError(interactionId, error)
            ])
        }

        return .success(update)
    }
}

extension GroupV2Access {

    fileprivate var backupAccessLevel: BackupProtoGroupV2AccessLevel {
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
