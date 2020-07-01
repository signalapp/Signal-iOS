//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import SignalServiceKit
import SignalMetadataKit
import ZKGroup

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

    public class func buildMemberProto(profileKeyCredential: ProfileKeyCredential,
                                       role: GroupsProtoMemberRole,
                                       groupV2Params: GroupV2Params) throws -> GroupsProtoMember {
        let builder = GroupsProtoMember.builder()
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
        let builder = GroupsProtoPendingMember.builder()

        let memberBuilder = GroupsProtoMember.builder()
        memberBuilder.setRole(role)
        let userId = try groupV2Params.userId(forUuid: uuid)
        memberBuilder.setUserID(userId)
        builder.setMember(try memberBuilder.build())

        return try builder.build()
    }

    public class func presentationData(profileKeyCredential: ProfileKeyCredential,
                                       groupV2Params: GroupV2Params) throws -> Data {

        let serverPublicParams = try self.serverPublicParams()
        let profileOperations = ClientZkProfileOperations(serverPublicParams: serverPublicParams)
        let presentation = try profileOperations.createProfileKeyCredentialPresentation(groupSecretParams: groupV2Params.groupSecretParams,
                                                                                        profileKeyCredential: profileKeyCredential)
        return presentation.serialize().asData
    }

    public typealias ProfileKeyCredentialMap = [UUID: ProfileKeyCredential]

    public class func buildNewGroupProto(groupModel: TSGroupModelV2,
                                         groupV2Params: GroupV2Params,
                                         profileKeyCredentialMap: ProfileKeyCredentialMap,
                                         localUuid: UUID) throws -> GroupsProtoGroup {

        // Collect credential for self.
        guard let localProfileKeyCredential = profileKeyCredentialMap[localUuid] else {
            throw OWSAssertionError("Missing localProfileKeyCredential.")
        }
        // Collect credentials for all members except self.

        let groupBuilder = GroupsProtoGroup.builder()
        let initialRevision: UInt32 = 0
        groupBuilder.setRevision(initialRevision)
        groupBuilder.setPublicKey(groupV2Params.groupPublicParamsData)
        // GroupsV2 TODO: Will production implementation of encryptString() pad?
        groupBuilder.setTitle(try groupV2Params.encryptGroupName(groupModel.groupName?.stripped ?? " "))

        let hasAvatarUrl = groupModel.avatarUrlPath != nil
        let hasAvatarData = groupModel.groupAvatarData != nil
        guard hasAvatarData == hasAvatarUrl else {
            throw OWSAssertionError("hasAvatarData: (\(hasAvatarData)) != hasAvatarUrl: (\(hasAvatarUrl))")
        }
        if let avatarUrl = groupModel.avatarUrlPath {
            groupBuilder.setAvatar(avatarUrl)
        }

        groupBuilder.setAccessControl(try buildAccessProto(groupAccess: groupModel.access))

        // * You will be member 0 and the only admin.
        // * Other members will be non-admin members.
        //
        // Add local user first to ensure that they are user 0.
        let groupMembership = groupModel.groupMembership
        let localAddress = SignalServiceAddress(uuid: localUuid)
        assert(groupMembership.isAdministrator(localAddress))
        assert(!groupMembership.isPending(localAddress))
        groupBuilder.addMembers(try buildMemberProto(profileKeyCredential: localProfileKeyCredential,
                                                     role: .administrator,
                                                     groupV2Params: groupV2Params))
        for (uuid, profileKeyCredential) in profileKeyCredentialMap {
            guard uuid != localUuid else {
                continue
            }
            let address = SignalServiceAddress(uuid: uuid)
            let isAdministrator = groupMembership.isAdministrator(address)
            let isPending = groupMembership.isPending(address)
            let role: GroupsProtoMemberRole = isAdministrator ? .administrator : .`default`
            guard !isPending else {
                continue
            }
            groupBuilder.addMembers(try buildMemberProto(profileKeyCredential: profileKeyCredential,
                                                         role: role,
                                                         groupV2Params: groupV2Params))
        }
        for address in groupMembership.pendingMembers {
            guard let uuid = address.uuid else {
                throw OWSAssertionError("Missing uuid.")
            }
            guard uuid != localUuid else {
                continue
            }
            let isAdministrator = groupMembership.isAdministrator(address)
            let role: GroupsProtoMemberRole = isAdministrator ? .administrator : .`default`
            groupBuilder.addPendingMembers(try buildPendingMemberProto(uuid: uuid,
                                                                       role: role,
                                                                       localUuid: localUuid,
                                                                       groupV2Params: groupV2Params))
        }

        return try groupBuilder.build()
    }

    public class func buildAccessProto(groupAccess: GroupAccess) throws -> GroupsProtoAccessControl {
        let builder = GroupsProtoAccessControl.builder()
        builder.setAttributes(GroupAccess.protoAccess(forGroupV2Access: groupAccess.attributes))
        builder.setMembers(GroupAccess.protoAccess(forGroupV2Access: groupAccess.members))
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
                owsFailDebug("Discarding oversize group change proto.")
            }
        }

        return try builder.build()
    }

    // MARK: -

    // This method throws if verification fails.
    public class func parseAndVerifyChangeActionsProto(_ changeProtoData: Data,
                                                       ignoreSignature: Bool) throws -> GroupsProtoGroupChangeActions {
        let changeProto = try GroupsProtoGroupChange.parseData(changeProtoData)
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
        let changeActionsProto = try GroupsProtoGroupChangeActions.parseData(changeActionsProtoData)
        return changeActionsProto
    }

    // MARK: -

    public class func parse(groupProto: GroupsProtoGroup,
                            downloadedAvatars: GroupV2DownloadedAvatars,
                            groupV2Params: GroupV2Params) throws -> GroupV2Snapshot {

        let title = groupV2Params.decryptGroupName(groupProto.title) ?? ""

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

        var members = [GroupV2SnapshotImpl.Member]()
        for memberProto in groupProto.members {
            guard let userID = memberProto.userID else {
                throw OWSAssertionError("Group member missing userID.")
            }
            guard memberProto.hasRole, let role = memberProto.role else {
                throw OWSAssertionError("Group member missing role.")
            }

            // Some userIds/uuidCiphertexts can be validated by
            // the service. This is one.
            let uuid = try groupV2Params.uuid(forUserId: userID)

            let member = GroupV2SnapshotImpl.Member(userID: userID,
                                                    uuid: uuid,
                                                    role: role)
            members.append(member)

            guard let profileKeyCiphertextData = memberProto.profileKey else {
                throw OWSAssertionError("Group member missing profileKeyCiphertextData.")
            }
            let profileKeyCiphertext = try ProfileKeyCiphertext(contents: [UInt8](profileKeyCiphertextData))
            let profileKey = try groupV2Params.profileKey(forProfileKeyCiphertext: profileKeyCiphertext,
                                                          uuid: uuid)
            profileKeys[uuid] = profileKey
        }

        var pendingMembers = [GroupV2SnapshotImpl.PendingMember]()
        for pendingMemberProto in groupProto.pendingMembers {
            guard let memberProto = pendingMemberProto.member else {
                throw OWSAssertionError("Group pending member missing memberProto.")
            }
            guard let userId = memberProto.userID else {
                throw OWSAssertionError("Group pending member missing userID.")
            }
            guard pendingMemberProto.hasTimestamp else {
                throw OWSAssertionError("Group pending member missing timestamp.")
            }
            guard let addedByUserId = pendingMemberProto.addedByUserID else {
                throw OWSAssertionError("Group pending member missing addedByUserID.")
            }
            let timestamp = pendingMemberProto.timestamp
            guard memberProto.hasRole, let role = memberProto.role else {
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
                owsFailDebug("Error parsing uuid: \(error)")
                continue
            }
            let pendingMember = GroupV2SnapshotImpl.PendingMember(userID: userId,
                                                                  uuid: uuid,
                                                                  timestamp: timestamp,
                                                                  role: role,
                                                                  addedByUuid: addedByUuid)
            pendingMembers.append(pendingMember)
        }

        guard let accessControl = groupProto.accessControl else {
            throw OWSAssertionError("Missing accessControl.")
        }
        guard let accessControlForAttributes = accessControl.attributes else {
            throw OWSAssertionError("Missing accessControl.members.")
        }
        guard let accessControlForMembers = accessControl.members else {
            throw OWSAssertionError("Missing accessControl.members.")
        }

        // If the timer blob is not populated or has zero duration,
        // disappearing messages should be disabled.
        let disappearingMessageToken = groupV2Params.decryptDisappearingMessagesTimer(groupProto.disappearingMessagesTimer)

        let revision = groupProto.revision
        let groupSecretParamsData = groupV2Params.groupSecretParamsData
        return GroupV2SnapshotImpl(groupSecretParamsData: groupSecretParamsData,
                                   groupProto: groupProto,
                                   revision: revision,
                                   title: title,
                                   avatarUrlPath: avatarUrlPath,
                                   avatarData: avatarData,
                                   members: members,
                                   pendingMembers: pendingMembers,
                                   accessControlForAttributes: accessControlForAttributes,
                                   accessControlForMembers: accessControlForMembers,
                                   disappearingMessageToken: disappearingMessageToken,
                                   profileKeys: profileKeys)
    }

    // MARK: -

    // We do not treat an empty response with no changes as an error.
    public class func parseChangesFromService(groupChangesProto: GroupsProtoGroupChanges,
                                              downloadedAvatars: GroupV2DownloadedAvatars,
                                              groupV2Params: GroupV2Params) throws -> [GroupV2Change] {
        var result = [GroupV2Change]()
        for changeStateProto in groupChangesProto.groupChanges {
            var snapshot: GroupV2Snapshot?
            if let snapshotProto = changeStateProto.groupState {
                snapshot = try parse(groupProto: snapshotProto,
                                     downloadedAvatars: downloadedAvatars,
                                     groupV2Params: groupV2Params)
            }
            guard let changeProto = changeStateProto.groupChange else {
                throw OWSAssertionError("Missing groupChange proto.")
            }
            // We can ignoreSignature because these protos came from the service.
            let changeActionsProto: GroupsProtoGroupChangeActions = try parseAndVerifyChangeActionsProto(changeProto, ignoreSignature: true)
            let diff = GroupV2Diff(changeActionsProto: changeActionsProto, downloadedAvatars: downloadedAvatars)
            result.append(GroupV2Change(snapshot: snapshot, diff: diff))
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
            return avatarUrlPaths.filter { $0.count > 0 }
        }
    }

    private class func collectAvatarUrlPaths(groupChangesProto: GroupsProtoGroupChanges, ignoreSignature: Bool,
                                             groupV2Params: GroupV2Params) throws -> [String] {
        var avatarUrlPaths = [String]()
        for changeStateProto in groupChangesProto.groupChanges {
            guard let groupState = changeStateProto.groupState else {
                throw OWSAssertionError("Missing groupState proto.")
            }
            avatarUrlPaths += collectAvatarUrlPaths(groupProto: groupState)

            guard let changeProto = changeStateProto.groupChange else {
                throw OWSAssertionError("Missing groupChange proto.")
            }
            // We can ignoreSignature because these protos came from the service.
            let changeActionsProto = try parseAndVerifyChangeActionsProto(changeProto, ignoreSignature: ignoreSignature)
            avatarUrlPaths += self.collectAvatarUrlPaths(changeActionsProto: changeActionsProto)
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
