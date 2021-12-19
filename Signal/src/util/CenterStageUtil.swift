//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

class CenterStageUtil {
    static func isCenterStageSupported() -> Bool {
        if #available(iOS 14.5, *) {
            let deviceTypes: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera]
            let frontSession = AVCaptureDevice.DiscoverySession(deviceTypes: deviceTypes,
                                                                mediaType: .video,
                                                                position: .front)
            
            if let device = AVCaptureDevice.select(session: frontSession, deviceTypes: deviceTypes) {
                if device.activeFormat.isCenterStageSupported {
                    return true
                }
            }
        }
        return false
    }
    
    static func setCooperative() {
        if #available(iOS 14.5, *) {
            AVCaptureDevice.centerStageControlMode = .cooperative
        }
    }
    
    static func setCenterStageEnabledIfAvailable(value: Bool) {
        if #available(iOS 14.5, *) {
            AVCaptureDevice.isCenterStageEnabled = value
        }
    }
}
