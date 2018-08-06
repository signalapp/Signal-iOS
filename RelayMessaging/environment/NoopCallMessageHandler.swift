//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import RelayServiceKit

@objc
public class NoopCallMessageHandler: NSObject, OWSCallMessageHandler {

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
