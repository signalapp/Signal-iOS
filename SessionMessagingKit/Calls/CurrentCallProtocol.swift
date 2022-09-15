// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import WebRTC

public protocol CurrentCallProtocol {
    var uuid: String { get }
    var callId: UUID { get }
    var webRTCSession: WebRTCSession { get }
    var hasStartedConnecting: Bool { get set }
    var hasEnded: Bool { get set }
    
    func updateCallMessage(mode: EndCallMode)
    func didReceiveRemoteSDP(sdp: RTCSessionDescription)
    func startSessionCall(_ db: Database)
}
