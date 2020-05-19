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
                                       urlPath: "/v1/groups/",
                                       httpMethod: "PUT",
                                       groupV2Params: groupV2Params,
                                       sessionManager: sessionManager,
                                       authCredential: authCredential)
    }

    static func buildUpdateGroupRequest(groupChangeProto: GroupsProtoGroupChangeActions,
                                        groupV2Params: GroupV2Params,
                                        sessionManager: AFHTTPSessionManager,
                                        authCredential: AuthCredential) throws -> NSURLRequest {

        let protoData = try groupChangeProto.serializedData()
        return try buildGroupV2Request(protoData: protoData,
                                       urlPath: "/v1/groups/",
                                       httpMethod: "PATCH",
                                       groupV2Params: groupV2Params,
                                       sessionManager: sessionManager,
                                       authCredential: authCredential)
    }

    static func buildFetchCurrentGroupV2SnapshotRequest(groupV2Params: GroupV2Params,
                                                        sessionManager: AFHTTPSessionManager,
                                                        authCredential: AuthCredential) throws -> NSURLRequest {

        return try buildGroupV2Request(protoData: nil,
                                       urlPath: "/v1/groups/",
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
                                       urlPath: urlPath,
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
                                       urlPath: urlPath,
                                       httpMethod: "GET",
                                       groupV2Params: groupV2Params,
                                       sessionManager: sessionManager,
                                       authCredential: authCredential)
    }

    private static func buildGroupV2Request(protoData: Data?,
                                            urlPath: String,
                                            httpMethod: String,
                                            groupV2Params: GroupV2Params,
                                            sessionManager: AFHTTPSessionManager,
                                            authCredential: AuthCredential) throws -> NSURLRequest {

        guard let url = URL(string: urlPath, relativeTo: sessionManager.baseURL) else {
            throw OWSAssertionError("Invalid URL.")
        }
        let request = NSMutableURLRequest(url: url)
        request.httpMethod = httpMethod

        if let protoData = protoData {
            request.httpBody = protoData
            request.setValue(OWSMimeTypeProtobuf, forHTTPHeaderField: "Content-Type")
        }

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
