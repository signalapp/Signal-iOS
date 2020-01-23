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
                                       groupParams: GroupParams) throws -> GroupsProtoMember {
        let builder = GroupsProtoMember.builder()
        builder.setRole(role)

        let serverPublicParams = try self.serverPublicParams()
        let profileOperations = ClientZkProfileOperations(serverPublicParams: serverPublicParams)
        let presentation = try profileOperations.createProfileKeyCredentialPresentation(groupSecretParams: groupParams.groupSecretParams,
                                                                                        profileKeyCredential: profileKeyCredential)
        builder.setPresentation(presentation.serialize().asData)

        return try builder.build()
    }

    public class func buildPendingMemberProto(uuid: UUID,
                                              role: GroupsProtoMemberRole,
                                              localUuid: UUID,
                                              groupParams: GroupParams) throws -> GroupsProtoPendingMember {
        let builder = GroupsProtoPendingMember.builder()

        let memberBuilder = GroupsProtoMember.builder()
        memberBuilder.setRole(role)
        let userId = try groupParams.userId(forUuid: uuid)
        memberBuilder.setUserID(userId)
        builder.setMember(try memberBuilder.build())

        // GroupsV2 TODO: What's the correct value here?
        let timestamp: UInt64 = NSDate.ows_millisecondTimeStamp()
        builder.setTimestamp(timestamp)

        let localUserID = try groupParams.userId(forUuid: localUuid)
        builder.setAddedByUserID(localUserID)

        return try builder.build()
    }

    public typealias ProfileKeyCredentialMap = [UUID: ProfileKeyCredential]

    public class func buildNewGroupProto(groupModel: TSGroupModel,
                                         groupParams: GroupParams,
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
        groupBuilder.setPublicKey(groupParams.groupPublicParamsData)
        groupBuilder.setTitle(try groupParams.encryptString(groupModel.groupName ?? ""))
        // GroupsV2 TODO: Avatar

        let accessControl = GroupsProtoAccessControl.builder()
        // GroupsV2 TODO: Pull these values from the group model.
        accessControl.setAttributes(.member)
        accessControl.setMembers(.member)
        groupBuilder.setAccessControl(try accessControl.build())

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
                                                     groupParams: groupParams))
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
                                                         groupParams: groupParams))
        }
        for address in groupMembership.allPendingMembers {
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
                                                                       groupParams: groupParams))
        }

        return try groupBuilder.build()
    }

    public class func buildGroupContextV2Proto(groupModel: TSGroupModel,
                                               groupChangeData: Data?) throws -> SSKProtoGroupContextV2 {

        guard let groupSecretParamsData = groupModel.groupSecretParamsData else {
            throw OWSAssertionError("Missing groupSecretParamsData.")
        }
        let groupSecretParams = try GroupSecretParams(contents: [UInt8](groupSecretParamsData))

        let builder = SSKProtoGroupContextV2.builder()
        builder.setMasterKey(try groupSecretParams.getMasterKey().serialize().asData)
        builder.setRevision(groupModel.groupV2Revision)

        if let groupChangeData = groupChangeData {
            assert(groupChangeData.count > 0)
            builder.setGroupChange(groupChangeData)
        }

        return try builder.build()
    }

    // MARK: -

    // This method throws if verification fails.
    public class func parseAndVerifyChangeProtoActions(_ changeProtoData: Data) throws -> GroupsProtoGroupChangeActions {
        let changeProto = try GroupsProtoGroupChange.parseData(changeProtoData)

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
}
