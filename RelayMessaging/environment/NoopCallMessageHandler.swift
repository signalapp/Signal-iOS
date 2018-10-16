//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import RelayServiceKit

@objc
public class NoopCallMessageHandler: NSObject, OWSCallMessageHandler {
    public func receivedHangup(withCallId callId: String) {
        owsFail("\(self.logTag) in \(#function).")
    }
        
    public func receivedIceUpdate(withThreadId threadId: String, sessionDescription sdp: String, sdpMid: String, sdpMLineIndex: Int32) {
        owsFail("\(self.logTag) in \(#function).")
    }
    
    public func receivedOffer(withThreadId threadId: String, originatorId: String, peerId: String, sessionDescription: String) {
        owsFail("\(self.logTag) in \(#function).")
    }
    
    public func receivedOffer(withThreadId threadId: String, peerId: String, sessionDescription: String) {
        owsFail("\(self.logTag) in \(#function).")
    }

    public func receivedOffer(_ offer: OWSSignalServiceProtosCallMessageOffer, from callerId: String) {
        owsFail("\(self.logTag) in \(#function).")
    }

    public func receivedAnswer(_ answer: OWSSignalServiceProtosCallMessageAnswer, from callerId: String) {
        owsFail("\(self.logTag) in \(#function).")
    }

    public func receivedIceUpdate(_ iceUpdate: OWSSignalServiceProtosCallMessageIceUpdate, from callerId: String) {
        owsFail("\(self.logTag) in \(#function).")
    }

    public func receivedHangup(_ hangup: OWSSignalServiceProtosCallMessageHangup, from callerId: String) {
        owsFail("\(self.logTag) in \(#function).")
    }

    public func receivedBusy(_ busy: OWSSignalServiceProtosCallMessageBusy, from callerId: String) {
        owsFail("\(self.logTag) in \(#function).")
    }
}
