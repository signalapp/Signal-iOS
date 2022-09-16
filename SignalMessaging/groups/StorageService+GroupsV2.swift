//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import LibSignalClient

public struct GroupsV2Request {
    let urlString: String
    let method: HTTPMethod
    let bodyData: Data?

    let headers = OWSHttpHeaders()

    func addHeader(_ header: String, value: String) {
        headers.addHeader(header, value: value, overwriteOnConflict: true)
    }
}

// MARK: -

public extension StorageService {

    typealias ProfileKeyCredentialMap = [UUID: ProfileKeyCredential]

    static func buildNewGroupRequest(groupProto: GroupsProtoGroup,
                                     groupV2Params: GroupV2Params,
                                     authCredential: AuthCredentialWithPni) throws -> GroupsV2Request {

        let protoData = try groupProto.serializedData()
        return try buildGroupV2Request(protoData: protoData,
                                       urlString: "/v1/groups/",
                                       method: .put,
                                       groupV2Params: groupV2Params,
                                       authCredential: authCredential)
    }

    static func buildUpdateGroupRequest(groupChangeProto: GroupsProtoGroupChangeActions,
                                        groupV2Params: GroupV2Params,
                                        authCredential: AuthCredentialWithPni,
                                        groupInviteLinkPassword: Data?) throws -> GroupsV2Request {

        var urlString = "/v1/groups/"
        if let groupInviteLinkPassword = groupInviteLinkPassword {
            urlString += "?inviteLinkPassword=\(groupInviteLinkPassword.asBase64Url)"
        }

        let protoData = try groupChangeProto.serializedData()
        return try buildGroupV2Request(protoData: protoData,
                                       urlString: urlString,
                                       method: .patch,
                                       groupV2Params: groupV2Params,
                                       authCredential: authCredential)
    }

    static func buildFetchCurrentGroupV2SnapshotRequest(
        groupV2Params: GroupV2Params,
        authCredential: AuthCredentialWithPni
    ) throws -> GroupsV2Request {
        return try buildGroupV2Request(
            protoData: nil,
            urlString: "/v1/groups/",
            method: .get,
            groupV2Params: groupV2Params,
            authCredential: authCredential
        )
    }

    static func buildFetchGroupChangeActionsRequest(
        groupV2Params: GroupV2Params,
        fromRevision: UInt32,
        requireSnapshotForFirstChange: Bool,
        authCredential: AuthCredentialWithPni
    ) throws -> GroupsV2Request {
        let urlPath = "/v1/groups/logs/\(fromRevision)?includeFirstState=\(requireSnapshotForFirstChange)&maxSupportedChangeEpoch=\(GroupManager.changeProtoEpoch)"
        return try buildGroupV2Request(
            protoData: nil,
            urlString: urlPath,
            method: .get,
            groupV2Params: groupV2Params,
            authCredential: authCredential
        )
    }

    static func buildGetJoinedAtRevisionRequest(
        groupV2Params: GroupV2Params,
        authCredential: AuthCredentialWithPni
    ) throws -> GroupsV2Request {
        return try buildGroupV2Request(
            protoData: nil,
            urlString: "/v1/groups/joined_at_version/",
            method: .get,
            groupV2Params: groupV2Params,
            authCredential: authCredential
        )
    }

    static func buildGroupAvatarUploadFormRequest(groupV2Params: GroupV2Params,
                                                  authCredential: AuthCredentialWithPni) throws -> GroupsV2Request {

        let urlPath = "/v1/groups/avatar/form"
        return try buildGroupV2Request(protoData: nil,
                                       urlString: urlPath,
                                       method: .get,
                                       groupV2Params: groupV2Params,
                                       authCredential: authCredential)
    }

    // inviteLinkPassword is not necessary if we're already a member or have a pending request.
    static func buildFetchGroupInviteLinkPreviewRequest(inviteLinkPassword: Data?,
                                                        groupV2Params: GroupV2Params,
                                                        authCredential: AuthCredentialWithPni) throws -> GroupsV2Request {

        var urlPath = "/v1/groups/join/"
        if let inviteLinkPassword = inviteLinkPassword {
            urlPath += "\(inviteLinkPassword.asBase64Url)"
        }

        return try buildGroupV2Request(protoData: nil,
                                       urlString: urlPath,
                                       method: .get,
                                       groupV2Params: groupV2Params,
                                       authCredential: authCredential)
    }

    static func buildFetchGroupExternalCredentials(groupV2Params: GroupV2Params,
                                                   authCredential: AuthCredentialWithPni) throws -> GroupsV2Request {

        return try buildGroupV2Request(protoData: nil,
                                       urlString: "/v1/groups/token",
                                       method: .get,
                                       groupV2Params: groupV2Params,
                                       authCredential: authCredential)
    }

    private static func buildGroupV2Request(protoData: Data?,
                                            urlString: String,
                                            method: HTTPMethod,
                                            groupV2Params: GroupV2Params,
                                            authCredential: AuthCredentialWithPni) throws -> GroupsV2Request {

        let request = GroupsV2Request(urlString: urlString, method: method, bodyData: protoData)

        // The censorship circumvention reflectors require a Content-Type
        // even if the body is empty.
        request.addHeader("Content-Type", value: OWSMimeTypeProtobuf)

        try self.addAuthorizationHeader(to: request,
                                        groupV2Params: groupV2Params,
                                        authCredential: authCredential)

        return request
    }

    // MARK: - Authorization Headers

    private static func addAuthorizationHeader(to request: GroupsV2Request,
                                               groupV2Params: GroupV2Params,
                                               authCredential: AuthCredentialWithPni) throws {

        let serverPublicParams = try GroupsV2Protos.serverPublicParams()
        let clientZkAuthOperations = ClientZkAuthOperations(serverPublicParams: serverPublicParams)
        let authCredentialPresentation = try clientZkAuthOperations.createAuthCredentialPresentation(groupSecretParams: groupV2Params.groupSecretParams, authCredential: authCredential)
        let authCredentialPresentationData = authCredentialPresentation.serialize().asData

        let username: String = groupV2Params.groupPublicParamsData.hexadecimalString
        let password: String = authCredentialPresentationData.hexadecimalString
        request.addHeader(OWSHttpHeaders.authHeaderKey,
                          value: try OWSHttpHeaders.authHeaderValue(username: username, password: password))
    }
}
