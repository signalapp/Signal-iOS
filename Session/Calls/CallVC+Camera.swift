import WebRTC

extension CallVC : CameraManagerDelegate {
    
    func handleVideoOutputCaptured(sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let rtcPixelBuffer = RTCCVPixelBuffer(pixelBuffer: pixelBuffer)
        let timestamp = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        let timestampNs = Int64(timestamp * 1000000000)
        let frame = RTCVideoFrame(buffer: rtcPixelBuffer, rotation: RTCVideoRotation._0, timeStampNs: timestampNs)
        frame.timeStamp = Int32(timestamp)
        call.webRTCSession.handleLocalFrameCaptured(frame)
    }
}
