import WebRTC

extension CallManager {
    
    public func handleCandidateMessage(_ candidate: RTCIceCandidate) {
        print("[Calls] Received ICE candidate message.")
        candidateQueue.append(candidate)
    }
    
    public func handleRemoteDescription(_ sdp: RTCSessionDescription) {
        print("[Calls] Received remote SDP: \(sdp.sdp).")
        peerConnection.setRemoteDescription(sdp, completionHandler: { [weak self] error in
            if let error = error {
                SNLog("Couldn't set SDP due to error: \(error).")
            } else {
                guard let self = self,
                    sdp.type == .offer, self.peerConnection.localDescription == nil else { return }
                self.acceptCall().retainUntilComplete()
            }
        })
    }
}
