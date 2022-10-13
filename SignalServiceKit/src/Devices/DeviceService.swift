//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

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
