//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
open class OWSDeviceProvisioningCodeService: NSObject {

    private static var provisioningCodeKey: String { "verificationCode" }

    @objc
    public func requestProvisioningCode(success: @escaping (String) -> Void,
                                        failure: @escaping (Error) -> Void) {
        let request = OWSRequestFactory.deviceProvisioningCodeRequest()
        firstly(on: DispatchQueue.global()) {
            Self.networkManager.makePromise(request: request)
        }.map(on: DispatchQueue.global()) { response in
            Logger.verbose("ProvisioningCode request succeeded")
            guard let json = response.responseBodyJson as? [String: String] else {
                throw OWSAssertionError("Missing or invalid JSON.")
            }
            guard let provisioningCode = json[Self.provisioningCodeKey]?.nilIfEmpty else {
                throw OWSAssertionError("Missing or invalid provisioningCode.")
            }
            return provisioningCode
        }.done(on: DispatchQueue.main) { provisioningCode in
            success(provisioningCode)
        }.catch(on: DispatchQueue.main) { error in
            owsFailDebugUnlessNetworkFailure(error)
            failure(error)
        }
    }
}
