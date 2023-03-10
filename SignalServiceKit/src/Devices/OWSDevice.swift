//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
public extension OWSDevice {

    // Updates the list of devices in the database.
    //
    // Returns true if any devices were added or removed (but not changed).
    class func replaceAll(_ newDevices: [OWSDevice], transaction: SDSAnyWriteTransaction) -> Bool {

        var wasDeviceAddedOrRemoved = false

        let oldDevices = OWSDevice.anyFetchAll(transaction: transaction)

        let buildDeviceMap = { (devices: [OWSDevice]) -> [Int: OWSDevice] in
            var deviceMap = [Int: OWSDevice]()
            for device in devices {
                deviceMap[device.deviceId] = device
            }
            return deviceMap
        }

        let oldDeviceMap = buildDeviceMap(oldDevices)
        let newDeviceMap = buildDeviceMap(newDevices)

        for oldDevice in oldDevices {
            if newDeviceMap[oldDevice.deviceId] == nil {
                Logger.verbose("Removing device: \(oldDevice)")
                oldDevice.anyRemove(transaction: transaction)
                wasDeviceAddedOrRemoved = true
            }
        }
        for newDevice in newDevices {
            if let oldDevice = oldDeviceMap[newDevice.deviceId] {
                let deviceDidChange = !oldDevice.areAttributesEqual(newDevice)
                if deviceDidChange {
                    Logger.verbose("Updating device: \(newDevice)")
                    oldDevice.anyUpdate(transaction: transaction) { device in
                        device.updateAttributes(with: newDevice)
                    }
                }
            } else {
                Logger.verbose("Adding device: \(newDevice)")
                newDevice.anyInsert(transaction: transaction)
                wasDeviceAddedOrRemoved = true
            }
        }

        if wasDeviceAddedOrRemoved {
            DispatchQueue.global().async {
                // Device changes can affect the UD access mode for a recipient,
                // so we need to fetch the profile for this user to update UD access mode.
                self.profileManager.fetchLocalUsersProfile(authedAccount: .implicit())
            }
        }
        return wasDeviceAddedOrRemoved
    }
}
