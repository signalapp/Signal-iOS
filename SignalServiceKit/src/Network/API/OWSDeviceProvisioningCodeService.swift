//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc
open class OWSDeviceProvisioningCodeService: NSObject {

    private static let provisioningCodeKey = "verificationCode"

    @objc
    public func requestProvisioningCode(success: @escaping (String) -> Void,
                                        failure: @escaping (Error) -> Void) {
        let request = OWSRequestFactory.deviceProvisioningCodeRequest()
        firstly(on: .global()) {
            Self.networkManager.makePromise(request: request)
        }.done(on: .global()) { response in
            Logger.verbose("ProvisioningCode request succeeded")
            guard let json = response.responseBodyJson as? [String: String] else {
                failure(OWSAssertionError("Missing or invalid JSON."))
                return
            }
            guard let provisioningCode = json[Self.provisioningCodeKey]?.nilIfEmpty else {
                failure(OWSAssertionError("Missing or invalid provisioningCode."))
                return
            }
            success(provisioningCode)
        }.catch(on: .global()) { error in
            owsFailDebugUnlessNetworkFailure(error)
            failure(error)
        }
    }
}
