import WebRTC

extension WebRTCSession {

    public func attachLocalRenderer(_ renderer: RTCVideoRenderer) {
        localVideoTrack.add(renderer)
    }
    
    public func attachRemoteRenderer(_ renderer: RTCVideoRenderer) {
        remoteVideoTrack?.add(renderer)
    }
    
    public func removeRemoteRenderer(_ renderer: RTCVideoRenderer) {
        remoteVideoTrack?.remove(renderer)
    }
    
    public func handleLocalFrameCaptured(_ videoFrame: RTCVideoFrame) {
        guard let videoCapturer = delegate?.videoCapturer else { return }
        localVideoSource.capturer(videoCapturer, didCapture: videoFrame)
    }
}
