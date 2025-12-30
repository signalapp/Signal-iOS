//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

/// Represents a proposed set of changes to a group.
///
/// When modifying groups, we capture the intended CHANGES to the group
/// state. If a user updates the description, we'll capture that they want
/// to update the description.
///
/// These updates are originally "based" on the latest known group
/// state/revision. However, when we try to apply them, we may run into a
/// conflict on the service. In this case, we fetch the latest group state,
/// and then we "rebase" our changes on top of that state.
///
/// We perform conflict resolution as part of this process. This type is
/// responsible for conflict resolution. For example, if we are trying to
/// add Alice and Bob, and if another user adds Alice before we do, we'll
/// only add Bob. If our change turns into a no-op (e.g., both Alice and Bob
/// are added by somebody else), we'll return nil; callers should interpret
/// this as a successful outcome.
public class GroupsV2OutgoingChanges {

    public let groupSecretParams: GroupSecretParams

    // MARK: -

    /// These properties capture the original intent of the local user.
    ///
    /// NOTE: These properties generally _DO NOT_ capture the new state of the
    /// group; they capture only "changed" aspects of group state.
    ///
    /// NOTE: Even if set, these properties _DO NOT_ necessarily translate into
    /// "change actions"; we only need to build change actions if _current_
    /// group state differs from the "changed" group state. Our client might
    /// race with similar changes made by other group members/clients. We must
    /// skip redundant changes.

    /// Non-nil if changed. Should not be able to be set to an empty string.
    private var newTitle: String?

    /// Non-nil if changed. Empty string is allowed.
    private var newDescriptionText: String?

    public private(set) var newAvatarData: Data?
    public private(set) var newAvatarUrlPath: String?
    private var shouldUpdateAvatar = false

    public private(set) var membersToAdd = [ServiceId]()
    /// Full, pending profile key or pending request members to remove.
    private var membersToRemove = [ServiceId]()
    private var membersToChangeRole = [Aci: TSGroupMemberRole]()

    /// These access properties should only be set if the value is changing.
    private var accessForMembers: GroupV2Access?
    private var accessForAttributes: GroupV2Access?
    private var accessForAddFromInviteLink: GroupV2Access?

    private enum InviteLinkPasswordMode {
        case ignore
        case rotate
        case ensureValid
    }

    private var inviteLinkPasswordMode: InviteLinkPasswordMode?

    private var shouldAcceptInvite = false
    private var shouldLeaveGroupDeclineInvite = false
    private var shouldRevokeInvalidInvites = false

    /// Non-nil if the value changed.
    private var isAnnouncementsOnly: Bool?

    private var shouldUpdateLocalProfileKey = false

    private var newLinkMode: GroupsV2LinkMode?

    /// Non-nil if dm state changed.
    private var newDisappearingMessageToken: DisappearingMessageToken?

    public init(groupSecretParams: GroupSecretParams) {
        self.groupSecretParams = groupSecretParams
    }

    public init(for groupModel: TSGroupModelV2) throws {
        self.groupSecretParams = try groupModel.secretParams()
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

    public func addMember(_ serviceId: ServiceId) {
        owsAssertDebug(!membersToAdd.contains(serviceId))
        membersToAdd.append(serviceId)
    }

    public func removeMember(_ serviceId: ServiceId) {
        owsAssertDebug(!membersToRemove.contains(serviceId))
        membersToRemove.append(serviceId)
    }

    public func changeRoleForMember(_ aci: Aci, role: TSGroupMemberRole) {
        owsAssertDebug(membersToChangeRole[aci] == nil)
        membersToChangeRole[aci] = role
    }

    public func setLocalShouldAcceptInvite() {
        owsAssertDebug(!shouldAcceptInvite)
        shouldAcceptInvite = true
    }

    public func setShouldLeaveGroupDeclineInvite() {
        owsAssertDebug(!shouldLeaveGroupDeclineInvite)
        shouldLeaveGroupDeclineInvite = true
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

    /// Given the current group state, build a change proto that reflects the
    /// elements of the "original intent" that are still necessary to perform.
    ///
    /// See comments on buildGroupChangeProto() below.
    public func buildGroupChangeProto(
        currentGroupModel: TSGroupModelV2,
        currentDisappearingMessageToken: DisappearingMessageToken,
        forceRefreshProfileKeyCredentials: Bool,
    ) async throws -> GroupsV2BuiltGroupChange? {
        let groupId = try self.groupSecretParams.getPublicParams().getGroupIdentifier()
        guard groupId.serialize() == currentGroupModel.groupId else {
            throw OWSAssertionError("Mismatched groupId.")
        }
        guard let localIdentifiers = DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction else {
            throw OWSAssertionError("Missing localIdentifiers.")
        }

        // Note that we're calculating the set of users for whom we MIGHT WANT
        // profile key credentials based on the "original intent". We always
        // include our own ACI because non-add operations (e.g., updating our
        // profile key) will require our own profile key credential.
        var newUserAcis: Set<Aci> = Set(membersToAdd.compactMap { $0 as? Aci })
        newUserAcis.insert(localIdentifiers.aci)

        let profileKeyCredentials = try await SSKEnvironment.shared.groupsV2Ref.loadProfileKeyCredentials(
            for: Array(newUserAcis),
            forceRefresh: forceRefreshProfileKeyCredentials,
        )

        return try self.buildGroupChangeProto(
            currentGroupModel: currentGroupModel,
            currentDisappearingMessageToken: currentDisappearingMessageToken,
            localIdentifiers: localIdentifiers,
            profileKeyCredentials: profileKeyCredentials,
        )
    }

    /// Given the current group state, build a change proto that reflects the
    /// elements of the "original intent" that are still necessary to perform.
    ///
    /// This method builds the actual set of actions _that are still necessary_.
    /// Conflicts can occur due to races. This is where we make a best effort to
    /// resolve conflicts.
    ///
    /// Conflict resolution guidelines:
    ///
    /// * “Orthogonal” changes are resolved by simply retrying.
    ///   * If you're trying to change the avatar and someone else changes the
    ///   title, there is no conflict.
    /// * Many conflicts can be resolved by “last writer wins”.
    ///   * E.g. changes to group name or avatar.
    /// * We skip identical changes.
    ///   * If you want to add Alice but Carol has already added Alice, we treat
    ///   this as redundant.
    /// * "Overlapping" changes are not conflicts.
    ///   * If you want to add (Alice and Bob) but Carol has already added
    ///   Alice, we convert your intent to just adding Bob.
    /// * We skip similar changes when they differ in details.
    ///   * If you try to add Alice as admin and Bob has already added Alice as
    ///   a normal member, we treat these as redundant. We could convert your
    ///   intent into changing Alice's role, but that can confuse the user.
    /// * We treat "obsolete" changes as an unresolvable conflict.
    ///   * If you try to change Alice's role to admin and Bob has already
    ///   kicked out Alice, we throw GroupsV2Error.conflictingChange.
    ///
    /// Essentially, our strategy is to "apply any changes that still make
    /// sense". If no changes do, we return nil.
    private func buildGroupChangeProto(
        currentGroupModel: TSGroupModelV2,
        currentDisappearingMessageToken: DisappearingMessageToken,
        localIdentifiers: LocalIdentifiers,
        profileKeyCredentials: [Aci: ExpiringProfileKeyCredential],
    ) throws -> GroupsV2BuiltGroupChange? {
        let groupV2Params = try currentGroupModel.groupV2Params()

        var actionsBuilder = GroupsProtoGroupChangeActions.builder()

        let localAci = localIdentifiers.aci

        let oldRevision = currentGroupModel.revision
        let newRevision = oldRevision + 1
        actionsBuilder.setRevision(newRevision)

        // Track member counts that are updated to reflect each new action.
        let currentGroupMembership = currentGroupModel.groupMembership

        var groupUpdateMessageBehavior: GroupUpdateMessageBehavior = .sendUpdateToOtherGroupMembers

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
                actionsBuilder.setModifyTitle(actionBuilder.buildInfallibly())
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
                actionsBuilder.setModifyDescription(actionBuilder.buildInfallibly())
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
                actionsBuilder.setModifyAvatar(actionBuilder.buildInfallibly())
                didChange = true
            }
        }

        if let inviteLinkPasswordMode {
            let newInviteLinkPassword: Data?
            switch inviteLinkPasswordMode {
            case .ignore:
                newInviteLinkPassword = currentGroupModel.inviteLinkPassword
            case .rotate:
                newInviteLinkPassword = GroupManager.generateInviteLinkPasswordV2()
            case .ensureValid:
                if
                    let oldInviteLinkPassword = currentGroupModel.inviteLinkPassword,
                    !oldInviteLinkPassword.isEmpty
                {
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
                actionsBuilder.setModifyInviteLinkPassword(actionBuilder.buildInfallibly())
                didChange = true
            }
        }

        var membersToUnban = [Aci]()

        if !membersToAdd.isEmpty {
            let fullOrInvitedMemberAddresses = currentGroupMembership.fullMembers.union(currentGroupMembership.invitedMembers)
            var fullOrInvitedMembers = Set(fullOrInvitedMemberAddresses.compactMap { $0.serviceId })

            for serviceId in membersToAdd {
                if currentGroupMembership.isFullMember(serviceId) {
                    // Another user has already added this member. They may have been added
                    // with a different role. We don't treat that as a conflict.
                } else if let aci = serviceId as? Aci, currentGroupMembership.isRequestingMember(aci) {
                    var actionBuilder = GroupsProtoGroupChangeActionsPromoteRequestingMemberAction.builder()
                    let userId = try groupV2Params.userId(for: aci)
                    actionBuilder.setUserID(userId)
                    actionBuilder.setRole(.default)
                    actionsBuilder.addPromoteRequestingMembers(actionBuilder.buildInfallibly())
                    didChange = true
                    membersToUnban.append(aci)

                    fullOrInvitedMembers.insert(aci)
                } else if let aci = serviceId as? Aci, let profileKeyCredential = profileKeyCredentials[aci] {
                    var actionBuilder = GroupsProtoGroupChangeActionsAddMemberAction.builder()
                    actionBuilder.setAdded(try GroupsV2Protos.buildMemberProto(
                        profileKeyCredential: profileKeyCredential,
                        role: .default,
                        groupV2Params: groupV2Params,
                    ))
                    actionsBuilder.addAddMembers(actionBuilder.buildInfallibly())
                    didChange = true
                    membersToUnban.append(aci)

                    fullOrInvitedMembers.insert(aci)
                } else if currentGroupMembership.isInvitedMember(serviceId) {
                    // Another user has already invited this member. They may have been added
                    // with a different role. We don't treat that as a conflict.
                } else {
                    var actionBuilder = GroupsProtoGroupChangeActionsAddPendingMemberAction.builder()
                    actionBuilder.setAdded(try GroupsV2Protos.buildPendingMemberProto(
                        serviceId: serviceId,
                        role: .default,
                        groupV2Params: groupV2Params,
                    ))
                    actionsBuilder.addAddPendingMembers(actionBuilder.buildInfallibly())
                    didChange = true
                    if let aci = serviceId as? Aci { membersToUnban.append(aci) }

                    fullOrInvitedMembers.insert(serviceId)
                }
            }
            guard fullOrInvitedMembers.count <= RemoteConfig.current.maxGroupSizeHardLimit else {
                throw GroupsV2Error.cannotBuildGroupChangeProto_tooManyMembers
            }
        }

        var membersToBan = [Aci]()

        for serviceId in self.membersToRemove {
            if let aci = serviceId as? Aci, currentGroupMembership.isFullMember(aci) {
                var actionBuilder = GroupsProtoGroupChangeActionsDeleteMemberAction.builder()
                let userId = try groupV2Params.userId(for: aci)
                actionBuilder.setDeletedUserID(userId)
                actionsBuilder.addDeleteMembers(actionBuilder.buildInfallibly())
                didChange = true
                membersToBan.append(aci)
            } else if currentGroupMembership.isInvitedMember(serviceId) {
                var actionBuilder = GroupsProtoGroupChangeActionsDeletePendingMemberAction.builder()
                let userId = try groupV2Params.userId(for: serviceId)
                actionBuilder.setDeletedUserID(userId)
                actionsBuilder.addDeletePendingMembers(actionBuilder.buildInfallibly())
                didChange = true
                // Don't ban invited members.
            } else if let aci = serviceId as? Aci, currentGroupMembership.isRequestingMember(aci) {
                var actionBuilder = GroupsProtoGroupChangeActionsDeleteRequestingMemberAction.builder()
                let userId = try groupV2Params.userId(for: aci)
                actionBuilder.setDeletedUserID(userId)
                actionsBuilder.addDeleteRequestingMembers(actionBuilder.buildInfallibly())
                didChange = true
                membersToBan.append(aci)
            } else {
                // Another user has already removed this member or revoked their
                // invitation. Redundant change, not a conflict.
                continue
            }
        }

        do {
            // Only ban/unban if relevant according to current group membership
            let acisToBan = membersToBan.filter { !currentGroupMembership.isBannedMember($0) }
            var acisToUnban = membersToUnban.filter { currentGroupMembership.isBannedMember($0) }

            let currentBannedMembers = currentGroupMembership.bannedMembers

            // If we will overrun the max number of banned members, unban currently
            // banned members until we have enough room, beginning with the
            // least-recently banned.
            let maxNumBannableIds = RemoteConfig.current.maxGroupSizeBannedMembers
            let netNumIdsToBan = acisToBan.count - acisToUnban.count
            let nOldMembersToUnban = currentBannedMembers.count + netNumIdsToBan - Int(maxNumBannableIds)

            if nOldMembersToUnban > 0 {
                let bannedSortedByAge = currentBannedMembers.sorted { member1, member2 -> Bool in
                    // Lower bannedAt time goes first
                    member1.value < member2.value
                }.map { aci, _ -> Aci in aci }

                acisToUnban += bannedSortedByAge.prefix(nOldMembersToUnban)
            }

            // Build the bans
            for aci in acisToBan {
                let bannedMember = try GroupsV2Protos.buildBannedMemberProto(aci: aci, groupV2Params: groupV2Params)

                var actionBuilder = GroupsProtoGroupChangeActionsAddBannedMemberAction.builder()
                actionBuilder.setAdded(bannedMember)

                actionsBuilder.addAddBannedMembers(actionBuilder.buildInfallibly())
                didChange = true
            }

            // Build the unbans
            for aci in acisToUnban {
                let userId = try groupV2Params.userId(for: aci)

                var actionBuilder = GroupsProtoGroupChangeActionsDeleteBannedMemberAction.builder()
                actionBuilder.setDeletedUserID(userId)

                actionsBuilder.addDeleteBannedMembers(actionBuilder.buildInfallibly())
                didChange = true
            }
        }

        if shouldRevokeInvalidInvites {
            if currentGroupMembership.invalidInviteUserIds.count < 1 {
                // Another user has already revoked any invalid invites.
                // We don't treat that as a conflict.
                owsFailDebug("No invalid invites to revoke.")
            }

            for invalidlyInvitedUserId in currentGroupMembership.invalidInviteUserIds {
                var actionBuilder = GroupsProtoGroupChangeActionsDeletePendingMemberAction.builder()
                actionBuilder.setDeletedUserID(invalidlyInvitedUserId)
                actionsBuilder.addDeletePendingMembers(actionBuilder.buildInfallibly())
                didChange = true
            }
        }

        for (aci, newRole) in self.membersToChangeRole {
            guard currentGroupMembership.isFullMember(aci) else {
                // User is no longer a member.
                throw GroupsV2Error.cannotBuildGroupChangeProto_conflictingChange
            }
            let currentRole = currentGroupMembership.role(for: aci)
            guard currentRole != newRole else {
                // Another user has already modified the role of this member.
                // We don't treat that as a conflict.
                continue
            }
            var actionBuilder = GroupsProtoGroupChangeActionsModifyMemberRoleAction.builder()
            let userId = try groupV2Params.userId(for: aci)
            actionBuilder.setUserID(userId)
            actionBuilder.setRole(newRole.asProtoRole)
            actionsBuilder.addModifyMemberRoles(actionBuilder.buildInfallibly())
            didChange = true
        }

        let currentAccess = currentGroupModel.access
        if let access = self.accessForMembers {
            if currentAccess.members == access {
                // Redundant change, not a conflict.
            } else {
                var actionBuilder = GroupsProtoGroupChangeActionsModifyMembersAccessControlAction.builder()
                actionBuilder.setMembersAccess(access.protoAccess)
                actionsBuilder.setModifyMemberAccess(actionBuilder.buildInfallibly())
                didChange = true
            }
        }
        if let access = self.accessForAttributes {
            if currentAccess.attributes == access {
                // Redundant change, not a conflict.
            } else {
                var actionBuilder = GroupsProtoGroupChangeActionsModifyAttributesAccessControlAction.builder()
                actionBuilder.setAttributesAccess(access.protoAccess)
                actionsBuilder.setModifyAttributesAccess(actionBuilder.buildInfallibly())
                didChange = true
            }
        }

        var accessForAddFromInviteLink = self.accessForAddFromInviteLink
        if
            currentGroupMembership.allMembersOfAnyKind.count == 1,
            currentGroupMembership.isFullMemberAndAdministrator(localAci),
            self.shouldLeaveGroupDeclineInvite
        {
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
                actionsBuilder.setModifyAddFromInviteLinkAccess(actionBuilder.buildInfallibly())
                didChange = true
            }
        }

        if self.shouldAcceptInvite {
            guard let localProfileKeyCredential = profileKeyCredentials[localAci] else {
                throw OWSAssertionError("Missing local profile key credential!")
            }

            let profileKeyCredentialPresentationData = try GroupsV2Protos.presentationData(
                profileKeyCredential: localProfileKeyCredential,
                groupV2Params: groupV2Params,
            )

            // Accepting an invite to our ACI uses a different change action
            // than an invite to our PNI. We can determine which scenario we're
            // in by the presence of our ACI or PNI in the invited member list.

            var promotedLocalAci: Bool
            let isLocalInvitedByAci = currentGroupMembership.isInvitedMember(localAci)
            let isLocalInvitedByPni = {
                guard let localPni = localIdentifiers.pni else { return false }
                return currentGroupMembership.isInvitedMember(localPni)
            }()

            if isLocalInvitedByAci {
                if isLocalInvitedByPni {
                    Logger.warn("Both local ACI and PNI were invited. Accepting invite by ACI.")
                }

                var actionBuilder = GroupsProtoGroupChangeActionsPromotePendingMemberAction.builder()
                actionBuilder.setPresentation(profileKeyCredentialPresentationData)

                actionsBuilder.addPromotePendingMembers(actionBuilder.buildInfallibly())

                promotedLocalAci = true
            } else if isLocalInvitedByPni {
                var actionBuilder = GroupsProtoGroupChangeActionsPromoteMemberPendingPniAciProfileKeyAction.builder()
                actionBuilder.setPresentation(profileKeyCredentialPresentationData)

                actionsBuilder.addPromotePniPendingMembers(actionBuilder.buildInfallibly())

                promotedLocalAci = true
            } else if currentGroupMembership.isFullMember(localAci) {
                Logger.warn("Accepting invite, but already a full member!")
                promotedLocalAci = false
            } else {
                owsFailDebug("Local user is neither invited nor a full member. How did we get here?")
                throw GroupsV2Error.cannotBuildGroupChangeProto_conflictingChange
            }

            if promotedLocalAci {
                didChange = true
            }
        }

        if self.shouldLeaveGroupDeclineInvite {
            // Check that we are still invited or in group.
            if
                let invitedAtServiceId = currentGroupMembership.localUserInvitedAtServiceId(
                    localIdentifiers: localIdentifiers,
                )
            {
                if invitedAtServiceId == localIdentifiers.pni {
                    // If we are declining an invite to our PNI, we should not send group
                    // update messages. Messages cannot come from our PNI, so we would be
                    // leaking our ACI.
                    groupUpdateMessageBehavior = .sendNothing
                }

                // Decline invite
                var actionBuilder = GroupsProtoGroupChangeActionsDeletePendingMemberAction.builder()
                let invitedAtUserId = try groupV2Params.userId(for: invitedAtServiceId)
                actionBuilder.setDeletedUserID(invitedAtUserId)
                actionsBuilder.addDeletePendingMembers(actionBuilder.buildInfallibly())
                didChange = true
            } else if currentGroupMembership.isFullMember(localAci) {
                // Leave group
                var actionBuilder = GroupsProtoGroupChangeActionsDeleteMemberAction.builder()
                let localUserId = try groupV2Params.userId(for: localAci)
                actionBuilder.setDeletedUserID(localUserId)
                actionsBuilder.addDeleteMembers(actionBuilder.buildInfallibly())
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
                actionsBuilder.setModifyDisappearingMessagesTimer(actionBuilder.buildInfallibly())
                didChange = true
            }
        }

        if let isAnnouncementsOnly = self.isAnnouncementsOnly {
            if isAnnouncementsOnly == currentGroupModel.isAnnouncementsOnly {
                // Redundant change, not a conflict.
            } else {
                var actionBuilder = GroupsProtoGroupChangeActionsModifyAnnouncementsOnlyAction.builder()
                actionBuilder.setAnnouncementsOnly(isAnnouncementsOnly)
                actionsBuilder.setModifyAnnouncementsOnly(actionBuilder.buildInfallibly())
                didChange = true
            }
        }

        if shouldUpdateLocalProfileKey {
            guard let profileKeyCredential = profileKeyCredentials[localAci] else {
                throw OWSAssertionError("Missing profile key credential: \(localAci)")
            }
            var actionBuilder = GroupsProtoGroupChangeActionsModifyMemberProfileKeyAction.builder()
            actionBuilder.setPresentation(try GroupsV2Protos.presentationData(
                profileKeyCredential: profileKeyCredential,
                groupV2Params: groupV2Params,
            ))
            actionsBuilder.addModifyMemberProfileKeys(actionBuilder.buildInfallibly())
            didChange = true
        }

        // MARK: - Change action insertion point

        guard didChange else {
            return nil
        }

        Logger.info("Updating group.")
        return GroupsV2BuiltGroupChange(
            proto: actionsBuilder.buildInfallibly(),
            groupUpdateMessageBehavior: groupUpdateMessageBehavior,
        )
    }
}
