import WebRTC

extension WebRTCSession {
    
    public func handleICECandidates(_ candidate: [RTCIceCandidate]) {
        SNLog("[Calls] Received ICE candidate message.")
        candidate.forEach { peerConnection?.add($0) }
    }
    
    public func handleRemoteSDP(_ sdp: RTCSessionDescription, from sessionID: String) {
        SNLog("[Calls] Received remote SDP: \(sdp.sdp).")
        peerConnection?.setRemoteDescription(sdp, completionHandler: { [weak self] error in
            if let error = error {
                SNLog("[Calls] Couldn't set SDP due to error: \(error).")
            } else {
                guard let self = self, sdp.type == .offer else { return }
                Storage.write { transaction in
                    self.sendAnswer(to: sessionID, using: transaction).retainUntilComplete()
                }
            }
        })
    }
}
