import WebRTC

extension CallManager {

    func attachLocalRenderer(_ renderer: RTCVideoRenderer) {
        localVideoTrack.add(renderer)
    }
    
    func attachRemoteRenderer(_ renderer: RTCVideoRenderer) {
        remoteVideoTrack?.add(renderer)
    }
    
    func handleLocalFrameCaptured(_ videoFrame: RTCVideoFrame) {
        localVideoSource.capturer(videoCapturer, didCapture: videoFrame)
    }
}
