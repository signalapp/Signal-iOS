import WebRTC

extension WebRTCWrapper {
    
    public func handleICECandidate(_ candidate: RTCIceCandidate) {
        print("[Calls] Received ICE candidate message.")
        candidateQueue.append(candidate)
    }
    
    public func handleRemoteSDP(_ sdp: RTCSessionDescription) {
        print("[Calls] Received remote SDP: \(sdp.sdp).")
        peerConnection.setRemoteDescription(sdp, completionHandler: { [weak self] error in
            if let error = error {
                SNLog("Couldn't set SDP due to error: \(error).")
            } else {
                guard let self = self,
                    sdp.type == .offer, self.peerConnection.localDescription == nil else { return }
                // Answer the call
                self.answer().retainUntilComplete()
            }
        })
    }
}
