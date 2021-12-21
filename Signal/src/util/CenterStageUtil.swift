//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

class CenterStageUtil {
    private static let observedKey = "isCenterStageEnabled"
    
    static func isCenterStageSupported() -> Bool {
        if #available(iOS 14.5, *) {
            let deviceTypes: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera]
            let frontSession = AVCaptureDevice.DiscoverySession(deviceTypes: deviceTypes,
                                                                mediaType: .video,
                                                                position: .front)
            
            if let device = AVCaptureDevice.select(session: frontSession, deviceTypes: deviceTypes) {
                return device.activeFormat.isCenterStageSupported
            }
        }
        return false
    }
    
    static func configCenterStage(observer: UIViewController, isSupportedHandler: (Bool) -> Void) {
        if isCenterStageSupported() {
            setCooperative()
            isSupportedHandler(true)
            KVOCenterStageEnabled(observer: observer)
        } else {
            isSupportedHandler(false)
        }
    }
    
    private static func KVOCenterStageEnabled(observer: UIViewController) {
        AVCaptureDevice.addObserver(observer, forKeyPath: observedKey, options: [.old, .new], context: nil)
    }
    
    static func handleObservedValue(forKeyPath: String?, change: [NSKeyValueChangeKey : Any]?, isSelectedHandler: (Bool) -> Void) {
        if forKeyPath == observedKey,
           let selected = change?[.newKey] as? Bool {
            isSelectedHandler(selected)
            return
        }
        isSelectedHandler(false)
    }
    
    static func setCooperative() {
        if #available(iOS 14.5, *) {
            AVCaptureDevice.centerStageControlMode = .cooperative
        }
    }
    
    static func setCenterStageEnabled(value: Bool) {
        if #available(iOS 14.5, *) {
            AVCaptureDevice.isCenterStageEnabled = value
        }
    }
}
