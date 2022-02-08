// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.
import WebRTC
import Foundation

class RemoteVideoView: RTCMTLVideoView {
    
    override func renderFrame(_ frame: RTCVideoFrame?) {
        super.renderFrame(frame)
        guard let frame = frame else { return }
        DispatchMainThreadSafe {
            let frameRotation = frame.rotation
            let deviceRotation = UIDevice.current.orientation
            switch deviceRotation {
            case .portrait, .portraitUpsideDown:
                // We don't have to do anything, the renderer will automatically make sure it's right-side-up.
                self.rotationOverride = nil
            case .landscapeLeft:
                switch frameRotation {
                case RTCVideoRotation._0: self.rotationOverride = NSNumber(value: RTCVideoRotation._90.rawValue) // Landscape left
                case RTCVideoRotation._90: self.rotationOverride = NSNumber(value: RTCVideoRotation._180.rawValue) // Portrait
                case RTCVideoRotation._180: self.rotationOverride = NSNumber(value: RTCVideoRotation._270.rawValue) // Landscape right
                case RTCVideoRotation._270: self.rotationOverride = NSNumber(value: RTCVideoRotation._0.rawValue) // Portrait upside-down
                default: self.rotationOverride = nil
                }
            case .landscapeRight:
                switch frameRotation {
                case RTCVideoRotation._0: self.rotationOverride = NSNumber(value: RTCVideoRotation._270.rawValue) // Landscape left
                case RTCVideoRotation._90: self.rotationOverride = NSNumber(value: RTCVideoRotation._0.rawValue) // Portrait
                case RTCVideoRotation._180: self.rotationOverride = NSNumber(value: RTCVideoRotation._90.rawValue) // Landscape right
                case RTCVideoRotation._270: self.rotationOverride = NSNumber(value: RTCVideoRotation._180.rawValue) // Portrait upside-down
                default: self.rotationOverride = nil
                }
            default:
                // Do nothing if we're face down, up, etc.
                // Assume we're already setup for the correct orientation.
                break
            }
        }
    }
}
