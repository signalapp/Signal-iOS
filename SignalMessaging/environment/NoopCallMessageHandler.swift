//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import SignalServiceKit

@objc
public class NoopCallMessageHandler: NSObject, OWSCallMessageHandler {

    public func receivedOffer(_ offer: SSKProtoCallMessageOffer, from callerId: String) {
        owsFail("")
    }

    public func receivedAnswer(_ answer: SSKProtoCallMessageAnswer, from callerId: String) {
        owsFail("")
    }

    public func receivedIceUpdate(_ iceUpdate: SSKProtoCallMessageIceUpdate, from callerId: String) {
        owsFail("")
    }

    public func receivedHangup(_ hangup: SSKProtoCallMessageHangup, from callerId: String) {
        owsFail("")
    }

    public func receivedBusy(_ busy: SSKProtoCallMessageBusy, from callerId: String) {
        owsFail("")
    }
}
