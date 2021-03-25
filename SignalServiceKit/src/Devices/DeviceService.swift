//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc
public class DeviceService: NSObject {

    @objc
    public static let shared = DeviceService()

    @objc(updateSecondaryDeviceCapabilities)
    public func objc_updateSecondaryDeviceCapabilities() -> AnyPromise {
        return AnyPromise(updateSecondaryDeviceCapabilities())
    }

    public func updateSecondaryDeviceCapabilities() -> Promise<Void> {
        return serviceClient.updateSecondaryDeviceCapabilities()
    }
}
