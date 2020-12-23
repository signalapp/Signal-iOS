//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import SignalServiceKit
import ZKGroup

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
public class GroupsV2ChangeSetImpl: NSObject, GroupsV2ChangeSet {

    // MARK: - Dependencies

    private var groupsV2: GroupsV2 {
        return SSKEnvironment.shared.groupsV2
    }

    private var tsAccountManager: TSAccountManager {
        return TSAccountManager.shared()
    }

    // MARK: -

    public let groupId: Data
    public let groupSecretParamsData: Data

    // MARK: - These properties capture the original intent of the local user.

    // Non-nil if the title changed.
    // When clearing the title, this will be the empty string.
    private var newTitle: String?

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

    private var shouldUpdateLocalProfileKey = false

    private var newLinkMode: GroupsV2LinkMode?

    // Non-nil if dm state changed.
    private var newDisappearingMessageToken: DisappearingMessageToken?

    @objc
    public required init(groupId: Data,
                         groupSecretParamsData: Data) {
        self.groupId = groupId
        self.groupSecretParamsData = groupSecretParamsData
    }

    @objc
    public required init(for groupModel: TSGroupModelV2) throws {
        self.groupId = groupModel.groupId
        self.groupSecretParamsData = groupModel.secretParamsData
    }

    // MARK: - Original Intent

    // Calculate the intended changes of the local user
    // by diffing two group models.
    @objc
    public func buildChangeSet(oldGroupModel: TSGroupModelV2,
                               newGroupModel: TSGroupModelV2,
                               oldDMConfiguration: OWSDisappearingMessagesConfiguration,
                               newDMConfiguration: OWSDisappearingMessagesConfiguration,
                               transaction: SDSAnyReadTransaction) throws {
        guard groupId == oldGroupModel.groupId else {
            throw OWSAssertionError("Mismatched groupId.")
        }
        guard groupId == newGroupModel.groupId else {
            throw OWSAssertionError("Mismatched groupId.")
        }

        // GroupsV2 TODO: Will production implementation of encryptString() pad?
        let oldTitle = oldGroupModel.groupName?.stripped ?? " "
        let newTitle = newGroupModel.groupName?.stripped ?? " "
        if oldTitle != newTitle {
            setTitle(newTitle)
        }

        if oldGroupModel.groupAvatarData != newGroupModel.groupAvatarData {
            let hasAvatarUrlPath = newGroupModel.avatarUrlPath != nil
            let hasAvatarData = newGroupModel.groupAvatarData != nil
            guard hasAvatarUrlPath == hasAvatarData else {
                throw OWSAssertionError("hasAvatarUrlPath: \(hasAvatarData) != hasAvatarData.")
            }

            setAvatar(avatarData: newGroupModel.groupAvatarData,
                      avatarUrlPath: newGroupModel.avatarUrlPath)
        }

        let oldGroupMembership = oldGroupModel.groupMembership
        let newGroupMembership = newGroupModel.groupMembership

        let oldUserUuids = oldGroupMembership.allMemberUuidsOfAnyKind
        let newUserUuids = newGroupMembership.allMemberUuidsOfAnyKind

        for uuid in newUserUuids.subtracting(oldUserUuids) {
            guard !newGroupMembership.isRequestingMember(uuid) else {
                owsFailDebug("Pending request members should never be added by diffing models.")
                continue
            }
            let isAdministrator = newGroupMembership.isFullOrInvitedAdministrator(uuid)
            let isPending = newGroupMembership.isInvitedMember(uuid)
            let role: TSGroupMemberRole = isAdministrator ? .administrator : .normal
            if isPending {
                addInvitedMember(uuid, role: role)
            } else {
                addMember(uuid, role: role)
            }
        }

        for uuid in oldUserUuids.subtracting(newUserUuids) {
            removeMember(uuid)
        }

        for invalidInvite in oldGroupMembership.invalidInvites {
            if !newGroupMembership.hasInvalidInvite(forUserId: invalidInvite.userId) {
                removeInvalidInvite(invalidInvite: invalidInvite)
            }
        }

        for uuid in oldUserUuids.intersection(newUserUuids) {
            if oldGroupMembership.isInvitedMember(uuid),
                newGroupMembership.isFullMember(uuid) {
                addMember(uuid, role: .normal)
            } else if oldGroupMembership.isRequestingMember(uuid),
                newGroupMembership.isFullMember(uuid) {
                // We only currently support accepting join requests
                // with "normal" role.
                addMember(uuid, role: .normal)
            }
        }

        let oldMemberUuids = Set(oldGroupMembership.fullMembers.compactMap { $0.uuid })
        let newMemberUuids = Set(newGroupMembership.fullMembers.compactMap { $0.uuid })
        for uuid in oldMemberUuids.intersection(newMemberUuids) {
            let oldIsAdministrator = oldGroupMembership.isFullMemberAndAdministrator(uuid)
            let newIsAdministrator = newGroupMembership.isFullMemberAndAdministrator(uuid)
            guard oldIsAdministrator != newIsAdministrator else {
                continue
            }
            let role: TSGroupMemberRole = newIsAdministrator ? .administrator : .normal
            changeRoleForMember(uuid, role: role)
        }

        if oldGroupModel.inviteLinkPassword != newGroupModel.inviteLinkPassword {
            owsFailDebug("We should never change the invite link password by diffing group models.")
        }

        let oldAccess = oldGroupModel.access
        let newAccess = newGroupModel.access
        if oldAccess.members != newAccess.members {
            setAccessForMembers(newAccess.members)
        }
        if oldAccess.attributes != newAccess.attributes {
            setAccessForAttributes(newAccess.attributes)
        }
        if oldAccess.addFromInviteLink != newAccess.addFromInviteLink {
            owsFailDebug("We should never change the invite link access by diffing group models.")
        }

        let oldDisappearingMessageToken = oldDMConfiguration.asToken
        let newDisappearingMessageToken = newDMConfiguration.asToken
        if oldDisappearingMessageToken != newDisappearingMessageToken {
            setNewDisappearingMessageToken(newDisappearingMessageToken)
        }
    }

    @objc
    public func setTitle(_ value: String?) {
        assert(self.newTitle == nil)
        // Non-nil if the title changed.
        self.newTitle = value ?? ""
    }

    @objc
    public func setAvatar(avatarData: Data?, avatarUrlPath: String?) {
        assert(self.newAvatarData == nil)
        assert(self.newAvatarUrlPath == nil)
        assert(!self.shouldUpdateAvatar)

        self.newAvatarData = avatarData
        self.newAvatarUrlPath = avatarUrlPath
        self.shouldUpdateAvatar = true
    }

    public func addMember(_ uuid: UUID, role: TSGroupMemberRole) {
        assert(membersToAdd[uuid] == nil)
        membersToAdd[uuid] = role
    }

    @objc
    public func removeMember(_ uuid: UUID) {
        assert(!membersToRemove.contains(uuid))
        membersToRemove.append(uuid)
    }

    @objc
    public func promoteInvitedMember(_ uuid: UUID) {
        assert(!invitedMembersToPromote.contains(uuid))
        invitedMembersToPromote.append(uuid)
    }

    public func changeRoleForMember(_ uuid: UUID, role: TSGroupMemberRole) {
        assert(membersToChangeRole[uuid] == nil)
        membersToChangeRole[uuid] = role
    }

    public func addInvitedMember(_ uuid: UUID, role: TSGroupMemberRole) {
        assert(invitedMembersToAdd[uuid] == nil)
        invitedMembersToAdd[uuid] = role
    }

    public func setShouldLeaveGroupDeclineInvite() {
        assert(!shouldLeaveGroupDeclineInvite)
        shouldLeaveGroupDeclineInvite = true
    }

    public func removeInvalidInvite(invalidInvite: InvalidInvite) {
        assert(invalidInvitesToRemove[invalidInvite.userId] == nil)
        invalidInvitesToRemove[invalidInvite.userId] = invalidInvite
    }

    public func setAccessForMembers(_ value: GroupV2Access) {
        assert(accessForMembers == nil)
        accessForMembers = value
    }

    public func setAccessForAttributes(_ value: GroupV2Access) {
        assert(accessForAttributes == nil)
        accessForAttributes = value
    }

    public func setNewDisappearingMessageToken(_ newDisappearingMessageToken: DisappearingMessageToken) {
        assert(self.newDisappearingMessageToken == nil)
        self.newDisappearingMessageToken = newDisappearingMessageToken
    }

    public func setShouldUpdateLocalProfileKey() {
        assert(!shouldUpdateLocalProfileKey)
        shouldUpdateLocalProfileKey = true
    }

    public func revokeInvalidInvites() {
        assert(!shouldRevokeInvalidInvites)
        shouldRevokeInvalidInvites = true
    }

    public func setLinkMode(_ linkMode: GroupsV2LinkMode) {
        assert(accessForAddFromInviteLink == nil)
        assert(inviteLinkPasswordMode == nil)

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
        assert(inviteLinkPasswordMode == nil)

        inviteLinkPasswordMode = .rotate
    }

    // MARK: - Change Protos

    private typealias ProfileKeyCredentialMap = [UUID: ProfileKeyCredential]

    // Given the "current" group state, build a change proto that
    // reflects the elements of the "original intent" that are still
    // necessary to perform.
    //
    // See comments on buildGroupChangeProto() below.
    public func buildGroupChangeProto(currentGroupModel: TSGroupModelV2,
                                      currentDisappearingMessageToken: DisappearingMessageToken) -> Promise<GroupsProtoGroupChangeActions> {
        guard groupId == currentGroupModel.groupId else {
            return Promise(error: OWSAssertionError("Mismatched groupId."))
        }
        guard let groupsV2Impl = groupsV2 as? GroupsV2Impl else {
            return Promise(error: OWSAssertionError("Invalid groupsV2: \(type(of: groupsV2))"))
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
        var uuidsForProfileKeyCredentials = Set<UUID>()
        uuidsForProfileKeyCredentials.formUnion(membersToAdd.keys)
        uuidsForProfileKeyCredentials.formUnion(invitedMembersToPromote)
        // This should be redundant, but we'll also double-check that we have
        // the local profile key credential.
        uuidsForProfileKeyCredentials.insert(localUuid)
        let addressesForProfileKeyCredentials: [SignalServiceAddress] = uuidsForProfileKeyCredentials.map { SignalServiceAddress(uuid: $0) }

        return firstly {
            groupsV2Impl.tryToEnsureProfileKeyCredentials(for: addressesForProfileKeyCredentials)
        }.then(on: .global()) { (_) -> Promise<ProfileKeyCredentialMap> in
            groupsV2Impl.loadProfileKeyCredentialData(for: Array(uuidsForProfileKeyCredentials))
        }.map(on: .global()) { (profileKeyCredentialMap: ProfileKeyCredentialMap) throws -> GroupsProtoGroupChangeActions in
            try self.buildGroupChangeProto(currentGroupModel: currentGroupModel,
                                           currentDisappearingMessageToken: currentDisappearingMessageToken,
                                           profileKeyCredentialMap: profileKeyCredentialMap)
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
                                       profileKeyCredentialMap: ProfileKeyCredentialMap) throws -> GroupsProtoGroupChangeActions {
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
                var actionBuilder = GroupsProtoGroupChangeActionsModifyTitleAction.builder()
                actionBuilder.setTitle(encryptedData)
                actionsBuilder.setModifyTitle(try actionBuilder.build())
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

        for (uuid, role) in self.invitedMembersToAdd {
            guard !currentGroupMembership.isMemberOfAnyKind(uuid) else {
                // Another user has already added or invited this member.
                // They may have been added with a different role.
                // We don't treat that as a conflict.
                continue
            }

            guard remainingMemberOfAnyKindUuids.count <= GroupManager.groupsV2MaxGroupSizeHardLimit else {
                throw GroupsV2Error.tooManyMembers
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
                throw GroupsV2Error.conflictingChange
            }
            let currentRole = currentGroupMembership.role(for: uuid)
            guard currentRole != newRole else {
                // Another user has already modifed the role of this member.
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
            // Check that pending member is still invited.
            guard currentGroupMembership.isInvitedMember(uuid) else {
                throw GroupsV2Error.redundantChange
            }
            guard let profileKeyCredential = profileKeyCredentialMap[uuid] else {
                throw OWSAssertionError("Missing profile key credential: \(uuid)")
            }
            var actionBuilder = GroupsProtoGroupChangeActionsPromotePendingMemberAction.builder()
            actionBuilder.setPresentation(try GroupsV2Protos.presentationData(profileKeyCredential: profileKeyCredential,
                                                                              groupV2Params: groupV2Params))
            actionsBuilder.addPromotePendingMembers(try actionBuilder.build())
            didChange = true

            remainingMemberOfAnyKindUuids.insert(uuid)
            remainingFullMemberUuids.insert(uuid)
        }

        if self.shouldLeaveGroupDeclineInvite {
            let canLeaveGroup = GroupManager.canLocalUserLeaveGroupWithoutChoosingNewAdmin(localUuid: localUuid,
                                                                                           remainingFullMemberUuids: remainingFullMemberUuids,
                                                                                           remainingAdminUuids: remainingAdminUuids)
            guard canLeaveGroup else {
                // This could happen if the last two admins leave at the same time
                // and race.
                throw GroupsV2Error.lastAdminCantLeaveGroup
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

        return try actionsBuilder.build()
    }
}
