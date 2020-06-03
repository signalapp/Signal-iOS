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
        return TSAccountManager.sharedInstance()
    }

    // MARK: -

    public let groupId: Data
    public let groupSecretParamsData: Data

    // MARK: - These properties capture the original intent of the local user.

    // Non-nil if the title changed.
    // When clearing the title, this will be the empty string.
    private var title: String?

    public var newAvatarData: Data?
    public var newAvatarUrlPath: String?
    private var shouldUpdateAvatar = false

    private var membersToAdd = [UUID: TSGroupMemberRole]()
    // Pending or non-pending members to remove.
    private var membersToRemove = [UUID]()
    private var membersToChangeRole = [UUID: TSGroupMemberRole]()
    private var pendingMembersToAdd = [UUID: TSGroupMemberRole]()

    // These access properties should only be set if the value is changing.
    private var accessForMembers: GroupV2Access?
    private var accessForAttributes: GroupV2Access?

    private var shouldAcceptInvite = false
    private var shouldLeaveGroupDeclineInvite = false

    private var shouldUpdateLocalProfileKey = false

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

        let oldUserUuids = Set(oldGroupMembership.allUsers.compactMap { $0.uuid })
        let newUserUuids = Set(newGroupMembership.allUsers.compactMap { $0.uuid })

        for uuid in newUserUuids.subtracting(oldUserUuids) {
            let isAdministrator = newGroupMembership.isAdministrator(SignalServiceAddress(uuid: uuid))
            let isPending = newGroupMembership.isPending(SignalServiceAddress(uuid: uuid))
            let role: TSGroupMemberRole = isAdministrator ? .administrator : .normal
            if isPending {
                addPendingMember(uuid, role: role)
            } else {
                addMember(uuid, role: role)
            }
        }

        for uuid in oldUserUuids.subtracting(newUserUuids) {
            removeMember(uuid)
        }

        let oldMemberUuids = Set(oldGroupMembership.nonPendingMembers.compactMap { $0.uuid })
        let newMemberUuids = Set(newGroupMembership.nonPendingMembers.compactMap { $0.uuid })
        for uuid in oldMemberUuids.intersection(newMemberUuids) {
            let address = SignalServiceAddress(uuid: uuid)
            let oldIsAdministrator = oldGroupMembership.isAdministrator(address)
            let newIsAdministrator = newGroupMembership.isAdministrator(address)
            guard oldIsAdministrator != newIsAdministrator else {
                continue
            }
            let role: TSGroupMemberRole = newIsAdministrator ? .administrator : .normal
            changeRoleForMember(uuid, role: role)
        }

        let oldAccess = oldGroupModel.access
        let newAccess = newGroupModel.access
        if oldAccess.members != newAccess.members {
            self.accessForMembers = newAccess.members
        }
        if oldAccess.attributes != newAccess.attributes {
            self.accessForAttributes = newAccess.attributes
        }

        let oldDisappearingMessageToken = oldDMConfiguration.asToken
        let newDisappearingMessageToken = newDMConfiguration.asToken
        if oldDisappearingMessageToken != newDisappearingMessageToken {
            setNewDisappearingMessageToken(newDisappearingMessageToken)
        }
    }

    @objc
    public func setTitle(_ value: String?) {
        assert(self.title == nil)
        // Non-nil if the title changed.
        self.title = value ?? ""
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

    @objc
    public func addNormalMember(_ uuid: UUID) {
        addMember(uuid, role: .normal)
    }

    @objc
    public func addAdministrator(_ uuid: UUID) {
        addMember(uuid, role: .administrator)
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

    public func changeRoleForMember(_ uuid: UUID, role: TSGroupMemberRole) {
        assert(membersToChangeRole[uuid] == nil)
        membersToChangeRole[uuid] = role
    }

    public func addPendingMember(_ uuid: UUID, role: TSGroupMemberRole) {
        assert(pendingMembersToAdd[uuid] == nil)
        pendingMembersToAdd[uuid] = role
    }

    public func setShouldAcceptInvite() {
        assert(!shouldAcceptInvite)
        shouldAcceptInvite = true
    }

    public func setShouldLeaveGroupDeclineInvite() {
        assert(!shouldLeaveGroupDeclineInvite)
        shouldLeaveGroupDeclineInvite = true
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
        // This should be redundant, but we'll also double-check that we have
        // the local profile key credential.
        uuidsForProfileKeyCredentials.insert(localUuid)
        let addressesForProfileKeyCredentials: [SignalServiceAddress] = uuidsForProfileKeyCredentials.map { SignalServiceAddress(uuid: $0) }
        if shouldAcceptInvite || shouldUpdateLocalProfileKey {
            uuidsForProfileKeyCredentials.insert(localUuid)
        }

        return firstly {
            groupsV2Impl.tryToEnsureProfileKeyCredentials(for: addressesForProfileKeyCredentials)
        }.then(on: .global()) { (_) -> Promise<ProfileKeyCredentialMap> in
            return groupsV2Impl.loadProfileKeyCredentialData(for: Array(uuidsForProfileKeyCredentials))
        }.map(on: .global()) { (profileKeyCredentialMap: ProfileKeyCredentialMap) throws -> GroupsProtoGroupChangeActions in
            return try self.buildGroupChangeProto(currentGroupModel: currentGroupModel,
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

        let actionsBuilder = GroupsProtoGroupChangeActions.builder()
        guard let localUuid = tsAccountManager.localUuid else {
            throw OWSAssertionError("Missing localUuid.")
        }
        let localAddress = SignalServiceAddress(uuid: localUuid)

        let oldRevision = currentGroupModel.revision
        let newRevision = oldRevision + 1
        Logger.verbose("Revision: \(oldRevision) -> \(newRevision)")
        actionsBuilder.setRevision(newRevision)

        var nonPendingAdministratorCount: Int = currentGroupModel.groupMembership.nonPendingAdministrators.count
        var allMemberCount = currentGroupModel.groupMembership.pendingAndNonPendingMemberCount

        var didChange = false

        if let title = self.title {
            if title == currentGroupModel.groupName {
                // Redundant change, not a conflict.
            } else {
                let encryptedData = try groupV2Params.encryptGroupName(title)
                let actionBuilder = GroupsProtoGroupChangeActionsModifyTitleAction.builder()
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
                let actionBuilder = GroupsProtoGroupChangeActionsModifyAvatarAction.builder()
                if let avatarUrlPath = newAvatarUrlPath {
                    actionBuilder.setAvatar(avatarUrlPath)
                } else {
                    // We're clearing the avatar.
                }
                actionsBuilder.setModifyAvatar(try actionBuilder.build())
                didChange = true
            }
        }

        let currentGroupMembership = currentGroupModel.groupMembership
        for (uuid, role) in self.membersToAdd {
            guard !currentGroupMembership.isPendingOrNonPendingMember(uuid) else {
                // Another user has already added or invited this member.
                // They may have been added with a different role.
                // We don't treat that as a conflict.
                continue
            }
            guard let profileKeyCredential = profileKeyCredentialMap[uuid] else {
                throw OWSAssertionError("Missing profile key credential: \(uuid)")
            }
            let actionBuilder = GroupsProtoGroupChangeActionsAddMemberAction.builder()
            actionBuilder.setAdded(try GroupsV2Protos.buildMemberProto(profileKeyCredential: profileKeyCredential,
                                                                       role: role.asProtoRole,
                                                                       groupV2Params: groupV2Params))
            actionsBuilder.addAddMembers(try actionBuilder.build())
            didChange = true

            if role == .administrator {
                nonPendingAdministratorCount += 1
            }
        }

        for uuid in self.membersToRemove {
            if currentGroupMembership.isNonPendingMember(uuid) {
                let actionBuilder = GroupsProtoGroupChangeActionsDeleteMemberAction.builder()
                let userId = try groupV2Params.userId(forUuid: uuid)
                actionBuilder.setDeletedUserID(userId)
                actionsBuilder.addDeleteMembers(try actionBuilder.build())
                didChange = true

                if currentGroupMembership.isAdministrator(SignalServiceAddress(uuid: uuid)) {
                    nonPendingAdministratorCount -= 1
                }
                allMemberCount -= 1
            } else if currentGroupMembership.isPendingMember(uuid) {
                let actionBuilder = GroupsProtoGroupChangeActionsDeletePendingMemberAction.builder()
                let userId = try groupV2Params.userId(forUuid: uuid)
                actionBuilder.setDeletedUserID(userId)
                actionsBuilder.addDeletePendingMembers(try actionBuilder.build())
                didChange = true
                allMemberCount -= 1
            } else {
                // Another user has already removed this member or revoked their
                // invitation.
                // Redundant change, not a conflict.
                continue
            }
        }

        for (uuid, role) in self.pendingMembersToAdd {
            guard !currentGroupMembership.isPendingOrNonPendingMember(uuid) else {
                // Another user has already added or invited this member.
                // They may have been added with a different role.
                // We don't treat that as a conflict.
                continue
            }

            guard allMemberCount <= GroupManager.maxGroupMemberCount else {
                throw GroupsV2Error.tooManyMembers
            }

            let actionBuilder = GroupsProtoGroupChangeActionsAddPendingMemberAction.builder()
            actionBuilder.setAdded(try GroupsV2Protos.buildPendingMemberProto(uuid: uuid,
                                                                              role: role.asProtoRole,
                                                                              localUuid: localUuid,
                                                                              groupV2Params: groupV2Params))
            actionsBuilder.addAddPendingMembers(try actionBuilder.build())
            didChange = true
            allMemberCount += 1
        }

        for (uuid, newRole) in self.membersToChangeRole {
            guard currentGroupMembership.isNonPendingMember(uuid) else {
                // User is no longer a member.
                throw GroupsV2Error.conflictingChange
            }
            let currentRole = currentGroupMembership.role(for: SignalServiceAddress(uuid: uuid))
            guard currentRole != newRole else {
                // Another user has already modifed the role of this member.
                // We don't treat that as a conflict.
                continue
            }
            let actionBuilder = GroupsProtoGroupChangeActionsModifyMemberRoleAction.builder()
            let userId = try groupV2Params.userId(forUuid: uuid)
            actionBuilder.setUserID(userId)
            actionBuilder.setRole(newRole.asProtoRole)
            actionsBuilder.addModifyMemberRoles(try actionBuilder.build())
            didChange = true

            if currentRole == .administrator {
                nonPendingAdministratorCount -= 1
            } else if newRole == .administrator {
                nonPendingAdministratorCount += 1
            }
        }

        let currentAccess = currentGroupModel.access
        if let access = self.accessForMembers {
            if currentAccess.members == access {
                // Redundant change, not a conflict.
            } else {
                let actionBuilder = GroupsProtoGroupChangeActionsModifyMembersAccessControlAction.builder()
                actionBuilder.setMembersAccess(GroupAccess.protoAccess(forGroupV2Access: access))
                actionsBuilder.setModifyMemberAccess(try actionBuilder.build())
                didChange = true
            }
        }
        if let access = self.accessForAttributes {
            if currentAccess.attributes == access {
                // Redundant change, not a conflict.
            } else {
                let actionBuilder = GroupsProtoGroupChangeActionsModifyAttributesAccessControlAction.builder()
                actionBuilder.setAttributesAccess(GroupAccess.protoAccess(forGroupV2Access: access))
                actionsBuilder.setModifyAttributesAccess(try actionBuilder.build())
                didChange = true
            }
        }

        if self.shouldAcceptInvite {
            // Check that we are still invited.
            guard currentGroupMembership.pendingMembers.contains(localAddress) else {
                throw GroupsV2Error.redundantChange
            }
            guard let profileKeyCredential = profileKeyCredentialMap[localUuid] else {
                throw OWSAssertionError("Missing profile key credential: \(localUuid)")
            }
            let actionBuilder = GroupsProtoGroupChangeActionsPromotePendingMemberAction.builder()
            actionBuilder.setPresentation(try GroupsV2Protos.presentationData(profileKeyCredential: profileKeyCredential,
                                                                              groupV2Params: groupV2Params))
            actionsBuilder.addPromotePendingMembers(try actionBuilder.build())
            didChange = true
        }

        if self.shouldLeaveGroupDeclineInvite {
            let isLastAdminInV2Group = (currentGroupMembership.isNonPendingMember(localAddress) &&
                currentGroupMembership.isAdministrator(localAddress) &&
                nonPendingAdministratorCount == 1)
            guard !isLastAdminInV2Group else {
                // This could happen if the last two admins leave at the same time
                // and race.
                throw GroupsV2Error.lastAdminCantLeaveGroup
            }

            // Check that we are still invited or in group.
            if currentGroupMembership.pendingMembers.contains(localAddress) {
                // Decline invite
                let actionBuilder = GroupsProtoGroupChangeActionsDeletePendingMemberAction.builder()
                let localUserId = try groupV2Params.userId(forUuid: localUuid)
                actionBuilder.setDeletedUserID(localUserId)
                actionsBuilder.addDeletePendingMembers(try actionBuilder.build())
                didChange = true
            } else if currentGroupMembership.nonPendingMembers.contains(localAddress) {
                // Leave group
                let actionBuilder = GroupsProtoGroupChangeActionsDeleteMemberAction.builder()
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
                let actionBuilder = GroupsProtoGroupChangeActionsModifyDisappearingMessagesTimerAction.builder()
                actionBuilder.setTimer(encryptedTimerData)
                actionsBuilder.setModifyDisappearingMessagesTimer(try actionBuilder.build())
                didChange = true
            }
        }

        if shouldUpdateLocalProfileKey {
            guard let profileKeyCredential = profileKeyCredentialMap[localUuid] else {
                throw OWSAssertionError("Missing profile key credential: \(localUuid)")
            }
            let actionBuilder = GroupsProtoGroupChangeActionsModifyMemberProfileKeyAction.builder()
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
