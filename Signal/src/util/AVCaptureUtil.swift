//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

func selectAVCaptureDevice(session: AVCaptureDevice.DiscoverySession, deviceTypes: [AVCaptureDevice.DeviceType]) -> AVCaptureDevice? {
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

func isCenterStageSupported() -> Bool {
    if #available(iOS 14.5, *) {
        let deviceTypes: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera]
        let frontSession = AVCaptureDevice.DiscoverySession(deviceTypes: deviceTypes,
                                                            mediaType: .video,
                                                            position: .front)
        
        if let device = selectAVCaptureDevice(session: frontSession, deviceTypes: deviceTypes) {
            if device.activeFormat.isCenterStageSupported {
                return true
            }
        }
    }
    return false
}

func setCentreStageCooperative() {
    if #available(iOS 14.5, *) {
        AVCaptureDevice.centerStageControlMode = .cooperative
    }
}
