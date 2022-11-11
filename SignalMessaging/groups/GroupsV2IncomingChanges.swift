//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import LibSignalClient

public struct ChangedGroupModel {
    public let oldGroupModel: TSGroupModelV2
    public let newGroupModel: TSGroupModelV2
    // newDisappearingMessageToken is only set of DM state changed.
    public let newDisappearingMessageToken: DisappearingMessageToken?
    public let changeAuthorUuid: UUID
    public let profileKeys: [UUID: Data]

    public init(oldGroupModel: TSGroupModelV2,
                newGroupModel: TSGroupModelV2,
                newDisappearingMessageToken: DisappearingMessageToken?,
                changeAuthorUuid: UUID,
                profileKeys: [UUID: Data]) {
        self.oldGroupModel = oldGroupModel
        self.newGroupModel = newGroupModel
        self.newDisappearingMessageToken = newDisappearingMessageToken
        self.changeAuthorUuid = changeAuthorUuid
        self.profileKeys = profileKeys
    }
}

// MARK: -

public class GroupsV2IncomingChanges: Dependencies {

    // GroupsV2IncomingChanges has one responsibility: applying incremental
    // changes to group models. It should exactly mimic the behavior
    // of the service. Applying these "diffs" allow us to do two things:
    //
    // * Update groups without the burden of contacting the service.
    // * Stay aligned with service state... mostly.
    //
    // We can always deviate due to a bug or due to new "change actions"
    // that the local client doesn't know about. We're not versioning
    // the changes so if we introduce a breaking changes to the "change
    // actions" we'll need to roll out support for the new actions
    // before they go live.
    //
    // This method applies a single set of "change actions" to a group
    // model, thereby deriving a new group model whose revision is
    // exactly 1 higher.
    class func applyChangesToGroupModel(groupThread: TSGroupThread,
                                        changeActionsProto: GroupsProtoGroupChangeActions,
                                        downloadedAvatars: GroupV2DownloadedAvatars,
                                        groupModelOptions: TSGroupModelOptions) throws -> ChangedGroupModel {
        guard let oldGroupModel = groupThread.groupModel as? TSGroupModelV2 else {
            throw OWSAssertionError("Invalid group model.")
        }
        guard let localUuid = tsAccountManager.localUuid else {
            throw OWSAssertionError("Missing localUuid.")
        }
        guard !oldGroupModel.isPlaceholderModel else {
            throw GroupsV2Error.cantApplyChangesToPlaceholder
        }
        let groupV2Params = try oldGroupModel.groupV2Params()
        // Many change actions have author info, e.g. addedByUserID. But we can
        // safely assume that all actions in the "change actions" have the same author.
        guard let changeAuthorUuidData = changeActionsProto.sourceUuid else {
            throw OWSAssertionError("Missing changeAuthorUuid.")
        }
        // Some userIds/uuidCiphertexts can be validated by
        // the service. This is one.
        let changeAuthorUuid = try groupV2Params.uuid(forUserId: changeAuthorUuidData)

        guard changeActionsProto.hasRevision else {
            throw OWSAssertionError("Missing revision.")
        }
        let newRevision = changeActionsProto.revision
        guard newRevision == oldGroupModel.revision + 1 else {
            throw OWSAssertionError("Unexpected revision: \(newRevision) != \(oldGroupModel.revision + 1).")
        }

        var newGroupName: String? = oldGroupModel.groupName
        var newGroupDescription: String? = oldGroupModel.descriptionText
        var newAvatarData: Data? = oldGroupModel.avatarData
        var newAvatarUrlPath = oldGroupModel.avatarUrlPath
        var newInviteLinkPassword: Data? = oldGroupModel.inviteLinkPassword
        var newIsAnnouncementsOnly: Bool = oldGroupModel.isAnnouncementsOnly
        var didJustAddSelfViaGroupLink = false

        let oldGroupMembership = oldGroupModel.groupMembership
        var groupMembershipBuilder = oldGroupMembership.asBuilder

        let oldGroupAccess: GroupAccess = oldGroupModel.access
        var newMembersAccess = oldGroupAccess.members
        var newAttributesAccess = oldGroupAccess.attributes
        var newAddFromInviteLinkAccess = oldGroupAccess.addFromInviteLink

        if !oldGroupMembership.isMemberOfAnyKind(changeAuthorUuid) {
            // Change author may have just added themself via a group invite link.
            Logger.warn("changeAuthorUuid not a member of the group.")
        }
        let isChangeAuthorMember = oldGroupMembership.isFullMember(changeAuthorUuid)
        let isChangeAuthorAdmin = oldGroupMembership.isFullMemberAndAdministrator(changeAuthorUuid)
        let canAddMembers: Bool
        switch oldGroupAccess.members {
        case .unknown:
            canAddMembers = false
        case .member:
            canAddMembers = isChangeAuthorMember
        case .administrator:
            canAddMembers = isChangeAuthorAdmin
        case .any:
            // We no longer honor the "any" level.
            canAddMembers = false
        case .unsatisfiable:
            canAddMembers = false
        }
        let canRemoveMembers = isChangeAuthorAdmin
        let canModifyRoles = isChangeAuthorAdmin
        let canEditAttributes: Bool
        switch oldGroupAccess.attributes {
        case .unknown:
            canEditAttributes = false
        case .member:
            canEditAttributes = isChangeAuthorMember
        case .administrator:
            canEditAttributes = isChangeAuthorAdmin
        case .any:
            // We no longer honor the "any" level.
            canEditAttributes = false
        case .unsatisfiable:
            canEditAttributes = false
        }
        let canEditAccess = isChangeAuthorAdmin
        let canEditInviteLinks = isChangeAuthorAdmin
        let canEditIsAnnouncementsOnly = isChangeAuthorAdmin

        // This client can learn of profile keys from parsing group state protos.
        // After parsing, we should fill in profileKeys in the profile manager.
        var profileKeys = [UUID: Data]()

        for action in changeActionsProto.addMembers {
            let didJoinFromInviteLink = (action.hasJoinFromInviteLink && action.joinFromInviteLink)

            if !canAddMembers && !didJoinFromInviteLink {
                owsFailDebug("Cannot add members.")
            }

            guard let member = action.added else {
                throw OWSAssertionError("Missing member.")
            }
            guard let userId = member.userID else {
                throw OWSAssertionError("Missing userID.")
            }
            guard let protoRole = member.role else {
                throw OWSAssertionError("Missing role.")
            }
            guard let role = TSGroupMemberRole.role(for: protoRole) else {
                throw OWSAssertionError("Invalid role: \(protoRole.rawValue)")
            }
            if role == .administrator && !isChangeAuthorAdmin {
                owsFailDebug("Only admins can add admins.")
            }

            // Some userIds/uuidCiphertexts can be validated by
            // the service. This is one.
            let uuid = try groupV2Params.uuid(forUserId: userId)

            guard !oldGroupMembership.isFullMember(uuid) else {
                throw OWSAssertionError("Invalid membership.")
            }
            groupMembershipBuilder.removeInvalidInvite(userId: userId)
            groupMembershipBuilder.remove(uuid)
            groupMembershipBuilder.addFullMember(uuid, role: role, didJoinFromInviteLink: didJoinFromInviteLink)

            if changeAuthorUuid == localUuid,
               uuid == localUuid {
                didJustAddSelfViaGroupLink = true
            }

            guard let profileKeyCiphertextData = member.profileKey else {
                throw OWSAssertionError("Missing profileKeyCiphertext.")
            }
            let profileKeyCiphertext = try ProfileKeyCiphertext(contents: [UInt8](profileKeyCiphertextData))
            let profileKey = try groupV2Params.profileKey(forProfileKeyCiphertext: profileKeyCiphertext,
                                                          uuid: uuid)

            profileKeys[uuid] = profileKey
        }

        for action in changeActionsProto.deleteMembers {
            guard let userId = action.deletedUserID else {
                throw OWSAssertionError("Missing userID.")
            }
            // Some userIds/uuidCiphertexts can be validated by
            // the service. This is one.
            let uuid = try groupV2Params.uuid(forUserId: userId)

            if !canRemoveMembers && uuid != changeAuthorUuid {
                // Admin can kick any member.
                // Any member can leave the group.
                owsFailDebug("Cannot kick member.")
            }
            if !oldGroupMembership.isFullMember(uuid) {
                owsFailDebug("Invalid membership.")
            }
            groupMembershipBuilder.removeInvalidInvite(userId: userId)
            groupMembershipBuilder.remove(uuid)
        }

        for action in changeActionsProto.modifyMemberRoles {
            if !canModifyRoles {
                owsFailDebug("Cannot modify member role.")
            }

            guard let userId = action.userID else {
                throw OWSAssertionError("Missing userID.")
            }
            guard let protoRole = action.role else {
                throw OWSAssertionError("Missing role.")
            }
            guard let role = TSGroupMemberRole.role(for: protoRole) else {
                throw OWSAssertionError("Invalid role: \(protoRole.rawValue)")
            }

            if !isChangeAuthorAdmin {
                owsFailDebug("Only admins can add admins (or resign as admin).")
            }

            // Some userIds/uuidCiphertexts can be validated by
            // the service. This is one.
            let uuid = try groupV2Params.uuid(forUserId: userId)

            guard oldGroupMembership.isFullMember(uuid) else {
                throw OWSAssertionError("Invalid membership.")
            }
            if oldGroupMembership.role(for: uuid) == role {
                owsFailDebug("Member already has that role.")
            }
            groupMembershipBuilder.remove(uuid)
            groupMembershipBuilder.addFullMember(uuid, role: role)
        }

        for action in changeActionsProto.modifyMemberProfileKeys {
            let (aci, _, profileKey) = try action.getAciProperties(groupV2Params: groupV2Params)

            guard oldGroupMembership.isFullMember(aci) else {
                throw OWSAssertionError("Attempting to modify profile key for ACI that is not a member!")
            }

            profileKeys[aci] = profileKey
        }

        for action in changeActionsProto.addPendingMembers {
            if !canAddMembers {
                owsFailDebug("Cannot invite member.")
            }

            guard let pendingMember = action.added else {
                throw OWSAssertionError("Missing pendingMember.")
            }
            guard let member = pendingMember.member else {
                throw OWSAssertionError("Missing member.")
            }
            guard let userId = member.userID else {
                throw OWSAssertionError("Missing userID.")
            }
            guard let protoRole = member.role else {
                throw OWSAssertionError("Missing role.")
            }
            guard let role = TSGroupMemberRole.role(for: protoRole) else {
                throw OWSAssertionError("Invalid role: \(protoRole.rawValue)")
            }
            guard let addedByUserId = pendingMember.addedByUserID else {
                throw OWSAssertionError("Group pending member missing addedByUserId.")
            }

            // Some userIds/uuidCiphertexts can be validated by
            // the service. This is one.
            let addedByUuid = try groupV2Params.uuid(forUserId: addedByUserId)

            if role == .administrator && !isChangeAuthorAdmin {
                owsFailDebug("Only admins can add admins.")
            }
            if addedByUuid != changeAuthorUuid {
                owsFailDebug("Unexpected addedByUuid.")
            }

            // Some userIds/uuidCiphertexts can be validated by
            // the service. This one cannot.  Therefore we need to
            // be robust to invalid ciphertexts.
            let uuid: UUID
            do {
                uuid = try groupV2Params.uuid(forUserId: userId)
            } catch {
                groupMembershipBuilder.addInvalidInvite(userId: userId, addedByUserId: addedByUserId)
                if DebugFlags.groupsV2ignoreCorruptInvites {
                    Logger.warn("Error parsing uuid: \(error)")
                } else {
                    owsFailDebug("Error parsing uuid: \(error)")
                }
                continue
            }
            guard !oldGroupMembership.isMemberOfAnyKind(uuid) else {
                throw OWSAssertionError("Invalid membership.")
            }
            groupMembershipBuilder.removeInvalidInvite(userId: userId)
            groupMembershipBuilder.remove(uuid)
            groupMembershipBuilder.addInvitedMember(uuid, role: role, addedByUuid: addedByUuid)
        }

        for action in changeActionsProto.deletePendingMembers {
            guard let userId = action.deletedUserID else {
                throw OWSAssertionError("Missing userID.")
            }

            // DeletePendingMemberAction is used to remove invalid invites,
            // so uuid ciphertexts might be invalid.
            do {
                let uuid = try groupV2Params.uuid(forUserId: userId)

                if !canRemoveMembers && uuid != changeAuthorUuid {
                    // Admin can revoke any invitation.
                    // The invitee can decline the invitation.
                    owsFailDebug("Cannot revoke invitation.")
                }

                guard oldGroupMembership.hasInvalidInvite(forUserId: userId) ||
                        oldGroupMembership.isInvitedMember(uuid) else {
                    throw OWSAssertionError("Invalid membership.")
                }
                groupMembershipBuilder.removeInvalidInvite(userId: userId)
                groupMembershipBuilder.remove(uuid)
            } catch {
                if !canRemoveMembers {
                    // Admin can revoke any invitation.
                    owsFailDebug("Cannot revoke invitation.")
                }

                guard oldGroupMembership.hasInvalidInvite(forUserId: userId) else {
                    throw OWSAssertionError("Invalid membership.")
                }
                groupMembershipBuilder.removeInvalidInvite(userId: userId)
            }
        }

        for action in changeActionsProto.promotePendingMembers {
            let (aci, aciCiphertext, profileKey) = try action.getAciProperties(groupV2Params: groupV2Params)

            guard oldGroupMembership.isInvitedMember(aci) else {
                throw OWSAssertionError("Attempting to promote ACI that is not currently invited!")
            }
            guard !oldGroupMembership.isFullMember(aci) else {
                throw OWSAssertionError("Attempting to promote ACI that is already a full member!")
            }
            guard let role = oldGroupMembership.role(for: aci) else {
                throw OWSAssertionError("Attempting to promote ACI, but missing invited role")
            }

            groupMembershipBuilder.removeInvalidInvite(userId: aciCiphertext)
            groupMembershipBuilder.remove(aci)
            groupMembershipBuilder.addFullMember(aci, role: role)

            if aci != changeAuthorUuid {
                // Only the invitee can accept an invitation.
                owsFailDebug("Cannot accept the invitation.")
            }

            profileKeys[aci] = profileKey
        }

        for action in changeActionsProto.addRequestingMembers {
            guard let requestingMember = action.added else {
                throw OWSAssertionError("Missing requestingMember.")
            }
            // Some userIds/uuidCiphertexts can be validated by
            // the service. This is one.
            guard let userId = requestingMember.userID else {
                throw OWSAssertionError("Missing userID.")
            }
            let uuid = try groupV2Params.uuid(forUserId: userId)

            guard let profileKeyCiphertextData = requestingMember.profileKey else {
                throw OWSAssertionError("Missing profileKeyCiphertext.")
            }
            let profileKeyCiphertext = try ProfileKeyCiphertext(contents: [UInt8](profileKeyCiphertextData))
            let profileKey = try groupV2Params.profileKey(forProfileKeyCiphertext: profileKeyCiphertext,
                                                          uuid: uuid)

            guard !oldGroupMembership.isMemberOfAnyKind(uuid) else {
                throw OWSAssertionError("Invalid membership.")
            }
            groupMembershipBuilder.removeInvalidInvite(userId: userId)
            groupMembershipBuilder.remove(uuid)
            groupMembershipBuilder.addRequestingMember(uuid)

            profileKeys[uuid] = profileKey
        }

        for action in changeActionsProto.deleteRequestingMembers {

            guard let userId = action.deletedUserID else {
                throw OWSAssertionError("Missing userID.")
            }
            // Some userIds/uuidCiphertexts can be validated by
            // the service. This is one.
            let uuid = try groupV2Params.uuid(forUserId: userId)

            if !canRemoveMembers && uuid != changeAuthorUuid {
                owsFailDebug("Cannot remove members.")
            }

            guard oldGroupMembership.isMemberOfAnyKind(uuid) else {
                throw OWSAssertionError("Invalid membership.")
            }

            groupMembershipBuilder.removeInvalidInvite(userId: userId)
            groupMembershipBuilder.remove(uuid)
        }

        for action in changeActionsProto.promoteRequestingMembers {
            guard let userId = action.userID else {
                throw OWSAssertionError("Missing userID.")
            }
            // Some userIds/uuidCiphertexts can be validated by
            // the service. This is one.
            let uuid = try groupV2Params.uuid(forUserId: userId)

            if oldGroupModel.isPlaceholderModel {
                // We can't check permissions using a placeholder.
            } else if !canAddMembers && uuid != changeAuthorUuid {
                owsFailDebug("Cannot add members.")
            }

            guard let protoRole = action.role else {
                throw OWSAssertionError("Missing role.")
            }
            guard let role = TSGroupMemberRole.role(for: protoRole) else {
                throw OWSAssertionError("Invalid role: \(protoRole.rawValue)")
            }

            guard oldGroupMembership.isRequestingMember(uuid) else {
                throw OWSAssertionError("Invalid membership.")
            }
            groupMembershipBuilder.removeInvalidInvite(userId: userId)
            groupMembershipBuilder.remove(uuid)
            groupMembershipBuilder.addFullMember(uuid, role: role)
        }

        for action in changeActionsProto.addBannedMembers {
            guard
                let userId = action.added?.userID,
                let bannedAtTimestamp = action.added?.bannedAtTimestamp
            else {
                throw OWSAssertionError("Invalid addBannedMember action")
            }

            let uuid = try groupV2Params.uuid(forUserId: userId)

            groupMembershipBuilder.addBannedMember(uuid, bannedAtTimestamp: bannedAtTimestamp)
        }

        for action in changeActionsProto.deleteBannedMembers {
            guard let userId = action.deletedUserID else {
                throw OWSAssertionError("Invalid deleteBannedMember action")
            }

            let uuid = try groupV2Params.uuid(forUserId: userId)

            groupMembershipBuilder.removeBannedMember(uuid)
        }

        if let action = changeActionsProto.modifyTitle {
            if !canEditAttributes {
                owsFailDebug("Cannot modify title.")
            }

            // Change clears or updates the group title.
            newGroupName = groupV2Params.decryptGroupName(action.title)
        }

        if let action = changeActionsProto.modifyDescription {
            if !canEditAttributes {
                owsFailDebug("Cannot modify description.")
            }

            // Change clears or updates the group title.
            newGroupDescription = groupV2Params.decryptGroupDescription(action.descriptionBytes)
        }

        if let action = changeActionsProto.modifyAvatar {
            if !canEditAttributes {
                owsFailDebug("Cannot modify avatar.")
            }

            if let avatarUrl = action.avatar,
               !avatarUrl.isEmpty {
                do {
                    newAvatarData = try downloadedAvatars.avatarData(for: avatarUrl)
                    newAvatarUrlPath = avatarUrl
                } catch {
                    owsFailDebug("Missing or invalid avatar: \(error)")
                    newAvatarData = nil
                    newAvatarUrlPath = nil
                }
            } else {
                // Change clears the group avatar.
                newAvatarData = nil
                newAvatarUrlPath = nil
            }
        }

        var newDisappearingMessageToken: DisappearingMessageToken?
        if let action = changeActionsProto.modifyDisappearingMessagesTimer {
            if !canEditAttributes {
                owsFailDebug("Cannot modify disappearing message timer.")
            }

            // If the timer blob is not populated or has zero duration,
            // disappearing messages should be disabled.
            newDisappearingMessageToken = groupV2Params.decryptDisappearingMessagesTimer(action.timer)
        }

        if let action = changeActionsProto.modifyAttributesAccess {
            if !canEditAccess {
                owsFailDebug("Cannot edit attributes access.")
            }

            guard let protoAccess = action.attributesAccess else {
                throw OWSAssertionError("Missing access.")
            }
            newAttributesAccess = GroupV2Access.access(forProtoAccess: protoAccess)

            if newAttributesAccess == .unknown {
                owsFailDebug("Unknown attributes access.")
            }
        }

        if let action = changeActionsProto.modifyMemberAccess {
            if !canEditAccess {
                owsFailDebug("Cannot edit member access.")
            }

            guard let protoAccess = action.membersAccess else {
                throw OWSAssertionError("Missing access.")
            }
            newMembersAccess = GroupV2Access.access(forProtoAccess: protoAccess)

            if newMembersAccess == .unknown {
                owsFailDebug("Unknown member access.")
            }
        }

        if let action = changeActionsProto.modifyAddFromInviteLinkAccess {
            if !canEditInviteLinks {
                owsFailDebug("Cannot edit addFromInviteLink access.")
            }

            guard let protoAccess = action.addFromInviteLinkAccess else {
                throw OWSAssertionError("Missing access.")
            }
            newAddFromInviteLinkAccess = GroupV2Access.access(forProtoAccess: protoAccess)

            if newAddFromInviteLinkAccess == .unknown {
                owsFailDebug("Unknown addFromInviteLink access.")
            }
        }

        if let action = changeActionsProto.modifyInviteLinkPassword {
            if !canEditInviteLinks {
                owsFailDebug("Cannot modify inviteLinkPassword.")
            }

            // Change clears or updates the group inviteLinkPassword.
            newInviteLinkPassword = action.inviteLinkPassword
        }

        if let action = changeActionsProto.modifyAnnouncementsOnly {
            if !canEditIsAnnouncementsOnly {
                owsFailDebug("Cannot modify inviteLinkPassword.")
            }

            newIsAnnouncementsOnly = action.announcementsOnly
        }

        let newGroupMembership = groupMembershipBuilder.build()
        let newGroupAccess = GroupAccess(members: newMembersAccess, attributes: newAttributesAccess, addFromInviteLink: newAddFromInviteLinkAccess)

        GroupsV2Protos.validateInviteLinkState(inviteLinkPassword: newInviteLinkPassword, groupAccess: newGroupAccess)

        var builder = oldGroupModel.asBuilder
        builder.name = newGroupName
        builder.descriptionText = newGroupDescription
        builder.avatarData = newAvatarData
        builder.groupMembership = newGroupMembership
        builder.groupAccess = newGroupAccess
        builder.groupV2Revision = newRevision
        builder.avatarUrlPath = newAvatarUrlPath
        builder.inviteLinkPassword = newInviteLinkPassword
        builder.isAnnouncementsOnly = newIsAnnouncementsOnly

        builder.didJustAddSelfViaGroupLink = didJustAddSelfViaGroupLink

        builder.apply(options: groupModelOptions)

        let newGroupModel = try builder.buildAsV2()

        return ChangedGroupModel(oldGroupModel: oldGroupModel,
                                 newGroupModel: newGroupModel,
                                 newDisappearingMessageToken: newDisappearingMessageToken,
                                 changeAuthorUuid: changeAuthorUuid,
                                 profileKeys: profileKeys)
    }
}

// MARK: - HasAciAndProfileKey

private protocol HasAciAndProfileKey {
    var userID: Data? { get }
    var profileKey: Data? { get }
    var presentation: Data? { get }
}

extension GroupsProtoGroupChangeActionsModifyMemberProfileKeyAction: HasAciAndProfileKey {}
extension GroupsProtoGroupChangeActionsPromotePendingMemberAction: HasAciAndProfileKey {}

private extension HasAciAndProfileKey {
    typealias AciProperties = (
        aci: UUID,
        aciCiphertext: Data,
        profileKey: Data
    )

    func getAciProperties(groupV2Params: GroupV2Params) throws -> AciProperties {
        if
            let aciCiphertext = userID,
            let profileKeyData = profileKey
        {
            let aci = try groupV2Params.uuid(forUserId: aciCiphertext)

            let profileKeyCiphertext = try ProfileKeyCiphertext(contents: [UInt8](profileKeyData))
            let profileKey = try groupV2Params.profileKey(
                forProfileKeyCiphertext: profileKeyCiphertext,
                uuid: aci
            )

            return (
                aci: aci,
                aciCiphertext: aciCiphertext,
                profileKey: profileKey
            )
        } else if let presentationData = presentation {
            // We should only ever fall back to presentation data if a client
            // is parsing *old* group history, since the server has been writing
            // the properties required for the block above for a long time.

            let presentation = try ProfileKeyCredentialPresentation(contents: [UInt8](presentationData))
            let aciCiphertext = try presentation.getUuidCiphertext()
            let aci = try groupV2Params.uuid(forUuidCiphertext: aciCiphertext)

            let profileKeyCiphertext = try presentation.getProfileKeyCiphertext()
            let profileKey = try groupV2Params.profileKey(
                forProfileKeyCiphertext: profileKeyCiphertext,
                uuid: aci
            )

            return (
                aci: aci,
                aciCiphertext: aciCiphertext.serialize().asData,
                profileKey: profileKey
            )
        } else {
            throw OWSAssertionError("Malformed proto!")
        }
    }
}
