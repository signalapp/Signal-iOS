//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

public struct ContactDiscoveryService {

    public struct IntersectionQuery: Codable {
        public let addressCount: UInt
        public let commitment: Data
        public let data: Data
        public let iv: Data
        public let mac: Data

        public struct EnclaveEnvelope: Codable {
            public let requestId: Data
            public let data: Data
            public let iv: Data
            public let mac: Data
        }
        public let envelopes: [RemoteAttestation.CDSAttestation.Id: EnclaveEnvelope]
    }

    public struct IntersectionResponse {
        let requestId: Data
        let data: Data
        let iv: Data
        let mac: Data
    }

    private var networkManager: TSNetworkManager {
        return SSKEnvironment.shared.networkManager
    }

    // MARK: -

    public func getRegisteredSignalUsers(query: ContactDiscoveryService.IntersectionQuery,
                                         cookies: [HTTPCookie],
                                         authUsername: String,
                                         authPassword: String,
                                         enclaveName: String,
                                         host: String,
                                         censorshipCircumventionPrefix: String) -> Promise<IntersectionResponse> {

        firstly(on: .sharedUtility) { () -> Promise<TSNetworkManager.Response> in
            self.networkManager.makePromise(request: self.buildIntersectionRequest(
                query: query,
                cookies: cookies,
                authUsername: authUsername,
                authPassword: authPassword,
                enclaveName: enclaveName,
                host: host,
                censorshipCircumventionPrefix: censorshipCircumventionPrefix)
            )

        }.map(on: .sharedUtility) { (_: URLSessionDataTask, responseObject: Any?) throws -> IntersectionResponse in
            guard let params = ParamParser(responseObject: responseObject) else {
                throw ContactDiscoveryError.assertionError(description: "missing response dict")
            }
            return IntersectionResponse(
                requestId: try params.requiredBase64EncodedData(key: "requestId"),
                data: try params.requiredBase64EncodedData(key: "data"),
                iv: try params.requiredBase64EncodedData(key: "iv", byteCount: 12),
                mac: try params.requiredBase64EncodedData(key: "mac", byteCount: 16))
        }
    }

    // MARK: -

    private func buildIntersectionRequest(query: IntersectionQuery,
                                          cookies: [HTTPCookie],
                                          authUsername: String,
                                          authPassword: String,
                                          enclaveName: String,
                                          host: String,
                                          censorshipCircumventionPrefix: String) -> TSRequest {
        let path = "v1/discovery/\(enclaveName)"
        let parameters: [String: Any] = [
            "addressCount": query.addressCount,
            "commitment": query.commitment.base64EncodedString(),
            "data": query.data.base64EncodedString(),
            "iv": query.iv.base64EncodedString(),
            "mac": query.mac.base64EncodedString(),
            "envelopes": query.envelopes.mapValues {
                [
                    "requestId": $0.requestId.base64EncodedString(),
                    "data": $0.data.base64EncodedString(),
                    "iv": $0.iv.base64EncodedString(),
                    "mac": $0.mac.base64EncodedString()
                ]
            }
        ]
        let request = TSRequest(url: URL(string: path)!, method: "PUT", parameters: parameters)

        request.authUsername = authUsername
        request.authPassword = authPassword
        request.customHost = host
        request.customCensorshipCircumventionPrefix = censorshipCircumventionPrefix

        // Don't bother with the default cookie store;
        // these cookies are ephemeral.
        //
        // NOTE: TSNetworkManager now separately disables default cookie handling for all requests.
        request.httpShouldHandleCookies = false

        // Set the cookie header.
        assert(request.allHTTPHeaderFields?.count == 0)
        request.allHTTPHeaderFields = HTTPCookie.requestHeaderFields(with: cookies)

        return request
    }
}
