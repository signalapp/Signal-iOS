//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public struct GroupsV2Request {
    let urlString: String
    let method: HTTPMethod
    let bodyData: Data?

    var headers = HttpHeaders()

    mutating func addHeader(_ header: String, value: String) {
        headers.addHeader(header, value: value, overwriteOnConflict: true)
    }
}

// MARK: -

public extension StorageService {

    static func buildNewGroupRequest(
        groupProto: GroupsProtoGroup,
        groupV2Params: GroupV2Params,
        authCredential: AuthCredentialWithPni,
    ) throws -> GroupsV2Request {
        let protoData = try groupProto.serializedData()
        return try buildGroupV2Request(
            protoData: protoData,
            urlString: "v2/groups",
            method: .put,
            secretParams: groupV2Params.groupSecretParams,
            authCredential: authCredential,
        )
    }

    static func buildUpdateGroupRequest(
        groupChangeProto: GroupsProtoGroupChangeActions,
        groupV2Params: GroupV2Params,
        authCredential: AuthCredentialWithPni,
        groupInviteLinkPassword: Data?,
    ) throws -> GroupsV2Request {

        var urlString = "v2/groups"
        if let groupInviteLinkPassword {
            urlString += "?inviteLinkPassword=\(groupInviteLinkPassword.asBase64Url)"
        }

        let protoData = try groupChangeProto.serializedData()
        return try buildGroupV2Request(
            protoData: protoData,
            urlString: urlString,
            method: .patch,
            secretParams: groupV2Params.groupSecretParams,
            authCredential: authCredential,
        )
    }

    static func buildFetchCurrentGroupV2SnapshotRequest(
        groupV2Params: GroupV2Params,
        authCredential: AuthCredentialWithPni,
    ) throws -> GroupsV2Request {
        return try buildGroupV2Request(
            protoData: nil,
            urlString: "v2/groups",
            method: .get,
            secretParams: groupV2Params.groupSecretParams,
            authCredential: authCredential,
        )
    }

    static func buildFetchGroupChangeActionsRequest(
        secretParams: GroupSecretParams,
        fromRevision: UInt32,
        limit: UInt32?,
        includeFirstState: Bool,
        gseExpiration: UInt64,
        authCredential: AuthCredentialWithPni,
    ) throws -> GroupsV2Request {
        var queryItems = [URLQueryItem]()
        queryItems.append(URLQueryItem(name: "includeFirstState", value: "\(includeFirstState)"))
        queryItems.append(URLQueryItem(name: "maxSupportedChangeEpoch", value: "\(GroupManager.changeProtoEpoch)"))
        if let limit {
            queryItems.append(URLQueryItem(name: "limit", value: "\(limit)"))
        }

        var urlComponents = URLComponents()
        urlComponents.path = "v2/groups/logs/\(fromRevision)"
        urlComponents.queryItems = queryItems

        var request = try buildGroupV2Request(
            protoData: nil,
            urlString: urlComponents.url!.relativeString,
            method: .get,
            secretParams: secretParams,
            authCredential: authCredential,
        )

        request.addHeader("Cached-Send-Endorsements", value: "\(gseExpiration)")

        return request
    }

    static func buildGetJoinedAtRevisionRequest(
        secretParams: GroupSecretParams,
        authCredential: AuthCredentialWithPni,
    ) throws -> GroupsV2Request {
        return try buildGroupV2Request(
            protoData: nil,
            urlString: "/v2/groups/joined_at_version/",
            method: .get,
            secretParams: secretParams,
            authCredential: authCredential,
        )
    }

    static func buildGroupAvatarUploadFormRequest(
        groupV2Params: GroupV2Params,
        authCredential: AuthCredentialWithPni,
    ) throws -> GroupsV2Request {

        let urlPath = "/v2/groups/avatar/form"
        return try buildGroupV2Request(
            protoData: nil,
            urlString: urlPath,
            method: .get,
            secretParams: groupV2Params.groupSecretParams,
            authCredential: authCredential,
        )
    }

    // inviteLinkPassword is not necessary if we're already a member or have a pending request.
    static func buildFetchGroupInviteLinkPreviewRequest(
        inviteLinkPassword: Data?,
        groupV2Params: GroupV2Params,
        authCredential: AuthCredentialWithPni,
    ) throws -> GroupsV2Request {

        var urlPath = "/v2/groups/join/"
        if let inviteLinkPassword {
            urlPath += "\(inviteLinkPassword.asBase64Url)"
        }

        return try buildGroupV2Request(
            protoData: nil,
            urlString: urlPath,
            method: .get,
            secretParams: groupV2Params.groupSecretParams,
            authCredential: authCredential,
        )
    }

    static func buildFetchGroupExternalCredentials(
        groupV2Params: GroupV2Params,
        authCredential: AuthCredentialWithPni,
    ) throws -> GroupsV2Request {
        return try buildGroupV2Request(
            protoData: nil,
            urlString: "/v2/groups/token",
            method: .get,
            secretParams: groupV2Params.groupSecretParams,
            authCredential: authCredential,
        )
    }

    private static func buildGroupV2Request(
        protoData: Data?,
        urlString: String,
        method: HTTPMethod,
        secretParams: GroupSecretParams,
        authCredential: AuthCredentialWithPni,
    ) throws -> GroupsV2Request {

        var request = GroupsV2Request(urlString: urlString, method: method, bodyData: protoData)

        // The censorship circumvention reflectors require a Content-Type
        // even if the body is empty.
        request.addHeader("Content-Type", value: MimeType.applicationXProtobuf.rawValue)

        try self.addAuthorizationHeader(
            to: &request,
            groupSecretParams: secretParams,
            authCredential: authCredential,
        )

        return request
    }

    // MARK: - Authorization Headers

    private static func addAuthorizationHeader(
        to request: inout GroupsV2Request,
        groupSecretParams: GroupSecretParams,
        authCredential: AuthCredentialWithPni,
    ) throws {
        let serverPublicParams = GroupsV2Protos.serverPublicParams()
        let clientZkAuthOperations = ClientZkAuthOperations(serverPublicParams: serverPublicParams)
        let authCredentialPresentation = try clientZkAuthOperations.createAuthCredentialPresentation(groupSecretParams: groupSecretParams, authCredential: authCredential)
        let authCredentialPresentationData = authCredentialPresentation.serialize()

        let username: String = try groupSecretParams.getPublicParams().serialize().hexadecimalString
        let password: String = authCredentialPresentationData.hexadecimalString
        request.addHeader(
            HttpHeaders.authHeaderKey,
            value: HttpHeaders.authHeaderValue(username: username, password: password),
        )
    }
}
