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

    public class func buildNewGroupProto(groupModel: TSGroupModel,
                                         groupV2Params: GroupV2Params,
                                         profileKeyCredentialMap: ProfileKeyCredentialMap,
                                         localUuid: UUID) throws -> GroupsProtoGroup {
        // Collect credential for self.
        guard let localProfileKeyCredential = profileKeyCredentialMap[localUuid] else {
            throw OWSAssertionError("Missing localProfileKeyCredential.")
        }
        // Collect credentials for all members except self.

        let groupBuilder = GroupsProtoGroup.builder()
        // GroupsV2 TODO: Constant-ize, revisit.
        groupBuilder.setVersion(0)
        groupBuilder.setPublicKey(groupV2Params.groupPublicParamsData)
        groupBuilder.setTitle(try groupV2Params.encryptString(groupModel.groupName ?? ""))
        // GroupsV2 TODO: Avatar

        groupBuilder.setAccessControl(try buildAccessProto(groupAccess: groupModel.groupAccess))

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

    public class func buildGroupContextV2Proto(groupModel: TSGroupModel,
                                               changeActionsProtoData: Data?) throws -> SSKProtoGroupContextV2 {

        guard let groupSecretParamsData = groupModel.groupSecretParamsData else {
            throw OWSAssertionError("Missing groupSecretParamsData.")
        }
        let groupSecretParams = try GroupSecretParams(contents: [UInt8](groupSecretParamsData))

        let builder = SSKProtoGroupContextV2.builder()
        builder.setMasterKey(try groupSecretParams.getMasterKey().serialize().asData)
        builder.setRevision(groupModel.groupV2Revision)

        if let changeActionsProtoData = changeActionsProtoData {
            assert(changeActionsProtoData.count > 0)
            builder.setGroupChange(changeActionsProtoData)
        }

        return try builder.build()
    }

    // MARK: -

    // This method throws if verification fails.
    public class func parseAndVerifyChangeActionsProto(_ changeProtoData: Data) throws -> GroupsProtoGroupChangeActions {
        let changeProto = try GroupsProtoGroupChange.parseData(changeProtoData)
        return try parseAndVerifyChangeActionsProto(changeProto)
    }

    // This method throws if verification fails.
    public class func parseAndVerifyChangeActionsProto(_ changeProto: GroupsProtoGroupChange) throws -> GroupsProtoGroupChangeActions {
        guard let serverSignatureData = changeProto.serverSignature else {
            throw OWSAssertionError("Missing serverSignature.")
        }
        let serverSignature = try NotarySignature(contents: [UInt8](serverSignatureData))
        guard let changeActionsProtoData = changeProto.actions else {
            throw OWSAssertionError("Missing changeActionsProtoData.")
        }
        let serverPublicParams = try self.serverPublicParams()
        try serverPublicParams.verifySignature(message: [UInt8](changeActionsProtoData),
                                               notarySignature: serverSignature)
        let changeActionsProto = try GroupsProtoGroupChangeActions.parseData(changeActionsProtoData)
        return changeActionsProto
    }

    // MARK: -

    // GroupsV2 TODO: How can we make this parsing less brittle?
    public class func parse(groupProto: GroupsProtoGroup,
                            groupV2Params: GroupV2Params) throws -> GroupV2Snapshot {

        // This client can learn of profile keys from parsing group state protos.
        // After parsing, we should fill in profileKeys in the profile manager.
        var profileKeys = [UUID: Data]()

        // GroupsV2 TODO: Is GroupsProtoAccessControl required?
        guard let accessControl = groupProto.accessControl else {
            throw OWSAssertionError("Missing accessControl.")
        }
        guard let accessControlForAttributes = accessControl.attributes else {
            throw OWSAssertionError("Missing accessControl.members.")
        }
        guard let accessControlForMembers = accessControl.members else {
            throw OWSAssertionError("Missing accessControl.members.")
        }

        var members = [GroupV2SnapshotImpl.Member]()
        for memberProto in groupProto.members {
            guard let userID = memberProto.userID else {
                throw OWSAssertionError("Group member missing userID.")
            }
            guard memberProto.hasRole, let role = memberProto.role else {
                throw OWSAssertionError("Group member missing role.")
            }
            guard let profileKeyCiphertextData = memberProto.profileKey else {
                throw OWSAssertionError("Group member missing profileKeyCiphertextData.")
            }
            let profileKeyCiphertext = try ProfileKeyCiphertext(contents: [UInt8](profileKeyCiphertextData))
            let profileKey = try groupV2Params.profileKey(forProfileKeyCiphertext: profileKeyCiphertext)
            // NOTE: presentation is set when creating and updating groups, not
            //       when fetching group state.
            guard memberProto.hasJoinedAtVersion else {
                throw OWSAssertionError("Group member missing joinedAtVersion.")
            }
            let joinedAtVersion = memberProto.joinedAtVersion

            let uuid = try groupV2Params.uuid(forUserId: userID)
            let member = GroupV2SnapshotImpl.Member(userID: userID,
                                                    uuid: uuid,
                                                    role: role,
                                                    profileKey: profileKey,
                                                    joinedAtVersion: joinedAtVersion)
            members.append(member)

            profileKeys[uuid] = profileKey
        }

        var pendingMembers = [GroupV2SnapshotImpl.PendingMember]()
        for pendingMemberProto in groupProto.pendingMembers {
            guard let memberProto = pendingMemberProto.member else {
                throw OWSAssertionError("Group pending member missing memberProto.")
            }
            guard let userID = memberProto.userID else {
                throw OWSAssertionError("Group pending member missing userID.")
            }
            guard pendingMemberProto.hasTimestamp else {
                throw OWSAssertionError("Group pending member missing timestamp.")
            }
            let timestamp = pendingMemberProto.timestamp
            let uuid = try groupV2Params.uuid(forUserId: userID)
            guard memberProto.hasRole, let role = memberProto.role else {
                throw OWSAssertionError("Group member missing role.")
            }
            guard let addedByUserID = pendingMemberProto.addedByUserID else {
                throw OWSAssertionError("Group pending member missing addedByUserID.")
            }
            let addedByUuid = try groupV2Params.uuid(forUserId: addedByUserID)
            let pendingMember = GroupV2SnapshotImpl.PendingMember(userID: userID,
                                                                  uuid: uuid,
                                                                  timestamp: timestamp,
                                                                  role: role,
                                                                  addedByUuid: addedByUuid)
            pendingMembers.append(pendingMember)
        }

        var title = ""
        if let titleData = groupProto.title {
            do {
                title = try groupV2Params.decryptString(titleData)
            } catch {
                owsFailDebug("Could not decrypt title: \(error).")
            }
        }

        // GroupsV2 TODO: Avatar
        //        public var avatar: String? {

        var disappearingMessageToken = DisappearingMessageToken.disabledToken
        if let disappearingMessagesTimerEncrypted = groupProto.disappearingMessagesTimer {
            // If the timer blob is not populated or has zero duration,
            // disappearing messages should be disabled.
            do {
                let disappearingMessagesTimerDecrypted = try groupV2Params.decryptBlob(disappearingMessagesTimerEncrypted)
                let disappearingMessagesProto = try GroupsProtoDisappearingMessagesTimer.parseData(disappearingMessagesTimerDecrypted)
                let durationSeconds = disappearingMessagesProto.duration
                if durationSeconds != 0 {
                    disappearingMessageToken = DisappearingMessageToken(isEnabled: true, durationSeconds: durationSeconds)
                }
            } catch {
                owsFailDebug("Could not decrypt and parse disappearing messages state: \(error).")
            }
        }

        let revision = groupProto.version
        let groupSecretParamsData = groupV2Params.groupSecretParamsData
        return GroupV2SnapshotImpl(groupSecretParamsData: groupSecretParamsData,
                                   groupProto: groupProto,
                                   revision: revision,
                                   title: title,
                                   members: members,
                                   pendingMembers: pendingMembers,
                                   accessControlForAttributes: accessControlForAttributes,
                                   accessControlForMembers: accessControlForMembers,
                                   disappearingMessageToken: disappearingMessageToken,
                                   profileKeys: profileKeys)
    }

    // MARK: -

    // We do not treat an empty response with no changes as an error.
    public class func parse(groupChangesProto: GroupsProtoGroupChanges,
                            groupV2Params: GroupV2Params) throws -> [GroupV2Change] {
        var result = [GroupV2Change]()
        for changeStateProto in groupChangesProto.groupChanges {
            guard let snapshotProto = changeStateProto.groupState else {
                throw OWSAssertionError("Missing groupState proto.")
            }
            let snapshot = try parse(groupProto: snapshotProto,
                                     groupV2Params: groupV2Params)
            guard let changeProto = changeStateProto.groupChange else {
                throw OWSAssertionError("Missing groupChange proto.")
            }
            let changeActionsProto: GroupsProtoGroupChangeActions = try parseAndVerifyChangeActionsProto(changeProto)
            result.append(GroupV2Change(snapshot: snapshot, changeActionsProto: changeActionsProto))
        }
        return result
    }
}
