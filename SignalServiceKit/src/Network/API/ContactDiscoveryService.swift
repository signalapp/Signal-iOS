//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

public struct ContactDiscoveryService {
    enum ServiceError: Error {
        case error5xx(httpCode: Int)
        case tooManyRequests(httpCode: Int)
        case error4xx(httpCode: Int)
        case invalidResponse(_ description: String)
    }

    public struct IntersectionResponse {
        let data: Data
        let iv: Data
        let mac: Data
    }

    private var networkManager: TSNetworkManager {
        return SSKEnvironment.shared.networkManager
    }

    public func getRegisteredSignalUsers(remoteAttestation: RemoteAttestation,
                                  addressCount: UInt,
                                  encryptedAddressData: Data,
                                  cryptIv: Data,
                                  cryptMac: Data) -> Promise<IntersectionResponse> {

        let request = OWSRequestFactory.cdsEnclaveRequest(withRequestId: remoteAttestation.requestId,
                                                          addressCount: addressCount,
                                                          encryptedAddressData: encryptedAddressData,
                                                          cryptIv: cryptIv,
                                                          cryptMac: cryptMac,
                                                          enclaveName: remoteAttestation.enclaveName,
                                                          authUsername: remoteAttestation.auth.username,
                                                          authPassword: remoteAttestation.auth.password,
                                                          cookies: remoteAttestation.cookies)

        return firstly { () -> Promise<TSNetworkManager.Response> in
            self.networkManager.makePromise(request: request)
            }.map { (_: URLSessionDataTask, responseObject: Any?) throws -> IntersectionResponse in
                guard let params = ParamParser(responseObject: responseObject) else {
                    throw ContactDiscoveryError.parseError(description: "missing response dict")
                }

                return IntersectionResponse(data: try params.requiredBase64EncodedData(key: "data"),
                                            iv: try params.requiredBase64EncodedData(key: "iv"),
                                            mac: try params.requiredBase64EncodedData(key: "mac"))
            }.recover { error -> Promise<IntersectionResponse> in
                guard !IsNetworkConnectivityFailure(error) else {
                    Logger.warn("Network error: \(error)")
                    throw error
                }

                if let statusCode = error.httpStatusCode {
                    if statusCode == 429 {
                        // TODO add Retry-After for rate limiting
                        throw ServiceError.tooManyRequests(httpCode: statusCode)
                    } else if statusCode / 100 == 4 {
                        throw ServiceError.error4xx(httpCode: statusCode)
                    } else if statusCode / 100 == 5 {
                        // TODO add Retry-After for rate limiting
                        throw ServiceError.error5xx(httpCode: statusCode)
                    }
                }

                owsFailDebug("unexpected error: \(error)")
                throw error
        }
    }
}
