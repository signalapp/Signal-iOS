//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
open class OWSDeviceProvisioningCodeService: NSObject {

    private static let provisioningCodeKey = "verificationCode"

    @objc
    public func requestProvisioningCode(success: @escaping (String) -> Void,
                                        failure: @escaping (Error) -> Void) {
        let request = OWSRequestFactory.deviceProvisioningCodeRequest()
        firstly(on: .global()) {
            Self.networkManager.makePromise(request: request)
        }.map(on: .global()) { response in
            Logger.verbose("ProvisioningCode request succeeded")
            guard let json = response.responseBodyJson as? [String: String] else {
                throw OWSAssertionError("Missing or invalid JSON.")
            }
            guard let provisioningCode = json[Self.provisioningCodeKey]?.nilIfEmpty else {
                throw OWSAssertionError("Missing or invalid provisioningCode.")
            }
            return provisioningCode
        }.done(on: .main) { provisioningCode in
            success(provisioningCode)
        }.catch(on: .main) { error in
            owsFailDebugUnlessNetworkFailure(error)
            failure(error)
        }
    }
}
