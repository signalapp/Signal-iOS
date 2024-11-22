//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public class GroupsV2Protos {

    private init() {}

    // MARK: -

    public class func serverPublicParams() -> ServerPublicParams {
        return try! ServerPublicParams(contents: TSConstants.serverPublicParams)
    }

    // MARK: -

    public class func buildMemberProto(
        profileKeyCredential: ExpiringProfileKeyCredential,
        role: GroupsProtoMemberRole,
        groupV2Params: GroupV2Params
    ) throws -> GroupsProtoMember {
        var builder = GroupsProtoMember.builder()
        builder.setRole(role)
        let presentationData = try self.presentationData(
            profileKeyCredential: profileKeyCredential,
            groupV2Params: groupV2Params
        )
        builder.setPresentation(presentationData)
        return builder.buildInfallibly()
    }

    public class func buildPendingMemberProto(
        serviceId: ServiceId,
        role: GroupsProtoMemberRole,
        groupV2Params: GroupV2Params
    ) throws -> GroupsProtoPendingMember {
        var builder = GroupsProtoPendingMember.builder()

        var memberBuilder = GroupsProtoMember.builder()
        memberBuilder.setRole(role)
        let userId = try groupV2Params.userId(for: serviceId)
        memberBuilder.setUserID(userId)
        builder.setMember(memberBuilder.buildInfallibly())

        return builder.buildInfallibly()
    }

    public class func buildRequestingMemberProto(profileKeyCredential: ExpiringProfileKeyCredential,
                                                 groupV2Params: GroupV2Params) throws -> GroupsProtoRequestingMember {
        var builder = GroupsProtoRequestingMember.builder()
        let presentationData = try self.presentationData(
            profileKeyCredential: profileKeyCredential,
            groupV2Params: groupV2Params
        )
        builder.setPresentation(presentationData)
        return builder.buildInfallibly()
    }

    public class func buildBannedMemberProto(aci: Aci, groupV2Params: GroupV2Params) throws -> GroupsProtoBannedMember {
        var builder = GroupsProtoBannedMember.builder()

        let userId = try groupV2Params.userId(for: aci)
        builder.setUserID(userId)

        return builder.buildInfallibly()
    }

    public class func presentationData(
        profileKeyCredential: ExpiringProfileKeyCredential,
        groupV2Params: GroupV2Params
    ) throws -> Data {
        let serverPublicParams = self.serverPublicParams()
        let profileOperations = ClientZkProfileOperations(serverPublicParams: serverPublicParams)
        let presentation = try profileOperations.createProfileKeyCredentialPresentation(
            groupSecretParams: groupV2Params.groupSecretParams,
            profileKeyCredential: profileKeyCredential
        )
        return presentation.serialize().asData
    }

    public class func buildNewGroupProto(
        groupModel: TSGroupModelV2,
        disappearingMessageToken: DisappearingMessageToken,
        groupV2Params: GroupV2Params,
        profileKeyCredentialMap: GroupsV2.ProfileKeyCredentialMap,
        localAci: Aci
    ) throws -> GroupsProtoGroup {
        // Collect credential for self.
        guard let localProfileKeyCredential = profileKeyCredentialMap[localAci] else {
            throw OWSAssertionError("Missing localProfileKeyCredential.")
        }
        // Collect credentials for all members except self.

        var groupBuilder = GroupsProtoGroup.builder()
        let initialRevision: UInt32 = 0
        groupBuilder.setRevision(initialRevision)
        groupBuilder.setPublicKey(groupV2Params.groupPublicParamsData)
        // GroupsV2 TODO: Will production implementation of encryptString() pad?

        let groupTitle = groupModel.groupName?.ows_stripped() ?? " "
        let groupTitleEncrypted = try groupV2Params.encryptGroupName(groupTitle)
        guard groupTitle.glyphCount <= GroupManager.maxGroupNameGlyphCount else {
            throw OWSAssertionError("groupTitle is too long.")
        }
        guard groupTitleEncrypted.count <= GroupManager.maxGroupNameEncryptedByteCount else {
            throw OWSAssertionError("Encrypted groupTitle is too long.")
        }
        groupBuilder.setTitle(groupTitleEncrypted)

        let hasAvatarUrl = groupModel.avatarUrlPath != nil
        let hasAvatarData = groupModel.avatarData != nil
        guard hasAvatarData == hasAvatarUrl else {
            throw OWSAssertionError("hasAvatarData: (\(hasAvatarData)) != hasAvatarUrl: (\(hasAvatarUrl))")
        }
        if let avatarUrl = groupModel.avatarUrlPath {
            groupBuilder.setAvatar(avatarUrl)
        }

        let groupAccess = groupModel.access
        groupBuilder.setAccessControl(buildAccessProto(groupAccess: groupAccess))

        if let inviteLinkPassword = groupModel.inviteLinkPassword, !inviteLinkPassword.isEmpty {
            groupBuilder.setInviteLinkPassword(inviteLinkPassword)
        }

        // * You will be member 0 and the only admin.
        // * Other members will be non-admin members.
        //
        // Add local user first to ensure that they are user 0.
        let groupMembership = groupModel.groupMembership
        assert(groupMembership.isFullMemberAndAdministrator(localAci))
        groupBuilder.addMembers(try buildMemberProto(
            profileKeyCredential: localProfileKeyCredential,
            role: .administrator,
            groupV2Params: groupV2Params
        ))
        for (aci, profileKeyCredential) in profileKeyCredentialMap {
            guard aci != localAci else {
                continue
            }
            let isInvited = groupMembership.isInvitedMember(aci)
            guard !isInvited else {
                continue
            }
            let isAdministrator = groupMembership.isFullMemberAndAdministrator(aci)
            let role: GroupsProtoMemberRole = isAdministrator ? .administrator : .`default`
            groupBuilder.addMembers(try buildMemberProto(
                profileKeyCredential: profileKeyCredential,
                role: role,
                groupV2Params: groupV2Params
            ))
        }
        for address in groupMembership.invitedMembers {
            guard let serviceId = address.serviceId else {
                throw OWSAssertionError("Missing uuid.")
            }
            guard serviceId != localAci else {
                continue
            }
            let isAdministrator = groupMembership.isFullOrInvitedAdministrator(serviceId)
            let role: GroupsProtoMemberRole = isAdministrator ? .administrator : .`default`
            groupBuilder.addPendingMembers(try buildPendingMemberProto(
                serviceId: serviceId,
                role: role,
                groupV2Params: groupV2Params
            ))
        }

        for (aci, _) in groupMembership.bannedMembers {
            owsFailDebug("There should never be a banned member in a freshly created group!")

            groupBuilder.addBannedMembers(try buildBannedMemberProto(aci: aci, groupV2Params: groupV2Params))
        }

        let encryptedTimerData = try groupV2Params.encryptDisappearingMessagesTimer(disappearingMessageToken)
        groupBuilder.setDisappearingMessagesTimer(encryptedTimerData)

        validateInviteLinkState(inviteLinkPassword: groupModel.inviteLinkPassword, groupAccess: groupAccess)

        groupBuilder.setAnnouncementsOnly(groupModel.isAnnouncementsOnly)

        return groupBuilder.buildInfallibly()
    }

    public class func validateInviteLinkState(inviteLinkPassword: Data?, groupAccess: GroupAccess) {
        let canJoinFromInviteLink = groupAccess.canJoinFromInviteLink
        let hasInviteLinkPassword = inviteLinkPassword?.count ?? 0 > 0
        if canJoinFromInviteLink, !hasInviteLinkPassword {
            owsFailDebug("Invite links enabled without inviteLinkPassword.")
        } else if !canJoinFromInviteLink, hasInviteLinkPassword {
            // We don't clear the password when disabling invite links,
            // so that the link doesn't change if it is re-enabled.
        }
    }

    public class func buildAccessProto(groupAccess: GroupAccess) -> GroupsProtoAccessControl {
        var builder = GroupsProtoAccessControl.builder()
        builder.setAttributes(groupAccess.attributes.protoAccess)
        builder.setMembers(groupAccess.members.protoAccess)
        builder.setAddFromInviteLink(groupAccess.addFromInviteLink.protoAccess)
        return builder.buildInfallibly()
    }

    public class func buildGroupContextProto(
        groupModel: TSGroupModelV2,
        groupChangeProtoData: Data?
    ) throws -> SSKProtoGroupContextV2 {
        let builder = SSKProtoGroupContextV2.builder()
        builder.setMasterKey(try groupModel.masterKey().serialize().asData)
        builder.setRevision(groupModel.revision)

        if let groupChangeProtoData {
            if groupChangeProtoData.count <= GroupManager.maxEmbeddedChangeProtoLength {
                assert(groupChangeProtoData.count > 0)
                builder.setGroupChange(groupChangeProtoData)
            } else {
                // This isn't necessarily a bug, but it should be rare.
                owsFailDebug("Discarding oversize group change proto.")
            }
        }

        return builder.buildInfallibly()
    }

    // MARK: -

    public enum VerificationOperation {
        case alreadyTrusted
        case verifySignature(groupId: Data)
    }

    /// This method throws if verification fails.
    public static func parseGroupChangeProto(
        _ changeProto: GroupsProtoGroupChange,
        verificationOperation: VerificationOperation
    ) throws -> GroupsProtoGroupChangeActions {
        guard let changeActionsProtoData = changeProto.actions else {
            throw OWSAssertionError("Missing changeActionsProtoData.")
        }
        if case .verifySignature = verificationOperation {
            let serverSignature = try NotarySignature(contents: [UInt8](changeProto.serverSignature ?? Data()))
            try self.serverPublicParams().verifySignature(message: [UInt8](changeActionsProtoData), notarySignature: serverSignature)
        }
        let result = try GroupsProtoGroupChangeActions(serializedData: changeActionsProtoData)
        if case .verifySignature(let groupId) = verificationOperation {
            guard result.groupID == groupId else {
                throw OWSAssertionError("Invalid groupId.")
            }
        }
        return result
    }

    // MARK: -

    class func parse(
        groupResponseProto: GroupsProtoGroupResponse,
        downloadedAvatars: GroupV2DownloadedAvatars,
        groupV2Params: GroupV2Params
    ) throws -> GroupV2SnapshotResponse {
        guard let groupProto = groupResponseProto.group else {
            throw OWSAssertionError("Missing group state in response.")
        }
        return GroupV2SnapshotResponse(
            groupSnapshot: try parse(groupProto: groupProto, downloadedAvatars: downloadedAvatars, groupV2Params: groupV2Params),
            groupSendEndorsements: groupResponseProto.groupSendEndorsementsResponse
        )
    }

    class func parse(
        groupProto: GroupsProtoGroup,
        downloadedAvatars: GroupV2DownloadedAvatars,
        groupV2Params: GroupV2Params
    ) throws -> GroupV2Snapshot {

        let title = groupV2Params.decryptGroupName(groupProto.title) ?? ""
        let descriptionText = groupV2Params.decryptGroupDescription(groupProto.descriptionBytes)

        var avatarUrlPath: String?
        var avatarData: Data?
        if let avatar = groupProto.avatar, !avatar.isEmpty {
            avatarUrlPath = avatar
            do {
                avatarData = try downloadedAvatars.avatarData(for: avatar)
            } catch {
                // This should only occur if the avatar is no longer available
                // on the CDN.
                owsFailDebug("Could not download avatar: \(error).")
                avatarData = nil
                avatarUrlPath = nil
            }
        }

        // This client can learn of profile keys from parsing group state protos.
        // After parsing, we should fill in profileKeys in the profile manager.
        var profileKeys = [Aci: Data]()

        var groupMembershipBuilder = GroupMembership.Builder()

        for memberProto in groupProto.members {
            guard let userID = memberProto.userID else {
                throw OWSAssertionError("Group member missing userID.")
            }
            let protoRole = memberProto.role
            guard let role = TSGroupMemberRole.role(for: protoRole) else {
                throw OWSAssertionError("Group member missing role.")
            }

            // Some userIds/uuidCiphertexts can be validated by
            // the service. This is one.
            let aci = try groupV2Params.aci(for: userID)

            guard !groupMembershipBuilder.hasMemberOfAnyKind(SignalServiceAddress(aci)) else {
                owsFailDebug("Duplicate user in group: \(aci)")
                continue
            }
            groupMembershipBuilder.addFullMember(
                aci,
                role: role,
                didJoinFromInviteLink: false,
                didJoinFromAcceptedJoinRequest: false
            )

            guard let profileKeyCiphertextData = memberProto.profileKey else {
                throw OWSAssertionError("Group member missing profileKeyCiphertextData.")
            }
            let profileKeyCiphertext = try ProfileKeyCiphertext(contents: [UInt8](profileKeyCiphertextData))
            let profileKey = try groupV2Params.profileKey(forProfileKeyCiphertext: profileKeyCiphertext, aci: aci)
            profileKeys[aci] = profileKey
        }

        for pendingMemberProto in groupProto.pendingMembers {
            guard let memberProto = pendingMemberProto.member else {
                throw OWSAssertionError("Group pending member missing memberProto.")
            }
            guard let userId = memberProto.userID else {
                throw OWSAssertionError("Group pending member missing userID.")
            }
            guard let addedByUserId = pendingMemberProto.addedByUserID else {
                throw OWSAssertionError("Group pending member missing addedByUserID.")
            }
            let protoRole = memberProto.role
            guard let role = TSGroupMemberRole.role(for: protoRole) else {
                throw OWSAssertionError("Group member missing role.")
            }

            // Some userIds/uuidCiphertexts can be validated by
            // the service. This is one.
            let addedByAci = try groupV2Params.aci(for: addedByUserId)

            // Some userIds/uuidCiphertexts can be validated by
            // the service. This one cannot.  Therefore we need to
            // be robust to invalid ciphertexts.
            let serviceId: ServiceId
            do {
                serviceId = try groupV2Params.serviceId(for: userId)
            } catch {
                guard !groupMembershipBuilder.hasInvalidInvite(userId: userId) else {
                    owsFailDebug("Duplicate invalid invite in group: \(userId)")
                    continue
                }
                groupMembershipBuilder.addInvalidInvite(userId: userId, addedByUserId: addedByUserId)
                owsFailDebug("Error parsing uuid: \(error)")
                continue
            }
            guard !groupMembershipBuilder.hasMemberOfAnyKind(SignalServiceAddress(serviceId)) else {
                owsFailDebug("Duplicate user in group: \(serviceId)")
                continue
            }
            groupMembershipBuilder.addInvitedMember(serviceId, role: role, addedByAci: addedByAci)
        }

        for requestingMemberProto in groupProto.requestingMembers {
            guard let userId = requestingMemberProto.userID else {
                throw OWSAssertionError("Group requesting member missing userID.")
            }

            // Some userIds/uuidCiphertexts can be validated by
            // the service. This is one.
            let aci = try groupV2Params.aci(for: userId)

            guard !groupMembershipBuilder.hasMemberOfAnyKind(SignalServiceAddress(aci)) else {
                owsFailDebug("Duplicate user in group: \(aci)")
                continue
            }
            groupMembershipBuilder.addRequestingMember(aci)

            guard let profileKeyCiphertextData = requestingMemberProto.profileKey else {
                throw OWSAssertionError("Group member missing profileKeyCiphertextData.")
            }
            let profileKeyCiphertext = try ProfileKeyCiphertext(contents: [UInt8](profileKeyCiphertextData))
            let profileKey = try groupV2Params.profileKey(forProfileKeyCiphertext: profileKeyCiphertext, aci: aci)
            profileKeys[aci] = profileKey
        }

        for bannedMemberProto in groupProto.bannedMembers {
            guard let userId = bannedMemberProto.userID else {
                throw OWSAssertionError("Group banned member missing userID.")
            }

            let bannedAtTimestamp = bannedMemberProto.bannedAtTimestamp
            let aci = try groupV2Params.aci(for: userId)

            groupMembershipBuilder.addBannedMember(aci, bannedAtTimestamp: bannedAtTimestamp)
        }

        let groupMembership = groupMembershipBuilder.build()

        let inviteLinkPassword = groupProto.inviteLinkPassword

        let isAnnouncementsOnly = groupProto.announcementsOnly

        guard let accessControl = groupProto.accessControl else {
            throw OWSAssertionError("Missing accessControl.")
        }
        let accessControlForAttributes = accessControl.attributes
        let accessControlForMembers = accessControl.members
        // If group state does not have "invite link" access specified,
        // assume invite links are disabled.
        let accessControlForAddFromInviteLink = accessControl.addFromInviteLink

        // If the timer blob is not populated or has zero duration,
        // disappearing messages should be disabled.
        let disappearingMessageToken = groupV2Params.decryptDisappearingMessagesTimer(groupProto.disappearingMessagesTimer)

        let groupAccess = GroupAccess(
            members: GroupV2Access.access(forProtoAccess: accessControlForMembers),
            attributes: GroupV2Access.access(forProtoAccess: accessControlForAttributes),
            addFromInviteLink: GroupV2Access.access(forProtoAccess: accessControlForAddFromInviteLink)
        )

        validateInviteLinkState(inviteLinkPassword: inviteLinkPassword, groupAccess: groupAccess)

        let revision = groupProto.revision
        let groupSecretParams = groupV2Params.groupSecretParams
        return GroupV2Snapshot(
            groupSecretParams: groupSecretParams,
            revision: revision,
            title: title,
            descriptionText: descriptionText,
            avatarUrlPath: avatarUrlPath,
            avatarData: avatarData,
            groupMembership: groupMembership,
            groupAccess: groupAccess,
            inviteLinkPassword: inviteLinkPassword,
            disappearingMessageToken: disappearingMessageToken,
            isAnnouncementsOnly: isAnnouncementsOnly,
            profileKeys: profileKeys
        )
    }

    // MARK: -

    public class func parseGroupInviteLinkPreview(_ protoData: Data,
                                                  groupV2Params: GroupV2Params) throws -> GroupInviteLinkPreview {
        let joinInfoProto = try GroupsProtoGroupJoinInfo.init(serializedData: protoData)
        guard let titleData = joinInfoProto.title,
            !titleData.isEmpty else {
                throw OWSAssertionError("Missing or invalid titleData.")
        }
        guard let title = groupV2Params.decryptGroupName(titleData) else {
            throw OWSAssertionError("Missing or invalid title.")
        }

        let descriptionText: String? = groupV2Params.decryptGroupDescription(joinInfoProto.descriptionBytes)

        let avatarUrlPath: String? = joinInfoProto.avatar
        let memberCount = joinInfoProto.memberCount

        let protoAccess = joinInfoProto.addFromInviteLink
        let rawAccess = GroupV2Access.access(forProtoAccess: protoAccess)
        let addFromInviteLinkAccess = GroupAccess.filter(forAddFromInviteLink: rawAccess)
        guard addFromInviteLinkAccess != .unknown else {
            throw OWSAssertionError("Unknown addFromInviteLinkAccess.")
        }
        let revision = joinInfoProto.revision
        let isLocalUserRequestingMember = joinInfoProto.pendingAdminApproval

        return GroupInviteLinkPreview(title: title,
                                      descriptionText: descriptionText,
                                      avatarUrlPath: avatarUrlPath,
                                      memberCount: memberCount,
                                      addFromInviteLinkAccess: addFromInviteLinkAccess,
                                      revision: revision,
                                      isLocalUserRequestingMember: isLocalUserRequestingMember)
    }

    // MARK: -

    public struct ParsedChange {
        public var groupProto: GroupsProtoGroup?
        public var changeActionsProto: GroupsProtoGroupChangeActions?

        public init?(groupProto: GroupsProtoGroup?, changeActionsProto: GroupsProtoGroupChangeActions?) {
            guard groupProto != nil || changeActionsProto != nil else {
                return nil
            }
            self.groupProto = groupProto
            self.changeActionsProto = changeActionsProto
        }
    }

    // We do not treat an empty response with no changes as an error.
    public class func parseChangesFromService(groupChangesProto: GroupsProtoGroupChanges) throws -> [ParsedChange] {
        var results = [ParsedChange]()
        for changeStateData in groupChangesProto.groupChanges {
            let changeStateProto = try GroupsProtoGroupChangesGroupChangeState(serializedData: changeStateData)

            let parsedChange = ParsedChange(
                groupProto: changeStateProto.groupState,
                changeActionsProto: try changeStateProto.groupChange.map {
                    // No need to verify the signature; these are from the service.
                    return try parseGroupChangeProto($0, verificationOperation: .alreadyTrusted)
                }
            )

            guard let parsedChange else {
                throw OWSAssertionError("both groupState and groupChange are absent")
            }

            results.append(parsedChange)
        }
        return results
    }

    // MARK: -

    public class func collectAvatarUrlPaths(
        groupProtos: [GroupsProtoGroup] = [],
        changeActionsProtos: [GroupsProtoGroupChangeActions] = []
    ) throws -> [String] {
        var avatarUrlPaths = [String]()
        for groupProto in groupProtos {
            avatarUrlPaths += self.collectAvatarUrlPaths(groupProto: groupProto)
        }
        for changeActionsProto in changeActionsProtos {
            avatarUrlPaths += self.collectAvatarUrlPaths(changeActionsProto: changeActionsProto)
        }
        // Discard empty avatar urls.
        return avatarUrlPaths.filter { !$0.isEmpty }
    }

    private class func collectAvatarUrlPaths(changeActionsProto: GroupsProtoGroupChangeActions) -> [String] {
        guard let modifyAvatarAction = changeActionsProto.modifyAvatar else {
            return []
        }
        guard let avatarUrlPath = modifyAvatarAction.avatar else {
            return []
        }
        return [avatarUrlPath]
    }

    private class func collectAvatarUrlPaths(groupProto: GroupsProtoGroup) -> [String] {
        guard let avatarUrlPath = groupProto.avatar else {
            return []
        }
        return [avatarUrlPath]
    }
}
