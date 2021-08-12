import WebRTC

extension CallManager {

    public func attachLocalRenderer(_ renderer: RTCVideoRenderer) {
        localVideoTrack.add(renderer)
    }
    
    public func attachRemoteRenderer(_ renderer: RTCVideoRenderer) {
        remoteVideoTrack?.add(renderer)
    }
    
    public func handleLocalFrameCaptured(_ videoFrame: RTCVideoFrame) {
        localVideoSource.capturer(videoCapturer, didCapture: videoFrame)
    }
}
