import WebRTC

extension CallVCV2 : CallManagerDelegate {
    
    /// Invoked by `CallManager` upon initiating or accepting a call. This method sends the SDP to the other
    /// party before streaming starts.
    func sendSDP(_ sdp: RTCSessionDescription) {
        guard let room = room else { return }
        let json = [
            "type" : RTCSessionDescription.string(for: sdp.type),
            "sdp" : sdp.sdp
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: json, options: [ .prettyPrinted ]) else { return }
        print("[Calls] Sending SDP to test call server: \(json).")
        TestCallServer.send(data, roomID: room.roomID, userID: room.clientID).retainUntilComplete()
    }
    
    /// Invoked when the peer connection has generated an ICE candidate.
    func sendICECandidate(_ candidate: RTCIceCandidate) {
        guard let room = room else { return }
        let json = [
            "type" : "candidate",
            "label" : "\(candidate.sdpMLineIndex)",
            "id" : candidate.sdpMid,
            "candidate" : candidate.sdp
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: json, options: [ .prettyPrinted ]) else { return }
        print("[Calls] Sending ICE candidate to test call server: \(json).")
        TestCallServer.send(data, roomID: room.roomID, userID: room.clientID).retainUntilComplete()
    }
}
