//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import SignalServiceKit
import SignalMetadataKit
import ZKGroup

public class GroupsV2Utils {
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

    // GroupsV2 TODO: Can we build protos for the "create group" and "update group" scenarios here?
    // There might be real differences.
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

    // GroupsV2 TODO: Can we build protos for the "create group" and "update group" scenarios here?
    // There might be real differences.
    public class func buildPendingMemberProto(profileKeyCredential: ProfileKeyCredential,
                                              role: GroupsProtoMemberRole,
                                              localUuid: UUID,
                                              groupParams: GroupParams) throws -> GroupsProtoPendingMember {
        let builder = GroupsProtoPendingMember.builder()

        builder.setMember(try buildMemberProto(profileKeyCredential: profileKeyCredential,
                                               role: role,
                                               groupParams: groupParams))

        // GroupsV2 TODO: What's the correct value here?
        let timestamp: UInt64 = NSDate.ows_millisecondTimeStamp()
        builder.setTimestamp(timestamp)

        let localUserID = try groupParams.userId(forUuid: localUuid)
        builder.setAddedByUserID(localUserID)

        return try builder.build()
    }
}

// MARK: -

public extension UUID {
    func asZKGUuid() throws -> ZKGUuid {
        return try withUnsafeBytes(of: self.uuid) { (buffer: UnsafeRawBufferPointer) in
            try ZKGUuid(contents: [UInt8](buffer))
        }
    }
}

// MARK: -

public extension ZKGUuid {
    func asUUID() -> UUID {
        return serialize().asData.withUnsafeBytes {
            UUID(uuid: $0.bindMemory(to: uuid_t.self).first!)
        }
    }
}

// MARK: -

public extension ProfileKeyVersion {
    // GroupsV2 TODO: We might move this to the wrappers.
    func asHexadecimalString() throws -> String {
        let profileKeyVersionData = serialize().asData
        // A peculiarity of ProfileKeyVersion is that its contents
        // are an ASCII-encoded hexadecimal string of the profile key
        // version, rather than the raw version bytes.
        guard let profileKeyVersionString = String(data: profileKeyVersionData, encoding: .ascii) else {
            throw OWSAssertionError("Invalid profile key version.")
        }
        return profileKeyVersionString
    }
}
