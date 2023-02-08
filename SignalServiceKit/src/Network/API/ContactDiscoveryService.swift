//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct ContactDiscoveryService: Dependencies {

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

    // MARK: -

    public func getRegisteredSignalUsers(query: ContactDiscoveryService.IntersectionQuery,
                                         cookies: [HTTPCookie],
                                         authUsername: String,
                                         authPassword: String,
                                         enclaveName: String,
                                         host: String,
                                         censorshipCircumventionPrefix: String) -> Promise<IntersectionResponse> {
        owsAssertDebug(authUsername.strippedOrNil != nil)
        owsAssertDebug(authPassword.strippedOrNil != nil)
        owsAssertDebug(enclaveName.strippedOrNil != nil)
        owsAssertDebug(host.strippedOrNil != nil)

        return firstly(on: DispatchQueue.sharedUtility) { () -> Promise<HTTPResponse> in
            let urlSession = Self.signalService.urlSessionForCds(host: host,
                                                                 censorshipCircumventionPrefix: censorshipCircumventionPrefix)
            let request = self.buildIntersectionRequest(
                query: query,
                cookies: cookies,
                authUsername: authUsername,
                authPassword: authPassword,
                enclaveName: enclaveName
            )
            guard let requestUrl = request.url else {
                owsFailDebug("Missing requestUrl.")
                throw OWSHTTPError.missingRequest
            }
            return firstly {
                urlSession.promiseForTSRequest(request)
            }.recover(on: DispatchQueue.global()) { error -> Promise<HTTPResponse> in
                // OWSUrlSession should only throw OWSHTTPError or OWSAssertionError.
                if let httpError = error as? OWSHTTPError {
                    throw httpError
                } else {
                    owsFailDebug("Unexpected error: \(error)")
                    throw OWSHTTPError.invalidRequest(requestUrl: requestUrl)
                }
            }
        }.map(on: DispatchQueue.sharedUtility) { (response: HTTPResponse) throws -> IntersectionResponse in
            guard let json = response.responseBodyJson else {
                throw OWSAssertionError("Invalid JSON")
            }
            guard let params = ParamParser(responseObject: json) else {
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
                                          enclaveName: String) -> TSRequest {
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

        // Set the cookie header.
        // OWSURLSession disables default cookie handling for all requests.
        assert(request.allHTTPHeaderFields?.count == 0)
        request.allHTTPHeaderFields = HTTPCookie.requestHeaderFields(with: cookies)

        return request
    }
}
