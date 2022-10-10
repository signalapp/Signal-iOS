import WebRTC

extension CallVC : CameraManagerDelegate {
    
    func handleVideoOutputCaptured(sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let rtcPixelBuffer = RTCCVPixelBuffer(pixelBuffer: pixelBuffer)
        let timestamp = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        let timestampNs = Int64(timestamp * 1000000000)
        let rotation: RTCVideoRotation = {
            switch UIDevice.current.orientation {
                case .landscapeRight: return RTCVideoRotation._90
                case .portraitUpsideDown: return RTCVideoRotation._180
                case .landscapeLeft: return RTCVideoRotation._270
                default: return RTCVideoRotation._0
            }
        }()
        
        let frame = RTCVideoFrame(buffer: rtcPixelBuffer, rotation: rotation, timeStampNs: timestampNs)
        frame.timeStamp = Int32(timestamp)
        call.webRTCSession.handleLocalFrameCaptured(frame)
    }
}
