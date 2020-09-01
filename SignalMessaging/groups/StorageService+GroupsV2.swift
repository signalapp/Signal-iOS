//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import ZKGroup

public extension StorageService {

    typealias ProfileKeyCredentialMap = [UUID: ProfileKeyCredential]

    static func buildNewGroupRequest(groupProto: GroupsProtoGroup,
                                     groupV2Params: GroupV2Params,
                                     sessionManager: AFHTTPSessionManager,
                                     authCredential: AuthCredential) throws -> NSURLRequest {

        let protoData = try groupProto.serializedData()
        return try buildGroupV2Request(protoData: protoData,
                                       urlString: "/v1/groups/",
                                       httpMethod: "PUT",
                                       groupV2Params: groupV2Params,
                                       sessionManager: sessionManager,
                                       authCredential: authCredential)
    }

    static func buildUpdateGroupRequest(groupChangeProto: GroupsProtoGroupChangeActions,
                                        groupV2Params: GroupV2Params,
                                        sessionManager: AFHTTPSessionManager,
                                        authCredential: AuthCredential,
                                        groupInviteLinkPassword: Data?) throws -> NSURLRequest {

        var urlString = "/v1/groups/"
        if let groupInviteLinkPassword = groupInviteLinkPassword {
            urlString += "?inviteLinkPassword=\(groupInviteLinkPassword.asBase64Url)"
        }

        let protoData = try groupChangeProto.serializedData()
        return try buildGroupV2Request(protoData: protoData,
                                       urlString: urlString,
                                       httpMethod: "PATCH",
                                       groupV2Params: groupV2Params,
                                       sessionManager: sessionManager,
                                       authCredential: authCredential)
    }

    static func buildFetchCurrentGroupV2SnapshotRequest(groupV2Params: GroupV2Params,
                                                        sessionManager: AFHTTPSessionManager,
                                                        authCredential: AuthCredential) throws -> NSURLRequest {

        return try buildGroupV2Request(protoData: nil,
                                       urlString: "/v1/groups/",
                                       httpMethod: "GET",
                                       groupV2Params: groupV2Params,
                                       sessionManager: sessionManager,
                                       authCredential: authCredential)
    }

    static func buildFetchGroupChangeActionsRequest(groupV2Params: GroupV2Params,
                                                    fromRevision: UInt32,
                                                    requireSnapshotForFirstChange: Bool,
                                                    sessionManager: AFHTTPSessionManager,
                                                    authCredential: AuthCredential) throws -> NSURLRequest {

        // GroupsV2 TODO: Apply GroupManager.changeProtoEpoch.
        // GroupsV2 TODO: Apply requireSnapshotForFirstChange.
        let urlPath = "/v1/groups/logs/\(OWSFormat.formatUInt32(fromRevision))"
        return try buildGroupV2Request(protoData: nil,
                                       urlString: urlPath,
                                       httpMethod: "GET",
                                       groupV2Params: groupV2Params,
                                       sessionManager: sessionManager,
                                       authCredential: authCredential)
    }

    static func buildGroupAvatarUploadFormRequest(groupV2Params: GroupV2Params,
                                                  sessionManager: AFHTTPSessionManager,
                                                  authCredential: AuthCredential) throws -> NSURLRequest {

        let urlPath = "/v1/groups/avatar/form"
        return try buildGroupV2Request(protoData: nil,
                                       urlString: urlPath,
                                       httpMethod: "GET",
                                       groupV2Params: groupV2Params,
                                       sessionManager: sessionManager,
                                       authCredential: authCredential)
    }

    static func buildFetchGroupInviteLinkPreviewRequest(inviteLinkPassword: Data,
                                                        groupV2Params: GroupV2Params,
                                                        sessionManager: AFHTTPSessionManager,
                                                        authCredential: AuthCredential) throws -> NSURLRequest {

        let urlPath = "/v1/groups/join/\(inviteLinkPassword.asBase64Url)"
        return try buildGroupV2Request(protoData: nil,
                                       urlString: urlPath,
                                       httpMethod: "GET",
                                       groupV2Params: groupV2Params,
                                       sessionManager: sessionManager,
                                       authCredential: authCredential)
    }

    private static func buildGroupV2Request(protoData: Data?,
                                            urlString: String,
                                            httpMethod: String,
                                            groupV2Params: GroupV2Params,
                                            sessionManager: AFHTTPSessionManager,
                                            authCredential: AuthCredential) throws -> NSURLRequest {

        guard let url = OWSURLSession.buildUrl(urlString: urlString, baseUrl: sessionManager.baseURL) else {
            throw OWSAssertionError("Invalid URL.")
        }

        var error: NSError?
        let request = sessionManager.requestSerializer.request(
            withMethod: httpMethod,
            urlString: url.absoluteString,
            parameters: nil,
            error: &error
        )
        if let error = error {
            owsFailDebug("Error: \(error)")
            throw error
        }

        if let protoData = protoData {
            request.httpBody = protoData
        }

        // The censorship circumvention reflectors require a Content-Type
        // even if the body is empty.
        request.setValue(OWSMimeTypeProtobuf, forHTTPHeaderField: "Content-Type")

        try self.addAuthorizationHeader(to: request,
                                        groupV2Params: groupV2Params,
                                        authCredential: authCredential)

        return request
    }

    // MARK: - Authorization Headers

    private static func addAuthorizationHeader(to request: NSMutableURLRequest,
                                               groupV2Params: GroupV2Params,
                                               authCredential: AuthCredential) throws {

        let serverPublicParams = try GroupsV2Protos.serverPublicParams()
        let clientZkAuthOperations = ClientZkAuthOperations(serverPublicParams: serverPublicParams)
        let authCredentialPresentation = try clientZkAuthOperations.createAuthCredentialPresentation(groupSecretParams: groupV2Params.groupSecretParams, authCredential: authCredential)
        let authCredentialPresentationData = authCredentialPresentation.serialize().asData

        let username: String = groupV2Params.groupPublicParamsData.hexadecimalString
        let password: String = authCredentialPresentationData.hexadecimalString
        let auth = Auth(username: username, password: password)
        request.setValue(try auth.authHeader(), forHTTPHeaderField: "Authorization")
    }
}
