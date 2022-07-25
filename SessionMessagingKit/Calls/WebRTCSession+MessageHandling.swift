// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import WebRTC
import SessionUtilitiesKit

extension WebRTCSession {
    
    public func handleICECandidates(_ candidate: [RTCIceCandidate]) {
        SNLog("[Calls] Received ICE candidate message.")
        candidate.forEach { peerConnection?.add($0, completionHandler: { _ in  }) }
    }
    
    public func handleRemoteSDP(_ sdp: RTCSessionDescription, from sessionId: String) {
        SNLog("[Calls] Received remote SDP: \(sdp.sdp).")
        
        peerConnection?.setRemoteDescription(sdp, completionHandler: { [weak self] error in
            if let error = error {
                SNLog("[Calls] Couldn't set SDP due to error: \(error).")
            }
            else {
                guard sdp.type == .offer else { return }
                
                self?.sendAnswer(to: sessionId).retainUntilComplete()
            }
        })
    }
}
