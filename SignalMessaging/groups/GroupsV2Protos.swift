//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import LibSignalClient

public class GroupsV2Protos {

    private init() {}

    // MARK: -

    private class func serverPublicParamsData() throws -> Data {
        guard let data = Data(base64Encoded: TSConstants.serverPublicParamsBase64),
            data.count > 0 else {
                throw OWSAssertionError("Invalid server public params")
        }

        return data
    }

    public class func serverPublicParams() throws -> ServerPublicParams {
        let data = try serverPublicParamsData()
        let bytes = [UInt8](data)
        return try ServerPublicParams(contents: bytes)
    }

    // MARK: -

    public class func buildMemberProto(profileKeyCredential: ExpiringProfileKeyCredential,
                                       role: GroupsProtoMemberRole,
                                       groupV2Params: GroupV2Params) throws -> GroupsProtoMember {
        var builder = GroupsProtoMember.builder()
        builder.setRole(role)
        let presentationData = try self.presentationData(profileKeyCredential: profileKeyCredential,
                                                         groupV2Params: groupV2Params)
        builder.setPresentation(presentationData)
        return try builder.build()
    }

    public class func buildPendingMemberProto(uuid: UUID,
                                              role: GroupsProtoMemberRole,
                                              localUuid: UUID,
                                              groupV2Params: GroupV2Params) throws -> GroupsProtoPendingMember {
        var builder = GroupsProtoPendingMember.builder()

        var memberBuilder = GroupsProtoMember.builder()
        memberBuilder.setRole(role)
        let userId = try groupV2Params.userId(forUuid: uuid)
        memberBuilder.setUserID(userId)
        builder.setMember(try memberBuilder.build())

        return try builder.build()
    }

    public class func buildRequestingMemberProto(profileKeyCredential: ExpiringProfileKeyCredential,
                                                 groupV2Params: GroupV2Params) throws -> GroupsProtoRequestingMember {
        var builder = GroupsProtoRequestingMember.builder()
        let presentationData = try self.presentationData(profileKeyCredential: profileKeyCredential,
                                                         groupV2Params: groupV2Params)
        builder.setPresentation(presentationData)
        return try builder.build()
    }

    public class func buildBannedMemberProto(uuid: UUID, groupV2Params: GroupV2Params) throws -> GroupsProtoBannedMember {
        var builder = GroupsProtoBannedMember.builder()

        let userId = try groupV2Params.userId(forUuid: uuid)
        builder.setUserID(userId)

        return try builder.build()
    }

    public class func presentationData(profileKeyCredential: ExpiringProfileKeyCredential,
                                       groupV2Params: GroupV2Params) throws -> Data {

        let serverPublicParams = try self.serverPublicParams()
        let profileOperations = ClientZkProfileOperations(serverPublicParams: serverPublicParams)
        let presentation = try profileOperations.createProfileKeyCredentialPresentation(groupSecretParams: groupV2Params.groupSecretParams,
                                                                                        profileKeyCredential: profileKeyCredential)
        return presentation.serialize().asData
    }

    public class func buildNewGroupProto(groupModel: TSGroupModelV2,
                                         disappearingMessageToken: DisappearingMessageToken,
                                         groupV2Params: GroupV2Params,
                                         profileKeyCredentialMap: GroupsV2Swift.ProfileKeyCredentialMap,
                                         localUuid: UUID) throws -> GroupsProtoGroup {

        // Collect credential for self.
        guard let localProfileKeyCredential = profileKeyCredentialMap[localUuid] else {
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
        groupBuilder.setAccessControl(try buildAccessProto(groupAccess: groupAccess))

        if let inviteLinkPassword = groupModel.inviteLinkPassword,
            !inviteLinkPassword.isEmpty {
                groupBuilder.setInviteLinkPassword(inviteLinkPassword)
        }

        // * You will be member 0 and the only admin.
        // * Other members will be non-admin members.
        //
        // Add local user first to ensure that they are user 0.
        let groupMembership = groupModel.groupMembership
        assert(groupMembership.isFullMemberAndAdministrator(localUuid))
        groupBuilder.addMembers(try buildMemberProto(profileKeyCredential: localProfileKeyCredential,
                                                     role: .administrator,
                                                     groupV2Params: groupV2Params))
        for (uuid, profileKeyCredential) in profileKeyCredentialMap {
            guard uuid != localUuid else {
                continue
            }
            let isInvited = groupMembership.isInvitedMember(uuid)
            guard !isInvited else {
                continue
            }
            let isAdministrator = groupMembership.isFullMemberAndAdministrator(uuid)
            let role: GroupsProtoMemberRole = isAdministrator ? .administrator : .`default`
            groupBuilder.addMembers(try buildMemberProto(profileKeyCredential: profileKeyCredential,
                                                         role: role,
                                                         groupV2Params: groupV2Params))
        }
        for address in groupMembership.invitedMembers {
            guard let uuid = address.uuid else {
                throw OWSAssertionError("Missing uuid.")
            }
            guard uuid != localUuid else {
                continue
            }
            let isAdministrator = groupMembership.isFullOrInvitedAdministrator(uuid)
            let role: GroupsProtoMemberRole = isAdministrator ? .administrator : .`default`
            groupBuilder.addPendingMembers(try buildPendingMemberProto(uuid: uuid,
                                                                       role: role,
                                                                       localUuid: localUuid,
                                                                       groupV2Params: groupV2Params))
        }

        for (uuid, _) in groupMembership.bannedMembers {
            owsFailDebug("There should never be a banned member in a freshly created group!")

            groupBuilder.addBannedMembers(try buildBannedMemberProto(uuid: uuid, groupV2Params: groupV2Params))
        }

        let encryptedTimerData = try groupV2Params.encryptDisappearingMessagesTimer(disappearingMessageToken)
        groupBuilder.setDisappearingMessagesTimer(encryptedTimerData)

        validateInviteLinkState(inviteLinkPassword: groupModel.inviteLinkPassword, groupAccess: groupAccess)

        groupBuilder.setAnnouncementsOnly(groupModel.isAnnouncementsOnly)

        return try groupBuilder.build()
    }

    public class func validateInviteLinkState(inviteLinkPassword: Data?, groupAccess: GroupAccess) {
        let canJoinFromInviteLink = groupAccess.canJoinFromInviteLink
        let hasInviteLinkPassword = inviteLinkPassword?.count ?? 0 > 0
        if canJoinFromInviteLink, !hasInviteLinkPassword {
            owsFailDebug("Invite links enabled without inviteLinkPassword.")
        } else if !canJoinFromInviteLink, hasInviteLinkPassword {
            // We don't clear the password when disabling invite links,
            // so that the link doesn't change if it is re-enabled.
            Logger.verbose("inviteLinkPassword set but invite links not enabled.")
        }
    }

    public class func buildAccessProto(groupAccess: GroupAccess) throws -> GroupsProtoAccessControl {
        var builder = GroupsProtoAccessControl.builder()
        builder.setAttributes(groupAccess.attributes.protoAccess)
        builder.setMembers(groupAccess.members.protoAccess)
        builder.setAddFromInviteLink(groupAccess.addFromInviteLink.protoAccess)
        return try builder.build()
    }

    public class func masterKeyData(forGroupModel groupModel: TSGroupModelV2) throws -> Data {
        return try masterKeyData(forGroupSecretParamsData: groupModel.secretParamsData)
    }

    public class func masterKeyData(forGroupSecretParamsData groupSecretParamsData: Data) throws -> Data {
        let groupSecretParams = try GroupSecretParams(contents: [UInt8](groupSecretParamsData))
        return try groupSecretParams.getMasterKey().serialize().asData
    }

    public class func buildGroupContextV2Proto(groupModel: TSGroupModelV2,
                                               changeActionsProtoData: Data?) throws -> SSKProtoGroupContextV2 {

        let builder = SSKProtoGroupContextV2.builder()
        builder.setMasterKey(try masterKeyData(forGroupModel: groupModel))
        builder.setRevision(groupModel.revision)

        if let changeActionsProtoData = changeActionsProtoData {
            if changeActionsProtoData.count <= GroupManager.maxEmbeddedChangeProtoLength {
                assert(changeActionsProtoData.count > 0)
                builder.setGroupChange(changeActionsProtoData)
            } else {
                // This isn't necessarily a bug, but it should be rare.
                owsFailDebug("Discarding oversize group change proto.")
            }
        }

        return try builder.build()
    }

    // MARK: -

    // This method throws if verification fails.
    public class func parseAndVerifyChangeActionsProto(_ changeProtoData: Data,
                                                       ignoreSignature: Bool) throws -> GroupsProtoGroupChangeActions {
        let changeProto = try GroupsProtoGroupChange(serializedData: changeProtoData)
        guard changeProto.hasChangeEpoch,
            changeProto.changeEpoch <= GroupManager.changeProtoEpoch else {
            throw OWSAssertionError("Invalid embedded change proto epoch: \(changeProto.changeEpoch).")
        }
        return try parseAndVerifyChangeActionsProto(changeProto,
                                                    ignoreSignature: ignoreSignature)
    }

    // This method throws if verification fails.
    public class func parseAndVerifyChangeActionsProto(_ changeProto: GroupsProtoGroupChange,
                                                       ignoreSignature: Bool) throws -> GroupsProtoGroupChangeActions {
        guard let changeActionsProtoData = changeProto.actions else {
            throw OWSAssertionError("Missing changeActionsProtoData.")
        }
        if !ignoreSignature {
            guard let serverSignatureData = changeProto.serverSignature else {
                throw OWSAssertionError("Missing serverSignature.")
            }
            let serverSignature = try NotarySignature(contents: [UInt8](serverSignatureData))
            let serverPublicParams = try self.serverPublicParams()
            try serverPublicParams.verifySignature(message: [UInt8](changeActionsProtoData),
                                                   notarySignature: serverSignature)
        }
        let changeActionsProto = try GroupsProtoGroupChangeActions(serializedData: changeActionsProtoData)
        return changeActionsProto
    }

    // MARK: -

    public class func parse(groupProto: GroupsProtoGroup,
                            downloadedAvatars: GroupV2DownloadedAvatars,
                            groupV2Params: GroupV2Params) throws -> GroupV2Snapshot {

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
        var profileKeys = [UUID: Data]()

        var groupMembershipBuilder = GroupMembership.Builder()

        for memberProto in groupProto.members {
            guard let userID = memberProto.userID else {
                throw OWSAssertionError("Group member missing userID.")
            }
            guard memberProto.hasRole,
                let protoRole = memberProto.role,
                let role = TSGroupMemberRole.role(for: protoRole) else {
                    throw OWSAssertionError("Group member missing role.")
            }

            // Some userIds/uuidCiphertexts can be validated by
            // the service. This is one.
            let uuid = try groupV2Params.uuid(forUserId: userID)

            let address = SignalServiceAddress(uuid: uuid)
            guard !groupMembershipBuilder.hasMemberOfAnyKind(address) else {
                owsFailDebug("Duplicate user in group: \(address)")
                continue
            }
            groupMembershipBuilder.addFullMember(address, role: role, didJoinFromInviteLink: false)

            guard let profileKeyCiphertextData = memberProto.profileKey else {
                throw OWSAssertionError("Group member missing profileKeyCiphertextData.")
            }
            let profileKeyCiphertext = try ProfileKeyCiphertext(contents: [UInt8](profileKeyCiphertextData))
            let profileKey = try groupV2Params.profileKey(forProfileKeyCiphertext: profileKeyCiphertext,
                                                          uuid: uuid)
            profileKeys[uuid] = profileKey
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
            guard memberProto.hasRole,
                let protoRole = memberProto.role,
                let role = TSGroupMemberRole.role(for: protoRole) else {
                    throw OWSAssertionError("Group member missing role.")
            }

            // Some userIds/uuidCiphertexts can be validated by
            // the service. This is one.
            let addedByUuid = try groupV2Params.uuid(forUserId: addedByUserId)

            // Some userIds/uuidCiphertexts can be validated by
            // the service. This one cannot.  Therefore we need to
            // be robust to invalid ciphertexts.
            let uuid: UUID
            do {
                uuid = try groupV2Params.uuid(forUserId: userId)
            } catch {
                guard !groupMembershipBuilder.hasInvalidInvite(userId: userId) else {
                    owsFailDebug("Duplicate invalid invite in group: \(userId)")
                    continue
                }
                groupMembershipBuilder.addInvalidInvite(userId: userId, addedByUserId: addedByUserId)
                owsFailDebug("Error parsing uuid: \(error)")
                continue
            }
            let address = SignalServiceAddress(uuid: uuid)
            guard !groupMembershipBuilder.hasMemberOfAnyKind(address) else {
                owsFailDebug("Duplicate user in group: \(address)")
                continue
            }
            groupMembershipBuilder.addInvitedMember(address, role: role, addedByUuid: addedByUuid)
        }

        for requestingMemberProto in groupProto.requestingMembers {
            guard let userId = requestingMemberProto.userID else {
                throw OWSAssertionError("Group requesting member missing userID.")
            }

            // Some userIds/uuidCiphertexts can be validated by
            // the service. This is one.
            let uuid = try groupV2Params.uuid(forUserId: userId)

            let address = SignalServiceAddress(uuid: uuid)
            guard !groupMembershipBuilder.hasMemberOfAnyKind(address) else {
                owsFailDebug("Duplicate user in group: \(address)")
                continue
            }
            groupMembershipBuilder.addRequestingMember(address)

            guard let profileKeyCiphertextData = requestingMemberProto.profileKey else {
                throw OWSAssertionError("Group member missing profileKeyCiphertextData.")
            }
            let profileKeyCiphertext = try ProfileKeyCiphertext(contents: [UInt8](profileKeyCiphertextData))
            let profileKey = try groupV2Params.profileKey(forProfileKeyCiphertext: profileKeyCiphertext,
                                                          uuid: uuid)
            profileKeys[uuid] = profileKey
        }

        for bannedMemberProto in groupProto.bannedMembers {
            guard let userId = bannedMemberProto.userID else {
                throw OWSAssertionError("Group banned member missing userID.")
            }

            let bannedAtTimestamp = bannedMemberProto.bannedAtTimestamp
            let uuid = try groupV2Params.uuid(forUserId: userId)

            groupMembershipBuilder.addBannedMember(uuid, bannedAtTimestamp: bannedAtTimestamp)
        }

        let groupMembership = groupMembershipBuilder.build()

        let inviteLinkPassword = groupProto.inviteLinkPassword

        let isAnnouncementsOnly = (groupProto.hasAnnouncementsOnly
                                    ? groupProto.announcementsOnly
                                    : false)

        guard let accessControl = groupProto.accessControl else {
            throw OWSAssertionError("Missing accessControl.")
        }
        guard let accessControlForAttributes = accessControl.attributes else {
            throw OWSAssertionError("Missing accessControl.members.")
        }
        guard let accessControlForMembers = accessControl.members else {
            throw OWSAssertionError("Missing accessControl.members.")
        }
        // If group state does not have "invite link" access specified,
        // assume invite links are disabled.
        let accessControlForAddFromInviteLink = accessControl.addFromInviteLink ?? .unsatisfiable

        // If the timer blob is not populated or has zero duration,
        // disappearing messages should be disabled.
        let disappearingMessageToken = groupV2Params.decryptDisappearingMessagesTimer(groupProto.disappearingMessagesTimer)

        let groupAccess = GroupAccess(members: GroupV2Access.access(forProtoAccess: accessControlForMembers),
                                      attributes: GroupV2Access.access(forProtoAccess: accessControlForAttributes),
                                      addFromInviteLink: GroupV2Access.access(forProtoAccess: accessControlForAddFromInviteLink))

        validateInviteLinkState(inviteLinkPassword: inviteLinkPassword, groupAccess: groupAccess)

        let revision = groupProto.revision
        let groupSecretParamsData = groupV2Params.groupSecretParamsData
        return GroupV2SnapshotImpl(groupSecretParamsData: groupSecretParamsData,
                                   groupProto: groupProto,
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
                                   profileKeys: profileKeys)
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
        guard joinInfoProto.hasMemberCount,
            joinInfoProto.hasAddFromInviteLink else {
            throw OWSAssertionError("Missing or invalid memberCount.")
        }
        let memberCount = joinInfoProto.memberCount

        guard let protoAccess = joinInfoProto.addFromInviteLink else {
            throw OWSAssertionError("Missing or invalid addFromInviteLinkAccess.")
        }
        let rawAccess = GroupV2Access.access(forProtoAccess: protoAccess)
        let addFromInviteLinkAccess = GroupAccess.filter(forAddFromInviteLink: rawAccess)
        guard addFromInviteLinkAccess != .unknown else {
            throw OWSAssertionError("Unknown addFromInviteLinkAccess.")
        }
        guard joinInfoProto.hasRevision else {
            throw OWSAssertionError("Missing or invalid revision.")
        }
        let revision = joinInfoProto.revision
        let isLocalUserRequestingMember = joinInfoProto.hasPendingAdminApproval && joinInfoProto.pendingAdminApproval

        return GroupInviteLinkPreview(title: title,
                                      descriptionText: descriptionText,
                                      avatarUrlPath: avatarUrlPath,
                                      memberCount: memberCount,
                                      addFromInviteLinkAccess: addFromInviteLinkAccess,
                                      revision: revision,
                                      isLocalUserRequestingMember: isLocalUserRequestingMember)
    }

    // MARK: -

    // We do not treat an empty response with no changes as an error.
    public class func parseChangesFromService(groupChangesProto: GroupsProtoGroupChanges,
                                              downloadedAvatars: GroupV2DownloadedAvatars,
                                              groupV2Params: GroupV2Params) throws -> [GroupV2Change] {
        var result = [GroupV2Change]()
        for changeStateData in groupChangesProto.groupChanges {
            let changeStateProto = try GroupsProtoGroupChangesGroupChangeState(serializedData: changeStateData)

            var snapshot: GroupV2Snapshot?
            if let snapshotProto = changeStateProto.groupState {
                snapshot = try parse(groupProto: snapshotProto,
                                     downloadedAvatars: downloadedAvatars,
                                     groupV2Params: groupV2Params)
            }

            var changeActionsProto: GroupsProtoGroupChangeActions?
            if let changeProto = changeStateProto.groupChange {
                // We can ignoreSignature because these protos came from the service.
                changeActionsProto = try parseAndVerifyChangeActionsProto(changeProto, ignoreSignature: true)
            }

            guard snapshot != nil || changeActionsProto != nil else {
                throw OWSAssertionError("both groupState and groupChange are absent")
            }

            result.append(GroupV2Change(snapshot: snapshot,
                                        changeActionsProto: changeActionsProto,
                                        downloadedAvatars: downloadedAvatars))
        }
        return result
    }

    // MARK: -

    public class func collectAvatarUrlPaths(groupProto: GroupsProtoGroup? = nil,
                                            groupChangesProto: GroupsProtoGroupChanges? = nil,
                                            changeActionsProto: GroupsProtoGroupChangeActions? = nil,
                                            ignoreSignature: Bool,
                                            groupV2Params: GroupV2Params) -> Promise<[String]> {
        return DispatchQueue.global().async(.promise) { () throws -> [String] in
            var avatarUrlPaths = [String]()
            if let groupProto = groupProto {
                avatarUrlPaths += self.collectAvatarUrlPaths(groupProto: groupProto)
            }
            if let groupChangesProto = groupChangesProto {
                avatarUrlPaths += try self.collectAvatarUrlPaths(groupChangesProto: groupChangesProto,
                                                                 ignoreSignature: ignoreSignature,
                                                                 groupV2Params: groupV2Params)
            }
            if let changeActionsProto = changeActionsProto {
                avatarUrlPaths += self.collectAvatarUrlPaths(changeActionsProto: changeActionsProto)
            }
            // Discard empty avatar urls.
            return avatarUrlPaths.filter { !$0.isEmpty }
        }
    }

    private class func collectAvatarUrlPaths(groupChangesProto: GroupsProtoGroupChanges, ignoreSignature: Bool,
                                             groupV2Params: GroupV2Params) throws -> [String] {
        var avatarUrlPaths = [String]()
        for changeStateData in groupChangesProto.groupChanges {
            let changeStateProto = try GroupsProtoGroupChangesGroupChangeState(serializedData: changeStateData)
            if let groupState = changeStateProto.groupState {
                avatarUrlPaths += collectAvatarUrlPaths(groupProto: groupState)
            }

            if let changeProto = changeStateProto.groupChange {
                // We can ignoreSignature because these protos came from the service.
                let changeActionsProto = try parseAndVerifyChangeActionsProto(changeProto, ignoreSignature: ignoreSignature)
                avatarUrlPaths += self.collectAvatarUrlPaths(changeActionsProto: changeActionsProto)
            }
        }
        return avatarUrlPaths
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
