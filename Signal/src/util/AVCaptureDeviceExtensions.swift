//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import AVFoundation

extension AVCaptureDevice {
    static func select(session: AVCaptureDevice.DiscoverySession, deviceTypes: [AVCaptureDevice.DeviceType]) -> AVCaptureDevice? {
        var deviceMap = [AVCaptureDevice.DeviceType: AVCaptureDevice]()
        for device in session.devices {
            deviceMap[device.deviceType] = device
        }
        for deviceType in deviceTypes {
            if let device = deviceMap[deviceType] {
                return device
            }
        }
        return nil
    }
}


