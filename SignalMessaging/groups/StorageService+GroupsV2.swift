//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import ZKGroup

public extension StorageService {

    typealias ProfileKeyCredentialMap = [UUID: ProfileKeyCredential]

    static func buildNewGroupRequest(groupProto: GroupsProtoGroup,
                                     groupParams: GroupParams,
                                     sessionManager: AFHTTPSessionManager,
                                     authCredentialMap: [UInt32: AuthCredential],
                                     redemptionTime: UInt32) throws -> NSURLRequest {

        let protoData = try groupProto.serializedData()
        return try buildGroupV2Request(protoData: protoData,
                                            urlPath: "/v1/groups/",
                                            httpMethod: "PUT",
                                            groupParams: groupParams,
                                            sessionManager: sessionManager,
                                            authCredentialMap: authCredentialMap,
                                            redemptionTime: redemptionTime)
    }

    static func buildUpdateGroupRequest(groupChangeProto: GroupsProtoGroupChangeActions,
                                        groupParams: GroupParams,
                                        sessionManager: AFHTTPSessionManager,
                                        authCredentialMap: [UInt32: AuthCredential],
                                        redemptionTime: UInt32) throws -> NSURLRequest {

        let protoData = try groupChangeProto.serializedData()
        return try buildGroupV2Request(protoData: protoData,
                                            urlPath: "/v1/groups/",
                                            httpMethod: "PATCH",
                                            groupParams: groupParams,
                                            sessionManager: sessionManager,
                                            authCredentialMap: authCredentialMap,
                                            redemptionTime: redemptionTime)
    }

    static func buildFetchGroupStateRequest(groupParams: GroupParams,
                                            sessionManager: AFHTTPSessionManager,
                                            authCredentialMap: [UInt32: AuthCredential],
                                            redemptionTime: UInt32) throws -> NSURLRequest {

        return try buildGroupV2Request(protoData: nil,
                                            urlPath: "/v1/groups/",
                                            httpMethod: "GET",
                                            groupParams: groupParams,
                                            sessionManager: sessionManager,
                                            authCredentialMap: authCredentialMap,
                                            redemptionTime: redemptionTime)
    }

    private static func buildGroupV2Request(protoData: Data?,
                                                 urlPath: String,
                                                 httpMethod: String,
                                                 groupParams: GroupParams,
                                                 sessionManager: AFHTTPSessionManager,
                                                 authCredentialMap: [UInt32: AuthCredential],
                                                 redemptionTime: UInt32) throws -> NSURLRequest {

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
                                        groupParams: groupParams,
                                        authCredentialMap: authCredentialMap,
                                        redemptionTime: redemptionTime)

        return request
    }

    // MARK: - Authorization Headers

    private static func addAuthorizationHeader(to request: NSMutableURLRequest,
                                               groupParams: GroupParams,
                                               authCredentialMap: [UInt32: AuthCredential],
                                               redemptionTime: UInt32) throws {

        guard let authCredential = authCredentialMap[redemptionTime] else {
            throw OWSAssertionError("No auth credential for redemption time.")
        }

        let serverPublicParams = try GroupsV2Utils.serverPublicParams()
        let clientZkAuthOperations = ClientZkAuthOperations(serverPublicParams: serverPublicParams)
        let authCredentialPresentation = try clientZkAuthOperations.createAuthCredentialPresentation(groupSecretParams: groupParams.groupSecretParams, authCredential: authCredential)
        let authCredentialPresentationData = authCredentialPresentation.serialize().asData

        let username: String = groupParams.groupPublicParamsData.hexadecimalString
        let password: String = authCredentialPresentationData.hexadecimalString
        let auth = Auth(username: username, password: password)
        request.setValue(try auth.authHeader(), forHTTPHeaderField: "Authorization")
    }
}
