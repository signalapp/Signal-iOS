//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

extension TSInfoMessage {
    @objc(TSInfoMessageUpdateMessages)
    public class LegacyPersistableGroupUpdateItemsWrapper: NSObject, NSCopying, NSSecureCoding {
        public let updateItems: [LegacyPersistableGroupUpdateItem]

        public init(_ updateItems: [LegacyPersistableGroupUpdateItem]) {
            self.updateItems = updateItems
        }

        // MARK: NSCopying

        public func copy(with _: NSZone? = nil) -> Any {
            self
        }

        // MARK: NSSecureCoding

        public static var supportsSecureCoding: Bool { true }

        private static let messagesKey = "messagesKey"

        public func encode(with aCoder: NSCoder) {
            let jsonEncoder = JSONEncoder()
            do {
                let messagesData = try jsonEncoder.encode(updateItems)
                aCoder.encode(messagesData, forKey: Self.messagesKey)
            } catch let error {
                owsFailDebug("Failed to encode updateItems data: \(error)")
                return
            }
        }

        public required init?(coder aDecoder: NSCoder) {
            guard let updateItemsData = aDecoder.decodeObject(
                forKey: Self.messagesKey
            ) as? Data else {
                owsFailDebug("Failed to decode updateItems data")
                return nil
            }

            let jsonDecoder = JSONDecoder()
            do {
                updateItems = try jsonDecoder.decode(
                    [LegacyPersistableGroupUpdateItem].self,
                    from: updateItemsData
                )
            } catch let error {
                owsFailDebug("Failed to decode updateItems data: \(error)")
                return nil
            }

            super.init()
        }
    }

    @objc(TSInfoMessageUpdateMessagesV2)
    public class PersistableGroupUpdateItemsWrapper: NSObject, NSCopying, NSSecureCoding {
        public let updateItems: [PersistableGroupUpdateItem]

        public init(_ updateItems: [PersistableGroupUpdateItem]) {
            self.updateItems = updateItems
        }

        // MARK: NSCopying

        public func copy(with _: NSZone? = nil) -> Any {
            self
        }

        // MARK: NSSecureCoding

        public static var supportsSecureCoding: Bool { true }

        private static let messagesKey = "messagesKey"

        public func encode(with aCoder: NSCoder) {
            let jsonEncoder = JSONEncoder()
            do {
                let messagesData = try jsonEncoder.encode(updateItems)
                aCoder.encode(messagesData, forKey: Self.messagesKey)
            } catch let error {
                owsFailDebug("Failed to encode updateItems data: \(error)")
                return
            }
        }

        public required init?(coder aDecoder: NSCoder) {
            guard let updateItemsData = aDecoder.decodeObject(
                forKey: Self.messagesKey
            ) as? Data else {
                owsFailDebug("Failed to decode updateItems data")
                return nil
            }

            let jsonDecoder = JSONDecoder()
            do {
                updateItems = try jsonDecoder.decode(
                    [PersistableGroupUpdateItem].self,
                    from: updateItemsData
                )
            } catch let error {
                owsFailDebug("Failed to decode updateItems data: \(error)")
                return nil
            }

            super.init()
        }
    }
}

// MARK: -

extension TSInfoMessage {

    public enum LegacyPersistableGroupUpdateItem: Codable {
        enum CodingKeys: String, CodingKey {
            case sequenceOfInviteLinkRequestAndCancels
            case invitedPniPromotedToFullMemberAci
            case inviteRemoved
        }

        case sequenceOfInviteLinkRequestAndCancels(count: UInt, isTail: Bool)
        case invitedPniPromotedToFullMemberAci(pni: PniUuid, aci: AciUuid)
        case inviteRemoved(invitee: ServiceIdUppercaseString, wasLocalUser: Bool)

        func toNewItem(
            updater: GroupUpdateSource,
            oldGroupModel: TSGroupModel?,
            localIdentifiers: LocalIdentifiers
        ) -> PersistableGroupUpdateItem? {
            switch self {
            case .sequenceOfInviteLinkRequestAndCancels(let count, let isTail):
                switch updater {
                case .unknown, .legacyE164, .rejectedInviteToPni, .localUser:
                    owsFailDebug("How did we get one of these without a valid updater? that should be impossible")
                    return nil
                case .aci(let aci):
                    return .sequenceOfInviteLinkRequestAndCancels(
                        requester: aci.codableUuid,
                        count: count,
                        isTail: isTail
                    )
                }

            case .invitedPniPromotedToFullMemberAci(let pni, let aci):
                return .invitedPniPromotedToFullMemberAci(
                    newMember: aci,
                    inviter: oldGroupModel?.groupMembership.addedByAci(
                        forInvitedMember: SignalServiceAddress(pni.wrappedValue)
                    )?.codableUuid
                )
            case .inviteRemoved(let invitee, let wasLocalUser):
                let remover: ServiceId
                var wasRejectedInvite = false
                switch updater {
                case .aci(let aci):
                    remover = aci
                case .rejectedInviteToPni(let pni):
                    remover = pni
                    wasRejectedInvite = true
                case .localUser(let originalSource):
                    switch originalSource {
                    case .aci(let aci):
                        remover = aci
                    case .rejectedInviteToPni(let pni):
                        remover = pni
                        wasRejectedInvite = true
                    case .unknown, .legacyE164, .localUser:
                        owsFailDebug("Invalid!")
                        return nil
                    }
                case .unknown, .legacyE164:
                    owsFailDebug("Only acis or pnis can remove an invite")
                    return nil
                }

                let inviterAci = oldGroupModel?.groupMembership.addedByAci(
                    forInvitedMember: SignalServiceAddress(invitee.wrappedValue)
                )

                if wasLocalUser {
                    if wasRejectedInvite || localIdentifiers.contains(serviceId: remover) {
                        // Local user invite that was rejected.
                        if let inviterAci {
                            return .localUserDeclinedInviteFromInviter(
                                inviterAci: inviterAci.codableUuid
                            )
                        } else {
                            return .localUserDeclinedInviteFromUnknownUser
                        }
                    } else {
                        // Local user invite that was removed by another user.
                        if let removerAci = remover as? Aci {
                            return .localUserInviteRevoked(revokerAci: removerAci.codableUuid)
                        } else {
                            return .localUserInviteRevokedByUnknownUser
                        }
                    }
                } else {
                    if wasRejectedInvite || invitee.wrappedValue == remover {
                        // Other user rejected an invite.
                        if let inviterAci {
                            if inviterAci == localIdentifiers.aci {
                                return .otherUserDeclinedInviteFromLocalUser(invitee: invitee)
                            } else {
                                return .otherUserDeclinedInviteFromInviter(
                                    invitee: invitee,
                                    inviterAci: inviterAci.codableUuid
                                )
                            }
                        } else {
                            return .otherUserDeclinedInviteFromUnknownUser(invitee: invitee)
                        }
                    } else {
                        // Other user's invite was revoked.
                        if let removerAci = remover as? Aci {
                            if removerAci == localIdentifiers.aci {
                                return .otherUserInviteRevokedByLocalUser(invitee: invitee)
                            } else {
                                return .unnamedUserInvitesWereRevokedByOtherUser(
                                    updaterAci: removerAci.codableUuid,
                                    count: 1
                                )
                            }
                        } else {
                            return .unnamedUserInvitesWereRevokedByUnknownUser(count: 1)
                        }
                    }
                }
            }
        }
    }

    public enum PersistableGroupUpdateItem: Codable {
        enum CodingKeys: String, CodingKey {
            case sequenceOfInviteLinkRequestAndCancels
            case invitedPniPromotedToFullMemberAci
            case genericUpdateByLocalUser
            case genericUpdateByOtherUser
            case genericUpdateByUnknownUser
            case createdByLocalUser
            case createdByOtherUser
            case createdByUnknownUser
            case inviteFriendsToNewlyCreatedGroup
            case wasMigrated
            case localUserInvitedAfterMigration
            case otherUsersInvitedAfterMigration
            case otherUsersDroppedAfterMigration
            case nameChangedByLocalUser
            case nameChangedByOtherUser
            case nameChangedByUnknownUser
            case nameRemovedByLocalUser
            case nameRemovedByOtherUser
            case nameRemovedByUnknownUser
            case avatarChangedByLocalUser
            case avatarChangedByOtherUser
            case avatarChangedByUnknownUser
            case avatarRemovedByLocalUser
            case avatarRemovedByOtherUser
            case avatarRemovedByUnknownUser
            case descriptionChangedByLocalUser
            case descriptionChangedByOtherUser
            case descriptionChangedByUnknownUser
            case descriptionRemovedByLocalUser
            case descriptionRemovedByOtherUser
            case descriptionRemovedByUnknownUser
            case membersAccessChangedByLocalUser
            case membersAccessChangedByOtherUser
            case membersAccessChangedByUnknownUser
            case attributesAccessChangedByLocalUser
            case attributesAccessChangedByOtherUser
            case attributesAccessChangedByUnknownUser
            case announcementOnlyEnabledByLocalUser
            case announcementOnlyEnabledByOtherUser
            case announcementOnlyEnabledByUnknownUser
            case announcementOnlyDisabledByLocalUser
            case announcementOnlyDisabledByOtherUser
            case announcementOnlyDisabledByUnknownUser
            case localUserWasGrantedAdministratorByLocalUser
            case localUserWasGrantedAdministratorByOtherUser
            case localUserWasGrantedAdministratorByUnknownUser
            case otherUserWasGrantedAdministratorByLocalUser
            case otherUserWasGrantedAdministratorByOtherUser
            case otherUserWasGrantedAdministratorByUnknownUser
            case localUserWasRevokedAdministratorByLocalUser
            case localUserWasRevokedAdministratorByOtherUser
            case localUserWasRevokedAdministratorByUnknownUser
            case otherUserWasRevokedAdministratorByLocalUser
            case otherUserWasRevokedAdministratorByOtherUser
            case otherUserWasRevokedAdministratorByUnknownUser
            case localUserLeft
            case localUserRemoved
            case localUserRemovedByUnknownUser
            case otherUserLeft
            case otherUserRemovedByLocalUser
            case otherUserRemoved
            case otherUserRemovedByUnknownUser
            case localUserWasInvitedByLocalUser
            case localUserWasInvitedByOtherUser
            case localUserWasInvitedByUnknownUser
            case otherUserWasInvitedByLocalUser
            case unnamedUsersWereInvitedByLocalUser
            case unnamedUsersWereInvitedByOtherUser
            case unnamedUsersWereInvitedByUnknownUser
            case localUserAcceptedInviteFromInviter
            case localUserAcceptedInviteFromUnknownUser
            case otherUserAcceptedInviteFromLocalUser
            case otherUserAcceptedInviteFromInviter
            case otherUserAcceptedInviteFromUnknownUser
            case localUserJoined
            case otherUserJoined
            case localUserAddedByLocalUser
            case localUserAddedByOtherUser
            case localUserAddedByUnknownUser
            case otherUserAddedByLocalUser
            case otherUserAddedByOtherUser
            case otherUserAddedByUnknownUser
            case localUserDeclinedInviteFromInviter
            case localUserDeclinedInviteFromUnknownUser
            case otherUserDeclinedInviteFromLocalUser
            case otherUserDeclinedInviteFromInviter
            case otherUserDeclinedInviteFromUnknownUser
            case unnamedUserDeclinedInviteFromInviter
            case unnamedUserDeclinedInviteFromUnknownUser
            case localUserInviteRevoked
            case localUserInviteRevokedByUnknownUser
            case otherUserInviteRevokedByLocalUser
            case unnamedUserInvitesWereRevokedByLocalUser
            case unnamedUserInvitesWereRevokedByOtherUser
            case unnamedUserInvitesWereRevokedByUnknownUser
            case localUserRequestedToJoin
            case otherUserRequestedToJoin
            case localUserRequestApproved
            case localUserRequestApprovedByUnknownUser
            case otherUserRequestApprovedByLocalUser
            case otherUserRequestApproved
            case otherUserRequestApprovedByUnknownUser
            case localUserRequestCanceledByLocalUser
            case localUserRequestRejectedByUnknownUser
            case otherUserRequestRejectedByLocalUser
            case otherUserRequestRejectedByOtherUser
            case otherUserRequestCanceledByOtherUser
            case otherUserRequestRejectedByUnknownUser
            case disappearingMessagesEnabledByLocalUser
            case disappearingMessagesEnabledByOtherUser
            case disappearingMessagesEnabledByUnknownUser
            case disappearingMessagesDisabledByLocalUser
            case disappearingMessagesDisabledByOtherUser
            case disappearingMessagesDisabledByUnknownUser
            case inviteLinkResetByLocalUser
            case inviteLinkResetByOtherUser
            case inviteLinkResetByUnknownUser
            case inviteLinkEnabledWithoutApprovalByLocalUser
            case inviteLinkEnabledWithoutApprovalByOtherUser
            case inviteLinkEnabledWithoutApprovalByUnknownUser
            case inviteLinkEnabledWithApprovalByLocalUser
            case inviteLinkEnabledWithApprovalByOtherUser
            case inviteLinkEnabledWithApprovalByUnknownUser
            case inviteLinkDisabledByLocalUser
            case inviteLinkDisabledByOtherUser
            case inviteLinkDisabledByUnknownUser
            case inviteLinkApprovalDisabledByLocalUser
            case inviteLinkApprovalDisabledByOtherUser
            case inviteLinkApprovalDisabledByUnknownUser
            case inviteLinkApprovalEnabledByLocalUser
            case inviteLinkApprovalEnabledByOtherUser
            case inviteLinkApprovalEnabledByUnknownUser
            case localUserJoinedViaInviteLink
            case otherUserJoinedViaInviteLink
        }

        /// Represents a sequence of "request to join" and "canceled request to
        /// join" from the same user.
        ///
        /// - Note
        /// We do not use this case when the requestor is the local user; we show these
        /// as separate ``localUserRequestedToJoin`` and
        /// ``localUserRequestCanceledByLocalUser``.
        case sequenceOfInviteLinkRequestAndCancels(requester: AciUuid, count: UInt, isTail: Bool)

        /// Someone was invited to the group by their PNI, and in accepting the
        /// invite "promoted" their membership from the invited PNI to their
        /// "full member" ACI.
        ///
        /// - Note
        /// The user in question may be another user, or the local user.
        case invitedPniPromotedToFullMemberAci(newMember: AciUuid, inviter: AciUuid?)

        case genericUpdateByLocalUser
        case genericUpdateByOtherUser(updaterAci: AciUuid)
        case genericUpdateByUnknownUser

        case createdByLocalUser
        case createdByOtherUser(updaterAci: AciUuid)
        case createdByUnknownUser

        case inviteFriendsToNewlyCreatedGroup

        /// The group was migrated from gv1 to gv2
        case wasMigrated
        /// As part of a gv1->gv2 migration, the user who did the migration could'nt add the local user
        /// and invited them instead (because the migrating user lacked the local user's profile key).
        /// We have never generated these locally, but they may be present in backups from other clients.
        case localUserInvitedAfterMigration
        /// As part of a gv1->gv2 migration, gv1 members whose acis were known but profile keys
        /// were not known were invited to the new gv2 group.
        /// We have never generated these locally, but they may be present in backups from other clients.
        case otherUsersInvitedAfterMigration(count: UInt)
        /// As part of a gv1->gv2 migration, gv1 members whose acis were not known were removed
        /// from the group.
        /// We have never generated these locally, but they may be present in backups from other clients. 
        case otherUsersDroppedAfterMigration(count: UInt)

        case nameChangedByLocalUser(newGroupName: String)
        case nameChangedByOtherUser(updaterAci: AciUuid, newGroupName: String)
        case nameChangedByUnknownUser(newGroupName: String)

        case nameRemovedByLocalUser
        case nameRemovedByOtherUser(updaterAci: AciUuid)
        case nameRemovedByUnknownUser

        case avatarChangedByLocalUser
        case avatarChangedByOtherUser(updaterAci: AciUuid)
        case avatarChangedByUnknownUser

        case avatarRemovedByLocalUser
        case avatarRemovedByOtherUser(updaterAci: AciUuid)
        case avatarRemovedByUnknownUser

        case descriptionChangedByLocalUser(newDescription: String)
        case descriptionChangedByOtherUser(updaterAci: AciUuid, newDescription: String)
        case descriptionChangedByUnknownUser(newDescription: String)

        case descriptionRemovedByLocalUser
        case descriptionRemovedByOtherUser(updaterAci: AciUuid)
        case descriptionRemovedByUnknownUser

        case membersAccessChangedByLocalUser(newAccess: GroupV2Access)
        case membersAccessChangedByOtherUser(updaterAci: AciUuid, newAccess: GroupV2Access)
        case membersAccessChangedByUnknownUser(newAccess: GroupV2Access)

        case attributesAccessChangedByLocalUser(newAccess: GroupV2Access)
        case attributesAccessChangedByOtherUser(updaterAci: AciUuid, newAccess: GroupV2Access)
        case attributesAccessChangedByUnknownUser(newAccess: GroupV2Access)

        case announcementOnlyEnabledByLocalUser
        case announcementOnlyEnabledByOtherUser(updaterAci: AciUuid)
        case announcementOnlyEnabledByUnknownUser

        case announcementOnlyDisabledByLocalUser
        case announcementOnlyDisabledByOtherUser(updaterAci: AciUuid)
        case announcementOnlyDisabledByUnknownUser

        case localUserWasGrantedAdministratorByLocalUser
        case localUserWasGrantedAdministratorByOtherUser(updaterAci: AciUuid)
        case localUserWasGrantedAdministratorByUnknownUser

        case otherUserWasGrantedAdministratorByLocalUser(userAci: AciUuid)
        case otherUserWasGrantedAdministratorByOtherUser(updaterAci: AciUuid, userAci: AciUuid)
        case otherUserWasGrantedAdministratorByUnknownUser(userAci: AciUuid)

        case localUserWasRevokedAdministratorByLocalUser
        case localUserWasRevokedAdministratorByOtherUser(updaterAci: AciUuid)
        case localUserWasRevokedAdministratorByUnknownUser

        case otherUserWasRevokedAdministratorByLocalUser(userAci: AciUuid)
        case otherUserWasRevokedAdministratorByOtherUser(updaterAci: AciUuid, userAci: AciUuid)
        case otherUserWasRevokedAdministratorByUnknownUser(userAci: AciUuid)

        case localUserLeft
        case localUserRemoved(removerAci: AciUuid)
        case localUserRemovedByUnknownUser

        case otherUserLeft(userAci: AciUuid)
        case otherUserRemovedByLocalUser(userAci: AciUuid)
        case otherUserRemoved(removerAci: AciUuid, userAci: AciUuid)
        case otherUserRemovedByUnknownUser(userAci: AciUuid)

        case localUserWasInvitedByLocalUser
        case localUserWasInvitedByOtherUser(updaterAci: AciUuid)
        case localUserWasInvitedByUnknownUser

        case otherUserWasInvitedByLocalUser(inviteeServiceId: ServiceIdUppercaseString)

        case unnamedUsersWereInvitedByLocalUser(count: UInt)
        case unnamedUsersWereInvitedByOtherUser(updaterAci: AciUuid, count: UInt)
        case unnamedUsersWereInvitedByUnknownUser(count: UInt)

        case localUserAcceptedInviteFromInviter(inviterAci: AciUuid)
        case localUserAcceptedInviteFromUnknownUser
        case otherUserAcceptedInviteFromLocalUser(userAci: AciUuid)
        case otherUserAcceptedInviteFromInviter(userAci: AciUuid, inviterAci: AciUuid)
        case otherUserAcceptedInviteFromUnknownUser(userAci: AciUuid)

        case localUserJoined
        case otherUserJoined(userAci: AciUuid)

        case localUserAddedByLocalUser
        case localUserAddedByOtherUser(updaterAci: AciUuid)
        case localUserAddedByUnknownUser

        case otherUserAddedByLocalUser(userAci: AciUuid)
        case otherUserAddedByOtherUser(updaterAci: AciUuid, userAci: AciUuid)
        case otherUserAddedByUnknownUser(userAci: AciUuid)

        case localUserDeclinedInviteFromInviter(inviterAci: AciUuid)
        case localUserDeclinedInviteFromUnknownUser
        case otherUserDeclinedInviteFromLocalUser(invitee: ServiceIdUppercaseString)
        case otherUserDeclinedInviteFromInviter(invitee: ServiceIdUppercaseString, inviterAci: AciUuid)
        case otherUserDeclinedInviteFromUnknownUser(invitee: ServiceIdUppercaseString)
        case unnamedUserDeclinedInviteFromInviter(inviterAci: AciUuid)
        case unnamedUserDeclinedInviteFromUnknownUser

        case localUserInviteRevoked(revokerAci: AciUuid)
        case localUserInviteRevokedByUnknownUser
        // For a single invite we revoked we keep the invitee.
        // For many, or if someone else revoked, we just keep the number.
        case otherUserInviteRevokedByLocalUser(invitee: ServiceIdUppercaseString)
        case unnamedUserInvitesWereRevokedByLocalUser(count: UInt)
        case unnamedUserInvitesWereRevokedByOtherUser(updaterAci: AciUuid, count: UInt)
        case unnamedUserInvitesWereRevokedByUnknownUser(count: UInt)

        case localUserRequestedToJoin
        case otherUserRequestedToJoin(userAci: AciUuid)

        case localUserRequestApproved(approverAci: AciUuid)
        case localUserRequestApprovedByUnknownUser
        case otherUserRequestApprovedByLocalUser(userAci: AciUuid)
        case otherUserRequestApproved(userAci: AciUuid, approverAci: AciUuid)
        case otherUserRequestApprovedByUnknownUser(userAci: AciUuid)

        case localUserRequestCanceledByLocalUser
        case localUserRequestRejectedByUnknownUser

        case otherUserRequestRejectedByLocalUser(requesterAci: AciUuid)
        case otherUserRequestRejectedByOtherUser(updaterAci: AciUuid, requesterAci: AciUuid)
        case otherUserRequestCanceledByOtherUser(requesterAci: AciUuid)
        case otherUserRequestRejectedByUnknownUser(requesterAci: AciUuid)

        case disappearingMessagesEnabledByLocalUser(durationMs: UInt64)
        case disappearingMessagesEnabledByOtherUser(updaterAci: AciUuid, durationMs: UInt64)
        case disappearingMessagesEnabledByUnknownUser(durationMs: UInt64)

        case disappearingMessagesDisabledByLocalUser
        case disappearingMessagesDisabledByOtherUser(updaterAci: AciUuid)
        case disappearingMessagesDisabledByUnknownUser

        case inviteLinkResetByLocalUser
        case inviteLinkResetByOtherUser(updaterAci: AciUuid)
        case inviteLinkResetByUnknownUser

        case inviteLinkEnabledWithoutApprovalByLocalUser
        case inviteLinkEnabledWithoutApprovalByOtherUser(updaterAci: AciUuid)
        case inviteLinkEnabledWithoutApprovalByUnknownUser

        case inviteLinkEnabledWithApprovalByLocalUser
        case inviteLinkEnabledWithApprovalByOtherUser(updaterAci: AciUuid)
        case inviteLinkEnabledWithApprovalByUnknownUser

        case inviteLinkDisabledByLocalUser
        case inviteLinkDisabledByOtherUser(updaterAci: AciUuid)
        case inviteLinkDisabledByUnknownUser

        case inviteLinkApprovalDisabledByLocalUser
        case inviteLinkApprovalDisabledByOtherUser(updaterAci: AciUuid)
        case inviteLinkApprovalDisabledByUnknownUser

        case inviteLinkApprovalEnabledByLocalUser
        case inviteLinkApprovalEnabledByOtherUser(updaterAci: AciUuid)
        case inviteLinkApprovalEnabledByUnknownUser

        case localUserJoinedViaInviteLink
        case otherUserJoinedViaInviteLink(userAci: AciUuid)
    }
}
