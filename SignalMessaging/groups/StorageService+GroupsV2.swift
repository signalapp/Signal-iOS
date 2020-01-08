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

        let groupProtoData = try groupProto.serializedData()

        let urlPath = "/v1/groups/"
        guard let url = URL(string: urlPath, relativeTo: sessionManager.baseURL) else {
            throw OWSAssertionError("Invalid URL.")
        }
        let request = NSMutableURLRequest(url: url)
        let method = "PUT"
        request.httpMethod = method
        request.httpBody = groupProtoData

        request.setValue(OWSMimeTypeProtobuf, forHTTPHeaderField: "Content-Type")

        try self.addAuthorizationHeader(to: request,
                                        groupParams: groupParams,
                                        authCredentialMap: authCredentialMap,
                                        redemptionTime: redemptionTime)

        return request
    }

    static func buildUpdateGroupRequest(groupChangeProto: GroupsProtoGroupChangeActions,
                                        groupParams: GroupParams,
                                        sessionManager: AFHTTPSessionManager,
                                        authCredentialMap: [UInt32: AuthCredential],
                                        redemptionTime: UInt32) throws -> NSURLRequest {

        let groupProtoData = try groupChangeProto.serializedData()

        let urlPath = "/v1/groups/"
        guard let url = URL(string: urlPath, relativeTo: sessionManager.baseURL) else {
            throw OWSAssertionError("Invalid URL.")
        }
        let request = NSMutableURLRequest(url: url)
        let method = "PATCH"
        request.httpMethod = method
        request.httpBody = groupProtoData

        request.setValue(OWSMimeTypeProtobuf, forHTTPHeaderField: "Content-Type")

        try self.addAuthorizationHeader(to: request,
                                        groupParams: groupParams,
                                        authCredentialMap: authCredentialMap,
                                        redemptionTime: redemptionTime)

        return request
    }

    static func buildFetchGroupStateRequest(groupModel: TSGroupModel,
                                            groupParams: GroupParams,
                                            sessionManager: AFHTTPSessionManager,
                                            authCredentialMap: [UInt32: AuthCredential],
                                            redemptionTime: UInt32) throws -> NSURLRequest {

        let urlPath = "/v1/groups/"
        guard let url = URL(string: urlPath, relativeTo: sessionManager.baseURL) else {
            throw OWSAssertionError("Invalid URL.")
        }
        let request = NSMutableURLRequest(url: url)
        let method = "GET"
        request.httpMethod = method

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
