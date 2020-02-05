//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc
public class DeviceService: NSObject {
    private let serviceClient: SignalServiceClient = SignalServiceRestClient()

    @objc
    public static let shared = DeviceService()

    @objc(updateCapabilities)
    public func objc_updateCapabilities() -> AnyPromise {
        return AnyPromise(updateCapabilities())
    }

    public func updateCapabilities() -> Promise<Void> {
        return serviceClient.updateDeviceCapabilities()
    }
}
