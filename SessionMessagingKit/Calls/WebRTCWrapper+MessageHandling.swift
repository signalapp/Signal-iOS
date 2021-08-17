import WebRTC

extension WebRTCWrapper {
    
    public func handleICECandidate(_ candidate: RTCIceCandidate) {
        print("[Calls] Received ICE candidate message.")
        peerConnection.add(candidate)
    }
    
    public func handleRemoteSDP(_ sdp: RTCSessionDescription, from sessionID: String) {
        print("[Calls] Received remote SDP: \(sdp.sdp).")
        peerConnection.setRemoteDescription(sdp, completionHandler: { [weak self] error in
            if let error = error {
                SNLog("Couldn't set SDP due to error: \(error).")
            } else {
                guard let self = self,
                    sdp.type == .offer, self.peerConnection.localDescription == nil else { return }
                // Automatically answer the call
                Storage.write { transaction in
                    self.sendAnswer(to: sessionID, using: transaction).retainUntilComplete()
                }
            }
        })
    }
}
