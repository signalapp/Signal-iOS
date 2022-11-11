//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
open class OWSDeviceProvisioningService: NSObject {

    @objc
    public func provision(messageBody: Data,
                          ephemeralDeviceId: String,
                          success: @escaping () -> Void,
                          failure: @escaping (Error) -> Void) {
        let request = OWSRequestFactory.deviceProvisioningRequest(withMessageBody: messageBody,
                                                                  ephemeralDeviceId: ephemeralDeviceId)
        firstly {
            Self.networkManager.makePromise(request: request)
        }.done(on: .main) { _ in
            Logger.verbose("Provisioning request succeeded")
            success()
        }.catch(on: .main) { error in
            owsFailDebugUnlessNetworkFailure(error)
            failure(error)
        }
    }
}
