//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import LibSignalClient

// Represents a proposed set of changes to a group.
//
// There are up to three group revisions involved:
//
// * "old" (e.g. oldGroupModel): the group model before the changes were made.
// * "modified" (e.g. modifiedGroupModel): the group model after the changes were made.
// * "current" (e.g. currentGroupModel): the group model at the time we apply the changes.
//
// Example:
//
// * User edits a group at "old" revision N.
// * Client diff against a "modified" group model and determines that the title changed
//   and captures that in this instance.
// * We try to update the group on the service, computing a GroupChange proto against
//   the latest known revision N.
// * Another client has made (possibly conflicting) changes. Group is now at revision
//   N+1 on service.
// * We try again, computing a new GroupChange proto against revision N+1.
//
// This class serves two roles:
//
// * To capture the user intent (i.e. the difference between "old" and "modified").
// * To try to generate a "change" proto that applies that intent to the latest group state.
//
// The latter can be non-trivial:
//
// * If we try to add a new member and another user beats us to it, we'll throw
//   GroupsV2Error.redundantChange when computing a GroupChange proto.
// * If we add (alice and bob) but another user adds (alice) first, we'll just add (bob).
@objc
public class GroupsV2OutgoingChangesImpl: NSObject, GroupsV2OutgoingChanges {

    public let groupId: Data
    public let groupSecretParamsData: Data

    // MARK: -

    // These properties capture the original intent of the local user.
    //
    // NOTE: These properties generally _DO NOT_ capture the new state of the group;
    // they capture only "changed" aspects of group state.
    //
    // NOTE: Even if set, these properties _DO NOT_ necessarily translate into
    // "change actions"; we only need to build change actions if _current_ group
    // state differs from the "changed" group state.  Our client might race with
    // similar changes made by other group members/clients.  We can & must skip
    // redundant changes.

    // Non-nil if changed. Should not be able to be set to an empty string.
    private var newTitle: String?

    // Non-nil if changed. Empty string is allowed.
    private var newDescriptionText: String?

    public var newAvatarData: Data?
    public var newAvatarUrlPath: String?
    private var shouldUpdateAvatar = false

    private var membersToAdd = [UUID: TSGroupMemberRole]()
    // Full, pending profile key or pending request members to remove.
    private var membersToRemove = [UUID]()
    private var membersToChangeRole = [UUID: TSGroupMemberRole]()
    private var invitedMembersToAdd = [UUID: TSGroupMemberRole]()
    private var invalidInvitesToRemove = [Data: InvalidInvite]()
    private var invitedMembersToPromote = [UUID]()

    // Banning
    private var membersToBan = [UUID]()
    private var membersToUnban = [UUID]()

    // These access properties should only be set if the value is changing.
    private var accessForMembers: GroupV2Access?
    private var accessForAttributes: GroupV2Access?
    private var accessForAddFromInviteLink: GroupV2Access?

    private enum InviteLinkPasswordMode {
        case ignore
        case rotate
        case ensureValid
    }

    private var inviteLinkPasswordMode: InviteLinkPasswordMode?

    private var shouldLeaveGroupDeclineInvite = false
    private var shouldRevokeInvalidInvites = false

    // Non-nil if the value changed.
    private var isAnnouncementsOnly: Bool?

    private var shouldUpdateLocalProfileKey = false

    private var newLinkMode: GroupsV2LinkMode?

    // Non-nil if dm state changed.
    private var newDisappearingMessageToken: DisappearingMessageToken?

    public init(groupId: Data, groupSecretParamsData: Data) {
        self.groupId = groupId
        self.groupSecretParamsData = groupSecretParamsData
    }

    public init(for groupModel: TSGroupModelV2) {
        self.groupId = groupModel.groupId
        self.groupSecretParamsData = groupModel.secretParamsData
    }

    public func setTitle(_ value: String) {
        owsAssertDebug(self.newTitle == nil)
        owsAssertDebug(!value.isEmpty)
        self.newTitle = value
    }

    public func setDescriptionText(_ value: String?) {
        owsAssertDebug(self.newDescriptionText == nil)
        self.newDescriptionText = value ?? ""
    }

    public func setAvatar(_ avatar: (data: Data, urlPath: String)?) {
        owsAssertDebug(self.newAvatarData == nil)
        owsAssertDebug(self.newAvatarUrlPath == nil)
        owsAssertDebug(!self.shouldUpdateAvatar)

        self.newAvatarData = avatar?.data
        self.newAvatarUrlPath = avatar?.urlPath
        self.shouldUpdateAvatar = true
    }

    public func addMember(_ uuid: UUID, role: TSGroupMemberRole) {
        owsAssertDebug(membersToAdd[uuid] == nil)
        membersToAdd[uuid] = role
    }

    @objc
    public func removeMember(_ uuid: UUID) {
        owsAssertDebug(!membersToRemove.contains(uuid))
        membersToRemove.append(uuid)
    }

    public func addBannedMember(_ uuid: UUID) {
        owsAssertDebug(!membersToBan.contains(uuid))
        membersToBan.append(uuid)
    }

    public func removeBannedMember(_ uuid: UUID) {
        owsAssertDebug(!membersToUnban.contains(uuid))
        membersToUnban.append(uuid)
    }

    @objc
    public func promoteInvitedMember(_ uuid: UUID) {
        owsAssertDebug(!invitedMembersToPromote.contains(uuid))
        invitedMembersToPromote.append(uuid)
    }

    public func changeRoleForMember(_ uuid: UUID, role: TSGroupMemberRole) {
        owsAssertDebug(membersToChangeRole[uuid] == nil)
        membersToChangeRole[uuid] = role
    }

    public func addInvitedMember(_ uuid: UUID, role: TSGroupMemberRole) {
        owsAssertDebug(invitedMembersToAdd[uuid] == nil)
        invitedMembersToAdd[uuid] = role
    }

    public func setShouldLeaveGroupDeclineInvite() {
        owsAssertDebug(!shouldLeaveGroupDeclineInvite)
        shouldLeaveGroupDeclineInvite = true
    }

    public func removeInvalidInvite(invalidInvite: InvalidInvite) {
        owsAssertDebug(invalidInvitesToRemove[invalidInvite.userId] == nil)
        invalidInvitesToRemove[invalidInvite.userId] = invalidInvite
    }

    public func setAccessForMembers(_ value: GroupV2Access) {
        owsAssertDebug(accessForMembers == nil)
        accessForMembers = value
    }

    public func setAccessForAttributes(_ value: GroupV2Access) {
        owsAssertDebug(accessForAttributes == nil)
        accessForAttributes = value
    }

    public func setNewDisappearingMessageToken(_ newDisappearingMessageToken: DisappearingMessageToken) {
        owsAssertDebug(self.newDisappearingMessageToken == nil)
        self.newDisappearingMessageToken = newDisappearingMessageToken
    }

    public func revokeInvalidInvites() {
        owsAssertDebug(!shouldRevokeInvalidInvites)
        shouldRevokeInvalidInvites = true
    }

    public func setLinkMode(_ linkMode: GroupsV2LinkMode) {
        owsAssertDebug(accessForAddFromInviteLink == nil)
        owsAssertDebug(inviteLinkPasswordMode == nil)

        switch linkMode {
        case .disabled:
            accessForAddFromInviteLink = .unsatisfiable
            inviteLinkPasswordMode = .ignore
        case .enabledWithoutApproval, .enabledWithApproval:
            accessForAddFromInviteLink = (linkMode == .enabledWithoutApproval
                                            ? .any
                                            : .administrator)
            inviteLinkPasswordMode = .ensureValid
        }
    }

    public func rotateInviteLinkPassword() {
        owsAssertDebug(inviteLinkPasswordMode == nil)

        inviteLinkPasswordMode = .rotate
    }

    public func setIsAnnouncementsOnly(_ isAnnouncementsOnly: Bool) {
        owsAssertDebug(self.isAnnouncementsOnly == nil)

        self.isAnnouncementsOnly = isAnnouncementsOnly
    }

    public func setShouldUpdateLocalProfileKey() {
        owsAssertDebug(!shouldUpdateLocalProfileKey)
        shouldUpdateLocalProfileKey = true
    }

    // MARK: - Change Protos

    // Given the "current" group state, build a change proto that
    // reflects the elements of the "original intent" that are still
    // necessary to perform.
    //
    // See comments on buildGroupChangeProto() below.
    public func buildGroupChangeProto(
        currentGroupModel: TSGroupModelV2,
        currentDisappearingMessageToken: DisappearingMessageToken,
        forceRefreshProfileKeyCredentials: Bool
    ) -> Promise<GroupsProtoGroupChangeActions> {
        guard groupId == currentGroupModel.groupId else {
            return Promise(error: OWSAssertionError("Mismatched groupId."))
        }
        guard let localUuid = tsAccountManager.localUuid else {
            return Promise(error: OWSAssertionError("Missing localUuid."))
        }

        // Note that we're calculating the set of users for whom we need
        // profile key credentials for based on the "original intent".
        // We could slightly optimize by only gathering profile key
        // credentials that we'll actually need to build the change proto.
        //
        // NOTE: We don't (and can't) gather profile key credentials for pending members.
        var newUserUuids: Set<UUID> = Set(membersToAdd.keys).union(invitedMembersToPromote)
        newUserUuids.insert(localUuid)

        return firstly(on: DispatchQueue.global()) { () -> Promise<GroupsV2Swift.ProfileKeyCredentialMap> in
            self.groupsV2Swift.loadProfileKeyCredentials(
                for: Array(newUserUuids),
                forceRefresh: forceRefreshProfileKeyCredentials
            )
        }.map(on: DispatchQueue.global()) { (profileKeyCredentialMap: GroupsV2Swift.ProfileKeyCredentialMap) throws -> GroupsProtoGroupChangeActions in
            try self.buildGroupChangeProto(
                currentGroupModel: currentGroupModel,
                currentDisappearingMessageToken: currentDisappearingMessageToken,
                profileKeyCredentialMap: profileKeyCredentialMap
            )
        }
    }

    // Given the "current" group state, build a change proto that
    // reflects the elements of the "original intent" that are still
    // necessary to perform.
    //
    // This method builds the actual set of actions _that are still necessary_.
    // Conflicts can occur due to races. This is where we make a best effort to
    // resolve conflicts.
    //
    // Conflict resolution guidelines:
    //
    // * “Orthogonal” changes are resolved by simply retrying.
    //   * If you're trying to change the avatar and someone
    //     else changes the title, there is no conflict.
    // * Many conflicts can be resolved by “last writer wins”.
    //   * E.g. changes to group name or avatar.
    // * We skip identical changes.
    //   * If you want to add Alice but Carol has already
    //     added Alice, we treat this as redundant.
    // * "Overlapping" changes are not conflicts.
    //   * If you want to add (Alice and Bob) but Carol has already
    //     added Alice, we convert your intent to just adding Bob.
    // * We skip similar changes when they have similar intent.
    //   * If you try to add Alice but Bob has already invited
    //     Alice, we treat these as redundant. The intent - to get
    //     Alice into the group - is the same.
    // * We skip similar changes when they differ in details.
    //   * If you try to add Alice as admin and Bob has already
    //     added Alice as a normal member, we treat these as
    //     redundant.  We could convert your intent into
    //     changing Alice's role, but that can confuse the user.
    // * We treat "obsolete" changes as an unresolvable conflict.
    //   * If you try to change Alice's role to admin and Bob has
    //     already kicked out Alice, we throw
    //     GroupsV2Error.conflictingChange.
    //
    // Essentially, our strategy is to "apply any changes that
    // still make sense".  If no changes do, we throw
    // GroupsV2Error.redundantChange.
    private func buildGroupChangeProto(currentGroupModel: TSGroupModelV2,
                                       currentDisappearingMessageToken: DisappearingMessageToken,
                                       profileKeyCredentialMap: GroupsV2Swift.ProfileKeyCredentialMap) throws -> GroupsProtoGroupChangeActions {
        let groupV2Params = try currentGroupModel.groupV2Params()

        var actionsBuilder = GroupsProtoGroupChangeActions.builder()
        guard let localUuid = tsAccountManager.localUuid else {
            throw OWSAssertionError("Missing localUuid.")
        }

        let oldRevision = currentGroupModel.revision
        let newRevision = oldRevision + 1
        Logger.verbose("Revision: \(oldRevision) -> \(newRevision)")
        actionsBuilder.setRevision(newRevision)

        // Track member counts that are updated to reflect each
        // new action.
        var remainingMemberOfAnyKindUuids = Set(currentGroupModel.groupMembership.allMembersOfAnyKind.compactMap { $0.uuid })
        var remainingFullMemberUuids = Set(currentGroupModel.groupMembership.fullMembers.compactMap { $0.uuid })
        var remainingAdminUuids = Set(currentGroupModel.groupMembership.fullMemberAdministrators.compactMap { $0.uuid })

        var didChange = false

        if let newTitle = self.newTitle {
            if newTitle == currentGroupModel.groupName {
                // Redundant change, not a conflict.
            } else {
                let encryptedData = try groupV2Params.encryptGroupName(newTitle)
                guard newTitle.glyphCount <= GroupManager.maxGroupNameGlyphCount else {
                    throw OWSAssertionError("groupTitle is too long.")
                }
                guard encryptedData.count <= GroupManager.maxGroupNameEncryptedByteCount else {
                    throw OWSAssertionError("Encrypted groupTitle is too long.")
                }
                var actionBuilder = GroupsProtoGroupChangeActionsModifyTitleAction.builder()
                actionBuilder.setTitle(encryptedData)
                actionsBuilder.setModifyTitle(try actionBuilder.build())
                didChange = true
            }
        }

        if let newDescriptionText = self.newDescriptionText {
            if newDescriptionText.nilIfEmpty == currentGroupModel.descriptionText?.nilIfEmpty {
                // Redundant change, not a conflict.
            } else {
                guard newDescriptionText.glyphCount <= GroupManager.maxGroupDescriptionGlyphCount else {
                    throw OWSAssertionError("group description is too long.")
                }
                let encryptedData = try groupV2Params.encryptGroupDescription(newDescriptionText)
                guard encryptedData.count <= GroupManager.maxGroupDescriptionEncryptedByteCount else {
                    throw OWSAssertionError("Encrypted group description is too long.")
                }
                var actionBuilder = GroupsProtoGroupChangeActionsModifyDescriptionAction.builder()
                actionBuilder.setDescriptionBytes(encryptedData)
                actionsBuilder.setModifyDescription(try actionBuilder.build())
                didChange = true
            }
        }

        if shouldUpdateAvatar {
            if newAvatarUrlPath == currentGroupModel.avatarUrlPath {
                // Redundant change, not a conflict.
                owsFailDebug("This should never occur.")
            } else {
                var actionBuilder = GroupsProtoGroupChangeActionsModifyAvatarAction.builder()
                if let avatarUrlPath = newAvatarUrlPath {
                    actionBuilder.setAvatar(avatarUrlPath)
                } else {
                    // We're clearing the avatar.
                }
                actionsBuilder.setModifyAvatar(try actionBuilder.build())
                didChange = true
            }
        }

        if let inviteLinkPasswordMode = inviteLinkPasswordMode {
            let newInviteLinkPassword: Data?
            switch inviteLinkPasswordMode {
            case .ignore:
                newInviteLinkPassword = currentGroupModel.inviteLinkPassword
            case .rotate:
                newInviteLinkPassword = GroupManager.generateInviteLinkPasswordV2()
            case .ensureValid:
                if let oldInviteLinkPassword = currentGroupModel.inviteLinkPassword,
                   !oldInviteLinkPassword.isEmpty {
                    newInviteLinkPassword = oldInviteLinkPassword
                } else {
                    newInviteLinkPassword = GroupManager.generateInviteLinkPasswordV2()
                }
            }

            if newInviteLinkPassword == currentGroupModel.inviteLinkPassword {
                // Redundant change, not a conflict.
            } else {
                var actionBuilder = GroupsProtoGroupChangeActionsModifyInviteLinkPasswordAction.builder()
                if let inviteLinkPassword = newInviteLinkPassword {
                    actionBuilder.setInviteLinkPassword(inviteLinkPassword)
                }
                actionsBuilder.setModifyInviteLinkPassword(try actionBuilder.build())
                didChange = true
            }
        }

        let currentGroupMembership = currentGroupModel.groupMembership
        for (uuid, role) in membersToAdd {
            guard !currentGroupMembership.isFullMember(uuid) else {
                // Another user has already added this member.
                // They may have been added with a different role.
                // We don't treat that as a conflict.
                continue
            }
            if currentGroupMembership.isRequestingMember(uuid) {
                var actionBuilder = GroupsProtoGroupChangeActionsPromoteRequestingMemberAction.builder()
                let userId = try groupV2Params.userId(forUuid: uuid)
                actionBuilder.setUserID(userId)
                actionBuilder.setRole(role.asProtoRole)
                actionsBuilder.addPromoteRequestingMembers(try actionBuilder.build())

                remainingMemberOfAnyKindUuids.insert(uuid)
                remainingFullMemberUuids.insert(uuid)
                if role == .administrator {
                    remainingAdminUuids.insert(uuid)
                }
            } else {
                guard let profileKeyCredential = profileKeyCredentialMap[uuid] else {
                    throw OWSAssertionError("Missing profile key credential: \(uuid)")
                }
                var actionBuilder = GroupsProtoGroupChangeActionsAddMemberAction.builder()
                actionBuilder.setAdded(try GroupsV2Protos.buildMemberProto(profileKeyCredential: profileKeyCredential,
                                                                           role: role.asProtoRole,
                                                                           groupV2Params: groupV2Params))
                actionsBuilder.addAddMembers(try actionBuilder.build())

                remainingMemberOfAnyKindUuids.insert(uuid)
                remainingFullMemberUuids.insert(uuid)
                if role == .administrator {
                    remainingAdminUuids.insert(uuid)
                }
            }
            didChange = true
        }

        for uuid in self.membersToRemove {
            if currentGroupMembership.isFullMember(uuid) {
                var actionBuilder = GroupsProtoGroupChangeActionsDeleteMemberAction.builder()
                let userId = try groupV2Params.userId(forUuid: uuid)
                actionBuilder.setDeletedUserID(userId)
                actionsBuilder.addDeleteMembers(try actionBuilder.build())
                didChange = true

                remainingMemberOfAnyKindUuids.remove(uuid)
                remainingFullMemberUuids.remove(uuid)
                if currentGroupMembership.isFullMemberAndAdministrator(uuid) {
                    remainingAdminUuids.remove(uuid)
                }
            } else if currentGroupMembership.isInvitedMember(uuid) {
                var actionBuilder = GroupsProtoGroupChangeActionsDeletePendingMemberAction.builder()
                let userId = try groupV2Params.userId(forUuid: uuid)
                actionBuilder.setDeletedUserID(userId)
                actionsBuilder.addDeletePendingMembers(try actionBuilder.build())
                didChange = true

                remainingMemberOfAnyKindUuids.remove(uuid)
                remainingFullMemberUuids.remove(uuid)
            } else if currentGroupMembership.isRequestingMember(uuid) {
                var actionBuilder = GroupsProtoGroupChangeActionsDeleteRequestingMemberAction.builder()
                let userId = try groupV2Params.userId(forUuid: uuid)
                actionBuilder.setDeletedUserID(userId)
                actionsBuilder.addDeleteRequestingMembers(try actionBuilder.build())
                didChange = true

                remainingMemberOfAnyKindUuids.remove(uuid)
                remainingFullMemberUuids.remove(uuid)
            } else {
                // Another user has already removed this member or revoked their
                // invitation.
                // Redundant change, not a conflict.
                continue
            }
        }

        do {
            // Only ban/unban if relevant according to current group membership
            let uuidsToBan = membersToBan.filter { !currentGroupMembership.isBannedMember($0) }
            var uuidsToUnban = membersToUnban.filter { currentGroupMembership.isBannedMember($0) }

            let currentBannedMembers = currentGroupMembership.bannedMembers

            // If we will overrun the max number of banned members, unban currently
            // banned members until we have enough room, beginning with the
            // least-recently banned.
            let maxNumBannableIds = RemoteConfig.groupsV2MaxBannedMembers
            let netNumIdsToBan = uuidsToBan.count - uuidsToUnban.count
            let nOldMembersToUnban = currentBannedMembers.count + netNumIdsToBan - Int(maxNumBannableIds)

            if nOldMembersToUnban > 0 {
                let bannedSortedByAge = currentBannedMembers.sorted { member1, member2 -> Bool in
                    // Lower bannedAt time goes first
                    member1.value < member2.value
                }.map { (uuid, _) -> UUID in uuid }

                uuidsToUnban += bannedSortedByAge.prefix(nOldMembersToUnban)
            }

            // Build the bans
            for uuid in uuidsToBan {
                let bannedMember = try GroupsV2Protos.buildBannedMemberProto(uuid: uuid, groupV2Params: groupV2Params)

                var actionBuilder = GroupsProtoGroupChangeActionsAddBannedMemberAction.builder()
                actionBuilder.setAdded(bannedMember)

                actionsBuilder.addAddBannedMembers(try actionBuilder.build())
                didChange = true
            }

            // Build the unbans
            for uuid in uuidsToUnban {
                let userId = try groupV2Params.userId(forUuid: uuid)

                var actionBuilder = GroupsProtoGroupChangeActionsDeleteBannedMemberAction.builder()
                actionBuilder.setDeletedUserID(userId)

                actionsBuilder.addDeleteBannedMembers(try actionBuilder.build())
                didChange = true
            }
        }

        for (uuid, role) in self.invitedMembersToAdd {
            guard !currentGroupMembership.isMemberOfAnyKind(uuid) else {
                // Another user has already added or invited this member.
                // They may have been added with a different role.
                // We don't treat that as a conflict.
                continue
            }

            guard remainingMemberOfAnyKindUuids.count <= GroupManager.groupsV2MaxGroupSizeHardLimit else {
                throw GroupsV2Error.cannotBuildGroupChangeProto_tooManyMembers
            }

            var actionBuilder = GroupsProtoGroupChangeActionsAddPendingMemberAction.builder()
            actionBuilder.setAdded(try GroupsV2Protos.buildPendingMemberProto(uuid: uuid,
                                                                              role: role.asProtoRole,
                                                                              localUuid: localUuid,
                                                                              groupV2Params: groupV2Params))
            actionsBuilder.addAddPendingMembers(try actionBuilder.build())
            didChange = true

            remainingMemberOfAnyKindUuids.insert(uuid)
            if role == .administrator {
                remainingAdminUuids.insert(uuid)
            }
        }

        if shouldRevokeInvalidInvites {
            if currentGroupMembership.invalidInvites.count < 1 {
                // Another user has already revoked any invalid invites.
                // We don't treat that as a conflict.
                owsFailDebug("No invalid invites to revoke.")
            }
            for invalidInvite in currentGroupMembership.invalidInvites {
                var actionBuilder = GroupsProtoGroupChangeActionsDeletePendingMemberAction.builder()
                actionBuilder.setDeletedUserID(invalidInvite.userId)
                actionsBuilder.addDeletePendingMembers(try actionBuilder.build())
                didChange = true
            }
        } else {
            for invalidInvite in invalidInvitesToRemove.values {
                guard currentGroupMembership.hasInvalidInvite(forUserId: invalidInvite.userId) else {
                    // Another user has already removed this invite.
                    // We don't treat that as a conflict.
                    continue
                }

                var actionBuilder = GroupsProtoGroupChangeActionsDeletePendingMemberAction.builder()
                actionBuilder.setDeletedUserID(invalidInvite.userId)
                actionsBuilder.addDeletePendingMembers(try actionBuilder.build())
                didChange = true
            }
        }

        for (uuid, newRole) in self.membersToChangeRole {
            guard currentGroupMembership.isFullMember(uuid) else {
                // User is no longer a member.
                throw GroupsV2Error.cannotBuildGroupChangeProto_conflictingChange
            }
            let currentRole = currentGroupMembership.role(for: uuid)
            guard currentRole != newRole else {
                // Another user has already modified the role of this member.
                // We don't treat that as a conflict.
                continue
            }
            var actionBuilder = GroupsProtoGroupChangeActionsModifyMemberRoleAction.builder()
            let userId = try groupV2Params.userId(forUuid: uuid)
            actionBuilder.setUserID(userId)
            actionBuilder.setRole(newRole.asProtoRole)
            actionsBuilder.addModifyMemberRoles(try actionBuilder.build())
            didChange = true

            if currentRole == .administrator {
                remainingAdminUuids.remove(uuid)
            } else if newRole == .administrator {
                remainingAdminUuids.insert(uuid)
            }
        }

        let currentAccess = currentGroupModel.access
        if let access = self.accessForMembers {
            if currentAccess.members == access {
                // Redundant change, not a conflict.
            } else {
                var actionBuilder = GroupsProtoGroupChangeActionsModifyMembersAccessControlAction.builder()
                actionBuilder.setMembersAccess(access.protoAccess)
                actionsBuilder.setModifyMemberAccess(try actionBuilder.build())
                didChange = true
            }
        }
        if let access = self.accessForAttributes {
            if currentAccess.attributes == access {
                // Redundant change, not a conflict.
            } else {
                var actionBuilder = GroupsProtoGroupChangeActionsModifyAttributesAccessControlAction.builder()
                actionBuilder.setAttributesAccess(access.protoAccess)
                actionsBuilder.setModifyAttributesAccess(try actionBuilder.build())
                didChange = true
            }
        }

        var accessForAddFromInviteLink = self.accessForAddFromInviteLink
        if currentGroupMembership.allMembersOfAnyKind.count == 1 &&
            currentGroupMembership.isFullMemberAndAdministrator(localUuid) &&
            self.shouldLeaveGroupDeclineInvite {
            // If we're the last admin to leave the group,
            // disable the group invite link.
            accessForAddFromInviteLink = .unsatisfiable
        }

        if let access = accessForAddFromInviteLink {
            if currentAccess.addFromInviteLink == access {
                // Redundant change, not a conflict.
            } else {
                var actionBuilder = GroupsProtoGroupChangeActionsModifyAddFromInviteLinkAccessControlAction.builder()
                actionBuilder.setAddFromInviteLinkAccess(access.protoAccess)
                actionsBuilder.setModifyAddFromInviteLinkAccess(try actionBuilder.build())
                didChange = true
            }
        }

        for uuid in invitedMembersToPromote {
            if currentGroupMembership.isInvitedMember(uuid) {
                guard let profileKeyCredential = profileKeyCredentialMap[uuid] else {
                    throw OWSAssertionError("Missing profile key credential: \(uuid)")
                }

                var actionBuilder = GroupsProtoGroupChangeActionsPromotePendingMemberAction.builder()
                actionBuilder.setPresentation(try GroupsV2Protos.presentationData(
                    profileKeyCredential: profileKeyCredential,
                    groupV2Params: groupV2Params
                ))

                actionsBuilder.addPromotePendingMembers(try actionBuilder.build())
                didChange = true

                remainingMemberOfAnyKindUuids.insert(uuid)
                remainingFullMemberUuids.insert(uuid)
            } else if currentGroupMembership.isFullMember(uuid) {
                // Redundant change, not a conflict.
            } else {
                throw GroupsV2Error.cannotBuildGroupChangeProto_conflictingChange
            }

        }

        if self.shouldLeaveGroupDeclineInvite {
            let canLeaveGroup = GroupManager.canLocalUserLeaveGroupWithoutChoosingNewAdmin(localUuid: localUuid,
                                                                                           remainingFullMemberUuids: remainingFullMemberUuids,
                                                                                           remainingAdminUuids: remainingAdminUuids)
            guard canLeaveGroup else {
                // This could happen if the last two admins leave at the same time
                // and race.
                throw GroupsV2Error.cannotBuildGroupChangeProto_lastAdminCantLeaveGroup
            }

            // Check that we are still invited or in group.
            if currentGroupMembership.isInvitedMember(localUuid) {
                // Decline invite
                var actionBuilder = GroupsProtoGroupChangeActionsDeletePendingMemberAction.builder()
                let localUserId = try groupV2Params.userId(forUuid: localUuid)
                actionBuilder.setDeletedUserID(localUserId)
                actionsBuilder.addDeletePendingMembers(try actionBuilder.build())
                didChange = true
            } else if currentGroupMembership.isFullMember(localUuid) {
                // Leave group
                var actionBuilder = GroupsProtoGroupChangeActionsDeleteMemberAction.builder()
                let localUserId = try groupV2Params.userId(forUuid: localUuid)
                actionBuilder.setDeletedUserID(localUserId)
                actionsBuilder.addDeleteMembers(try actionBuilder.build())
                didChange = true
            } else {
                // Redundant change, not a conflict.
            }
        }

        if let newDisappearingMessageToken = self.newDisappearingMessageToken {
            if newDisappearingMessageToken == currentDisappearingMessageToken {
                // Redundant change, not a conflict.
            } else {
                let encryptedTimerData = try groupV2Params.encryptDisappearingMessagesTimer(newDisappearingMessageToken)
                var actionBuilder = GroupsProtoGroupChangeActionsModifyDisappearingMessagesTimerAction.builder()
                actionBuilder.setTimer(encryptedTimerData)
                actionsBuilder.setModifyDisappearingMessagesTimer(try actionBuilder.build())
                didChange = true
            }
        }

        if let isAnnouncementsOnly = self.isAnnouncementsOnly {
            if isAnnouncementsOnly == currentGroupModel.isAnnouncementsOnly {
                // Redundant change, not a conflict.
            } else {
                var actionBuilder = GroupsProtoGroupChangeActionsModifyAnnouncementsOnlyAction.builder()
                actionBuilder.setAnnouncementsOnly(isAnnouncementsOnly)
                actionsBuilder.setModifyAnnouncementsOnly(try actionBuilder.build())
                didChange = true
            }
        }

        if shouldUpdateLocalProfileKey {
            guard let profileKeyCredential = profileKeyCredentialMap[localUuid] else {
                throw OWSAssertionError("Missing profile key credential: \(localUuid)")
            }
            var actionBuilder = GroupsProtoGroupChangeActionsModifyMemberProfileKeyAction.builder()
            actionBuilder.setPresentation(try GroupsV2Protos.presentationData(profileKeyCredential: profileKeyCredential,
                                                                              groupV2Params: groupV2Params))
            actionsBuilder.addModifyMemberProfileKeys(try actionBuilder.build())
            didChange = true
        }

        guard didChange else {
            throw GroupsV2Error.redundantChange
        }

        let actionsProto = try actionsBuilder.build()
        Logger.info("Updating group.")
        return actionsProto
    }
}
