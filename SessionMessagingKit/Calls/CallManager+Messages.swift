import WebRTC

extension CallManager {
    
    public func handleCandidateMessage(_ candidate: RTCIceCandidate) {
        candidateQueue.append(candidate)
    }
    
    public func handleRemoteDescription(_ sdp: RTCSessionDescription) {
        peerConnection.setRemoteDescription(sdp, completionHandler: { [weak self] error in
            if let error = error {
                SNLog("Couldn't set SDP due to error: \(error).")
            } else {
                guard let self = self else { return }
                if sdp.type == .offer, self.peerConnection.localDescription == nil {
                    self.acceptCall()
                }
            }
        })
    }
    
    public func drainMessageQueue() {
        for candidate in candidateQueue {
            peerConnection.add(candidate)
        }
        candidateQueue.removeAll()
    }
}
